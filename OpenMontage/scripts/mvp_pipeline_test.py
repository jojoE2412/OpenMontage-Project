#!/usr/bin/env python3
"""Minimal local MVP execution probe for OpenMontage.

This is intentionally not a generic pipeline runner. It proves the smallest
programmatic path supplied by this repository:

1. create an OpenMontage workspace with init_project();
2. create a local synthetic A/V fixture with FFmpeg;
3. invoke the existing VideoCompose tool to write renders/final.mp4.

No cloud provider, AI coding agent, or OpenMontage production source is
modified. Missing local prerequisites are reported and the probe exits before
attempting a render.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import shutil
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from lib.checkpoint import init_project


def _run(command: list[str], *, cwd: Path | None = None) -> None:
    subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)


def _write_report(project_dir: Path, report: dict) -> Path:
    path = project_dir / "artifacts" / "mvp_pipeline_test_report.json"
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-id", help="Optional kebab-case project ID.")
    args = parser.parse_args()

    project_id = args.project_id or f"mvp-local-{uuid.uuid4().hex[:8]}"
    project_dir = init_project(
        project_id,
        title="MVP Local Compose Probe",
        pipeline_type="animated-explainer",
    )
    report = {
        "project_id": project_id,
        "project_dir": str(project_dir),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "purpose": "Programmatic local compose proof; not a complete AI-agent pipeline.",
        "prerequisites": {
            "ffmpeg": shutil.which("ffmpeg"),
            "ffprobe": shutil.which("ffprobe"),
            "pyyaml": importlib.util.find_spec("yaml") is not None,
        },
    }

    missing = [
        name
        for name, value in report["prerequisites"].items()
        if not value
    ]
    if missing:
        report["status"] = "blocked"
        report["blocked_at"] = "local prerequisite check"
        report["missing"] = missing
        report["next_step"] = (
            "Install the missing local prerequisites, then rerun this probe. "
            "No cloud credential is required for this fixture-based experiment."
        )
        path = _write_report(project_dir, report)
        print(f"BLOCKED: missing {', '.join(missing)}")
        print(f"Workspace: {project_dir}")
        print(f"Report: {path}")
        return 2

    fixture = project_dir / "assets" / "video" / "fixture.mp4"
    final_video = project_dir / "renders" / "final.mp4"
    try:
        _run([
            "ffmpeg", "-y",
            "-f", "lavfi", "-i", "color=c=navy:s=640x360:d=2:r=30",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest", str(fixture),
        ])

        from tools.video.video_compose import VideoCompose

        result = VideoCompose().execute({
            "operation": "compose",
            "edit_decisions": {
                "cuts": [
                    {
                        "source": str(fixture),
                        "in_seconds": 0,
                        "out_seconds": 2,
                        "speed": 1.0,
                    },
                ],
            },
            "output_path": str(final_video),
            "codec": "libx264",
            "crf": 23,
            "preset": "fast",
        })
        if not result.success or not final_video.is_file():
            raise RuntimeError(result.error or "VideoCompose did not create final.mp4")

        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration,size", "-of", "json", str(final_video)],
            check=True,
            capture_output=True,
            text=True,
        )
        report["status"] = "completed"
        report["output"] = str(final_video)
        report["ffprobe"] = json.loads(probe.stdout)
        report["note"] = "Compose proved; semantic pipeline stages remain agent-driven."
        exit_code = 0
    except Exception as exc:
        report["status"] = "failed"
        report["blocked_at"] = "fixture creation or VideoCompose execution"
        report["error"] = str(exc)
        exit_code = 1

    path = _write_report(project_dir, report)
    print(f"Status: {report['status']}")
    print(f"Workspace: {project_dir}")
    print(f"Report: {path}")
    if report["status"] == "completed":
        print(f"Final video: {final_video}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
