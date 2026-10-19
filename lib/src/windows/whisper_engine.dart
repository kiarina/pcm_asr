// whisper.cpp through dart:ffi. One long-lived background isolate owns the
// whisper_context*; requests are serialized on it so the UI isolate never
// blocks on inference. Derived from the whisper_cpp package of the
// flutter-realtime-audio-analysis lab (MIT).
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class WhisperSegment {
  const WhisperSegment({
    required this.start,
    required this.end,
    required this.text,
  });
  final double start;
  final double end;
  final String text;
}

class WhisperResult {
  const WhisperResult({
    required this.text,
    required this.segments,
    required this.language,
    required this.elapsed,
  });
  final String text;
  final List<WhisperSegment> segments;
  final String language;

  /// Time inside whisper_full (measured in the worker isolate).
  final Duration elapsed;
}

class WhisperException implements Exception {
  const WhisperException(this.message, {this.aborted = false});
  final String message;
  final bool aborted;
  @override
  String toString() => 'WhisperException: $message';
}

/// A flag the decoder polls; set it from any isolate to stop a transcription.
class WhisperAbortFlag {
  WhisperAbortFlag() : _ptr = calloc<Int32>();
  final Pointer<Int32> _ptr;
  int get address => _ptr.address;
  void set() => _ptr.value = 1;
  void clear() => _ptr.value = 0;
  void free() => calloc.free(_ptr);
}

class WhisperEngine {
  WhisperEngine._(
    this._isolate,
    this._sendPort,
    this._receivePort,
    this._replies,
  );

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final StreamIterator<Object?> _replies;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  static Future<WhisperEngine> load({
    required String path,
    bool useGpu = false,
  }) async {
    final receivePort = ReceivePort();
    final replies = StreamIterator<Object?>(receivePort);
    final isolate = await Isolate.spawn(
      _workerMain,
      receivePort.sendPort,
      debugName: 'pcm_asr_whisper',
      errorsAreFatal: false,
    );
    await replies.moveNext();
    final sendPort = replies.current as SendPort;
    final engine = WhisperEngine._(isolate, sendPort, receivePort, replies);
    try {
      await engine._call(['load', path, useGpu]);
    } catch (_) {
      engine._shutdown();
      rethrow;
    }
    return engine;
  }

  /// Transcribes 16 kHz mono float32 PCM in [-1, 1].
  Future<WhisperResult> transcribe(
    Float32List pcm16kMono, {
    required String language,
    int threads = 0,
    bool noContext = true,
    bool suppressNonSpeech = true,
    double temperature = 0,
    WhisperAbortFlag? abort,
  }) async {
    final reply = await _call([
      'transcribe',
      TransferableTypedData.fromList([pcm16kMono]),
      language,
      threads,
      noContext,
      suppressNonSpeech,
      temperature,
      abort?.address ?? 0,
    ]) as List<Object?>;
    return WhisperResult(
      text: reply[0] as String,
      segments: [
        for (final s in reply[1] as List<Object?>)
          WhisperSegment(
            start: (s as List<Object?>)[0] as double,
            end: s[1] as double,
            text: s[2] as String,
          ),
      ],
      language: reply[2] as String,
      elapsed: Duration(microseconds: reply[3] as int),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await _call(['dispose']);
    } finally {
      _shutdown();
    }
  }

  static String get backend => _utf8(_Lib.instance.backend());

  /// True when the DLL has a GPU backend and a device is present. Initializes
  /// the ggml backend registry; call it off the UI isolate when it matters.
  static bool get gpuAvailable => _Lib.instance.gpuAvailable() != 0;

  Future<Object?> _call(List<Object?> request) {
    if (_disposed)
      return Future.error(const WhisperException('engine disposed'));
    final c = Completer<Object?>();
    _queue = _queue.then((_) async {
      _sendPort.send(request);
      if (!await _replies.moveNext()) {
        c.completeError(const WhisperException('worker isolate exited'));
        return;
      }
      final r = _replies.current as List<Object?>;
      if (r[0] == true) {
        c.complete(r[1]);
      } else {
        c.completeError(
          WhisperException(
            r[1] as String,
            aborted: r.length > 2 && r[2] == true,
          ),
        );
      }
    });
    return c.future;
  }

