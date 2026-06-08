# Whisper ASR Webservice

This addon runs [whisper-asr-webservice](https://github.com/ahmetoner/whisper-asr-webservice) as a Home Assistant addon. It uses OpenAI Whisper to automatically generate subtitles, and provides an ASR API that Bazarr can use as a subtitle provider.

Key advantage over SubGen: audio is processed in **chunks**, keeping memory usage low and constant regardless of file length. This makes it suitable for long films on low-memory systems.

No API keys, no cloud, no cost — everything runs locally on your Home Assistant machine.

DO NOT COMPLAIN IF IT FAILS - YOU PROBABLY RAN OUT OF RAM - TESTED WITH 16GB RAM, WORKS WITH MOVIES LESS THAN 1 HOURS RUNTIME ON MODEL SMALL-INT8

## Installation

1. In Home Assistant, navigate to **Settings → Add-ons → Add-on Store**
2. Click on the **three dots** (top right) → **Repositories**
3. Add `https://github.com/Xornop/ha-addons`
4. Search for **Whisper ASR Webservice** and install the addon

## Settings

| Setting | Default | Description |
|---|---|---|
| `ASR_MODEL` | `small` | Whisper model size. Larger = more accurate but slower. `small` or `medium` recommended for CPU. |
| `ASR_ENGINE` | `faster_whisper` | Backend engine. `faster_whisper` is recommended for CPU (faster and less memory than `openai_whisper`). |
| `ASR_COMPUTE_TYPE` | `int8` | Compute precision. `int8` uses least memory and is fastest on CPU. |
| `WHISPER_LANG` | `ja` | Source audio language code (e.g. `ja` for Japanese, `en` for English). Used when task is `transcribe`. |
| `WHISPER_TASK` | `translate` | `transcribe` = subtitles in original audio language. `translate` = always translate to English. |
| `ASR_PORT` | `9001` | Port the ASR webservice listens on. Use this port in Bazarr. |

## Configuring Bazarr

1. Open Bazarr → **Settings → Providers**
2. Add the **Whisper** provider
3. Set the **endpoint** to:
   ```
   http://<your-HA-ip>:9001
   ```
4. Set the **Connection/response timeout** to at least `60` seconds
5. Set the **Transcription/translation timeout** to at least `14400` seconds (4 hours, for long films)
6. Save

## Model selection advice

| Model | CPU Speed | Quality | Recommended for |
|---|---|---|---|
| `tiny` | Very fast | Poor | Testing only |
| `base` | Fast | Fair | Fast systems |
| `small` | Medium | Good | **Good balance** |
| `medium` | Slow | Very good | **Best for accuracy** |
| `large-v3` | Very slow | Excellent | GPU only |

## Notes

- On first start, the addon downloads the selected Whisper model. This may take a few minutes.
- The model is stored in `/data/models` and persists across restarts.
- This addon runs on port `9001` by default to avoid conflicts with SubGen (port `9000`).
- All processing happens locally. No data is sent to external servers.
- Audio is processed in chunks, so memory usage stays low even for very long films.
