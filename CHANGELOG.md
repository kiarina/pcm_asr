## 0.1.2

- Windows: the pinned whisper.cpp sources are fetched at configure time (SHA-256 verified) when
  `third_party/whisper.cpp` is absent, so a pub.dev user needs no manual step; whisper is built
  outside the app's build tree (`%LOCALAPPDATA%\pcm_asr`, or `PCM_ASR_WORK`) so the Vulkan shader
  generator no longer exceeds MAX_PATH from a deep Flutter build directory. `PCM_ASR_VULKAN=0`
  forces a CPU-only DLL.
- `RecognitionSupport.modelBytes`: the size of the download `prepare()` would start, when known.
- Apple: `needsNetworkForModel` is false once the asset is installed.

## 0.1.1

- Same sources as 0.1.0; the 0.1.0 archive accidentally contained local build outputs (28 MB). Use 0.1.1.

## 0.1.0

First release.

- One contract on every platform: `support()` (engine, on-device, model state, download size), `prepare()` (with progress), `transcribe()` of one finalized
  PCM16 segment returning the final text with the caller's request id, `cancel()`, `dispose()`.
- macOS 26+ and iOS 26+: Apple SpeechAnalyzer, on device.
- Android 13+: `SpeechRecognizer` fed through a pipe (`EXTRA_AUDIO_SOURCE`), on device where the device has an
  on-device recognizer; no `RECORD_AUDIO` permission.
- Web: `SpeechRecognition.start(MediaStreamTrack)` in desktop Chrome/Edge 135+ (cloud recognition).
- Windows: whisper.cpp inside the package; large-v3-turbo q5_0 on a Vulkan GPU, small on the CPU; models
  downloaded by `prepare()` and verified by SHA-256.