  void _shutdown() {
    _disposed = true;
    _receivePort.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

// ---------------------------------------------------------------------------
// FFI bindings to src/pcm_asr_whisper.h

typedef _InitFileC = Pointer<Void> Function(Pointer<Char>, Int32);
typedef _InitFile = Pointer<Void> Function(Pointer<Char>, int);
typedef _CtxVoidC = Void Function(Pointer<Void>);
typedef _CtxVoid = void Function(Pointer<Void>);
typedef _TranscribeC = Int32 Function(
  Pointer<Void>,
  Pointer<Float>,
  Int32,
  Pointer<Char>,
  Int32,
  Int32,
  Int32,
  Float,
  Pointer<Int32>,
);
typedef _Transcribe = int Function(
  Pointer<Void>,
  Pointer<Float>,
  int,
  Pointer<Char>,
  int,
  int,
  int,
  double,
  Pointer<Int32>,
);
typedef _CtxIntC = Int32 Function(Pointer<Void>);
typedef _CtxInt = int Function(Pointer<Void>);
typedef _CtxIdxStrC = Pointer<Char> Function(Pointer<Void>, Int32);
typedef _CtxIdxStr = Pointer<Char> Function(Pointer<Void>, int);
typedef _CtxIdxI64C = Int64 Function(Pointer<Void>, Int32);
typedef _CtxIdxI64 = int Function(Pointer<Void>, int);
typedef _CtxStrC = Pointer<Char> Function(Pointer<Void>);
typedef _CtxStr = Pointer<Char> Function(Pointer<Void>);
typedef _StrC = Pointer<Char> Function();
typedef _IntRetC = Int32 Function();
typedef _IntRet = int Function();
typedef _IntArgC = Void Function(Int32);
typedef _IntArg = void Function(int);

class _Lib {
  _Lib(DynamicLibrary l)
    : setLogEnabled = l.lookupFunction<_IntArgC, _IntArg>(
        'paw_set_log_enabled',
      ),
      initFromFile = l.lookupFunction<_InitFileC, _InitFile>(
        'paw_init_from_file',
      ),
      free = l.lookupFunction<_CtxVoidC, _CtxVoid>('paw_free'),
      transcribe = l.lookupFunction<_TranscribeC, _Transcribe>(
        'paw_transcribe',
      ),
      nSegments = l.lookupFunction<_CtxIntC, _CtxInt>('paw_n_segments'),
      segmentText = l.lookupFunction<_CtxIdxStrC, _CtxIdxStr>(
        'paw_segment_text',
      ),
      segmentT0 = l.lookupFunction<_CtxIdxI64C, _CtxIdxI64>('paw_segment_t0'),
      segmentT1 = l.lookupFunction<_CtxIdxI64C, _CtxIdxI64>('paw_segment_t1'),
      resultLanguage = l.lookupFunction<_CtxStrC, _CtxStr>(
        'paw_result_language',
      ),
      gpuAvailable = l.lookupFunction<_IntRetC, _IntRet>('paw_gpu_available'),
      backend = l.lookupFunction<_StrC, _StrC>('paw_backend'),
      systemInfo = l.lookupFunction<_StrC, _StrC>('paw_system_info');

  static final _Lib instance = _Lib(DynamicLibrary.open('pcm_asr_whisper.dll'));

  final _IntArg setLogEnabled;
  final _InitFile initFromFile;
  final _CtxVoid free;
  final _Transcribe transcribe;
  final _CtxInt nSegments;
  final _CtxIdxStr segmentText;
  final _CtxIdxI64 segmentT0;
  final _CtxIdxI64 segmentT1;
  final _CtxStr resultLanguage;
  final _IntRet gpuAvailable;
  final Pointer<Char> Function() backend;
  final Pointer<Char> Function() systemInfo;
}

String _utf8(Pointer<Char> p) => utf8.decode(_bytes(p), allowMalformed: true);

Uint8List _bytes(Pointer<Char> p) {
  if (p == nullptr) return Uint8List(0);
  final bytes = p.cast<Uint8>();
  var n = 0;
  while (bytes[n] != 0) {
    n++;
  }
  return Uint8List.fromList(bytes.asTypedList(n));
}

void _workerMain(SendPort reply) {
  final port = ReceivePort();
  reply.send(port.sendPort);
  final lib = _Lib.instance;
  var ctx = nullptr.cast<Void>();

  port.listen((Object? message) {
    final m = message as List<Object?>;
    try {
      switch (m[0]) {
        case 'load':
          final p = (m[1] as String).toNativeUtf8();
          try {
            ctx = lib.initFromFile(p.cast(), (m[2] as bool) ? 1 : 0);
          } finally {
            malloc.free(p);
          }
          if (ctx == nullptr) {
            reply.send([false, 'failed to load model ${m[1]}']);
          } else {
            reply.send([true, null]);
          }
        case 'transcribe':
          if (ctx == nullptr) throw const WhisperException('no model loaded');
          final pcm = (m[1] as TransferableTypedData)
              .materialize()
              .asFloat32List();
          final lang = (m[2] as String).toNativeUtf8();
          final buf = malloc<Float>(pcm.isEmpty ? 1 : pcm.length);
          try {
            buf.asTypedList(pcm.length).setAll(0, pcm);
            final abort = Pointer<Int32>.fromAddress(m[7] as int);
            final sw = Stopwatch()..start();
            final rc = lib.transcribe(
              ctx,
              buf,
              pcm.length,
              lang.cast(),
              m[3] as int,
              (m[4] as bool) ? 1 : 0,
              (m[5] as bool) ? 1 : 0,
              m[6] as double,
              abort,
            );
            sw.stop();
            if (rc == 1) {
              reply.send([false, 'aborted', true]);
              return;
            }
            if (rc != 0) throw WhisperException('whisper_full failed ($rc)');
            final n = lib.nSegments(ctx);
            final segs = <List<Object?>>[];
            final all = BytesBuilder(copy: false);
            for (var i = 0; i < n; i++) {
              final raw = lib.segmentText(ctx, i);
              all.add(_bytes(raw));
              segs.add([
                lib.segmentT0(ctx, i) / 100.0,
                lib.segmentT1(ctx, i) / 100.0,
                _utf8(raw).trim(),
              ]);
            }
            final text = utf8
                .decode(all.takeBytes(), allowMalformed: true)
                .trim();
            reply.send([
              true,
              [
                text,
                segs,
                _utf8(lib.resultLanguage(ctx)),
                sw.elapsedMicroseconds,
              ],
            ]);
          } finally {
            malloc.free(buf);
            malloc.free(lang);
          }
        case 'dispose':
          if (ctx != nullptr) lib.free(ctx);
          ctx = nullptr;
          reply.send([true, null]);
          port.close();
      }
    } catch (e) {
      reply.send([false, e is WhisperException ? e.message : e.toString()]);
    }
  });
}
