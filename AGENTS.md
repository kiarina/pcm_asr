# AGENTS.md

このリポジトリで作業するエージェント向けのガイドラインです。

## 作業前に読むもの

- `README.md`（公開向けの説明。契約と対応表）
- `lib/src/types.dart`（Dart の契約。ここが正典）
- `tasks/`（残っている作業。1 タスク 1 ファイル）
- `CHANGELOG.md`

実証の来歴と実測は labs の `2026/10/19/flutter-pcm-asr-plugin`（調査は同 `research/`、結果は同 `results/`、
マイクからの体験アプリは同 `demo/`）。この repo はそこから写して所有し、lab とは同期しない。

## 設計の決まり

- 約束は「確定済みの PCM16 区間を 1 つ渡すと、その要求の最終文字が 1 つ返る」だけ。マイクは開かない。
  区間の切り方・VAD・話者の判定は呼び出し側が持つ。partial は返さない
- `support()` は engine・外部 PCM の可否・端末内かどうか・モデルの状態・locale を**別々のフィールド**で返す。
  単一の bool に畳まない。「非対応を返す実装がある」だけの OS を対応済みと表示しない
- エンジンは OS 標準を優先する。Apple は SpeechAnalyzer（macOS 26 / iOS 26 以上。要求ごとに analyzer を作り
  `finalizeAndFinish` を待つ。**1 件ずつ直列**: iOS は 3 件同時で "Maximum number of recognizers reached"）、Android は `SpeechRecognizer` に pipe で PCM を渡す（API 33 以上。`stopListening` は呼ばない、
  pipe を閉じる前に無音を書く、service が開くのを待つ、要求ごとに writer の thread、`ERROR_CLIENT`／`SERVER_DISCONNECTED`／`BUSY` は作り直して再試行）、Web は `SpeechRecognition.start(track)`
  （desktop の Chrome / Edge 135 以上、cloud。track が終わっても確定しないので `stop()` を呼ぶ）
- **Windows だけはパッケージの内部で whisper.cpp を動かす**（オーナー、2026-10-19）。OS の認識器では日本語の外部 PCM が成立しないため。
  契約は同じで `engine: whisper.cpp`・`on_device: true` を返し、重みは `prepare()` で Hugging Face の `ggerganov/whisper.cpp` から
  hash を固定して取る。実測（2026-10-19、G-GEAR）の結果、**Vulkan の GPU があれば large-v3-turbo q5_0（CER 0 %、約 100 ms）、
  無ければ small（CER 7 %、8 スレッドで 1.4 秒）** を既定にし（オーナー確定、2026-10-19）、`PcmAsrWindows.model` で上書きできる。threads の既定は min(8, 論理コア)。
  ロード後に 0.5 秒の雑音で暖機する（Vulkan のパイプラインのコンパイルが最初の要求に 3〜8 秒乗る）。RMS 0.001 未満の区間は whisper に
  渡さず空文字にする（無音で幻覚する）。whisper は当面 Windows 限定
- Web は cloud（音声をブラウザーのサービスへ送る）で対応に数える。`on_device: false` をそのまま返し、利用者への説明はアプリの責任（オーナー、2026-10-19）
- Android の PCM は待たずに書く（Pixel 6 で文字が同じまま 7 倍速かった）。field report は実時間を求めているので、
  `configure` で戻せるようにしておき、他端末で問題が出たら既定を見直す
- 認証値・録音・会話文・個人環境のパスを公開物に混ぜない。例題の音声は共有素材（`kiarina/test-assets`）だけ
- Windows の build: `src/CMakeLists.txt` が Vulkan SDK（`VULKAN_SDK`）を見つけると `GGML_VULKAN=ON`（DLL は約 47 MB、無いと CPU のみで 1.6 MB）。
  ggml のシェーダー生成（ExternalProject）は深い build ディレクトリで MSBuild の MAX_PATH を超えて `MSB4184` で落ちるので、
  短いパス（junction）から build する。CMake のディレクトリ名は `s`・`w` に縮めてある

## 検証

- `flutter analyze` と `flutter test`（Dart の契約と MethodChannel の写像）
- 実機の通しは lab の `tools/evaluate.py` と同じ判定（6 区間 × 3 パス、非空 18/18、ID 一致 18/18、正規化 CER、異常系 3 件）。
  この repo に写すときは `tool/` に置く
- CI のビルド成功だけで実機の動作を主張しない。対応表に書く OS は実機で確かめたものだけ

## 公開

pub.dev への公開は取り消せない（discontinue しかできない）。公開の前に名前・version・公開内容・対応範囲をオーナーに示し、
`flutter pub publish --dry-run` の結果を見せる。`publish_to: none` は公開の直前まで外さない。
