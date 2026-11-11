from __future__ import annotations

from datetime import datetime, timezone
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Project(BaseModel):
    id: str
    name: str
    created_at: datetime
    updated_at: datetime
    workspace_path: str


class Asset(BaseModel):
    id: str
    project_id: str
    name: str
    type: str
    path: str
    mime_type: str
    size: int
    duration: float | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime


class JobStatus(StrEnum):
    queued = 'queued'
    running = 'running'
    completed = 'completed'
    failed = 'failed'
    cancelled = 'cancelled'


class CapabilityJobRequest(BaseModel):
    type: Literal['capability'] = 'capability'
    capability: str
    operation: str
    project_id: str
    input_asset_ids: list[str] = Field(default_factory=list)
    parameters: dict[str, Any] = Field(default_factory=dict)


class PipelineJobRequest(BaseModel):
    type: Literal['pipeline'] = 'pipeline'
    pipeline_id: str
    project_id: str
    input_asset_ids: list[str] = Field(default_factory=list)
    parameters: dict[str, Any] = Field(default_factory=dict)


class Job(BaseModel):
    id: str
    project_id: str
    type: Literal['capability', 'pipeline']
    capability: str | None = None
    operation: str | None = None
    pipeline_id: str | None = None
    status: JobStatus
    progress: int = 0
    current_step: str
    created_at: datetime
    started_at: datetime | None = None
    completed_at: datetime | None = None
    error: str | None = None
    input: dict[str, Any]
    output_artifact_ids: list[str] = Field(default_factory=list)


class Artifact(BaseModel):
    id: str
    project_id: str
    job_id: str
    type: str
    path: str
    mime_type: str
    size: int
    metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime


class TrimParameters(BaseModel):
    start: float = Field(ge=0)
    end: float = Field(gt=0)

    @model_validator(mode='after')
    def end_after_start(self) -> 'TrimParameters':
        if self.end <= self.start:
            raise ValueError('end must be greater than start')
        return self


class SpeedParameters(BaseModel):
    speed_factor: float = Field(ge=0.1, le=100)


class CropParameters(BaseModel):
    target_aspect: Literal['portrait', 'square', 'landscape', 'cinematic', 'vertical_4_5']


class ColorGradeParameters(BaseModel):
    profile: str
    intensity: float = Field(default=1.0, ge=0, le=1)


class AudioEnhancementParameters(BaseModel):
    preset: str


class AudioVolumeParameters(BaseModel):
    volume: float = Field(ge=0, le=1)


class AudioTrimParameters(BaseModel):
    start_seconds: float = Field(ge=0)
    end_seconds: float = Field(gt=0)

    @model_validator(mode='after')
    def end_after_start(self) -> 'AudioTrimParameters':
        if self.end_seconds <= self.start_seconds:
            raise ValueError('end_seconds must be greater than start_seconds')
        return self


class VideoGenerationParameters(BaseModel):
    provider_tool_id: str = Field(min_length=1, max_length=120)
    prompt: str = Field(min_length=12, max_length=2000)
    negative_prompt: str = Field(default='', max_length=2000)
    mode: Literal['text_to_video', 'image_to_video', 'reference_to_video'] = 'text_to_video'
    aspect_ratio: str = '16:9'
    duration_seconds: float = Field(default=5, gt=0, le=30)
    fps: int | None = Field(default=None, ge=1, le=120)
    width: int | None = Field(default=None, ge=64, le=4096)
    height: int | None = Field(default=None, ge=64, le=4096)
    num_frames: int | None = Field(default=None, ge=1, le=1200)
    num_inference_steps: int | None = Field(default=None, ge=1, le=200)
    guidance_scale: float | None = Field(default=None, ge=0, le=100)
    seed: int | None = Field(default=None, ge=0, le=2**32 - 1)
    model_id: str | None = Field(default=None, max_length=120)
    reference_artifact_id: str | None = Field(default=None, max_length=120)


