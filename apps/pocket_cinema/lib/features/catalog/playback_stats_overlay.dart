import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'rendering_window.dart';

/// Measures native callback cadence and completed Flutter raster frames.
/// Neither is a count of unique decoded video images or physical scanouts.
class PlaybackStatsOverlay extends StatefulWidget {
  const PlaybackStatsOverlay({required this.player, super.key});

  final Player? Function() player;

  @override
  State<PlaybackStatsOverlay> createState() => _PlaybackStatsOverlayState();
}

class _PlaybackStatsOverlayState extends State<PlaybackStatsOverlay>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.pocketcinema.app/rendering');
  final _frames = RenderingWindow();
  Timer? _timer;
  bool _sampling = false;
  bool _foreground = true;
  bool _nativeAvailable = false;
  String _text = 'Screen FPS: measuring…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_timings);
    unawaited(_startNative());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  Future<void> _startNative() async {
    try {
      await _channel.invokeMethod<void>('start');
      if (!mounted) {
        await _channel.invokeMethod<void>('stop');
        return;
      }
      _nativeAvailable = true;
    } on MissingPluginException {
      // Other platforms can still report Flutter raster timings.
    } on PlatformException {
      // Keep Flutter timing diagnostics available if the native bridge fails.
    }
  }

  void _timings(List<FrameTiming> timings) {
    if (!_foreground) return;
    for (final frame in timings) {
      _frames.add(
        RenderSample(
          finishedUs: frame.timestampInMicroseconds(
            FramePhase.rasterFinishWallTime,
          ),
          buildUs: frame.buildDuration.inMicroseconds,
          rasterUs: frame.rasterDuration.inMicroseconds,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _frames.clear();
  }

  Future<void> _sample() async {
    if (_sampling || !_foreground) return;
    final player = widget.player();
    final native = player?.platform;
    _sampling = true;
    try {
      final stats = _nativeAvailable
          ? await _channel.invokeMapMethod<String, dynamic>('sample')
          : null;
      if (!mounted) return;
      final hz =
          (stats?['refreshHz'] as num?)?.toDouble() ??
          View.of(context).display.refreshRate;
      final summary = _frames.sample(DateTime.now().microsecondsSinceEpoch, hz);
      final callbackFps = (stats?['callbackFps'] as num?)?.toDouble();
      final gap = (stats?['maxGapMs'] as num?)?.toDouble();
      var drops = '—', decoderDrops = '—', decoder = 'unavailable';
      if (native is NativePlayer) {
        try {
          final values = await Future.wait([
            native.getProperty('frame-drop-count'),
            native.getProperty('decoder-frame-drop-count'),
            native.getProperty('hwdec-current'),
          ]);
          drops = '${int.tryParse(values[0]) ?? '—'}';
          decoderDrops = '${int.tryParse(values[1]) ?? '—'}';
          decoder = values[2].isEmpty ? 'unavailable' : values[2];
        } catch (_) {
          // Native player can be disposed while an episode is being opened.
        }
      }
      if (!mounted || widget.player() != player) return;
      final status = player?.state.buffering == true
          ? ' • buffering'
          : player?.state.playing == true
          ? ''
          : ' • paused';
      final mode = kDebugMode
          ? 'debug'
          : kProfileMode
          ? 'profile'
          : 'release';
      final text =
          'Screen callbacks: ${callbackFps?.toStringAsFixed(1) ?? '—'} FPS'
          ' / ${hz.toStringAsFixed(1)} Hz\n'
          'Flutter render: ${summary.fps.toStringAsFixed(1)} FPS$status\n'
          'Worst gap: ${gap?.toStringAsFixed(1) ?? '—'} ms'
          ' • missed vsyncs: ${stats?['missedVsyncs'] ?? '—'} / 1s\n'
          'Slow renders: ${summary.slowFrames} / 2s'
          ' • build/raster: ${summary.buildMs.toStringAsFixed(1)} / '
          '${summary.rasterMs.toStringAsFixed(1)} ms\n'
          'Video drops: $drops output / $decoderDrops decoder\n'
          'HW: $decoder • $mode';
      if (_text != text) setState(() => _text = text);
    } catch (_) {
      // Opening, switching episodes, or closing can dispose the native player.
    } finally {
      _sampling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    WidgetsBinding.instance.removeObserver(this);
    if (_nativeAvailable) unawaited(_stopNative());
    super.dispose();
  }

  Future<void> _stopNative() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Activity may already be cleaning up its engine.
    } on MissingPluginException {
      // Platform bridge was removed during shutdown.
    }
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC0B0E16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: RepaintBoundary(
          child: Text(
            _text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              height: 1.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    ),
  );
}
