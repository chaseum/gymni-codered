"""Summarize phone-committed camera reps without moving session state into Vercel."""
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class CompletedRep(BaseModel):
    rep_index: int = Field(ge=0)
    duration_ms: float | None = Field(default=None, gt=0, allow_inf_nan=False)


class Issue(BaseModel):
    code: str = Field(min_length=1, max_length=80)


class Observation(BaseModel):
    source: Literal["live"]
    exercise: Literal["curl", "squat", "deadlift"]
    tracking_status: Literal["ready"]
    inference_provenance: Literal["trained_model", "reviewed_rules"]
    completed_rep: CompletedRep
    issues: list[Issue] = Field(max_length=32)


class Rep(BaseModel):
    rep_count: int = Field(ge=1)
    observation: Observation


class SetRecord(BaseModel):
    set_id: str = Field(min_length=1, max_length=80)
    exercise: Literal["curl", "squat", "deadlift"]
    actual_reps: int = Field(ge=0, le=1000)
    active_duration_ms: float = Field(ge=0, allow_inf_nan=False)
    reps: list[Rep] = Field(max_length=1000)

    @model_validator(mode="after")
    def committed_reps(self):
        if self.actual_reps != len(self.reps):
            raise ValueError("Rep total must match committed records.")
        if any(rep.rep_count != index or rep.observation.exercise != self.exercise
               for index, rep in enumerate(self.reps, 1)):
            raise ValueError("Rep order and exercise must match the set.")
        return self


class Workout(BaseModel):
    schema_version: Literal[1]
    workout_id: UUID
    state: Literal["complete"]
    sets: list[SetRecord] = Field(max_length=100)

    def summary(self):
        sets = []
        for record in self.sets:
            durations = [rep.observation.completed_rep.duration_ms for rep in record.reps
                         if rep.observation.completed_rep.duration_ms is not None]
            issues = {}
            for rep in record.reps:
                for code in {issue.code for issue in rep.observation.issues}:
                    issues[code] = issues.get(code, 0) + 1
            sets.append({"set_id": record.set_id, "exercise": record.exercise,
                         "actual_reps": record.actual_reps, "active_duration_ms": record.active_duration_ms,
                         "mean_rep_duration_ms": sum(durations) / len(durations) if durations else None,
                         "issue_rep_counts": issues})
        return {"workout_id": str(self.workout_id), "total_reps": sum(item["actual_reps"] for item in sets),
                "sets": sets, "storage": "iphone", "workout_llm_tokens": 0}