class ImageGenerationParameters(BaseModel):
    provider_tool_id: str = Field(min_length=1, max_length=120)
    prompt: str = Field(min_length=3, max_length=2000)
    negative_prompt: str = Field(default='', max_length=2000)
    model_id: str | None = Field(default=None, max_length=120)
    aspect_ratio: str = '1:1'
    resolution: str = '1024'
    width: int | None = Field(default=None, ge=64, le=4096)
    height: int | None = Field(default=None, ge=64, le=4096)
    seed: int | None = Field(default=None, ge=0, le=2**32 - 1)
    reference_artifact_id: str | None = Field(default=None, max_length=120)


class TtsGenerationParameters(BaseModel):
    provider_tool_id: str = Field(min_length=1, max_length=120)
    text: str = Field(min_length=1, max_length=20000)
    model_id: str | None = Field(default=None, max_length=120)
    voice: str | None = Field(default=None, max_length=160)
    voice_id: str | None = Field(default=None, max_length=160)
    speaker_id: int | None = Field(default=None, ge=0, le=1000)
    language_code: str | None = Field(default=None, max_length=32)
    voice_language: str | None = Field(default=None, max_length=32)
    speed: float | None = Field(default=None, ge=0.25, le=4)
    speaking_rate: float | None = Field(default=None, ge=0.25, le=4)
    voice_speed: float | None = Field(default=None, ge=0.25, le=4)
    pitch: float | None = Field(default=None, ge=-50, le=50)
    instructions: str | None = Field(default=None, max_length=2000)
    format: str | None = Field(default=None, max_length=24)
    response_format: str | None = Field(default=None, max_length=24)
    length_scale: float | None = Field(default=None, ge=0.25, le=4)
    sentence_silence: float | None = Field(default=None, ge=0, le=10)


class MusicGenerationParameters(BaseModel):
    provider_tool_id: str = Field(min_length=1, max_length=120)
    prompt: str = Field(min_length=1, max_length=2000)
    model_id: str | None = Field(default=None, max_length=120)
    model: str | None = Field(default=None, max_length=120)
    duration_seconds: float | None = Field(default=None, gt=0, le=600)
    output_format: str | None = Field(default=None, max_length=24)
    format: str | None = Field(default=None, max_length=24)
    instrumental: bool | None = None
    force_instrumental: bool | None = None
    custom_mode: bool | None = None
    style: str | None = Field(default=None, max_length=500)
    title: str | None = Field(default=None, max_length=160)
    track_index: int | None = Field(default=None, ge=0, le=10)


class TranscriptionParameters(BaseModel):
    provider_tool_id: str = Field(min_length=1, max_length=120)
    model_size: Literal['tiny', 'base', 'small', 'medium', 'large-v2', 'large-v3'] = 'base'
    language: str | None = Field(default=None, max_length=16)
    diarize: bool = False


class UpscaleParameters(BaseModel):
    provider_tool_id: str = Field(min_length=1, max_length=120)
    scale: Literal[2, 4] = 4
    model_id: str | None = Field(default=None, max_length=120)
    face_enhance: bool = False
    denoise_strength: float = Field(default=0.5, ge=0, le=1)


class RenderParameters(BaseModel):
    transition: Literal['cut', 'crossfade', 'fade'] = 'cut'
    transition_duration: float = Field(default=0.5, ge=0.1, le=5)
    auto_normalize: bool = True
    target_resolution: str = Field(default='1920x1080', pattern=r'^\d{2,5}x\d{2,5}$')
    target_fps: int = Field(default=30, ge=1, le=120)


class SubtitleBurnParameters(BaseModel):
    subtitle_artifact_id: str = Field(min_length=1, max_length=120)


class SubtitleCue(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    start: float = Field(ge=0)
    end: float = Field(gt=0)

    @model_validator(mode='after')
    def end_after_start(self) -> 'SubtitleCue':
        if self.end <= self.start:
            raise ValueError('cue end must be greater than start')
        return self


class SubtitleGenerateParameters(BaseModel):
    segments: list[SubtitleCue] = Field(min_length=1, max_length=500)
    format: Literal['srt', 'vtt'] = 'srt'
    max_chars_per_line: int = Field(default=42, ge=10, le=120)
    max_words_per_cue: int = Field(default=8, ge=1, le=30)
