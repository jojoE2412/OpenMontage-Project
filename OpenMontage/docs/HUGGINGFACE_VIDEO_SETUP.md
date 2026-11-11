# Hugging Face video generation

OpenMontage routes short text-to-video requests through Hugging Face Inference
Providers (currently the `fal-ai` route) using the `huggingface_hub` client.
The token is read only by the backend from `HF_TOKEN`; it is never sent from or
stored in the Flutter app.

## Configure the backend

Create a Hugging Face user access token with the **Inference Providers**
permission, then set it in the OpenMontage backend environment before starting
the API server. For a local checkout, put this line in `OpenMontage/.env`:

```dotenv
HF_TOKEN=hf_your_token_here
```

Restart the backend after changing the environment. The provider appears as
available in the mobile app only when both the token and `huggingface_hub` are
available to the backend. Keep `.env` private and do not paste the token into
Flutter settings, project prompts, or issue reports.

Install the backend requirements in the environment that runs the API:

```powershell
python -m pip install -r requirements.txt
```

## Current mobile limits

The mobile route currently advertises `Wan-AI/Wan2.2-TI2V-5B` for text-to-video
only. It accepts 2–5 second clips (49–121 frames at the model's 24 FPS), with
provider-supported guidance, inference steps, negative prompt, and seed. The
model route targets 720p; aspect ratio and output dimensions are not exposed as
controls because this routed task contract does not provide those parameters.
Image-to-video is not advertised by this mobile provider route yet.

Hugging Face Free currently includes no monthly Inference Providers credits.
Usage can require purchased credits or an eligible paid plan, and charges depend
on the model/provider and request. OpenMontage does not set an account spending
limit; check Hugging Face's billing and usage pages before generating.

References: [Hugging Face text-to-video task](https://huggingface.co/docs/inference-providers/tasks/text-to-video),
[Inference Providers pricing](https://huggingface.co/docs/inference-providers/pricing).

## Local GPU on 4 GB cards

The local runtime includes a CogVideoX 2B preset for cards reporting 4 GB VRAM:
480x320 output, 8 FPS, and 2/4/6 second choices (17/33/49 frames). Diffusers
documents less than 4 GB peak VRAM with sequential CPU offload. This preset uses
that offload strategy and a smaller output, but actual available VRAM depends on
driver/display use; rendering can be very slow. The backend enables this route
only when CUDA and model dependencies are available. Other local models retain
their higher VRAM requirements and are blocked when the detected GPU does not
meet them.

For the local route, install the GPU dependencies (`requirements-gpu.txt` plus
`diffusers`, `transformers`, and `accelerate`) in the backend environment and
set `VIDEO_GEN_LOCAL_ENABLED=true`. Restart the backend, then check the runtime
card in the app; it reports the selected model's VRAM compatibility and CUDA
readiness.

Reference: [Diffusers CogVideoX memory table](https://huggingface.co/docs/diffusers/main/api/pipelines/cogvideox).
