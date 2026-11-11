# OpenMontage Mobile Backend API — Phase 1

Base path: `/api`. JSON is UTF-8. Project, asset, job, and artifact metadata is stored in SQLite; media files use each project's OpenMontage workspace. The database path can be set with `OPENMONTAGE_MOBILE_DB`; otherwise it is `~/.openmontage/mobile/mobile.sqlite3`.

Run from the OpenMontage repository root with `python -m uvicorn backend.app:app --host 0.0.0.0 --port 8001`. The Android emulator can reach the development host through Flutter's default `http://10.0.2.2:8001` base URL. A physical Android phone cannot use `10.0.2.2`; build/run it with `flutter run --dart-define=BACKEND_URL=http://<development-computer-LAN-IP>:8001` while both devices are on the same network and the host firewall allows inbound TCP port 8001. `BACKEND_URL` is a compile-time Flutter setting and uses the emulator URL when it is omitted. Check `GET /api/health` from the phone browser first. Project creation logs a safe started/completed/failure marker in the Uvicorn terminal to distinguish an unreachable request from a stalled storage operation.

The mobile API executes operations only when the corresponding OpenMontage tools and schema operations are available. It supports `video_generation:generate`, `image_generation:generate`, `tts:generate`, `music_generation:generate`, and `analysis:transcribe` through the selected available provider tool; `video_post:trim` and `video_post:speed` through `video_trimmer`; `video_post:crop` through `auto_reframe`; `video_post:burn_subtitles` through `video_compose`; and project `video_post:render` through `video_stitch`. It also supports `enhancement:color_grade`, `enhancement:upscale`, plus `audio_processing:enhance`, `audio_processing:volume`, and `audio_processing:trim` only when their registered tools and schemas are available. Music jobs take the provider ID and prompt plus only schema-supported duration, model, instrumental, style, title, and format inputs; output is validated as playable audio and saved as an audio artifact in the project. Pipeline job requests have a reserved contract and return `501` until an actual pipeline executor exists. The older `/api/videos` endpoints remain documented as legacy synthetic compose demo routes.

Local LTX diagnostics use the resource profile declared by `ltx_video_local` and host GPU/VRAM/CUDA facts. The diagnostics do not load a model; mobile generation jobs are accepted only when the selected registry tool reports available and the selected model supports the requested mode.

## Health

### `GET /api/health`

Response `200`:

```json
{"status":"ok","api_version":"1.0.0"}
```

## Runtime discovery

### `GET /api/capabilities`

Returns capability groups from `tools.tool_registry.registry.capability_catalog()`. Each item reports the registered tools, live availability, operations, schemas, artifact contract, provider/model metadata, and `mobile_job_operations` that this API actually executes. `video_post` lists trim/speed only when the available `video_trimmer` schema declares those operations, and crop when available `auto_reframe` declares target aspect presets. `enhancement` lists `color_grade` only when its tool and profile schema are available. `audio_processing` lists `enhance` only when `audio_enhance` and its preset schema are available, and `volume` only when `audio_mixer` declares mix and a bounded per-track volume field.

### `GET /api/providers?capability={capability_id}`

Returns provider tool contracts discovered from the OpenMontage registry, optionally filtered by top-level capability. Only public execution contracts are exposed; server filesystem paths and configuration values are omitted.

### `GET /api/models?capability={capability_id}&provider={provider_id}&tool={tool_id}`

Returns models advertised by each matching provider's `provider_matrix` or declared input schema. Availability remains attached to the provider tool, so the client can distinguish configured, unavailable, and unsupported choices instead of assuming every listed model can run.

### `GET /api/runtime/hardware`

Returns detected CPU, logical core count, RAM, NVIDIA GPU/VRAM, CUDA availability, and the local LTX readiness assessment against the tool's declared VRAM requirement. CUDA facts are reported as unavailable if PyTorch is missing; no model is loaded by this endpoint.

## Projects

### `POST /api/projects`

Request:

```json
{"name":"Product edit"}
```

Response `201`: project `id`, `name`, `created_at`, `updated_at`, `assets_url`. The server-owned `workspace_path` is never returned.

Errors: `422` for an empty or over-120-character name.

### `GET /api/projects`

Response `200`: `{"items":[Project...]}`.

### `GET /api/projects/{project_id}`

Response `200`: project object. Error `404` when absent.

## Assets

### `POST /api/projects/{project_id}/assets?filename={filename}`

