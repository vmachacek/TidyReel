import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'catalog_library.dart';
import 'catalog_metadata.dart';

Future<void> openCatalogArtworkPicker(
  BuildContext context,
  CatalogLibrary library,
  CatalogTitle title, {
  VoidCallback? onReviewMatch,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => CatalogArtworkPicker(
      library: library,
      title: title,
      onReviewMatch: onReviewMatch,
    ),
  ),
);

enum _ArtworkSource { tmdb, video }

/// Fetching and previewing never change the artwork saved in the library.
class CatalogArtworkPicker extends StatefulWidget {
  const CatalogArtworkPicker({
    required this.library,
    required this.title,
    this.onReviewMatch,
    super.key,
  });

  final CatalogLibrary library;
  final CatalogTitle title;
  final VoidCallback? onReviewMatch;

  @override
  State<CatalogArtworkPicker> createState() => _CatalogArtworkPickerState();
}

class _CatalogArtworkPickerState extends State<CatalogArtworkPicker> {
  CatalogArtworkKind _kind = CatalogArtworkKind.poster;
  late _ArtworkSource _source;
  CatalogArtworkFrame? _videoFrame;
  Duration _videoDuration = Duration.zero;
  bool _focusStart = true;
  double _positionMs = 0;
  int _frameRequest = 0;
  bool _loadingFrame = false;
  bool _captureRunning = false;
  bool _queuedFrame = false;
  String? _frameError;
  final _currentImages = <CatalogArtworkKind, Future<Uint8List?>>{};
  List<CatalogArtworkCandidate> _candidates = const [];
  final _selections = <CatalogArtworkKind, CatalogArtworkCandidate>{};
  bool _fetching = false;
  bool _saving = false;
  String? _fetchError;
  String? _saveError;

  bool get _enabled => widget.library.matcher.enabled;
  bool get _matched => widget.title.providerId?.isNotEmpty == true;
  bool get _canFetch => _enabled && _matched;
  bool get _fromVideo => _source == _ArtworkSource.video;
  Duration get _videoRangeDuration =>
      _focusStart && _videoDuration > const Duration(minutes: 1)
      ? const Duration(minutes: 1)
      : _videoDuration;
  double get _sliderMaximum => math
      .max(
        0,
        math.min(
          _videoRangeDuration.inMilliseconds,
          _videoDuration.inMilliseconds - 1,
        ),
      )
      .toDouble();
  bool get _canSave =>
      !_saving &&
      (_fromVideo
          ? _videoFrame != null && !_loadingFrame
          : _selected != null && !_fetching);
  CatalogArtworkCandidate? get _selected => _selections[_kind];
  List<CatalogArtworkCandidate> get _visibleCandidates =>
      _candidates.where((candidate) => candidate.kind == _kind).toList();

  @override
  void initState() {
    super.initState();
    _source = !_canFetch && widget.library.artworkVideo(widget.title) != null
        ? _ArtworkSource.video
        : _ArtworkSource.tmdb;
    for (final kind in CatalogArtworkKind.values) {
      _currentImages[kind] = widget.library.thumbnail(
        widget.title.first,
        backdrop: kind == CatalogArtworkKind.backdrop,
      );
    }
    if (_canFetch) unawaited(_refresh());
    if (_fromVideo) unawaited(_loadFrame());
  }

  String _errorMessage(Object error, String fallback) =>
      error is CatalogMetadataException ? error.message : fallback;

