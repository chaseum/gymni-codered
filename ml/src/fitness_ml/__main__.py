"""fitness-ml entry point.

    python -m fitness_ml sample            # print one contract-shaped observation (provenance=fixture)
    python -m fitness_ml run --source live # not implemented yet: pose pipeline is Chase's next prompt
"""
import argparse
import json
import sys

from .config import Config
from .types import CompletedRep, Observation


def main() -> int:
    ap = argparse.ArgumentParser(prog="fitness-ml")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("sample")
    sub.add_parser("config")
    run = sub.add_parser("run")
    run.add_argument("--source", choices=["live", "recorded"], required=True)
    run.add_argument("--video", help="MP4 path when --source recorded")
    run.add_argument("--exercise", choices=["curl", "squat", "deadlift"], required=True)
    args = ap.parse_args()

    cfg = Config()
    if args.cmd == "config":
        print(json.dumps(cfg, default=vars, indent=2))
    elif args.cmd == "sample":
        obs = Observation(observation_id="ml-sample-1", session_id=cfg.session_id, source="live",
                          source_timestamp_ms=2850, exercise="curl", tracking_status="ready", phase="lowered",
                          inference_provenance="fixture", completed_rep=CompletedRep(1, 1850),
                          measurements={"elbow_angle_deg": 158.0})
        print(json.dumps(obs.to_dict()))
    else:
        print("pose pipeline not implemented yet (see ml/src/fitness_ml/interfaces.py). "
              "Use `python -m gymai_backend.simulate` for mock observations.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
