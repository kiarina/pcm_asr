import 'package:pcm_asr/pcm_asr_windows.dart';

/// Lab knobs for the Windows whisper.cpp backend.
void configureWindows({String model = '', int? threads, bool? useGpu}) {
  if (model.isNotEmpty) {
    PcmAsrWindows.model = model == 'auto' ? null : WhisperModel.byName(model);
  }
  if (threads != null) PcmAsrWindows.threads = threads;
  if (useGpu != null) PcmAsrWindows.useGpu = useGpu;
}

String windowsBackend() => PcmAsrWindows.backendDescription;
