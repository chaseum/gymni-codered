"""Run one end-to-end Gemini-to-ElevenLabs cue generation example."""

from pathlib import Path

from backend.audio.dynamic_cue import CueRequest, save_spoken_cue


ROOT = Path(__file__).resolve().parent


def main() -> None:
    # Example input only. Replace these values with a real, reviewed analyzer event.
    request = CueRequest(
        exercise="deadlift",
        issue_code="back_too_curved",
        evidence="Back was too curved during the lift; calibrated target is 15 degrees.",
        recommended_action="Keep your back straighter throughout the lift.",
        confidence=0.93,
        tracking_status="ready",
        coach_approved=True,
    )
    output_path = ROOT / "assets" / "audio" / "dynamic_demo.mp3"
    spoken_text = save_spoken_cue(request, output_path)
    print(f'Gemini wrote: "{spoken_text}"')
    print(f"ElevenLabs audio saved to: {output_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
