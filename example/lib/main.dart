import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, FileMode, ProcessInfo, exit, stdout;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pcm_asr/pcm_asr.dart';

import 'windows_knobs_io.dart' if (dart.library.js_interop) 'windows_knobs_web.dart';

/// `--dart-define=PCM_ASR_AUTOTEST=1`: run the fixture on start, print one
/// JSON line per step prefixed with `PCM_ASR `, and (on desktop) exit.
const autotest = String.fromEnvironment('PCM_ASR_AUTOTEST') == '1';
const locale = String.fromEnvironment('PCM_ASR_LOCALE', defaultValue: 'ja-JP');

/// Android lab knobs: write pace (1.0 = real time) and silent tail in ms.
const androidPace = String.fromEnvironment('PCM_ASR_ANDROID_PACE');
const androidTailMs = String.fromEnvironment('PCM_ASR_ANDROID_TAIL_MS');

/// Windows lab knobs: whisper model name and thread count.
const whisperModel = String.fromEnvironment('PCM_ASR_WHISPER_MODEL');
const whisperThreads = String.fromEnvironment('PCM_ASR_WHISPER_THREADS');
const whisperGpu = String.fromEnvironment('PCM_ASR_WHISPER_GPU');

/// Also append every line to this file (Windows GUI apps have no stdout).
const logFile = String.fromEnvironment('PCM_ASR_LOG_FILE');

/// `--dart-define=PCM_ASR_SOAK=200`: after the checks, run this many
/// requests back to back and report memory and timing.
const soakRequests = int.fromEnvironment('PCM_ASR_SOAK');

void main() => runApp(const MaterialApp(home: FixturePage()));

class FixturePage extends StatefulWidget {
  const FixturePage({super.key});

  @override
  State<FixturePage> createState() => _FixturePageState();
}

class _FixturePageState extends State<FixturePage> {
  final asr = const PcmAsr();
  final lines = <String>[];
  bool running = false;

  @override
  void initState() {
    super.initState();
    if (autotest) scheduleMicrotask(run);
  }

