import 'package:pcm_asr/pcm_asr_windows.dart';

/// Lab knobs for the Windows whisper.cpp backend.
void configureWindows({String model = '', int? threads}) {
  if (model.isNotEmpty) PcmAsrWindows.model = WhisperModel.byName(model);
  if (threads != null) PcmAsrWindows.threads = threads;
}