  Future<void> _refresh() async {
    if (_fetching || _saving || !_canFetch) return;
    setState(() {
      _fetching = true;
      _fetchError = null;
      _saveError = null;
    });
    try {
      final candidates = await widget.library.refreshArtwork(widget.title);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        // A newly fetched list must be reviewed before anything is saved.
        _selections.clear();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _fetchError = _errorMessage(
          error,
          'Artwork could not be refreshed. Check your connection and try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    final candidate = _selected;
    final frame = _videoFrame;
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      if (_fromVideo) {
        await widget.library.selectVideoArtwork(widget.title, _kind, frame!);
      } else {
        await widget.library.selectArtwork(widget.title, candidate!);
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saveError = _errorMessage(
          error,
          'Artwork could not be saved. Your current artwork is still in use.',
        );
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _changeSource(_ArtworkSource source) {
    if (_saving || source == _source) return;
    setState(() {
      _source = source;
      _saveError = null;
      _loadingFrame = false;
      _queuedFrame = false;
      _frameRequest++;
    });
    if (_fromVideo && _videoFrame == null) unawaited(_loadFrame());
  }

  Future<void> _loadFrame() async {
    if (_saving ||
        !_fromVideo ||
        widget.library.artworkVideo(widget.title) == null) {
      return;
    }
    final request = ++_frameRequest;
    setState(() {
      _loadingFrame = true;
      _videoFrame = null;
      _frameError = null;
      _saveError = null;
    });
    if (_captureRunning) {
      _queuedFrame = true;
      return;
    }
    _captureRunning = true;
    try {
      final frame = await widget.library.videoArtworkFrame(
        widget.title,
        Duration(milliseconds: _positionMs.round()),
      );
      if (!mounted || request != _frameRequest) return;
      setState(() {
        _videoFrame = frame;
        _videoDuration = frame.duration;
        _positionMs = frame.position.inMilliseconds.toDouble();
      });
    } on Object catch (error) {
      if (!mounted || request != _frameRequest) return;
      setState(() {
        _frameError = _errorMessage(
          error,
          'The screenshot could not be captured. Try another position or retry.',
        );
      });
    } finally {
      _captureRunning = false;
      if (mounted && request == _frameRequest) {
        setState(() => _loadingFrame = false);
      }
      if (mounted && _queuedFrame) {
        _queuedFrame = false;
        unawaited(_loadFrame());
      }
    }
  }

  void _seekFrame(double position) {
    setState(() {
      _positionMs = position.clamp(0, _sliderMaximum);
      _videoFrame = null;
      _frameError = null;
      _saveError = null;
      _loadingFrame = false;
      _queuedFrame = false;
      _frameRequest++;
    });
  }

  void _changeVideoRange(bool focusStart) {
    if (_saving || focusStart == _focusStart) return;
    setState(() => _focusStart = focusStart);
    if (_positionMs > _sliderMaximum) {
      _seekFrame(_sliderMaximum);
      unawaited(_loadFrame());
    }
  }

  String _time(Duration time) {
    final seconds = time.inSeconds;
    final minutes = (seconds ~/ 60) % 60;
    final remaining = (seconds % 60).toString().padLeft(2, '0');
    return seconds >= 3600
        ? '${seconds ~/ 3600}:${minutes.toString().padLeft(2, '0')}:$remaining'
        : '${seconds ~/ 60}:$remaining';
  }

  void _reviewMatch() {
    Navigator.of(context).pop();
    widget.onReviewMatch?.call();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      key: const Key('artwork-screen'),
      appBar: AppBar(
        leading: BackButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        title: Text('Artwork for ${widget.title.name}'),
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Choose artwork',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pick an image from TMDB or capture a frame from S01E01. Your choice is saved on this device.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('artwork-source-tmdb'),
                      avatar: const Icon(Icons.image_search, size: 18),
                      label: const Text('TMDB images'),
                      selected: !_fromVideo,
                      onSelected: _saving
                          ? null
                          : (_) => _changeSource(_ArtworkSource.tmdb),
                    ),
                    ChoiceChip(
                      key: const Key('artwork-source-video'),
                      avatar: const Icon(Icons.video_library, size: 18),
                      label: const Text('S01E01 screenshot'),
                      selected: _fromVideo,
                      onSelected: _saving
                          ? null
                          : (_) => _changeSource(_ArtworkSource.video),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final kind in CatalogArtworkKind.values)
                      ChoiceChip(
                        key: Key('artwork-kind-${kind.name}'),
                        label: Text(
                          kind == CatalogArtworkKind.poster
                              ? 'Poster'
                              : 'Backdrop',
                        ),
                        selected: kind == _kind,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() {
                                _kind = kind;
                                _saveError = null;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _comparison(),
                const SizedBox(height: 20),
                if (_fromVideo) _videoEditor() else _onlineGallery(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_saveError != null) ...[
                _error(_saveError!),
                const SizedBox(height: 8),
              ],
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const Key('artwork-keep-current'),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Keep current'),
                  ),
                  FilledButton.icon(
                    key: const Key('artwork-use-selected'),
                    onPressed: _canSave ? () => unawaited(_save()) : null,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _fromVideo ? Icons.photo_camera : Icons.download,
                          ),
                    label: Text(
                      _saving
                          ? 'Saving…'
                          : _fromVideo
                          ? 'Use screenshot'
                          : 'Use selected',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _videoEditor() {
    final video = widget.library.artworkVideo(widget.title);
    if (video == null) {
      return const Text(
        'S01E01 is not in this library. Add the first episode to capture a screenshot.',
      );
    }
    final maximum = _sliderMaximum;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Screenshot from S01E01',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(video.file.displayName),
        const SizedBox(height: 8),
        const Text(
          'Move the slider and release to preview a frame, then use the screenshot as your artwork.',
        ),
        if (_kind == CatalogArtworkKind.poster) ...[
          const SizedBox(height: 8),
          const Text('The preview shows how the frame fits a poster.'),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const Key('artwork-range-start'),
              label: const Text('Start (first minute)'),
              selected: _focusStart,
              onSelected: _saving ? null : (_) => _changeVideoRange(true),
            ),
            ChoiceChip(
              key: const Key('artwork-range-whole'),
              label: const Text('Whole video'),
              selected: !_focusStart,
              onSelected: _saving ? null : (_) => _changeVideoRange(false),
            ),
          ],
        ),
        Slider(
          key: const Key('artwork-video-slider'),
          value: _positionMs.clamp(0, maximum),
          max: maximum,
          label: _time(Duration(milliseconds: _positionMs.round())),
          onChanged: maximum > 0 && !_saving ? _seekFrame : null,
          onChangeEnd: maximum > 0 && !_saving
              ? (_) => unawaited(_loadFrame())
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_time(Duration(milliseconds: _positionMs.round()))),
            Text(_time(_videoRangeDuration)),
          ],
        ),
        if (_loadingFrame) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Capturing screenshot…'),
        ],
        if (_frameError != null) ...[
          const SizedBox(height: 12),
          _error(_frameError!),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('artwork-video-retry'),
              onPressed: _saving ? null : () => unawaited(_loadFrame()),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry screenshot'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _onlineGallery() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!_enabled)
        const Text('Enable TMDB in Library Settings to refresh artwork.')
      else if (!_matched) ...[
        const Text(
          'Choose a TMDB match for this show before refreshing artwork.',
        ),
        if (widget.onReviewMatch != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _reviewMatch,
              icon: const Icon(Icons.manage_search),
              label: const Text('Review match'),
            ),
          ),
      ] else ...[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              '${_visibleCandidates.length} ${_kind == CatalogArtworkKind.poster ? 'posters' : 'backdrops'} from TMDB',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            OutlinedButton.icon(
              key: const Key('artwork-refresh'),
              onPressed: _fetching || _saving
                  ? null
                  : () => unawaited(_refresh()),
              icon: const Icon(Icons.refresh),
              label: Text(_fetchError == null ? 'Refresh again' : 'Retry'),
            ),
          ],
        ),
        if (_fetching) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Fetching artwork from TMDB…'),
        ],
        if (_fetchError != null) ...[
          const SizedBox(height: 12),
          _error(_fetchError!),
        ],
        if (_visibleCandidates.isNotEmpty) ...[
          const SizedBox(height: 12),
          _gallery(),
        ] else if (!_fetching && _fetchError == null) ...[
          const SizedBox(height: 12),
          Text(
            'TMDB has no ${_kind == CatalogArtworkKind.poster ? 'posters' : 'backdrops'} for this show. Your current artwork is still in use.',
          ),
        ],
      ],
    ],
  );
  Widget _error(String message) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Widget _comparison() => LayoutBuilder(
    builder: (context, constraints) {
      final aspect = _kind == CatalogArtworkKind.poster ? 2 / 3 : 16 / 9;
      final height = math.min(280.0, (constraints.maxWidth - 12) / 2 / aspect);
      Widget frame(Widget child) => SizedBox(
        height: height,
        width: double.infinity,
        child: Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: child,
              ),
            ),
          ),
        ),
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Current artwork'),
                const SizedBox(height: 8),
                frame(
                  FutureBuilder<Uint8List?>(
                    future: _currentImages[_kind],
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      return bytes == null
                          ? const _ArtworkPlaceholder('No current artwork')
                          : Image.memory(
                              bytes,
                              key: Key('artwork-current-${_kind.name}'),
                              fit: BoxFit.contain,
                              semanticLabel: 'Current ${_kind.name}',
                              errorBuilder: (_, _, _) =>
                                  const _ArtworkPlaceholder(
                                    'Current preview unavailable',
                                  ),
                            );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_fromVideo ? 'Screenshot preview' : 'Selected artwork'),
                const SizedBox(height: 8),
                frame(
                  _fromVideo
                      ? _videoFrame == null
                            ? _ArtworkPlaceholder(
                                _loadingFrame
                                    ? 'Capturing screenshot…'
                                    : 'Move the slider to choose a frame',
                              )
                            : Image.memory(
                                _videoFrame!.bytes,
                                key: const Key('artwork-video-preview'),
                                fit: BoxFit.cover,
                                semanticLabel:
                                    'S01E01 screenshot at ${_time(_videoFrame!.position)}',
                                errorBuilder: (_, _, _) =>
                                    const _ArtworkPlaceholder(
                                      'Screenshot preview unavailable',
                                    ),
                              )
                      : _selected == null
                      ? const _ArtworkPlaceholder('Select an image below')
                      : _ArtworkPreview(candidate: _selected!),
                ),
                if (_fromVideo && _videoFrame != null) ...[
                  const SizedBox(height: 6),
                  Text('S01E01 · ${_time(_videoFrame!.position)}'),
                ] else if (!_fromVideo && _selected != null) ...[
                  const SizedBox(height: 6),
                  Text(_description(_selected!)),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );

  String _description(CatalogArtworkCandidate candidate) =>
      '${candidate.width} × ${candidate.height} · ${candidate.language ?? 'No language'}';

  Widget _gallery() => LayoutBuilder(
    builder: (context, constraints) {
      final visible = _visibleCandidates;
      final columns = _kind == CatalogArtworkKind.poster
          ? constraints.maxWidth < 500
                ? 3
                : 5
          : constraints.maxWidth < 500
          ? 2
          : 3;
      return GridView.builder(
        key: Key('artwork-gallery-${_kind.name}'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: visible.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: _kind == CatalogArtworkKind.poster ? 2 / 3 : 16 / 9,
        ),
        itemBuilder: (context, index) {
          final candidate = visible[index];
          final selected = _selected?.filePath == candidate.filePath;
          return Semantics(
            button: true,
            selected: selected,
            label: '${_kind.name} ${index + 1}, ${_description(candidate)}',
            child: Material(
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InkWell(
                key: Key('artwork-candidate-${candidate.kind.name}-$index'),
                onTap: _saving || _fetching
                    ? null
                    : () => setState(() {
                        _selections[_kind] = candidate;
                        _saveError = null;
                      }),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ArtworkPreview(candidate: candidate),
                    if (selected)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.check_circle),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _ArtworkPreview extends StatelessWidget {
  const _ArtworkPreview({required this.candidate});
  final CatalogArtworkCandidate candidate;

  @override
  Widget build(BuildContext context) => Image.network(
    candidate.previewUrl,
    fit: BoxFit.contain,
    semanticLabel: '${candidate.kind.name} from TMDB',
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    errorBuilder: (_, _, _) => const _ArtworkPlaceholder('Preview unavailable'),
  );
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
