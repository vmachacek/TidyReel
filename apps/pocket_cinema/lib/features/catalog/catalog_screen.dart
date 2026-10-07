import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import '../../app/app_brand.dart';
import '../risk_spike/risk_spike_controller.dart';
import '../risk_spike/risk_spike_screen.dart';
import '../risk_spike/risk_spike_state.dart';
import '../risk_spike/widgets/failure_panel.dart';
import 'catalog_artwork_picker.dart';
import 'catalog_library.dart';
import 'catalog_metadata_settings.dart';
import 'cinema_player.dart';
import 'route_content_builder.dart';

const coral = Color(0xFFFF5A36);
const peach = Color(0xFFFFB4A3);
const panel = Color(0xFF181B24);

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    required this.controller,
    this.playbackSurface,
    super.key,
  });
  final RiskSpikeController controller;
  final Widget? playbackSurface;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final CatalogLibrary library = CatalogLibrary(widget.controller);
  String query = '', filter = 'All', sort = 'Recently Modified';
  bool listView = false;
  int destination = 0;
  List<CatalogTitle> titlesFor(List<StorageEntrySnapshot> entries) =>
      library.titlesFor(entries);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(autoScan);
    WidgetsBinding.instance.addPostFrameCallback((_) => autoScan());
  }

  void autoScan() {
    final state = widget.controller.state;
    if (state.root != null &&
        state.phase == RiskSpikePhase.ready &&
        !state.scanCompleted) {
      unawaited(widget.controller.scan(state.root!));
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(autoScan);
    library.dispose();
    super.dispose();
  }

  void diagnostics() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RiskSpikeScreen(
        controller: widget.controller,
        playbackSurface: widget.playbackSurface,
      ),
    ),
  );
  Future<void> connect() async {
    await widget.controller.chooseRoot();
  }

  void details(CatalogTitle title) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CatalogDetail(
        title: title,
        library: library,
        playbackSurface: widget.playbackSurface,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => RouteContentBuilder(
    animation: Listenable.merge([widget.controller, library]),
    builder: (context) {
      final state = widget.controller.state;
      final busy =
          state.phase == RiskSpikePhase.enumerating ||
          state.phase == RiskSpikePhase.choosingRoot ||
          state.phase == RiskSpikePhase.checkingGrant;
      if (state.root == null || state.canRepairRoot) {
        return Scaffold(
          appBar: AppBar(
            title: const AppBrand(),
            actions: [
              IconButton(
                onPressed: diagnostics,
                tooltip: 'Diagnostics',
                icon: const Icon(Icons.bug_report_outlined),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    key: const Key('folder-onboarding'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/branding/pocket_play.png',
                            width: 112,
                            height: 112,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Welcome to Pocket Cinema',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Start with your media folder',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: peach,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Choose the folder where you keep your movies and shows. Pocket Cinema needs access to that folder to build your library and play your videos.',
                        textAlign: TextAlign.center,
                        style: TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 28),
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '1. Choose your media folder',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 12),
                              Text(
                                '2. Allow access in the Android folder picker',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 12),
                              Text(
                                '3. We scan your videos and open your library',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (state.failure != null) ...[
                        FailurePanel(
                          failure: state.failure!,
                          controller: widget.controller,
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (state.phase == RiskSpikePhase.checkingGrant) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        const Text(
                          'Checking your saved folder…',
                          textAlign: TextAlign.center,
                        ),
                      ] else
                        FilledButton.icon(
                          key: const Key('onboarding-connect-folder'),
                          onPressed: busy ? null : connect,
                          icon: const Icon(Icons.folder_open),
                          label: Text(
                            busy
                                ? 'Waiting for folder selection…'
                                : 'Connect media folder',
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your videos stay on your device. You can change the folder later in Library.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: peach,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      final all = titlesFor(state.entries);
      final visible = all
          .where(
            (t) =>
                (t.name.toLowerCase().contains(query.toLowerCase()) ||
                    t.videos.any(
                      (v) => v.file.displayName.toLowerCase().contains(
                        query.toLowerCase(),
                      ),
                    )) &&
                (filter != 'Watchlist' || library.isSaved(t)) &&
                (filter != 'Movies' || !t.isSeries) &&
                (filter != 'TV Shows' || t.isSeries),
          )
          .toList();
      visible.sort(
        (a, b) => sort == 'A–Z'
            ? a.name.compareTo(b.name)
            : (b.modified ?? DateTime(1970)).compareTo(
                a.modified ?? DateTime(1970),
              ),
      );
      final movies = visible.where((t) => !t.isSeries).toList();
      final shows = visible.where((t) => t.isSeries).toList();
      final continuing = visible
          .where(
            (t) => t.videos.any(
              (v) => (library.positions[v.id] ?? 0) > 0 && !library.watched(v),
            ),
          )
          .toList();
      final spotlight = continuing.isNotEmpty
          ? continuing.first
          : visible.isNotEmpty
          ? visible.first
          : null;
      return Scaffold(
        appBar: AppBar(
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AppBrand(),
          ),
          actions: [
            TextButton.icon(
              onPressed: diagnostics,
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('Diagnostics'),
            ),
          ],
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width < 850
            ? NavigationBar(
                selectedIndex: destination,
                onDestinationSelected: (i) {
                  if (i < 2) setState(() => destination = i);
                  if (i == 2) activity();
                  if (i == 3) settings();
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.video_library_outlined),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.sync),
                    label: 'Activity',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tune),
                    label: 'Settings',
                  ),
                ],
              )
            : null,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: ListView(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
              ),
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final tab in [
                      'All',
                      'Movies',
                      'TV Shows',
                      'Watchlist',
                    ])
                      ChoiceChip(
                        label: Text(tab),
                        selected: filter == tab,
                        onSelected: (_) => setState(() => filter = tab),
                      ),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        onChanged: (v) => setState(() => query = v),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search your library…',
                          isDense: true,
                        ),
                      ),
                    ),
                    chip('LOCAL STORAGE • ${state.root!.displayName}'),
                    IconButton(
                      onPressed: settings,
                      tooltip: 'Library settings',
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (state.failure != null) ...[
                  FailurePanel(
                    failure: state.failure!,
                    controller: widget.controller,
                  ),
                  const SizedBox(height: 20),
                ],
                if (busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    'Scanning · ${state.discoveredCount} files discovered',
                    style: const TextStyle(color: peach),
                  ),
                  if (state.canCancel)
                    TextButton(
                      onPressed: widget.controller.cancelScan,
                      child: const Text('Cancel scan'),
                    ),
                ],
                if (spotlight != null && query.isEmpty && destination == 0) ...[
                  CinemaHero(
                    title: spotlight,
                    library: library,
                    eyebrow: continuing.isNotEmpty
                        ? 'CONTINUE WATCHING'
                        : 'FROM YOUR LIBRARY',
                    actions: [
                      FilledButton.icon(
                        onPressed: () => openVideo(
                          context,
                          library,
                          library.next(spotlight),
                          widget.playbackSurface,
                          queue: spotlight.videos,
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          continuing.isNotEmpty ? 'Resume' : 'Play Now',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => details(spotlight),
                        icon: const Icon(Icons.info_outline),
                        label: const Text('More Info'),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => library.toggleSaved(spotlight.id),
                        tooltip: 'Toggle watchlist',
                        icon: Icon(
                          library.isSaved(spotlight)
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Sort by:', style: TextStyle(color: peach)),
                    for (final option in ['Recently Modified', 'A–Z'])
                      ChoiceChip(
                        label: Text(option),
                        selected: sort == option,
                        onSelected: (_) => setState(() => sort = option),
                      ),
                    Text(
                      '${visible.length} titles · ${state.entries.length} files',
                      style: const TextStyle(color: peach, fontSize: 12),
                    ),
                    IconButton(
                      onPressed: () => setState(() => listView = !listView),
                      tooltip: listView ? 'Poster view' : 'List view',
                      icon: Icon(listView ? Icons.grid_view : Icons.view_list),
                    ),
                    IconButton(
                      onPressed: state.canRescan
                          ? () => widget.controller.scan(state.root!)
                          : null,
                      tooltip: 'Rescan library',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (all.isEmpty && !busy) emptyLibrary(state.scanCompleted),
                if (all.isNotEmpty && visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No videos match your search.'),
                  ),
                if (continuing.isNotEmpty &&
                    query.isEmpty &&
                    filter == 'All' &&
                    destination == 0)
                  shelf('Continue Watching', continuing),
                if (filter != 'Movies' && shows.isNotEmpty)
                  shelf('All TV Shows', shows),
                if (filter != 'TV Shows' && movies.isNotEmpty)
                  shelf('All Movies', movies),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget emptyLibrary(bool completed) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        const Icon(Icons.video_library_outlined, size: 64, color: peach),
        const SizedBox(height: 16),
        Text(
          completed
              ? 'No videos found in this folder'
              : 'Your library is ready to scan',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () =>
              widget.controller.scan(widget.controller.state.root!),
          icon: const Icon(Icons.refresh),
          label: const Text('Scan folder'),
        ),
        TextButton(
          onPressed: connect,
          child: const Text('Choose another folder'),
        ),
      ],
    ),
  );
  Widget shelf(String heading, List<CatalogTitle> titles) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      section(heading, '${titles.length} available'),
      if (listView) ...[
        for (final title in titles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: Icon(
                  title.isSeries ? Icons.tv : Icons.movie_outlined,
                  color: peach,
                ),
                title: Text(title.name),
                subtitle: Text(
                  title.isSeries
                      ? '${title.seasons.length} seasons · ${title.episodeCount} episodes'
                      : title.first.file.displayName,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => details(title),
              ),
            ),
          ),
      ] else
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth < 500
                ? 2
                : c.maxWidth < 850
                ? 3
                : c.maxWidth < 1100
                ? 4
                : 5;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: .60,
              children: [
                for (final title in titles)
                  PosterCard(
                    title: title,
                    library: library,
                    onTap: () => details(title),
                  ),
              ],
            );
          },
        ),
    ],
  );
  void activity() => showModalBottomSheet<void>(
    context: context,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Library Activity',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Text(
            '${widget.controller.state.videoCount} videos discovered\n${widget.controller.state.subtitleCount} subtitle files\n${widget.controller.state.ignoredCount} other files skipped',
          ),
          const SizedBox(height: 16),
          Text(
            widget.controller.state.scanCompleted
                ? 'Scan complete'
                : 'Scan not complete',
          ),
        ],
      ),
    ),
  );
  void settings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Library Settings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Text(
                widget.controller.state.root?.displayName ??
                    'No folder connected',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(connect());
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Change media folder'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  diagnostics();
                },
                child: const Text('Open Diagnostics'),
              ),
              const Divider(height: 32),
              CatalogMetadataSettings(library: library),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget chip(String label, {Color color = peach}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  decoration: BoxDecoration(
    color: const Color(0xCC0B0E16),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    label,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: .6,
    ),
  ),
);
Widget section(String name, String detail) => Padding(
  padding: const EdgeInsets.only(top: 32, bottom: 16),
  child: Wrap(
    spacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        name,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          fontFamily: 'Sora',
        ),
      ),
      Text(detail, style: const TextStyle(color: peach, fontSize: 12)),
    ],
  ),
);

