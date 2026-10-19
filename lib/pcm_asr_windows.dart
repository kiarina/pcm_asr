// Windows implementation: whisper.cpp inside the package.
//
// No speech engine of Windows takes external PCM for Japanese (the classic
// SAPI recognizer is unusable, the OneCore DNN engine is not reachable
// through SAPI, Windows.Media.SpeechRecognition is microphone-only, and the
// Windows AI Speech API is English-only and experimental), so this platform
// runs whisper.cpp with a ggml model fetched by `prepare()`.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'src/platform_interface.dart';
import 'src/types.dart';
import 'src/windows/whisper_engine.dart';

/// A ggml model on Hugging Face, pinned by size and SHA-256.
class WhisperModel {
  const WhisperModel(this.name, this.file, this.bytes, this.sha256);
  final String name;
  final String file;
  final int bytes;
  final String sha256;

  String get url => 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file';

  static const base = WhisperModel('base', 'ggml-base.bin', 147951465, '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe');
  static const small = WhisperModel('small', 'ggml-small.bin', 487601967, '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b');
  static const largeV3Turbo = WhisperModel('large-v3-turbo', 'ggml-large-v3-turbo.bin', 1624555275, '1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69');
  static const largeV3TurboQ5 = WhisperModel('large-v3-turbo-q5_0', 'ggml-large-v3-turbo-q5_0.bin', 574041195, '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2');

  static const all = [base, small, largeV3Turbo, largeV3TurboQ5];

  static WhisperModel byName(String name) => all.firstWhere((m) => m.name == name, orElse: () => throw ArgumentError('unknown whisper model: $name'));
}

class PcmAsrWindows extends PcmAsrPlatform {
  PcmAsrWindows();

  static void registerWith() {
    PcmAsrPlatform.instance = PcmAsrWindows();
  }

  /// The model `prepare()` fetches and `transcribe()` uses. Null picks
  /// automatically: large-v3-turbo q5_0 when a Vulkan GPU is present (every
  /// character of the lab's Japanese fixture right, ~100 ms per request on an
  /// RTX 3080 Ti), otherwise small (7 % CER, ~1.4 s on 8 CPU threads of an
  /// i9-12900K). Change it before `prepare()`; a running engine for another
  /// model is released first.
  static WhisperModel? model;

  /// whisper.cpp threads; 0 picks min(8, logical processors). whisper.cpp's
  /// own default (min(4, cores)) was 1.7 times slower on an 8-P-core CPU.
  static int threads = 0;

  /// One short decode after loading so the first real request does not pay
  /// for the Vulkan pipeline compilation (3 to 8 s cold in the lab).
  static bool warmUp = true;

  /// Use the GPU (Vulkan) when the DLL was built with it and a device exists;
  /// ggml falls back to the CPU otherwise.
  static bool useGpu = true;

  /// whisper.cpp version and the backends compiled into the DLL, e.g.
  /// `whisper.cpp v1.9.5 (Vulkan, CPU)`.
  static String get backendDescription => WhisperEngine.backend;

  /// Segments whose RMS is below this are answered with empty text without
  /// running whisper: on one second of digital silence whisper hallucinated a
  /// sentence ("この動画は…また次回!") even with non-speech suppression on.
  static double silenceRms = 0.001;

  /// Where models are stored; defaults to the app's support directory.
  static Future<Directory> Function() modelDirectory = () async {
    final dir = await getApplicationSupportDirectory();
    return Directory('${dir.path}${Platform.pathSeparator}pcm_asr${Platform.pathSeparator}whisper');
  };

  static const engineIdPrefix = 'whisper.cpp';

  WhisperEngine? _engine;
  WhisperModel? _loaded;
  final _running = <String, WhisperAbortFlag>{};

  static WhisperModel get effectiveModel => model ?? (WhisperEngine.gpuAvailable ? WhisperModel.largeV3TurboQ5 : WhisperModel.small);

