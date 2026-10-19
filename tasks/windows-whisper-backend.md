# Windows: whisper.cpp をパッケージの内部で動かす

## 目的と完了条件

Windows では OS の音声認識器で日本語の外部 PCM が成立しない（labs `2026/10/19/flutter-pcm-asr-plugin/research/windows.md`）。
そこで Windows だけ、pcm_asr の内部で whisper.cpp を動かし、同じ契約（`support` / `prepare` / `transcribe` / `cancel` / `dispose`）で
日本語の最終文字を返す（オーナーの決定、2026-10-19）。

完了条件: Windows の実機（開発機の G-GEAR、Core i9-12900K、Windows 11 25H2）で、lab と同じ 6 区間 × 3 パスの通しが通り、
base・small・large-v3-turbo の 3 つの速さと誤り率を並べて既定のモデルを決め、`support()` が
`engine: whisper.cpp`・`on_device: true`・`model_state` を正しく返すこと。

## やること

- [ ] `windows/` を `ffiPlugin: true` で足す（Apple・Android の MethodChannel と混在）。whisper.cpp の取り込み方は Spirits Garden の
  `prototypes/spirits/packages/whisper_cpp`（labs `2026/10/18/flutter-realtime-audio-analysis/packages/whisper_cpp` 由来、v1.9.5、CMake、CPU）を参考に、
  この repo が所有する形で写す。sibling import しない
- [ ] 重みの取得: `prepare(locale)` で Hugging Face `ggerganov/whisper.cpp` の ggml ファイルを hash を固定して取り、アプリの support dir に置く。
  `support()` は取得前なら `downloadable`、取得後なら `installed`。`needs_network_for_model: true`
- [ ] `transcribe`: PCM16 → float、`language=ja`、greedy、`no_context`、temperature 0。1 要求ずつ直列。`cancel` は whisper の abort callback で止める
- [ ] 3 モデルの実測（lab の `tools/evaluate.py` と同じ判定）: base（142 MB）、small（466 MB）、large-v3-turbo（f16 約 1.6 GB と q5_0 約 550 MB）。
  要求→確定の中央値・p95・最初、CER、モデルのロード時間、メモリ。連続した会話で要求が溜まらない速さかを見る
- [ ] 既定のモデルを決め、`support()` の `engine` にモデル名を含めるか決める（例: `whisper.cpp/small`）
- [ ] README の対応表と AGENTS.md を更新。利用者の `flutter build` に Visual Studio の C++ ツールが要ることを書く

## 参照

- Mac の small の実測（Metal、CER 7 %、中央値 144 ms）: labs `2026/10/19/apple-speech-scd-asr/README.md`
- Windows の CPU で whisper を動かした実例: labs `2026/10/18/flutter-realtime-audio-analysis`（README の Windows の欄）
- Windows の PC でビルドする型（対話タスク、plugin の symlink の罠）: agent `docs/playbooks/multi-machine-agent-orchestration.md`
