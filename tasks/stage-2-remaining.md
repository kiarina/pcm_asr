# 段階 2 の残り（公開候補にするまで）

5 環境の通し（6 区間 × 3 パス）と堅牢性の確認（極短・28 秒・同時 3 件・同じ ID・timeout・不正 PCM・dispose 後の再開）は通った
（labs `2026/10/19/flutter-pcm-asr-plugin/README.md`「堅牢性」、2026-10-20）。公開候補にするまでに残っているもの。

- [x] `prepare()` の進捗（`onProgress`、download / install / load / warmup。Windows はバイト、Apple は割合、Android は %、Web は無し）（2026-10-20）
- [ ] Windows の暖機を cold（ドライバーのシェーダーキャッシュが空）で確かめる
- [x] 連続の要求: macOS・iOS・Windows 300 件、Android 100 件、Web 30 件で失敗 0、RSS は増えない（labs README「連続要求」）。数時間の長時間はまだ
- [x] 入力上限 60 秒（`PcmAsr.maxSegment`、超えると `invalidPcm`。native を呼ぶ前に Dart で弾く）
- [ ] CI（`.github/workflows/ci.yml`: analyze・test、Android/Web・Apple（macos-26）・Windows（CPU のみ）の build）を足した。初回の run は GitHub の queue 待ちで結果未確認
- [x] `flutter pub publish --dry-run` は警告 0・308 KB（`.pubignore` で AGENTS.md・tasks・example の fixture を外す）。pub.dev の点数は公開後
- [x] README の利用例と環境ごとの準備を書いた
- [ ] マイクからの体験アプリ（labs の `demo/`）をこの repo の `example/` の 2 つ目にするか決める（モデル 90 MB を同梱しない形）