  static int get effectiveThreads => threads > 0 ? threads : math.min(8, Platform.numberOfProcessors);

  String _engineId() => '$engineIdPrefix/${effectiveModel.name}';

  static String? languageOf(String locale) {
    final tag = locale.replaceAll('_', '-').toLowerCase();
    final lang = tag.split('-').first;
    return _whisperLanguages.contains(lang) ? lang : null;
  }

  Future<File> _modelFile() async => File('${(await modelDirectory()).path}${Platform.pathSeparator}${effectiveModel.file}');

  @override
  Future<RecognitionSupport> support({required String locale}) async {
    final lang = languageOf(locale);
    final file = await _modelFile();
    final installed = await file.exists() && await file.length() == effectiveModel.bytes;
    return RecognitionSupport(
      engine: _engineId(),
      supported: lang != null,
      acceptsExternalPcm: true,
      onDevice: true,
      modelState: installed ? ModelState.installed : ModelState.downloadable,
      locale: lang,
      sampleRates: const [16000],
      needsNetworkForModel: !installed,
      reason: lang == null ? 'unsupported_locale' : null,
    );
  }

  @override
  Future<void> prepare({required String locale}) async {
    if (languageOf(locale) == null) {
      throw PcmAsrException(PcmAsrErrorCode.unsupportedLocale, 'whisper has no language for $locale');
    }
    final file = await _modelFile();
    final wanted = effectiveModel;
    if (!(await file.exists() && await file.length() == wanted.bytes)) {
      await _download(file, wanted);
    }
    if (_engine != null && _loaded != wanted) {
      await _engine!.dispose();
      _engine = null;
    }
    if (_engine == null) {
      _engine = await WhisperEngine.load(path: file.path, useGpu: useGpu);
      _loaded = wanted;
      if (warmUp) {
        // 0.5 s of faint noise: enough to build the pipelines, discarded.
        final noise = Float32List(8000);
        var seed = 12345;
        for (var i = 0; i < noise.length; i++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          noise[i] = (seed / 0x7fffffff - 0.5) * 0.02;
        }
        try {
          await _engine!.transcribe(noise, language: languageOf(locale)!, threads: effectiveThreads);
        } catch (_) {}
      }
    }
  }

