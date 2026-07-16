# Whisper Pro ASR (chunking, CPU-friendly)

This addon runs [ventura8/whisper-pro-asr](https://github.com/ventura8/Whisper-Pro-ASR) as a Home Assistant addon. It's an ASR (Automatic Speech Recognition) webservice built for Bazarr, with dynamic chunking of long media files to keep memory usage stable regardless of file length.

This image is marketed primarily for Whisper Large-V3 on GPU/NPU hardware, but the model is fully configurable via `ASR_MODEL` and works on CPU with smaller models like `small` or `tiny` using `int8` compute.

**Status: experimental.** This addon was built without direct access to the image's internals, so `run.sh` auto-detects the app's entry point at startup. If it fails to start, check the addon logs — they will show a filesystem listing to help pinpoint the correct path, which can then be hardcoded into `run.sh`.

## Installation

1. In Home Assistant, navigate to **Settings → Add-ons → Add-on Store**
2. Click on the **three dots** (top right) → **Repositories**
3. Add `https://github.com/Xornop/ha-addons`
4. Search for **Whisper Pro ASR** and install the addon

## Settings

| Setting | Default | Description |
|---|---|---|
| `ASR_MODEL` | `Systran/faster-whisper-small` | Faster-whisper model ID from HuggingFace. Use `Systran/faster-whisper-tiny` for lowest memory, `Systran/faster-whisper-small` for a good balance, or `Systran/faster-whisper-large-v3` for best quality (GPU recommended). |
| `ASR_DEVICE` | `CPU` | `AUTO`, `CPU`, or `CUDA`. |
| `ASR_COMPUTE_TYPE` | `int8` | `AUTO`, `int8`, `float16`, or `float32`. `int8` uses the least memory and is recommended for CPU. |
| `ASR_BEAM_SIZE` | `5` | Search breadth during decoding. Lower = faster/less memory, higher = more accurate. |
| `ASR_BATCH_SIZE` | `1` | Parallel segment batching. Keep at `1` for CPU/single-device stability. |
| `ENABLE_VOCAL_SEPARATION` | `false` | Vocal isolation preprocessing (UVR/MDX-NET). Disabled by default to save memory on CPU-only systems. |
| `ENABLE_LD_PREPROCESSING` | `true` | Language detection preprocessing. |
| `DEBUG` | `false` | Enable verbose logging. |

## Configuring Bazarr

1. Open Bazarr → **Settings → Providers**
2. Add the **Whisper** provider (or "whisper-asr-webservice" if listed — this image is API-compatible)
3. Set the **endpoint** to:
   ```
   http://<your-HA-ip>:9000
   ```
4. Set timeouts very high (e.g. `54000` seconds) for long movies
5. Enable **"Pass video filename to Whisper"** if you want path-based volume mapping to work (only applies if Bazarr and this addon share identical media paths, which is unlikely in a typical HA addon setup — in that case it automatically falls back to receiving the uploaded audio from Bazarr, same as SubGen/whisper-asr-webservice)
6. Save

## Notes

- Model cache persists across restarts via `/data/model_cache` (mapped from the addon's persistent storage).
- On first start, the addon downloads the selected model. This may take a while depending on model size.
- This is a third-party image not affiliated with SubGen or the official whisper-asr-webservice project. Behavior and stability are less established — treat this as an experiment, especially for very long files.
- If the addon fails to start, check the logs for the filesystem listing that `run.sh` prints, find where `whisper_server.py` (or equivalent) actually lives, and update the `candidate` paths in `run.sh` accordingly.