Upload a **raw media byte stream** with `Content-Type: application/octet-stream` (or the media type matching the extension). Supported video extensions: `.mp4`, `.mov`, `.m4v`, `.mkv`, `.webm`, `.avi`; audio: `.mp3`, `.wav`, `.m4a`, `.aac`, `.flac`, `.ogg`, `.opus`; images: `.jpg`, `.jpeg`, `.png`, `.webp`. Video and audio are validated with FFprobe; images are validated with Pillow and limited to 100 megapixels. Maximum upload size: 500 MiB. The backend generates its own storage name; client filesystem paths are not accepted.

Response `201`: asset metadata (`id`, `project_id`, `name`, `type`, `mime_type`, `size`, `duration`, `metadata`, `created_at`, `file_url`). Local filesystem path is omitted.

Errors: `400` empty/malformed upload; `404` project absent; `413` over size limit; `415` unsupported extension or invalid media; `422` unsafe filename; `503` FFprobe or Pillow is unavailable on the backend host.

### `GET /api/projects/{project_id}/assets`

Response `200`: `{"items":[Asset...]}`. Error `404` when project is absent.

### `GET /api/assets/{asset_id}/file`

Response `200`: original uploaded media bytes. Error `404` for missing metadata/file or a file outside its project workspace.

## Jobs

### `POST /api/projects/{project_id}/jobs`

Capability trim request:

```json
{
  "type":"capability",
  "capability":"video_post",
  "operation":"trim",
  "project_id":"project-id",
  "input_asset_ids":["asset-id"],
  "parameters":{"start":0.5,"end":8.0}
}
```

`start` is seconds from the beginning, `end` is the exclusive ending time in seconds and must be greater than `start` and no greater than the uploaded video's duration. Exactly one video asset from the project is required.

Response `202`: generic Job object with `id`, `project_id`, `type`, `capability`, `operation`, `status`, `progress`, `current_step`, timestamps, `error`, `input`, and `output_artifact_ids`.

Video generation uses the same endpoint with `capability="video_generation"`, `operation="generate"`, and parameters `provider_tool_id`, `prompt`, `mode` (`text_to_video` or `image_to_video`), `aspect_ratio`, `duration_seconds`, and optional schema-supported `model_id`, `seed`, `width`, `height`, and `num_frames`. Text-to-video accepts no input assets. Image-to-video accepts one project image asset in `input_asset_ids`, or a same-project image artifact ID as `reference_artifact_id`. The backend invokes the selected OpenMontage registry tool and creates a video artifact from its real output. An unavailable provider returns `503` with `provider_not_configured`; an execution failure marks the job `failed` with `generation_failed`.

Image generation uses `capability="image_generation"`, `operation="generate"`, and parameters `provider_tool_id`, `prompt`, plus optional schema-supported negative prompt, model, aspect ratio, resolution, dimensions, and seed. Image editing may include exactly one same-project image asset or image artifact as a reference when the selected provider schema supports image inputs. The backend invokes the selected OpenMontage registry tool, validates its output as an image, and creates a downloadable image artifact. An unavailable provider returns `503` with `provider_not_configured`; an execution failure marks the job `failed` with `generation_failed`.

TTS uses `capability="tts"`, `operation="generate"`, and a selected OpenMontage TTS provider ID with narration text. Model, voice, language, speed, and output format are forwarded only when declared in the provider input schema. The completed playable audio file is validated and stored as a project audio artifact. An unavailable provider returns `503` with `provider_not_configured`; an execution failure marks the job `failed` with `generation_failed`.

Transcription uses `capability="analysis"`, `operation="transcribe"`, one project audio or video asset, and the selected available OpenMontage transcriber tool. Model size, language, and diarization settings follow the tool schema. Its structured JSON output is saved as a project `transcript` artifact; Subtitle Studio can load its timed segments for review and SRT/VTT generation.

Upscale uses `capability="enhancement"`, `operation="upscale"`, one same-project image or video asset, and the selected OpenMontage `upscale` tool. Scale and model follow the tool schema. The real image or video output is validated and saved as a typed project artifact. An unavailable Real-ESRGAN runtime keeps the UI action disabled; no replacement output is synthesized.

Status lifecycle: `queued` → `running` → `completed` or `failed`. Progress is stage-level (0, 25, 50, 75, 100), not a claim of exact FFmpeg frame progress.

