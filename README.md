# pcm_asr (working name, not published)

Final transcription of **finalized PCM segments** with the OS speech engine.
The caller owns the microphone, the voice activity detection and the speaker
handling; this plugin turns one finished segment into final text and hands the
caller's request ID back with it. It never records.

```dart
final asr = const PcmAsr();
final support = await asr.support(locale: 'ja-JP');   // read every field, not just `supported`
if (!support.supported) return;                       // e.g. Web outside desktop Chrome/Edge
await asr.prepare(                                    // may download a model (OS asset, Android pack, whisper weights)
  locale: 'ja-JP',
  onProgress: (p) => print(p),                        // download / install / load / warmup
);
final result = await asr.transcribe(TranscribeRequest(
  id: 'segment-12',                                   // comes back unchanged: bind it to your own segment / speaker
  locale: 'ja-JP',
  audio: PcmSegment(pcm16le: bytes, sampleRate: 16000, channels: 1),
  timeout: const Duration(seconds: 20),
));
print('${result.id}: ${result.text} (${result.elapsed.inMilliseconds} ms, ${result.engine})');
await asr.dispose();
```

Where the audio goes: Apple, Android (on-device recognizer) and Windows keep it on
the device; the Web sends it to the browser vendor's speech service (`support.onDevice`
says which). No platform needs the microphone permission for this package; the
caller records.

Platform setup:

- **macOS / iOS**: nothing beyond macOS 26 / iOS 26. No `NSSpeechRecognitionUsageDescription`
  is needed for SpeechAnalyzer (it never sends audio to Apple). Not available in the iOS Simulator.
- **Android**: API 33+. No `RECORD_AUDIO`. The on-device recognizer must have the language installed;
  `prepare()` triggers the download and reports progress.
- **Web**: desktop Chrome/Edge 135+. Nothing to configure; cloud recognition.
- **Windows**: Visual Studio C++ tools (CMake 3.24+ for the source fetch). The first build downloads the pinned
  whisper.cpp sources and builds them under `%LOCALAPPDATA%\pcm_asr` (`PCM_ASR_WORK` moves it); install the
  Vulkan SDK (`VULKAN_SDK` set when building) for the GPU backend, `PCM_ASR_VULKAN=0` for a CPU-only DLL.
  An app that already builds its own whisper.cpp (for example through another plugin) cannot build this one
  next to it: the CMake targets `whisper` and `ggml` would be defined twice.
  The first `prepare()` downloads the model (574 MB for large-v3-turbo q5_0, 488 MB for small);
  `support().modelBytes` says how much before you start.

## Contract

- Input: interleaved signed 16-bit little-endian PCM, any sample rate the
  engine accepts (16 kHz mono is the reference input; Apple and the Windows
  whisper backend convert other rates, Android and Web require 16 kHz mono).
- One request, one final result. No partial results, no microphone.
- One locale per request, chosen by the caller: no platform detects the language. Apple's `SpeechTranscriber`
  is built for one locale (the macOS 27 SDK has no language-identification module), and the Windows backend
  rejects `auto` (`unsupportedLocale`) although whisper.cpp itself could detect. To transcribe speech in
  another language, pass that language's locale.
- `RecognitionSupport` reports separately whether the engine exists, takes
  external PCM, runs on the device, whether its model is installed,
  downloadable or unavailable, and how large the download would be when the
  engine knows (`modelBytes`; Windows whisper weights are 488 MB to 1.6 GB). `supported == true` only means a request for
  that locale can succeed once `prepare` has completed.
- Errors are `PcmAsrException` with a stable `PcmAsrErrorCode`:
  `unsupportedPlatform`, `unsupportedLocale`, `modelUnavailable`,
  `invalidPcm`, `timeout`, `cancelled`, `engineFailure`.
- `cancel(id)` stops one request; `dispose()` stops all and releases the
  engine. `TranscribeRequest.timeout` cancels natively when it passes.

## Platforms (state of the lab, 2026-10-19)

| Platform | Engine | On device | Notes |
| --- | --- | --- | --- |
| macOS 26+ | `SpeechAnalyzer` + `SpeechTranscriber` | yes | one analyzer per request, `finalizeAndFinish`; model assets managed by the OS |
| iOS 26+ | same (shared `darwin/` source) | yes | needs hardware that reports `SpeechTranscriber.isAvailable`; no Simulator |
| Android 13+ (API 33) | `android.speech.SpeechRecognizer` fed by a pipe (`EXTRA_AUDIO_SOURCE`) | when the device has an on-device recognizer | verified on a Pixel 6; PCM is written as fast as the pipe accepts (a lab knob restores real-time pace); a 0.6 s silent tail is appended; `stopListening` is never called |
| Web | `SpeechRecognition.start(MediaStreamTrack)` | no (cloud, unless the user installed Chrome's language pack) | desktop Chrome/Edge 135+ only; audio goes to the browser vendor's servers |
| Windows 10/11 x64 | whisper.cpp inside the package (`PcmAsrWindows`, dart:ffi; Vulkan GPU when built with the Vulkan SDK and a device exists, else CPU with AVX2) | yes | no OS engine takes external PCM for Japanese, so `prepare()` fetches a pinned ggml model from Hugging Face into the app's support directory. Default model: large-v3-turbo q5_0 (574 MB) on a Vulkan GPU, small (488 MB) on the CPU; override with `PcmAsrWindows.model`. whisper.cpp itself is fetched and built by the plugin's CMake (see setup below) |

Measured on the lab's six-segment Japanese fixture (request → final result, median):

| Platform | Engine | CER | Median |
| --- | --- | ---: | ---: |
| macOS 27, M1 Max | SpeechAnalyzer | 0 % | 99 ms |
| iOS 27, iPad Air 4 | SpeechAnalyzer | 0 % | 117 ms |
| Android 17, Pixel 6 | on-device SpeechRecognizer | 4.7 % | 458 ms |
| Web, Chrome 155 (cloud) | SpeechRecognition | 5.8 % | 3.4 s |
| Windows 11, RTX 3080 Ti (Vulkan) | whisper.cpp large-v3-turbo q5_0 | 0 % | 95 ms |
| Windows 11, i9-12900K (CPU, 8 threads) | whisper.cpp small | 7.0 % | 1.36 s |

Evidence and the full tables: `labs/2026/10/19/flutter-pcm-asr-plugin`.
