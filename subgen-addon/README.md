# SubGen - Whisper Subtitles for Bazarr

This addon runs [SubGen](https://github.com/McCloudS/subgen) as a Home Assistant addon. SubGen uses the OpenAI Whisper model to automatically generate subtitles, and provides an ASR API that Bazarr can use.

No API keys, no cloud, no cost — everything runs locally on your Home Assistant machine.

## Installation

1. In Home Assistant, navigate to **Settings → Add-ons → Add-on Store**
2. Click on the **three dots** (top right) → **Repositories**
3. Add `https://github.com/Xornop/ha-addons`
4. Search for **SubGen** and install the addon

## Settings

| Setting | Default | Description |
|---|---|---|
| `WHISPER_MODEL` | `small` | Whisper model size. Larger = more accurate but slower. `small` or `medium` recommended for CPU. |
| `TRANSCRIBE_DEVICE` | `cpu` | `cpu` (always available) or `cuda` (Nvidia GPU only) |
| `CONCURRENT_TRANSCRIPTIONS` | `1` | Number of files processed simultaneously. Keep at `1` for CPU. |
| `WHISPER_THREADS` | `4` | Number of CPU threads. Set to your CPU core count. |
| `TRANSCRIBE_OR_TRANSLATE` | `translate` | `transcribe` = subtitles in original audio language. `translate` = always translate to English. |
| `WEBHOOKPORT` | `9000` | Port the ASR webservice listens on. Use this port in Bazarr. |
| `SKIP_LANGUAGE_DETECT` | `true` | Skip automatic language detection. Recommended when using `translate` mode, prevents incorrect language detection on short audio samples. |
| `DEBUG` | `false` | Enable verbose logging. |

## Configuring Bazarr

1. Open Bazarr → **Settings → Providers**
2. Add the **Whisper** provider
3. Set the **endpoint** to:
   ```
   http://<your-HA-ip>:9000
   ```
   For example: `http://192.168.1.10:9000`
4. Set the **Connection/response timeout** to at least `60` seconds
5. Set the **Transcription/translation timeout** to at least `14400` seconds (4 hours, for long films)
6. Save

### Lowering the minimum score in Bazarr

Whisper subtitles have a fixed score that may be below Bazarr's default threshold, causing them to be skipped during automatic searches. Lower the minimum score:

- Go to **Settings → Sonarr** and/or **Settings → Radarr**
- Set **Minimum Score** to `60%` or lower

### Adaptive search throttling

If Bazarr repeatedly fails to find subtitles (e.g. due to crashes), it may throttle and stop searching for a while. To bypass this temporarily:

- Go to **Settings → Subtitles → Performance / Optimization**
- Disable **Adaptive Searching**, search manually, then re-enable it

## Model selection advice

| Model | CPU Speed | Quality | Recommended for |
|---|---|---|---|
| `tiny` | Very fast | Poor | Testing only |
| `base` | Fast | Fair | Fast systems |
| `small` | Medium | Good | **Good balance** |
| `medium` | Slow | Very good | **Default recommendation** |
| `large-v3` | Very slow | Excellent | GPU only |

## Notes

- On first start, SubGen downloads the selected Whisper model from HuggingFace. This may take a few minutes depending on your internet connection and model size.
- The model is stored in `/data/models` and persists across restarts.
- SubGen only processes files that Bazarr sends via the ASR API — it does not scan your media library directly.
- All processing happens locally. No data is sent to external servers.
- When using `translate` mode, it is recommended to enable `SKIP_LANGUAGE_DETECT` to avoid incorrect language detection on short or music-heavy audio samples.