class VideoArtwork extends StatelessWidget {
  const VideoArtwork({
    required this.video,
    required this.library,
    this.backdrop = false,
    super.key,
  });
  final CatalogVideo video;
  final CatalogLibrary library;
  final bool backdrop;
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: library.thumbnail(video, backdrop: backdrop),
    builder: (context, snapshot) => snapshot.data != null
        ? Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: panel,
              child: Center(
                child: Icon(Icons.movie_outlined, size: 64, color: peach),
              ),
            ),
          )
        : DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xFF303647),
                  Color(0xFF141821),
                  Color(0xFF2E191C),
                ],
              ),
            ),
            child: Center(
              child: Icon(
                video.series != null ? Icons.tv : Icons.movie_outlined,
                color: peach.withValues(alpha: .4),
                size: 64,
              ),
            ),
          ),
  );
}

class PosterCard extends StatelessWidget {
  const PosterCard({
    required this.title,
    required this.library,
    required this.onTap,
    super.key,
  });
  final CatalogTitle title;
  final CatalogLibrary library;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: panel,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoArtwork(video: library.next(title), library: library),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB30B0E16)],
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Expanded(
                        child: chip(
                          title.isSeries
                              ? '${title.seasons.length} Seasons'
                              : title.first.file.displayName
                                    .split('.')
                                    .last
                                    .toUpperCase(),
                        ),
                      ),
                      if (library.isSaved(title))
                        const Icon(Icons.bookmark, color: peach, size: 18),
                    ],
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    color: Colors.white54,
                    size: 44,
                  ),
                ),
              ],
            ),
          ),
          if (library.progress(library.next(title)) > 0)
            LinearProgressIndicator(
              value: library.progress(library.next(title)),
              minHeight: 3,
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  title.isSeries
                      ? '${title.episodeCount} Episodes · Local'
                      : fileSize(title.first.file.sizeBytes),
                  style: const TextStyle(color: peach, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class CinemaHero extends StatelessWidget {
  const CinemaHero({
    required this.title,
    required this.library,
    required this.eyebrow,
    required this.actions,
    super.key,
  });
  final CatalogTitle title;
  final CatalogLibrary library;
  final String eyebrow;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: c.maxWidth < 600 ? 390 : 420,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoArtwork(
              video: library.next(title),
              library: library,
              backdrop: true,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0x550B0E16),
                    Color(0xDD0B0E16),
                    Color(0xFF0B0E16),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.all(c.maxWidth < 600 ? 20 : 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        chip(eyebrow),
                        const SizedBox(height: 12),
                        Text(
                          title.name,
                          style: TextStyle(
                            fontSize: c.maxWidth < 600 ? 30 : 44,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            fontFamily: 'Sora',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title.isSeries
                              ? '${title.seasons.length} Seasons  •  ${title.episodeCount} Episodes  •  ${fileSize(title.sizeBytes)}'
                              : '${title.first.file.displayName.split('.').last.toUpperCase()}  •  ${fileSize(title.first.file.sizeBytes)}${title.first.year == null ? '' : '  •  ${title.first.year}'}',
                          style: const TextStyle(color: peach),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title.isSeries
                              ? library.next(title).file.relativePath
                              : title.first.file.relativePath,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(spacing: 10, runSpacing: 10, children: actions),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CatalogDetail extends StatefulWidget {
  const CatalogDetail({
    required this.title,
    required this.library,
    this.playbackSurface,
    super.key,
  });
  final CatalogTitle title;
  final CatalogLibrary library;
  final Widget? playbackSurface;
  @override
  State<CatalogDetail> createState() => _CatalogDetailState();
}

class _CatalogDetailState extends State<CatalogDetail> {
  late int season = widget.title.isSeries
      ? widget.library.next(widget.title).season ??
            widget.title.seasons.firstOrNull ??
            0
      : 0;
  bool unwatchedFirst = false;
  @override
  Widget build(BuildContext context) => RouteContentBuilder(
    animation: widget.library,
    builder: (context) {
      final library = widget.library;
      final title =
          library.currentTitles
              .where(
                (t) =>
                    t.id == widget.title.id ||
                    t.localIds.any(widget.title.localIds.contains),
              )
              .firstOrNull ??
          widget.title;
      final next = library.next(title);
      final episodes = title.videos.where((v) => v.season == season).toList();
      if (unwatchedFirst) {
        episodes.sort(
          (a, b) => (library.watched(a) ? 1 : 0).compareTo(
            library.watched(b) ? 1 : 0,
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const AppBrand()),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                CinemaHero(
                  title: title,
                  library: library,
                  eyebrow: title.isSeries
                      ? 'SERIES LIBRARY • LOCAL MEDIA'
                      : 'MOVIE LIBRARY • LOCAL MEDIA',
                  actions: [
                    FilledButton.icon(
                      onPressed: () => openVideo(
                        context,
                        library,
                        next,
                        widget.playbackSurface,
                        queue: title.videos,
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        (library.positions[next.id] ?? 0) > 0 &&
                                !library.watched(next)
                            ? 'Resume ${title.isSeries ? next.episodeCode : ''}'
                            : title.isSeries
                            ? 'Play ${next.episodeCode}'
                            : 'Play Movie',
                      ),
                    ),
                    if (title.isSeries)
                      OutlinedButton.icon(
                        onPressed: () {
                          final unwatched = title.videos.firstWhere(
                            (v) => !library.watched(v),
                            orElse: () => title.first,
                          );
                          openVideo(
                            context,
                            library,
                            unwatched,
                            widget.playbackSurface,
                            queue: title.videos,
                          );
                        },
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Next Unwatched'),
                      ),
                    IconButton.filledTonal(
                      onPressed: () => library.toggleSaved(title.id),
                      tooltip: 'Toggle watchlist',
                      icon: Icon(
                        library.isSaved(title)
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title.matchStatus ?? 'Local grouping',
                        style: const TextStyle(color: peach),
                      ),
                      TextButton.icon(
                        onPressed: () => unawaited(
                          reviewCatalogMatch(context, library, title),
                        ),
                        icon: const Icon(Icons.manage_search),
                        label: const Text('Review match'),
                      ),
                      if (title.isSeries)
                        OutlinedButton.icon(
                          key: const Key('refresh-tv-artwork'),
                          onPressed: () => unawaited(
                            openCatalogArtworkPicker(
                              context,
                              library,
                              title,
                              onReviewMatch: () => unawaited(
                                reviewCatalogMatch(context, library, title),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.image_search),
                          label: const Text('Refresh artwork'),
                        ),
                    ],
                  ),
                ),
                if (title.overview?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(title.overview!),
                  ),
                if (title.isSeries) ...[
                  section('Seasons', '${title.episodeCount} Episodes'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final number in title.seasons)
                        ChoiceChip(
                          label: Text(
                            number == 0 ? 'Specials' : 'Season $number',
                          ),
                          selected: season == number,
                          onSelected: (_) => setState(() => season = number),
                        ),
                      FilterChip(
                        label: const Text('Unwatched First'),
                        selected: unwatchedFirst,
                        onSelected: (v) => setState(() => unwatchedFirst = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, c) => GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: c.maxWidth < 600
                          ? 1
                          : c.maxWidth < 950
                          ? 2
                          : 3,
                      childAspectRatio: 1.25,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      children: [
                        for (final video in episodes)
                          EpisodeCard(
                            video: video,
                            library: library,
                            onTap: () => openVideo(
                              context,
                              library,
                              video,
                              widget.playbackSurface,
                              queue: title.videos,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                section(
                  'Storage & Local Media Inspector',
                  fileSize(title.sizeBytes),
                ),
                for (final video in title.isSeries ? [next] : title.videos)
                  MediaInspector(video: video, library: library),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class EpisodeCard extends StatelessWidget {
  const EpisodeCard({
    required this.video,
    required this.library,
    required this.onTap,
    super.key,
  });
  final CatalogVideo video;
  final CatalogLibrary library;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: panel,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoArtwork(video: video, library: library, backdrop: true),
                Positioned(top: 10, left: 10, child: chip(video.episodeCode)),
                const Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    color: Colors.white70,
                    size: 44,
                  ),
                ),
                if (library.watched(video))
                  Positioned(
                    top: 10,
                    right: 10,
                    child: chip('✓ Watched', color: const Color(0xFF7BD0FF)),
                  ),
              ],
            ),
          ),
          LinearProgressIndicator(value: library.progress(video), minHeight: 3),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (video.needsReview)
                  Text(
                    video.reviewReason ?? 'Episode identification needs review',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: peach, fontSize: 11),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${library.watched(video)
                      ? 'Watched'
                      : library.progress(video) > 0
                      ? 'In progress'
                      : 'Unwatched'} · ${fileSize(video.file.sizeBytes)}',
                  style: const TextStyle(color: peach, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class MediaInspector extends StatelessWidget {
  const MediaInspector({required this.video, required this.library, super.key});
  final CatalogVideo video;
  final CatalogLibrary library;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder<MediaProbeResult?>(
        future: library.metadata(video),
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                video.file.relativePath,
                style: const TextStyle(color: peach),
              ),
              const SizedBox(height: 20),
              if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator()
              else
                Wrap(
                  spacing: 32,
                  runSpacing: 24,
                  children: [
                    metric('LOCAL FOOTPRINT', fileSize(video.file.sizeBytes)),
                    metric('DURATION', durationText(data?.duration)),
                    metric(
                      'RESOLUTION',
                      data?.width == null
                          ? 'Unavailable'
                          : '${data!.width} × ${data.height}',
                    ),
                    metric('VIDEO ENCODING', data?.videoCodec ?? 'Unavailable'),
                    metric(
                      'AUDIO STREAMS',
                      data?.audioCodecSummary ?? 'Unavailable',
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    ),
  );
}

Widget metric(String label, String value) => ConstrainedBox(
  constraints: const BoxConstraints(minWidth: 160),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: peach, fontSize: 11, letterSpacing: 1),
      ),
      const SizedBox(height: 8),
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    ],
  ),
);
void openVideo(
  BuildContext context,
  CatalogLibrary library,
  CatalogVideo video,
  Widget? surface, {
  List<CatalogVideo> queue = const [],
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CinemaPlayer(
        title: video.title,
        controller: library.controller,
        playbackSurface: surface,
        library: library,
        video: video,
        queue: queue,
      ),
    ),
  );
}
