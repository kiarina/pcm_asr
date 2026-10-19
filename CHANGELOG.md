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
