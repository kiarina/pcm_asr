# Windows: whisper.cpp をパッケージの内部で動かす

## 目的と完了条件

Windows では OS の音声認識器で日本語の外部 PCM が成立しない（labs `2026/10/19/flutter-pcm-asr-plugin/research/windows.md`）。
そこで Windows だけ、pcm_asr の内部で whisper.cpp を動かし、同じ契約（`support` / `prepare` / `transcribe` / `cancel` / `dispose`）で
日本語の最終文字を返す（オーナーの決定、2026-10-19）。

完了条件: Windows の実機（開発機の G-GEAR、Core i9-12900K、Windows 11 25H2）で、lab と同じ 6 区間 × 3 パスの通しが通り、
base・small・large-v3-turbo の 3 つの速さと誤り率を並べて既定のモデルを決め、`support()` が
`engine: whisper.cpp`・`on_device: true`・`model_state` を正しく返すこと。

## 現在地（2026-10-19）

実装して G-GEAR で通した。結果は labs `2026/10/19/flutter-pcm-asr-plugin/README.md`「Windows: パッケージ内の whisper.cpp」。
既定（GPU → large-v3-turbo q5_0、CPU → small、8 スレッド、暖機、無音の番人）は入れて auto で確認した（CER 0 %、中央値 95 ms、最初 103 ms）。

残り:

- [ ] GPU の無い PC での CPU の fallback（`gpuAvailable == false` → small）を実機で確かめる。G-GEAR には GPU があり未確認
- [ ] 暖機の効果を cold（ドライバーのシェーダーキャッシュが空）で確かめる。計測は warm の後だった
- [ ] `prepare()` の取得の進捗を出す口（1.6 GB の f16 は 47 秒かかった）。契約に progress が無い
- [ ] Vulkan の無い build（CPU のみ）でも `paw_gpu_available` が 0 を返すことの確認（ggml-backend.h の include は両方で通った）
- [ ] 公開物の案内: Vulkan SDK・短いパス・VC++ ツールの要件を README に書いた。pub.dev の点数（`flutter pub publish --dry-run`）は未確認

## やること（当初の計画）

- [x] `windows/` を `ffiPlugin: true` で足す（Apple・Android の MethodChannel と混在）。whisper.cpp の取り込み方は Spirits Garden の
  `prototypes/spirits/packages/whisper_cpp`（labs `2026/10/18/flutter-realtime-audio-analysis/packages/whisper_cpp` 由来、v1.9.5、CMake、CPU）を参考に、
  この repo が所有する形で写す。sibling import しない
- [x] 重みの取得: `prepare(locale)` で Hugging Face `ggerganov/whisper.cpp` の ggml ファイルを hash を固定して取り、アプリの support dir に置く。
  `support()` は取得前なら `downloadable`、取得後なら `installed`。`needs_network_for_model: true`
- [x] `transcribe`: PCM16 → float、`language=ja`、greedy、`no_context`、temperature 0。1 要求ずつ直列。`cancel` は whisper の abort callback で止める
- [x] 3 モデルの実測（lab の `tools/evaluate.py` と同じ判定）: base（142 MB）、small（466 MB）、large-v3-turbo（f16 約 1.6 GB と q5_0 約 550 MB）。
  要求→確定の中央値・p95・最初、CER、モデルのロード時間、メモリ。連続した会話で要求が溜まらない速さかを見る
- [x] 既定のモデルを決め、`support()` の `engine` にモデル名を含めるか決める（例: `whisper.cpp/small`）
- [x] README の対応表と AGENTS.md を更新。利用者の `flutter build` に Visual Studio の C++ ツールが要ることを書く

## 参照

- Mac の small の実測（Metal、CER 7 %、中央値 144 ms）: labs `2026/10/19/apple-speech-scd-asr/README.md`
- Windows の CPU で whisper を動かした実例: labs `2026/10/18/flutter-realtime-audio-analysis`（README の Windows の欄）
- Windows の PC でビルドする型（対話タスク、plugin の symlink の罠）: agent `docs/playbooks/multi-machine-agent-orchestration.md`
