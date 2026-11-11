"""Text-to-video generation through Hugging Face Inference Providers."""

from __future__ import annotations

import os
from pathlib import Path
import time

from tools.base_tool import (
    BaseTool,
    Determinism,
    ExecutionMode,
    ResourceProfile,
    RetryPolicy,
    ToolResult,
    ToolRuntime,
    ToolStability,
    ToolStatus,
    ToolTier,
)


_MODEL_ID = "Wan-AI/Wan2.2-TI2V-5B"


class HuggingFaceVideo(BaseTool):
    name = "huggingface_video"
    version = "0.1.0"
    tier = ToolTier.GENERATE
    capability = "video_generation"
    provider = "huggingface"
    stability = ToolStability.EXPERIMENTAL
    execution_mode = ExecutionMode.SYNC
    determinism = Determinism.STOCHASTIC
    runtime = ToolRuntime.API

    dependencies = ["env:HF_TOKEN", "python:huggingface_hub"]
    install_instructions = (
        "Configure HF_TOKEN in the OpenMontage backend environment. "
        "Create a Hugging Face user access token with Inference Providers permission."
    )
    capabilities = ["text_to_video", "model_selection"]
    supports = {
        "text_to_video": True,
        "image_to_video": False,
        "offline": False,
        "local_gpu": False,
        "huggingface_routed": True,
    }
    best_for = ["short prompt-to-video clips without using the workstation GPU"]
    not_good_for = ["image-conditioned generation or free inference with no Hugging Face credits"]
    provider_matrix = {
        _MODEL_ID: {
            "name": "Wan 2.2 TI2V 5B (Hugging Face routed)",
            "model": _MODEL_ID,
            "provider": "fal-ai",
            "operations": ["text_to_video"],
            "resolution": "720p",
            "fps": 24,
            "aspect_ratio": "16:9",
            "default_duration_seconds": 2,
            "max_duration_seconds": 5,
        }
    }
    input_schema = {
        "type": "object",
        "required": ["prompt", "output_path"],
        "properties": {
            "prompt": {"type": "string"},
            "operation": {"type": "string", "enum": ["text_to_video"], "default": "text_to_video"},
            "model": {"type": "string", "enum": [_MODEL_ID], "default": _MODEL_ID},
            "duration_hint": {"type": "string", "enum": ["2s", "3s", "4s", "5s"], "default": "2s"},
            "num_frames": {"type": "integer", "minimum": 49, "maximum": 121},
            "negative_prompt": {"type": "string"},
            "guidance_scale": {"type": "number", "minimum": 1, "maximum": 10, "default": 5},
            "num_inference_steps": {"type": "integer", "minimum": 1, "maximum": 50, "default": 20},
            "seed": {"type": "integer"},
            "output_path": {"type": "string"},
        },
    }
    resource_profile = ResourceProfile(cpu_cores=1, ram_mb=512, vram_mb=0, disk_mb=500, network_required=True)
    retry_policy = RetryPolicy(max_retries=0)
    idempotency_key_fields = ["prompt", "model", "num_frames", "seed"]
    side_effects = ["sends prompt to Hugging Face Inference Providers", "writes video file to output_path"]
    user_visible_verification = ["Check the returned video artifact and playback"]

    def get_status(self) -> ToolStatus:
        if not os.environ.get("HF_TOKEN"):
            return ToolStatus.UNAVAILABLE
        try:
            import huggingface_hub  # noqa: F401
        except ImportError:
            return ToolStatus.UNAVAILABLE
        return ToolStatus.AVAILABLE

    def estimate_cost(self, inputs: dict[str, object]) -> float:
        # HF/provider rates vary by account, provider, and model. Do not present
        # a guessed price as an estimate; actual usage is tracked by HF.
        return 0.0

    def estimate_runtime(self, inputs: dict[str, object]) -> float:
        return 180.0

    def execute(self, inputs: dict[str, object]) -> ToolResult:
        token = os.environ.get("HF_TOKEN")
        if not token:
            return ToolResult(success=False, error="HF_TOKEN is not configured in the OpenMontage backend.")
        output_path = Path(str(inputs.get("output_path", ""))).resolve()
        if not str(inputs.get("output_path", "")):
            return ToolResult(success=False, error="output_path is required")
        try:
            from huggingface_hub import InferenceClient

            client = InferenceClient(provider="fal-ai", api_key=token, timeout=900)
            started = time.time()
            video_bytes = client.text_to_video(
                str(inputs["prompt"]),
                model=str(inputs.get("model") or _MODEL_ID),
                num_frames=int(inputs.get("num_frames") or 49),
                negative_prompt=[str(inputs["negative_prompt"])] if inputs.get("negative_prompt") else None,
                guidance_scale=float(inputs.get("guidance_scale") or 5),
                num_inference_steps=int(inputs.get("num_inference_steps") or 20),
                seed=inputs.get("seed"),
            )
            if not isinstance(video_bytes, (bytes, bytearray)) or not video_bytes:
                return ToolResult(success=False, error="Hugging Face returned an empty video response.")
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_bytes(video_bytes)
            return ToolResult(
                success=True,
                data={"output": str(output_path)},
                artifacts=[str(output_path)],
                duration_seconds=round(time.time() - started, 2),
                model=str(inputs.get("model") or _MODEL_ID),
                seed=int(inputs["seed"]) if inputs.get("seed") is not None else None,
            )
        except Exception as exc:
            return ToolResult(success=False, error=f"Hugging Face video generation failed: {exc}")
