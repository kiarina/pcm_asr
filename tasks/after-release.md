# 0.1.2 を公開した後の残り

Windows の whisper.cpp backend（`tasks/windows-whisper-backend.md`、2026-10-19〜20）は完了し、0.1.2 まで公開した。
Spirits Garden の試作が通常の依存で使い、オーナーが本物のマイクで Mac・Windows とも OK と評価した（2026-10-20）。残りは次のとおり。

- [ ] CI: これまでの run はすべて `flutter analyze` の `asset_directory_does_not_exist` で赤だった（root の analyze が `example/` も見るのに、
  fixture の `assets/segments/` を作る step がその後ろにあった）。step の順を直した（2026-10-20）。次の push の run が緑になるか確かめる
- [ ] publisher `kiarina.dev` の付与（pub.dev のサイトでオーナーが行う）
- [ ] GPU の無い Windows の実機: CPU の small の fallback は `PCM_ASR_VULKAN=0` の DLL でだけ確かめた（CER 7 %、1.4 秒）
- [ ] 数時間の長時間の soak（今は数分。5 環境で失敗 0、メモリ安定）
- [ ] Windows のモデルの置き場所を変える口（`PcmAsrWindows.modelDirectory`）が README に無く、`package:pcm_asr/pcm_asr.dart` からは
  解析ツールに Web の stub（`registerWith` だけ）が見えるので設定できない。Spirits Garden の試作は `package:pcm_asr/pcm_asr_windows.dart`
  を直接 import して `~/.spirits/models/pcm_asr/whisper` を渡している（2026-10-29）。README に書き、main のライブラリからも設定できるようにする
- [ ] 例題アプリの fixture（`example/assets/segments/`）は `.pubignore` で公開物に入れていない。pub.dev から取った人が例題を動かすには
  `tool/prepare_example_segments.py` で作る必要があることを README に書くか、小さな公開素材を同梱するか決める
