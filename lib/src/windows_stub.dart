/// Stands in for `PcmAsrWindows` where dart:ffi does not exist (the Web).
/// The Dart plugin registrant imports `package:pcm_asr/pcm_asr.dart`, so the
/// Windows class must be reachable from the main library on every platform.
class PcmAsrWindows {
  static void registerWith() {}
}
