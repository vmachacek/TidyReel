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
import 'next_episode_prompt.dart';
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
  static int _nextWatchingSessionId = 0;
  final int _watchingSessionId = ++_nextWatchingSessionId;
  bool visible = true, fullscreen = false, opening = true;
  bool locked = false;
  late bool _lockHardwareVolumeButtons;
  bool autoplayCancelled = false;
  double brightness = 0.5;
  bool brightnessAvailable = false;
  double _confirmedBrightness = 0.5;
  double? _pendingBrightness;
  bool _applyingBrightness = false;
  bool _watchingClosed = false;
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
    _lockHardwareVolumeButtons = widget.library.lockHardwareVolumeButtons;
    widget.library.addListener(_lockPreferenceChanged);
    widget.controller.addListener(_playbackBlockChanged);
    _playbackBlockChanged();
    unawaited(syncControlsLock(false));
    unawaited(beginWatching());
    scheduleHide();
    unawaited(start(video));
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      widget.controller.refreshPlaybackSnapshot();
      checkAutoplay();
      if (++ticks % 4 == 0 && !opening) {
        widget.library.record(video, notify: false);
      }
      if (ticks % 20 == 0) unawaited(widget.library.persist());
    });
  }

  void _lockPreferenceChanged() {
    final value = widget.library.lockHardwareVolumeButtons;
    if (_lockHardwareVolumeButtons == value) return;
    _lockHardwareVolumeButtons = value;
    unawaited(syncControlsLock(locked));
  }

  void _playbackBlockChanged() {
    // A completed episode must not start another as the loading screen clears.
    if (widget.controller.playbackBlocked) autoplayCancelled = true;
  }

  @override
  void didUpdateWidget(CinemaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_playbackBlockChanged);
      widget.controller.addListener(_playbackBlockChanged);
      _playbackBlockChanged();
    }
    if (oldWidget.library != widget.library) {
      oldWidget.library.removeListener(_lockPreferenceChanged);
      widget.library.addListener(_lockPreferenceChanged);
      _lockPreferenceChanged();
    }
  }

  Future<void> start(CatalogVideo next) async {
    if (widget.controller.playbackBlocked) {
      opening = false;
      return;
    }
    video = next;
    opening = true;
    autoplayCancelled = false;
    final resume = widget.library.watched(next)
        ? 0
        : widget.library.positions[next.id] ?? 0;
    widget.controller.selectFile(next.file);
    await widget.controller.playSelected(
      startPosition: Duration(seconds: resume),
    );
    if (!mounted || _watchingClosed) return;
    if (mounted) setState(() => opening = false);
  }

  Future<void> togglePlayback() async {
    if (widget.controller.playbackBlocked || opening) return;
    if (widget.controller.playback.snapshot.isOpen) {
      await widget.controller.togglePlayPause();
    } else {
      await start(video);
    }
  }

  void playNext() {
    final next = nextVideo;
    if (widget.controller.playbackBlocked || opening || next == null) return;
    widget.library.record(video);
    unawaited(widget.library.persist());
    unawaited(start(next));
  }

  void checkAutoplay() {
    final playback = widget.controller.playback.snapshot;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (_watchingClosed ||
        widget.controller.playbackBlocked ||
        opening ||
        autoplayCancelled ||
        autoplayVideo == null ||
        !playback.isOpen ||
        !playback.isCompleted ||
        playback.isBuffering ||
        playback.failure != null ||
        widget.controller.state.failure != null ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        ModalRoute.isCurrentOf(context) == false) {
      return;
    }
    playNext();
  }

  void cancelAutoplay() {
    setState(() {
      autoplayCancelled = true;
      visible = true;
    });
    scheduleHide();
  }

  @override
  void dispose() {
    _releasePlayer();
    super.dispose();
  }

  void _releasePlayer() {
    if (_watchingClosed) return;
    _watchingClosed = true;
    _pendingBrightness = null;
    timer?.cancel();
    controlsTimer?.cancel();
    widget.library.removeListener(_lockPreferenceChanged);
    widget.controller.removeListener(_playbackBlockChanged);
    unawaited(syncControlsLock(false));
    unawaited(endWatching());
    if (!opening) widget.library.record(video);
    unawaited(widget.library.persist());
    unawaited(widget.controller.closePlayer());
  }

  void _playerPopped(bool didPop, Object? result) {
    if (!didPop) return;
    _releasePlayer();
    // Detach the outgoing view before another player starts during its animation.
    if (mounted) setState(() {});
  }

  Future<void> fullScreen() async {
    fullscreen = !fullscreen;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) setState(() => visible = !fullscreen);
  }

  void scheduleHide() {
    controlsTimer?.cancel();
    if (_watchingClosed || locked || !visible || activePointers > 0) return;
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
    unawaited(syncControlsLock(value));
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
        _watchingSessionId,
      );
      if (!mounted || _watchingClosed || value == null || !value.isFinite) {
        return;
      }
      setState(() {
        brightness = value.clamp(0.01, 1.0);
        _confirmedBrightness = brightness;
        brightnessAvailable = true;
      });
    } on MissingPluginException {
      // Playback remains usable on platforms without display controls.
    } on PlatformException catch (error) {
      debugPrint('Could not hold watching brightness: ${error.message}');
    }
  }

  Future<void> setBrightness(double value) async {
    if (locked || !brightnessAvailable || _watchingClosed) return;
    setState(() => brightness = value);
    _pendingBrightness = value;
    if (_applyingBrightness) return;
    _applyingBrightness = true;
    try {
      while (!_watchingClosed && _pendingBrightness != null) {
        final requested = _pendingBrightness!;
        _pendingBrightness = null;
        try {
          final applied = await _applyBrightness(requested);
          if (applied == null) return;
          _confirmedBrightness = applied;
        } on MissingPluginException {
          if (_watchingClosed) return;
          setState(() => brightnessAvailable = false);
          _pendingBrightness = null;
        } on PlatformException catch (error) {
          if (_watchingClosed) return;
          if (_pendingBrightness == null) {
            setState(() => brightness = _confirmedBrightness);
          }
          debugPrint('Could not adjust watching brightness: ${error.message}');
        }
      }
    } finally {
      _applyingBrightness = false;
    }
  }

  Future<double?> _applyBrightness(double value) async {
    try {
      await _controlsChannel.invokeMethod<void>('setBrightness', {
        'sessionId': _watchingSessionId,
        'brightness': value,
      });
    } on PlatformException catch (error) {
      if (error.code != 'NOT_WATCHING') rethrow;
      if (_watchingClosed) return null;
      final initial = await _controlsChannel.invokeMethod<double>(
        'beginWatching',
        _watchingSessionId,
      );
      if (_watchingClosed) {
        // A delayed native begin must not leave a closed player holding brightness.
        await endWatching();
        return null;
      }
      if (initial == null || !initial.isFinite) {
        throw PlatformException(code: 'BRIGHTNESS_UNAVAILABLE');
      }
      _confirmedBrightness = initial.clamp(0.01, 1.0);
      // Keep the latest drag position while the native session is being restored.
      value = _pendingBrightness ?? value;
      _pendingBrightness = null;
      await _controlsChannel.invokeMethod<void>('setBrightness', {
        'sessionId': _watchingSessionId,
        'brightness': value,
      });
    }
    return _watchingClosed ? null : value;
  }

  Future<void> endWatching() async {
    try {
      await _controlsChannel.invokeMethod<void>(
        'endWatching',
        _watchingSessionId,
      );
    } on MissingPluginException {
      // There is no native display override to release on this platform.
    } on PlatformException catch (error) {
      debugPrint('Could not restore display settings: ${error.message}');
    }
  }

  Future<void> syncControlsLock(bool value) async {
    try {
      await _controlsChannel.invokeMethod<void>('setLocked', {
        'locked': value,
        'lockHardwareVolumeButtons': _lockHardwareVolumeButtons,
      });
    } on MissingPluginException {
      // Touch controls remain locked on platforms without the Android bridge.
    } on PlatformException catch (error) {
      debugPrint('Could not update player controls lock: ${error.message}');
    }
  }

  CatalogVideo? get nextVideo {
    final index = widget.queue.indexWhere((v) => v.id == video.id);
    return index >= 0 && index + 1 < widget.queue.length
        ? widget.queue[index + 1]
        : null;
  }

  CatalogVideo? get autoplayVideo => video.series == null ? null : nextVideo;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _watchingClosed
        ? const AlwaysStoppedAnimation<double>(0)
        : widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final playback = state.playbackSnapshot;
      final duration = playback.duration.inSeconds,
          position = playback.position.inSeconds;
      final upcoming = autoplayVideo;
      final remaining = playback.duration - playback.position;
      final promptTop = visible
          ? 24.0 +
                (MediaQuery.textScalerOf(context).scale(14) * 3).clamp(
                  52.0,
                  double.infinity,
                )
          : 16.0;
      final showAutoplay =
          !widget.controller.playbackBlocked &&
          !locked &&
          !opening &&
          !autoplayCancelled &&
          upcoming != null &&
          playback.isOpen &&
          playback.duration > Duration.zero &&
          remaining <= const Duration(seconds: 15) &&
          state.failure == null &&
          playback.failure == null;
      return PopScope(
        canPop: !locked,
        onPopInvokedWithResult: _playerPopped,
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
                    if (!showAutoplay)
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
                                      onPressed: !opening
                                          ? togglePlayback
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
                    if (!showAutoplay)
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
                                    onPressed: !opening ? togglePlayback : null,
                                    tooltip: 'Play or pause',
                                    icon: Icon(
                                      playback.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    ),
                                  ),
                                  if (player != null)
                                    SizedBox(
                                      width: 220,
                                      child: Row(
                                        children: [
                                          IconButton(
                                            onPressed: () => setVolume(
                                              player!.state.volume > 0
                                                  ? 0
                                                  : 100,
                                            ),
                                            tooltip: 'Mute or unmute',
                                            icon: Icon(
                                              player!.state.volume > 0
                                                  ? Icons.volume_up
                                                  : Icons.volume_off,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 162,
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
                                          SizedBox(
                                            width: 162,
                                            child: Slider(
                                              key: const Key(
                                                'player-brightness-slider',
                                              ),
                                              value: brightness,
                                              min: 0.01,
                                              label:
                                                  '${(brightness * 100).round()}%',
                                              semanticFormatterCallback: (
                                                value,
                                              ) => 'Brightness ${(value * 100).round()} percent',
                                              onChanged: brightnessAvailable
                                                  ? setBrightness
                                                  : null,
                                              onChangeStart: (_) =>
                                                  controlsTimer?.cancel(),
                                              onChangeEnd: (_) =>
                                                  scheduleHide(),
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
                                      onPressed: opening ? null : playNext,
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
                    if (state.subtitleWarning != null && !showAutoplay)
                      Positioned(
                        top: 80,
                        left: 20,
                        right: 20,
                        child: chip(
                          'External subtitles could not be loaded. Video playback continues.',
                        ),
                      ),
                  ],
                  if (showAutoplay)
                    Positioned(
                      top: promptTop,
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.orientationOf(context) ==
                                        Orientation.landscape &&
                                    MediaQuery.sizeOf(context).height < 450
                                ? 600
                                : 360,
                          ),
                          child: NextEpisodePrompt(
                            key: const Key('next-episode-prompt'),
                            video: upcoming,
                            library: widget.library,
                            secondsRemaining:
                                (remaining.inMicroseconds /
                                        Duration.microsecondsPerSecond)
                                    .ceil()
                                    .clamp(0, 15),
                            paused: !playback.isPlaying,
                            onPlay: playNext,
                            onCancel: cancelAutoplay,
                            onTogglePlayback: togglePlayback,
                          ),
                        ),
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
