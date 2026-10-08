import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../infrastructure/playback/media_kit_playback_engine.dart';
import '../../infrastructure/playback/media_kit_playback_surface.dart';
import '../risk_spike/playback_session_coordinator.dart';
import '../risk_spike/risk_spike_controller.dart';
import '../risk_spike/widgets/failure_panel.dart';
import 'catalog_library.dart';
import 'catalog_screen.dart';
import 'playback_stats_overlay.dart';
import 'hold_to_activate_button.dart';

class CinemaPlayer extends StatefulWidget {
  const CinemaPlayer({
    required this.title,
    required this.controller,
    required this.library,
    required this.video,
    this.queue = const [],
    this.playbackSurface,
    super.key,
  });
  final String title;
  final RiskSpikeController controller;
  final CatalogLibrary library;
  final CatalogVideo video;
  final List<CatalogVideo> queue;
  final Widget? playbackSurface;
  @override
  State<CinemaPlayer> createState() => _CinemaPlayerState();
}

class _CinemaPlayerState extends State<CinemaPlayer> {
  static const _controlsChannel = MethodChannel(
    'com.pocketcinema.app/player_controls',
  );
  bool visible = true, fullscreen = false, opening = true;
  bool locked = false;
  double brightness = 0.5;
  bool brightnessAvailable = false;
  int activePointers = 0;
  Timer? controlsTimer;
  late CatalogVideo video = widget.video;
  Timer? timer;
  int ticks = 0;
  Player? get player {
    final session = widget.controller.playback;
    if (session is PlaybackSessionCoordinator &&
        session.activeEngine is MediaKitPlaybackEngine) {
      return (session.activeEngine! as MediaKitPlaybackEngine).player;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(syncVolumeLock(false));
    unawaited(beginWatching());
    scheduleHide();
    unawaited(start(video));
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      widget.controller.refreshPlaybackSnapshot();
      if (++ticks % 4 == 0 && !opening) {
        widget.library.record(video, notify: false);
      }
      if (ticks % 20 == 0) unawaited(widget.library.persist());
    });
  }

  Future<void> start(CatalogVideo next) async {
    video = next;
    opening = true;
    final resume = widget.library.watched(next)
        ? 0
        : widget.library.positions[next.id] ?? 0;
    widget.controller.selectFile(next.file);
    await widget.controller.playSelected(
      startPosition: Duration(seconds: resume),
    );
    if (!mounted) return;
    if (mounted) setState(() => opening = false);
  }

  @override
  void dispose() {
    timer?.cancel();
    controlsTimer?.cancel();
    unawaited(syncVolumeLock(false));
    unawaited(endWatching());
    if (!opening) widget.library.record(video);
    unawaited(widget.library.persist());
    unawaited(widget.controller.closePlayer());
    super.dispose();
  }

  Future<void> fullScreen() async {
    fullscreen = !fullscreen;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) setState(() => visible = !fullscreen);
  }

  void scheduleHide() {
    controlsTimer?.cancel();
    if (locked || !visible || activePointers > 0) return;
    controlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || locked) return;
      // Do not dismiss controls while a track/speed sheet is in use.
      if (ModalRoute.isCurrentOf(context) == false || opening) {
        scheduleHide();
        return;
      }
      setState(() => visible = false);
    });
  }

  void toggleControls() {
    if (locked) return;
    setState(() => visible = !visible);
    scheduleHide();
  }

  void setLocked(bool value) {
    controlsTimer?.cancel();
    setState(() {
      locked = value;
      visible = !value;
    });
    unawaited(syncVolumeLock(value));
    unawaited(HapticFeedback.mediumImpact());
    if (!value) scheduleHide();
  }

  Future<void> setVolume(double value) async {
    if (locked) return;
    await player?.setVolume(value);
    if (mounted) setState(() {});
  }

  Future<void> beginWatching() async {
    try {
      final value = await _controlsChannel.invokeMethod<double>(
        'beginWatching',
      );
      if (!mounted || value == null || !value.isFinite) return;
      setState(() {
        brightness = value.clamp(0.01, 1.0);
        brightnessAvailable = true;
      });
    } on MissingPluginException {
      // Playback remains usable on platforms without display controls.
    } on PlatformException catch (error) {
      debugPrint('Could not hold watching brightness: ${error.message}');
    }
  }

  Future<void> setBrightness(double value) async {
    if (locked || !brightnessAvailable) return;
    final previous = brightness;
    setState(() => brightness = value);
    try {
      await _controlsChannel.invokeMethod<void>('setBrightness', value);
    } on MissingPluginException {
      if (mounted) setState(() => brightnessAvailable = false);
    } on PlatformException catch (error) {
      if (mounted && brightness == value) {
        setState(() => brightness = previous);
      }
      debugPrint('Could not adjust watching brightness: ${error.message}');
    }
  }

  Future<void> endWatching() async {
    try {
      await _controlsChannel.invokeMethod<void>('endWatching');
    } on MissingPluginException {
      // There is no native display override to release on this platform.
    } on PlatformException catch (error) {
      debugPrint('Could not restore display settings: ${error.message}');
    }
  }

  Future<void> syncVolumeLock(bool value) async {
    try {
      await _controlsChannel.invokeMethod<void>('setLocked', value);
    } on MissingPluginException {
      // Touch controls remain locked on platforms without the Android bridge.
    } on PlatformException catch (error) {
      debugPrint('Could not update player volume lock: ${error.message}');
    }
  }

  CatalogVideo? get nextVideo {
    final index = widget.queue.indexWhere((v) => v.id == video.id);
    return index >= 0 && index + 1 < widget.queue.length
        ? widget.queue[index + 1]
        : null;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final playback = state.playbackSnapshot;
      final duration = playback.duration.inSeconds,
          position = playback.position.inSeconds;
      return PopScope(
        canPop: !locked,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Listener(
              onPointerDown: (_) {
                activePointers++;
                controlsTimer?.cancel();
              },
              onPointerUp: (_) {
                activePointers = (activePointers - 1).clamp(0, 100);
                scheduleHide();
              },
              onPointerCancel: (_) {
                activePointers = (activePointers - 1).clamp(0, 100);
                scheduleHide();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (playback.isOpen && widget.playbackSurface != null)
                    Center(
                      // This route owns the display across pauses and episodes.
                      // Diagnostics retains the surface's default wake lock.
                      child: switch (widget.playbackSurface!) {
                        MediaKitPlaybackSurface(:final session, :final key) =>
                          MediaKitPlaybackSurface(
                            session: session,
                            wakelock: false,
                            key: key,
                          ),
                        final surface => surface,
                      },
                    )
                  else
                    VideoArtwork(
                      video: video,
                      library: widget.library,
                      backdrop: true,
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: toggleControls,
                    ),
                  ),
                  if (visible)
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xEE0B0E16),
                              Colors.transparent,
                              Color(0xEE0B0E16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (visible) ...[
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            tooltip: 'Back to library',
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              video.series == null
                                  ? video.title
                                  : '${video.series} • ${video.episodeCode} · ${video.title}',
                              maxLines: 2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: playback.isOpen ? tracks : null,
                            tooltip: 'Audio & Subtitles',
                            icon: const Icon(Icons.subtitles_outlined),
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: opening || playback.isBuffering
                          ? const CircularProgressIndicator()
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  onPressed: playback.isOpen
                                      ? () => widget.controller.seekBy(
                                          const Duration(seconds: -10),
                                        )
                                      : null,
                                  iconSize: 32,
                                  icon: const Icon(Icons.replay_10),
                                ),
                                const SizedBox(width: 24),
                                SizedBox(
                                  width: 88,
                                  height: 88,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      shape: const CircleBorder(),
                                      padding: EdgeInsets.zero,
                                    ),
                                    onPressed: playback.isOpen
                                        ? widget.controller.togglePlayPause
                                        : null,
                                    child: Icon(
                                      playback.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      size: 44,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 24),
                                IconButton.filledTonal(
                                  onPressed: playback.isOpen
                                      ? () => widget.controller.seekBy(
                                          const Duration(seconds: 10),
                                        )
                                      : null,
                                  iconSize: 32,
                                  icon: const Icon(Icons.forward_10),
                                ),
                              ],
                            ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xEE0B0E16),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${clock(position)} / ${clock(duration)}',
                                  style: const TextStyle(color: peach),
                                ),
                                const Spacer(),
                                Text(
                                  '${clock((duration - position).clamp(0, duration))} remaining',
                                  style: const TextStyle(
                                    color: peach,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: duration > 0
                                  ? (position / duration).clamp(0, 1)
                                  : 0,
                              onChanged: playback.isOpen && duration > 0
                                  ? (v) => widget.controller.seekBy(
                                      Duration(
                                        seconds:
                                            (v * duration).round() - position,
                                      ),
                                    )
                                  : null,
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: playback.isOpen
                                      ? widget.controller.togglePlayPause
                                      : null,
                                  tooltip: 'Play or pause',
                                  icon: Icon(
                                    playback.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                  ),
                                ),
                                if (player != null)
                                  SizedBox(
                                    width: 140,
                                    child: Row(
                                      children: [
                                        IconButton(
                                          onPressed: () => setVolume(
                                            player!.state.volume > 0 ? 0 : 100,
                                          ),
                                          tooltip: 'Mute or unmute',
                                          icon: Icon(
                                            player!.state.volume > 0
                                                ? Icons.volume_up
                                                : Icons.volume_off,
                                          ),
                                        ),
                                        Expanded(
                                          child: Slider(
                                            value: player!.state.volume.clamp(
                                              0,
                                              100,
                                            ),
                                            max: 100,
                                            onChanged: setVolume,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                SizedBox(
                                  width: 220,
                                  child: Tooltip(
                                    message: 'Brightness',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.brightness_6_outlined,
                                          size: 22,
                                        ),
                                        Expanded(
                                          child: Slider(
                                            key: const Key(
                                              'player-brightness-slider',
                                            ),
                                            value: brightness,
                                            min: 0.01,
                                            label:
                                                '${(brightness * 100).round()}%',
                                            semanticFormatterCallback: (value) =>
                                                'Brightness ${(value * 100).round()} percent',
                                            onChanged: brightnessAvailable
                                                ? setBrightness
                                                : null,
                                            onChangeStart: (_) =>
                                                controlsTimer?.cancel(),
                                            onChangeEnd: (_) => scheduleHide(),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 36,
                                          child: Text(
                                            brightnessAvailable
                                                ? '${(brightness * 100).round()}%'
                                                : '—',
                                            style: const TextStyle(
                                              color: peach,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: playback.isOpen ? tracks : null,
                                  child: const Text('Audio & Subs'),
                                ),
                                if (player != null)
                                  TextButton(
                                    onPressed: speed,
                                    child: Text('${player!.state.rate}×'),
                                  ),
                                if (nextVideo != null)
                                  IconButton(
                                    onPressed: opening
                                        ? null
                                        : () {
                                            widget.library.record(video);
                                            unawaited(widget.library.persist());
                                            unawaited(start(nextVideo!));
                                          },
                                    tooltip: 'Next Episode',
                                    icon: const Icon(Icons.skip_next),
                                  ),
                                IconButton(
                                  onPressed: fullScreen,
                                  tooltip: 'Fullscreen',
                                  icon: Icon(
                                    fullscreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                  ),
                                ),
                                IconButton(
                                  onPressed: toggleControls,
                                  tooltip: 'Hide controls',
                                  icon: const Icon(
                                    Icons.visibility_off_outlined,
                                  ),
                                ),
                                HoldToActivateButton(
                                  key: const Key('lock-player'),
                                  label: 'Hold to lock player',
                                  icon: Icons.lock_outline,
                                  onActivate: () => setLocked(true),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (state.failure != null)
                      Positioned(
                        top: 80,
                        left: 20,
                        right: 20,
                        child: FailurePanel(
                          failure: state.failure!,
                          controller: widget.controller,
                        ),
                      ),
                    if (state.subtitleWarning != null)
                      Positioned(
                        top: 80,
                        left: 20,
                        right: 20,
                        child: chip(
                          'External subtitles could not be loaded. Video playback continues.',
                        ),
                      ),
                  ],
                  if (!locked)
                    Positioned(
                      top: visible ? 76 : 12,
                      right: 16,
                      child: PlaybackStatsOverlay(
                        key: ValueKey(video.id),
                        player: () => player,
                      ),
                    ),
                  if (locked) ...[
                    const Positioned.fill(
                      child: AbsorbPointer(child: SizedBox.expand()),
                    ),
                    Positioned(
                      bottom: 24,
                      right: 24,
                      child: HoldToActivateButton(
                        key: const Key('unlock-player'),
                        label: 'Hold to unlock player',
                        icon: Icons.lock_open,
                        onActivate: () => setLocked(false),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  Future<void> tracks() async {
    final active = player;
    if (active == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Audio & Subtitles',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Text('Audio', style: TextStyle(color: peach)),
              for (final track in active.state.tracks.audio)
                ListTile(
                  leading: Icon(
                    active.state.track.audio.id == track.id
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  title: Text(
                    track.title ??
                        track.language ??
                        (track.id == 'auto'
                            ? 'Automatic'
                            : track.id == 'no'
                            ? 'Off'
                            : 'Audio ${track.id}'),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await active.setAudioTrack(track);
                  },
                ),
              const SizedBox(height: 12),
              const Text('Subtitles', style: TextStyle(color: peach)),
              ListTile(
                title: const Text('Off'),
                onTap: () async {
                  Navigator.pop(context);
                  await active.setSubtitleTrack(SubtitleTrack.no());
                },
              ),
              for (final track in {
                ...active.state.tracks.subtitle,
                active.state.track.subtitle,
              }.where((t) => t.id != 'no'))
                ListTile(
                  leading: Icon(
                    active.state.track.subtitle.id == track.id
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  title: Text(
                    track.title ??
                        track.language ??
                        (track.id == 'auto'
                            ? 'Automatic'
                            : 'Subtitles ${track.id}'),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await active.setSubtitleTrack(track);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void speed() => showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Wrap(
        children: [
          for (final rate in [.5, .75, 1.0, 1.25, 1.5, 2.0])
            ListTile(
              title: Text('$rate×'),
              onTap: () async {
                Navigator.pop(context);
                await player?.setRate(rate);
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
    ),
  );
}

String clock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
