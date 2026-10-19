# pcm_asr example

Plays six finalized Japanese segments of a shared two-speaker conversation
through `pcm_asr` three times (forward, forward, reversed), then the error
paths the contract promises, and prints one `PCM_ASR {json}` line per step.

```sh
python3 ../tool/prepare_example_segments.py <path to conversation_2speaker_14s_16k.mp3>
flutter run --release --dart-define=PCM_ASR_AUTOTEST=1
```

`--dart-define=PCM_ASR_SOAK=300` adds 300 back-to-back requests; on Windows
`PCM_ASR_WHISPER_MODEL`, `PCM_ASR_WHISPER_THREADS`, `PCM_ASR_WHISPER_GPU` and
`PCM_ASR_LOG_FILE` select the model and a log file. `tool/evaluate_example_log.py`
turns the log into a summary with the character error rate.