Errors: `404` project/asset absent or asset belongs to another project; `422` invalid request/range or unsupported capability/operation; `501` pipeline job execution is not implemented in Phase 1.

Speed adjustment uses the same endpoint and lifecycle with `operation="speed"` and `parameters={"speed_factor":2.0}`. `speed_factor` follows the source schema bounds of `0.1` to `100`; clients should expose a narrower practical range.

Project render uses `capability="video_post"`, `operation="render"`, and 2–30 `input_asset_ids` that belong to that project and are video assets. Optional parameters are `transition` (`cut`, `crossfade`, or `fade`), `transition_duration` (0.1–5 seconds), `auto_normalize`, `target_resolution`, and `target_fps`. The adapter calls OpenMontage `video_stitch` with FFmpeg and stores a playable MP4 video artifact. Clip order follows the supplied asset ID order. `mobile_job_operations` exposes render only when the registered `video_stitch` schema declares `stitch` and the tool is available.

Subtitle burn uses `capability="video_post"`, `operation="burn_subtitles"`, exactly one project video asset, and `parameters={"subtitle_artifact_id":"..."}` pointing to a subtitle artifact in the same project. It invokes OpenMontage `video_compose` with `operation="burn_subtitles"` and creates a playable MP4 artifact. It requires the registered tool to expose that operation; FFmpeg must also include its subtitles/libass filter at runtime. This operation burns an existing SRT/VTT artifact and does not perform transcription.

Color grading uses `capability="enhancement"`, `operation="color_grade"`, and parameters `profile` and optional `intensity` (0 to 1). The profile must be declared by the currently available OpenMontage `color_grade` schema. The adapter calls that tool and stores a video artifact in the same project/job relationship.

Audio enhancement uses `capability="audio_processing"`, `operation="enhance"`, and a `preset` declared by the available OpenMontage `audio_enhance` schema. The adapter stores a typed audio artifact in the project/job relationship.

Volume adjustment uses `capability="audio_processing"`, `operation="volume"`, and `parameters={"volume":0.5}` (0–1 as declared by the OpenMontage mixer schema). It calls `audio_mixer` with one source track and stores the result as a WAV audio artifact.

Audio trimming uses `capability="audio_processing"`, `operation="trim"`, and `parameters={"start_seconds":0.5,"end_seconds":4.0}`. The backend validates the range against the uploaded audio duration, calls the OpenMontage `audio_mixer` trim operation, and stores a WAV audio artifact with the trim range in metadata.

Video crop/reframe uses `capability="video_post"`, `operation="crop"`, and a `target_aspect` preset from the available OpenMontage `auto_reframe` schema. It calls that tool, preserving its center/face-tracked behavior and writes a typed video artifact attached to the source project/job.

Manual subtitle formatting uses `capability="subtitle"`, `operation="generate"`, an `srt` or `vtt` format, and timed `{text,start,end}` segments. It requires no input asset, calls OpenMontage `subtitle_gen`, and stores a `subtitle` artifact. This formats user-provided timed cues; it does not claim to transcribe media. `mobile_job_operations` exposes it only when the registry reports the tool and both formats available.

Trim maps to the OpenMontage trimming implementation; speed maps to `video_trimmer` with `input_path`, `output_path`, `speed_factor`, and `codec="libx264"`. Every enabled operation creates an artifact attached to the project and job.

### `GET /api/jobs/{job_id}`

Response `200`: Job object. Error `404` if missing.

### `POST /api/jobs/{job_id}/cancel`

Cancels a queued job if the executor has not started it. Response `200`: updated Job. Error `404` if absent; `409` if already terminal or currently running (the OpenMontage tool invocation is synchronous and cannot safely be interrupted).

### `GET /api/jobs/{job_id}/artifacts`

Response `200`: `{"items":[Artifact...]}`. Artifact metadata has `id`, `project_id`, `job_id`, `type`, `mime_type`, `size`, `metadata`, `created_at`, and `download_url`; local path is omitted. Error `404` if job is absent.

## Artifacts

### `GET /api/artifacts/{artifact_id}/file`

Response `200`: artifact bytes with its recorded MIME type. Error `404` if missing or outside its project workspace.

## Legacy endpoints

`POST /api/videos`, `GET /api/videos/{job_id}`, and `GET /api/videos/{job_id}/file` are deprecated. They remain for existing callers and continue to run the synthetic local compose demonstration, not AI video generation. New integrations should use project, asset, and job endpoints above.
