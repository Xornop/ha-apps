# SubGen - Whisper Subtitles for Bazarr

This addon runs [SubGen](https://github.com/McCloudS/subgen) as a Home Assistant addon. SubGen uses the OpenAI Whisper model to automatically generate subtitles, and provides an ASR API that Bazarr can use.

## Installation

1. In Home Assistant, navigate to **Settings → Add-ons → Add-on Store**
2. Click on the **three dots** (top right) → **Repositories**
3. Add the URL of your GitHub repository where you placed this addon
4. Search for **SubGen** and install the addon

## Settings

| Setting | Default | Description |
|---|---|---|
| `whisper_model` | `small` | Whisper model. Larger = more accurate but slower. Choose `small` or `medium` for CPU. |
| `transcribe_device` | `cpu` | Use `cpu` (always available) or `cuda` (only with Nvidia GPU) |
| `concurrent_transcriptions` | `1` | Number of files processed simultaneously. Keep at `1` for CPU. |
| `whisper_threads` | `4` | Number of CPU threads. Set to the number of cores of your system. |
| `transcribe_or_translate` | `transcribe` | `transcribe` = subtitles in original language. `translate` = always to English. |
| `debug` | `false` | Enable verbose logging. |

## Configuring Bazarr

1. Open Bazarr → **Settings → Providers**
2. Add the **Whisper** provider
3. Set the **endpoint** 
For example: `http://192.168.1.10:9000`
4. Set the **timeout** to at least `120` seconds (or more for long movies)
5. Save

### Lowering the minimum score in Bazarr

Whisper subtitles have a fixed score that is standardly just too low to be downloaded automatically. Lower the minimum score in Bazarr:
- Series: set to **220** or lower (from 360)
- Movies: set to **60** or lower (from 180)

## Model Selection Advice

| Model | Speed (CPU) | Quality | Recommended for |
|---|---|---|---|
| `tiny` | Very fast | Fair | Testing |
| `base` | Fast | Decent | Fast systems |
| `small` | Medium | Good | **Default recommended** |
| `medium` | Slow | Very good | More powerful systems |
| `large-v3` | Very slow | Excellent | Only with GPU |

## Notes

- The first time the addon starts, it downloads the chosen Whisper model. This may take a while.
- The model is stored in `/data/models` and persists after a restart.
- SubGen only processes files that Bazarr offers through the ASR API — it does not scan directories on its own.
