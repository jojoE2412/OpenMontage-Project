from __future__ import annotations

import json
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from lib.checkpoint import init_project
from lib.paths import PROJECTS_DIR
from backend.models import Artifact, Asset, Job, JobStatus, Project


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class BackendStore:
    """SQLite metadata store; media stays in OpenMontage's canonical workspaces."""

    def __init__(self, database_path: Path | None = None, projects_root: Path | None = None) -> None:
        configured = os.environ.get("OPENMONTAGE_MOBILE_DB")
        self.database_path = database_path or Path(
            configured or Path.home() / ".openmontage" / "mobile" / "mobile.sqlite3"
        )
        self.projects_root = (projects_root or PROJECTS_DIR).resolve()
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self.initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, timeout=30)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    def initialize(self) -> None:
        with self._connect() as db:
            db.executescript(
                """
                CREATE TABLE IF NOT EXISTS projects (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                    workspace_path TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS assets (
                    id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id),
                    name TEXT NOT NULL, type TEXT NOT NULL, path TEXT NOT NULL,
                    mime_type TEXT NOT NULL, size INTEGER NOT NULL,
                    duration REAL, metadata_json TEXT NOT NULL, created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS jobs (
                    id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id),
                    type TEXT NOT NULL, capability TEXT, operation TEXT, pipeline_id TEXT,
                    status TEXT NOT NULL, progress INTEGER NOT NULL, current_step TEXT NOT NULL,
                    created_at TEXT NOT NULL, started_at TEXT, completed_at TEXT,
                    error TEXT, input_json TEXT NOT NULL, output_artifact_ids_json TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS artifacts (
                    id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id),
                    job_id TEXT NOT NULL REFERENCES jobs(id), type TEXT NOT NULL,
                    path TEXT NOT NULL, mime_type TEXT NOT NULL, size INTEGER NOT NULL,
                    metadata_json TEXT NOT NULL, created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_assets_project ON assets(project_id);
                CREATE INDEX IF NOT EXISTS idx_jobs_project ON jobs(project_id);
                CREATE INDEX IF NOT EXISTS idx_artifacts_job ON artifacts(job_id);
                """
            )

    def recover_interrupted_jobs(self) -> int:
        """Fail jobs that were active before a backend process restart."""
        now = _now()
        with self._connect() as db:
            cursor = db.execute(
                "UPDATE jobs SET status='failed', progress=100, current_step='failed', "
                "completed_at=?, error=? WHERE status IN ('queued', 'running')",
                (now, "Backend restarted before this job completed."),
            )
            return cursor.rowcount

    def create_project(self, name: str) -> Project:
        project_id = f"mobile-{uuid.uuid4().hex}"
        now = _now()
        # init_project owns the workspace layout used by OpenMontage tools.
        workspace = init_project(
            project_id,
            title=name,
            pipeline_type="unknown",
            pipeline_dir=self.projects_root,
        ).resolve()
        project = Project(
            id=project_id, name=name, created_at=now, updated_at=now,
            workspace_path=str(workspace),
        )
        with self._connect() as db:
            db.execute(
                "INSERT INTO projects VALUES (?, ?, ?, ?, ?)",
                (project.id, project.name, now, now, str(workspace)),
            )
        return project

    @staticmethod
    def _project(row: sqlite3.Row | None) -> Project | None:
        return Project.model_validate(dict(row)) if row else None

    def get_project(self, project_id: str) -> Project | None:
        with self._connect() as db:
            return self._project(db.execute("SELECT * FROM projects WHERE id=?", (project_id,)).fetchone())

    def list_projects(self) -> list[Project]:
        with self._connect() as db:
            return [Project.model_validate(dict(row)) for row in db.execute("SELECT * FROM projects ORDER BY created_at DESC")]

    def project_workspace(self, project_id: str) -> Path | None:
        project = self.get_project(project_id)
        if project is None:
            return None
        path = Path(project.workspace_path).resolve()
        if not path.is_relative_to(self.projects_root):
            return None
        return path

    def add_asset(self, *, project_id: str, name: str, path: Path, mime_type: str,
                  duration: float | None, metadata: dict[str, Any] | None = None,
                  asset_type: str = "video") -> Asset:
        workspace = self.project_workspace(project_id)
        if workspace is None:
            raise KeyError("project not found")
        resolved = path.resolve()
        if not resolved.is_relative_to(workspace):
            raise ValueError("asset path is outside project workspace")
        stat = resolved.stat()
        asset = Asset(
            id=f"asset-{uuid.uuid4().hex}", project_id=project_id, name=name,
            type=asset_type, path=str(resolved), mime_type=mime_type, size=stat.st_size,
            duration=duration, metadata=metadata or {}, created_at=_now(),
        )
        with self._connect() as db:
            db.execute(
                "INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (asset.id, asset.project_id, asset.name, asset.type, asset.path,
                 asset.mime_type, asset.size, asset.duration, json.dumps(asset.metadata), asset.created_at.isoformat()),
            )
            db.execute("UPDATE projects SET updated_at=? WHERE id=?", (asset.created_at.isoformat(), project_id))
        return asset

    @staticmethod
    def _asset(row: sqlite3.Row) -> Asset:
        item = dict(row)
        item["metadata"] = json.loads(item.pop("metadata_json"))
        return Asset.model_validate(item)

    def get_asset(self, asset_id: str) -> Asset | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM assets WHERE id=?", (asset_id,)).fetchone()
            return self._asset(row) if row else None

    def list_assets(self, project_id: str) -> list[Asset]:
        with self._connect() as db:
            rows = db.execute("SELECT * FROM assets WHERE project_id=? ORDER BY created_at DESC", (project_id,))
            return [self._asset(row) for row in rows]

    def create_job(self, *, project_id: str, capability: str, operation: str,
                   request_input: dict[str, Any]) -> Job:
        job = Job(
            id=f"job-{uuid.uuid4().hex}", project_id=project_id, type="capability",
            capability=capability, operation=operation, status=JobStatus.queued,
            current_step="queued", created_at=datetime.now(timezone.utc), input=request_input,
        )
        with self._connect() as db:
            db.execute(
                "INSERT INTO jobs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (job.id, project_id, job.type, capability, operation, None, job.status.value,
                 job.progress, job.current_step, job.created_at.isoformat(), None, None,
                 None, json.dumps(request_input), "[]"),
            )
        return job

    @staticmethod
    def _job(row: sqlite3.Row | None) -> Job | None:
        if row is None:
            return None
        item = dict(row)
        item["input"] = json.loads(item.pop("input_json"))
        item["output_artifact_ids"] = json.loads(item.pop("output_artifact_ids_json"))
        return Job.model_validate(item)

    def get_job(self, job_id: str) -> Job | None:
        with self._connect() as db:
            return self._job(db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone())

    def update_job(self, job_id: str, **changes: Any) -> Job | None:
        allowed = {"status", "progress", "current_step", "started_at", "completed_at", "error", "output_artifact_ids"}
        fields: list[str] = []
        values: list[Any] = []
        for key, value in changes.items():
            if key not in allowed:
                raise ValueError(f"unsupported job update field: {key}")
            if key == "status":
                value = value.value if isinstance(value, JobStatus) else value
            if key in {"started_at", "completed_at"} and value is not None:
                value = value.isoformat() if isinstance(value, datetime) else value
            if key == "output_artifact_ids":
                key, value = "output_artifact_ids_json", json.dumps(value)
            fields.append(f"{key}=?")
            values.append(value)
        if fields:
            values.append(job_id)
            with self._connect() as db:
                db.execute(f"UPDATE jobs SET {', '.join(fields)} WHERE id=?", values)
        return self.get_job(job_id)

    def add_artifact(self, *, project_id: str, job_id: str, path: Path,
                     mime_type: str, metadata: dict[str, Any] | None = None,
                     artifact_type: str = "video") -> Artifact:
        workspace = self.project_workspace(project_id)
        resolved = path.resolve()
        if workspace is None or not resolved.is_relative_to(workspace) or not resolved.is_file():
            raise ValueError("artifact is missing or outside project workspace")
        artifact = Artifact(
            id=f"artifact-{uuid.uuid4().hex}", project_id=project_id, job_id=job_id,
            type=artifact_type, path=str(resolved), mime_type=mime_type,
            size=resolved.stat().st_size, metadata=metadata or {}, created_at=datetime.now(timezone.utc),
        )
        with self._connect() as db:
            db.execute(
                "INSERT INTO artifacts VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (artifact.id, artifact.project_id, artifact.job_id, artifact.type,
                 artifact.path, artifact.mime_type, artifact.size,
                 json.dumps(artifact.metadata), artifact.created_at.isoformat()),
            )
            db.execute("UPDATE projects SET updated_at=? WHERE id=?", (artifact.created_at.isoformat(), project_id))
        return artifact

    @staticmethod
    def _artifact(row: sqlite3.Row) -> Artifact:
        item = dict(row)
        item["metadata"] = json.loads(item.pop("metadata_json"))
        return Artifact.model_validate(item)

    def get_artifact(self, artifact_id: str) -> Artifact | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM artifacts WHERE id=?", (artifact_id,)).fetchone()
            return self._artifact(row) if row else None

    def list_artifacts(self, job_id: str) -> list[Artifact]:
        with self._connect() as db:
            rows = db.execute("SELECT * FROM artifacts WHERE job_id=? ORDER BY created_at", (job_id,))
            return [self._artifact(row) for row in rows]

    def safe_media_path(self, path: str, project_id: str) -> Path | None:
        workspace = self.project_workspace(project_id)
        if workspace is None:
            return None
        resolved = Path(path).resolve()
        return resolved if resolved.is_relative_to(workspace) and resolved.is_file() else None


store = BackendStore()