  void log(String kind, Map<String, Object?> data) {
    final line = jsonEncode({'kind': kind, ...data});
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
      // Browser console / logcat.
      // ignore: avoid_print
      print('PCM_ASR $line');
    } else {
      stdout.writeln('PCM_ASR $line');
      if (logFile.isNotEmpty) File(logFile).writeAsStringSync('PCM_ASR $line\n', mode: FileMode.append, flush: true);
    }
    setState(() => lines.add(line));
  }

  Future<void> run() async {
    if (running) return;
    setState(() {
      running = true;
      lines.clear();
    });
    var ok = false;
    String? unsupportedReason;
    try {
      log('platform', {'os': kIsWeb ? 'web' : defaultTargetPlatform.name, 'locale': locale});
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        configureWindows(model: whisperModel, threads: int.tryParse(whisperThreads), useGpu: whisperGpu.isEmpty ? null : whisperGpu == '1');
        log('configure', {'whisper_model': whisperModel, 'threads': whisperThreads, 'gpu': whisperGpu, 'backend': windowsBackend()});
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && (androidPace.isNotEmpty || androidTailMs.isNotEmpty)) {
        await const MethodChannel('pcm_asr').invokeMethod('configure', {
          'pace': ?double.tryParse(androidPace),
          'tail_ms': ?int.tryParse(androidTailMs),
        });
        log('configure', {'pace': androidPace, 'tail_ms': androidTailMs});
      }
      final support = await asr.support(locale: locale);
      log('support', support.toJson());
      if (!support.supported) {
        unsupportedReason = support.reason ?? 'unsupported';
        return;
      }
      final prepareStart = DateTime.now();
      final progress = <String>[];
      await asr.prepare(locale: locale, onProgress: (p) {
        if (progress.isEmpty || !progress.last.startsWith(p.stage)) progress.add(p.toString());
        if (p.fraction == 1) progress.add(p.toString());
      });
      log('prepare', {'ms': DateTime.now().difference(prepareStart).inMilliseconds, 'model_state_before': support.modelState.name, 'progress': progress});

      final manifest = jsonDecode(await rootBundle.loadString('assets/segments/segments.json')) as List;
      final segments = <(Map<String, Object?>, Uint8List)>[];
      for (final raw in manifest) {
        final row = (raw as Map).cast<String, Object?>();
        final bytes = await rootBundle.load('assets/segments/${row['file']}');
        segments.add((row, bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)));
      }
      // Three passes as in the earlier lab: forward, forward, reversed.
      for (var trial = 0; trial < 3; trial++) {
        final order = trial == 2 ? segments.reversed.toList() : segments;
        for (final (row, pcm) in order) {
          final id = '${row['id']}#$trial';
          final sent = DateTime.now();
          try {
            final result = await asr.transcribe(TranscribeRequest(
              id: id,
              locale: locale,
              audio: PcmSegment(pcm16le: pcm, sampleRate: row['sample_rate'] as int, channels: row['channels'] as int),
            ));
            log('result', {
              ...result.toJson(),
              'trial': trial,
              'segment_id': row['id'],
              'speaker_id': row['speaker_id'],
              'round_trip_ms': DateTime.now().difference(sent).inMilliseconds,
              'id_matches': result.id == id,
            });
          } on PcmAsrException catch (e) {
            log('error', {'id': id, 'trial': trial, 'code': e.code.name, 'message': e.message});
          }
        }
      }
      // Error paths the contract promises.
      try {
        await asr.transcribe(TranscribeRequest(
          id: 'bad-locale',
          locale: 'xx-XX',
          audio: PcmSegment(pcm16le: segments.first.$2, sampleRate: 16000),
        ));
        log('error_check', {'case': 'unsupported_locale', 'ok': false});
      } on PcmAsrException catch (e) {
        log('error_check', {'case': 'unsupported_locale', 'ok': e.code == PcmAsrErrorCode.unsupportedLocale, 'code': e.code.name});
      }
      final cancelId = 'cancel-me';
      final pending = asr.transcribe(TranscribeRequest(
        id: cancelId,
        locale: locale,
        audio: PcmSegment(pcm16le: segments.first.$2, sampleRate: 16000),
      ));
      await asr.cancel(cancelId);
      try {
        final r = await pending;
        log('error_check', {'case': 'cancel', 'ok': true, 'note': 'finished before cancel', 'text': r.text});
      } on PcmAsrException catch (e) {
        log('error_check', {'case': 'cancel', 'ok': e.code == PcmAsrErrorCode.cancelled, 'code': e.code.name});
      }
      // Silence must give empty text, not an error.
      try {
        final r = await asr.transcribe(TranscribeRequest(
          id: 'silence',
          locale: locale,
          audio: PcmSegment(pcm16le: Uint8List(16000 * 2), sampleRate: 16000),
        ));
        log('error_check', {'case': 'silence', 'ok': true, 'text': r.text, 'elapsed_ms': r.elapsed.inMilliseconds});
      } on PcmAsrException catch (e) {
        log('error_check', {'case': 'silence', 'ok': false, 'code': e.code.name, 'message': e.message});
      }
      await robustness(segments);
      if (soakRequests > 0) await soak(segments);
      await asr.dispose();
      ok = true;
    } catch (e, st) {
      log('fatal', {'error': e.toString(), 'stack': st.toString()});
    } finally {
      log('done', {'ok': ok, 'reason': ?unsupportedReason});
      if (mounted) setState(() => running = false);
      if (autotest && !kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        exit(ok ? 0 : 1);
      }
    }
  }

  /// Many requests back to back: memory must not grow with the count.
  Future<void> soak(List<(Map<String, Object?>, Uint8List)> segments) async {
    int? rss() => kIsWeb ? null : ProcessInfo.currentRss;
    final before = rss();
    final elapsed = <int>[];
    var failures = 0;
    final started = DateTime.now();
    for (var i = 0; i < soakRequests; i++) {
      final (_, pcm) = segments[i % segments.length];
      try {
        final r = await asr.transcribe(TranscribeRequest(id: 'soak-$i', locale: locale, audio: PcmSegment(pcm16le: pcm, sampleRate: 16000)));
        elapsed.add(r.elapsed.inMilliseconds);
        if (r.text.isEmpty) failures++;
      } on PcmAsrException {
        failures++;
      }
    }
    final after = rss();
    elapsed.sort();
    log('soak', {
      'requests': soakRequests,
      'failures': failures,
      'seconds': DateTime.now().difference(started).inMilliseconds / 1000,
      'median_ms': elapsed.isEmpty ? null : elapsed[elapsed.length ~/ 2],
      'p95_ms': elapsed.isEmpty ? null : elapsed[(elapsed.length * 0.95).floor().clamp(0, elapsed.length - 1)],
      'rss_before_mb': before == null ? null : before / 1048576,
      'rss_after_mb': after == null ? null : after / 1048576,
    });
  }

  /// Edge cases the contract promises: very short and long input, concurrent
  /// and duplicate requests, a timeout, invalid PCM, use after dispose.
  Future<void> robustness(List<(Map<String, Object?>, Uint8List)> segments) async {
    final first = segments.first.$2;
    Future<void> check(String name, Future<Map<String, Object?>> Function() body) async {
      try {
        log('error_check', {'case': name, 'ok': true, ...await body()});
      } on PcmAsrException catch (e) {
        log('error_check', {'case': name, 'ok': false, 'code': e.code.name, 'message': e.message});
      } catch (e) {
        log('error_check', {'case': name, 'ok': false, 'error': e.toString()});
      }
    }

    // 100 ms: must come back (text may be empty), not fail.
    await check('short', () async {
      final r = await asr.transcribe(TranscribeRequest(id: 'short', locale: locale, audio: PcmSegment(pcm16le: Uint8List.sublistView(first, 0, 3200), sampleRate: 16000)));
      return {'text': r.text, 'elapsed_ms': r.elapsed.inMilliseconds};
    });
    // ~28 s: all six segments twice.
    await check('long', () async {
      final all = BytesBuilder(copy: false);
      for (var i = 0; i < 2; i++) {
        for (final (_, pcm) in segments) {
          all.add(pcm);
        }
      }
      final pcm = all.takeBytes();
      final r = await asr.transcribe(TranscribeRequest(id: 'long', locale: locale, audio: PcmSegment(pcm16le: pcm, sampleRate: 16000), timeout: const Duration(seconds: 90)));
      if (r.text.isEmpty) throw const PcmAsrException(PcmAsrErrorCode.engineFailure, 'empty text for 28 s of speech');
      return {'seconds': pcm.length / 32000, 'characters': r.text.length, 'elapsed_ms': r.elapsed.inMilliseconds};
    });
    // Three at once: every reply must carry its own id.
    await check('concurrent', () async {
      final futures = [
        for (var i = 0; i < 3; i++)
          asr.transcribe(TranscribeRequest(id: 'concurrent-$i', locale: locale, audio: PcmSegment(pcm16le: segments[i].$2, sampleRate: 16000), timeout: const Duration(seconds: 60))),
      ];
      final results = await Future.wait(futures);
      for (var i = 0; i < 3; i++) {
        if (results[i].id != 'concurrent-$i') throw const PcmAsrException(PcmAsrErrorCode.engineFailure, 'id mismatch');
        if (results[i].text.isEmpty) throw const PcmAsrException(PcmAsrErrorCode.engineFailure, 'empty text in concurrent request');
      }
      return {'elapsed_ms': [for (final r in results) r.elapsed.inMilliseconds]};
    });
    // Same id twice: the second must be refused, the first must finish.
    await check('duplicate_id', () async {
      final a = asr.transcribe(TranscribeRequest(id: 'dup', locale: locale, audio: PcmSegment(pcm16le: first, sampleRate: 16000)));
      String second;
      try {
        await asr.transcribe(TranscribeRequest(id: 'dup', locale: locale, audio: PcmSegment(pcm16le: first, sampleRate: 16000)));
        second = 'accepted';
      } on PcmAsrException catch (e) {
        second = e.code.name;
      }
      final r = await a;
      if (r.text.isEmpty) throw const PcmAsrException(PcmAsrErrorCode.engineFailure, 'first request lost its text');
      return {'second': second};
    });
    // 1 ms timeout: must be reported as timeout and leave the engine usable.
    await check('timeout', () async {
      try {
        await asr.transcribe(TranscribeRequest(id: 'timeout', locale: locale, audio: PcmSegment(pcm16le: first, sampleRate: 16000), timeout: const Duration(milliseconds: 1)));
        return {'note': 'finished within 1 ms'};
      } on PcmAsrException catch (e) {
        if (e.code != PcmAsrErrorCode.timeout) rethrow;
      }
      final r = await asr.transcribe(TranscribeRequest(id: 'after-timeout', locale: locale, audio: PcmSegment(pcm16le: first, sampleRate: 16000)));
      return {'after_timeout_text': r.text};
    });
    // Odd byte count: rejected before any native call.
    await check('invalid_pcm', () async {
      try {
        PcmSegment(pcm16le: Uint8List(3), sampleRate: 16000);
        throw const PcmAsrException(PcmAsrErrorCode.engineFailure, 'accepted an odd byte count');
      } on ArgumentError {
        return {};
      }
    });
    // Dispose twice, then use again (prepare + transcribe).
    await check('dispose_resume', () async {
      await asr.dispose();
      await asr.dispose();
      String afterDispose;
      try {
        final r = await asr.transcribe(TranscribeRequest(id: 'after-dispose', locale: locale, audio: PcmSegment(pcm16le: first, sampleRate: 16000)));
        afterDispose = r.text.isEmpty ? 'empty' : 'text';
      } on PcmAsrException catch (e) {
        afterDispose = e.code.name;
      }
      await asr.prepare(locale: locale);
      final r = await asr.transcribe(TranscribeRequest(id: 'resumed', locale: locale, audio: PcmSegment(pcm16le: first, sampleRate: 16000)));
      if (r.text.isEmpty) throw const PcmAsrException(PcmAsrErrorCode.engineFailure, 'no text after resume');
      return {'after_dispose': afterDispose};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('pcm_asr fixture')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(onPressed: running ? null : run, child: Text(running ? 'running…' : 'Run fixture ($locale)')),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: lines.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: SelectableText(lines[i], style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
