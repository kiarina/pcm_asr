# 段階 2 の残り（公開候補にするまで）

5 環境の通し（6 区間 × 3 パス）と堅牢性の確認（極短・28 秒・同時 3 件・同じ ID・timeout・不正 PCM・dispose 後の再開）は通った
（labs `2026/10/19/flutter-pcm-asr-plugin/README.md`「堅牢性」、2026-10-20）。公開候補にするまでに残っているもの。

- [ ] `prepare()` の進捗を出す口（Apple の asset、Android のモデル、Windows の重み 0.5〜1.6 GB）。契約に progress が無い
- [ ] Windows の暖機を cold（ドライバーのシェーダーキャッシュが空）で確かめる
- [ ] 長時間・連続の要求（数百件）でメモリと queue が増え続けないこと。Android の 1 recognizer の寿命、Apple の analyzer の解放
- [ ] 入力上限を決めて `invalidPcm` で返す（whisper は 30 秒の窓、Android は長いと仮説が巻き戻る）
- [ ] CI（`flutter analyze`・`flutter test`、macOS / Android / Web の build。Windows は Vulkan SDK と VC++ が要るので手元）
- [ ] `flutter pub publish --dry-run` と pub.dev の点数。`pubspec.lock` は入れない、`example/assets/segments` は生成物
- [ ] README の利用例を 5 環境ぶん最新に（Windows の要件、Web の送信先、Android のマイク権限が要らないこと）
- [ ] マイクからの体験アプリ（labs の `demo/`）をこの repo の `example/` の 2 つ目にするか決める（モデル 90 MB を同梱しない形）