  Future<void> _download(File file, WhisperModel model) async {
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(model.url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw PcmAsrException(PcmAsrErrorCode.modelUnavailable, 'GET ${model.url} -> ${response.statusCode}');
      }
      final sink = part.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
      }
      await sink.close();
      final got = (await sha256.bind(part.openRead()).first).toString();
      if (got != model.sha256) {
        await part.delete();
        throw PcmAsrException(PcmAsrErrorCode.modelUnavailable, 'sha256 mismatch for ${model.file}: $got');
      }
      await part.rename(file.path);
    } on SocketException catch (e) {
      throw PcmAsrException(PcmAsrErrorCode.modelUnavailable, 'download failed: $e');
    } finally {
      client.close();
    }
  }

  @override
  Future<TranscribeResult> transcribe(TranscribeRequest request) async {
    final lang = languageOf(request.locale);
    if (lang == null) throw PcmAsrException(PcmAsrErrorCode.unsupportedLocale, 'whisper has no language for ${request.locale}');
    if (_running.containsKey(request.id)) throw PcmAsrException(PcmAsrErrorCode.engineFailure, 'request id already running: ${request.id}');
    final engine = _engine;
    if (engine == null) throw const PcmAsrException(PcmAsrErrorCode.modelUnavailable, 'call prepare() first');
    final flag = WhisperAbortFlag();
    _running[request.id] = flag;
    final started = DateTime.now();
    try {
      final pcm = toMono16k(request.audio);
      if (rms(pcm) < silenceRms) {
        return TranscribeResult(id: request.id, text: '', engine: _engineId(), locale: request.locale, elapsed: DateTime.now().difference(started));
      }
      final work = engine.transcribe(pcm, language: lang, threads: effectiveThreads, abort: flag);
      WhisperResult result;
      try {
        result = await work.timeout(request.timeout);
      } on TimeoutException {
        flag.set();
        try {
          await work;
        } catch (_) {}
        throw PcmAsrException(PcmAsrErrorCode.timeout, 'No final result within ${request.timeout.inMilliseconds} ms');
      } on WhisperException catch (e) {
        if (e.aborted) throw PcmAsrException(PcmAsrErrorCode.cancelled, 'cancelled: ${request.id}');
        throw PcmAsrException(PcmAsrErrorCode.engineFailure, e.message);
      }
      return TranscribeResult(
        id: request.id,
        text: result.text,
        engine: _engineId(),
        locale: request.locale,
        elapsed: DateTime.now().difference(started),
        ranges: [for (final s in result.segments) TranscribedRange(text: s.text, start: s.start, end: s.end)],
      );
    } finally {
      _running.remove(request.id);
      flag.free();
    }
  }

  @override
  Future<void> cancel(String id) async {
    _running[id]?.set();
  }

  @override
  Future<void> dispose() async {
    for (final f in _running.values) {
      f.set();
    }
    final engine = _engine;
    _engine = null;
    _loaded = null;
    await engine?.dispose();
  }

  static double rms(Float32List pcm) {
    if (pcm.isEmpty) return 0;
    var sum = 0.0;
    for (final v in pcm) {
      sum += v * v;
    }
    return math.sqrt(sum / pcm.length);
  }

  /// PCM16LE interleaved → mono float32 at 16 kHz (linear resampling when the
  /// input rate differs).
  static Float32List toMono16k(PcmSegment audio) {
    final frames = audio.frameCount;
    final view = ByteData.sublistView(audio.pcm16le);
    final mono = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      var sum = 0;
      for (var c = 0; c < audio.channels; c++) {
        sum += view.getInt16((i * audio.channels + c) * 2, Endian.little);
      }
      mono[i] = sum / audio.channels / 32768.0;
    }
    if (audio.sampleRate == 16000) return mono;
    final ratio = audio.sampleRate / 16000;
    final out = Float32List((frames / ratio).floor());
    for (var i = 0; i < out.length; i++) {
      final src = i * ratio;
      final j = src.floor();
      final t = src - j;
      final a = mono[j];
      final b = j + 1 < frames ? mono[j + 1] : a;
      out[i] = a + (b - a) * t;
    }
    return out;
  }
}

// whisper.cpp's language list (whisper_lang_str ids 0..98).
const _whisperLanguages = {
  'en', 'zh', 'de', 'es', 'ru', 'ko', 'fr', 'ja', 'pt', 'tr', 'pl', 'ca', 'nl', 'ar', 'sv', 'it', 'id', 'hi', 'fi', 'vi', //
  'he', 'uk', 'el', 'ms', 'cs', 'ro', 'da', 'hu', 'ta', 'no', 'th', 'ur', 'hr', 'bg', 'lt', 'la', 'mi', 'ml', 'cy', 'sk', //
  'te', 'fa', 'lv', 'bn', 'sr', 'az', 'sl', 'kn', 'et', 'mk', 'br', 'eu', 'is', 'hy', 'ne', 'mn', 'bs', 'kk', 'sq', 'sw', //
  'gl', 'mr', 'pa', 'si', 'km', 'sn', 'yo', 'so', 'af', 'oc', 'ka', 'be', 'tg', 'sd', 'gu', 'am', 'yi', 'lo', 'uz', 'fo', //
  'ht', 'ps', 'tk', 'nn', 'mt', 'sa', 'lb', 'my', 'bo', 'tl', 'mg', 'as', 'tt', 'haw', 'ln', 'ha', 'ba', 'jw', 'su', 'yue',
};
