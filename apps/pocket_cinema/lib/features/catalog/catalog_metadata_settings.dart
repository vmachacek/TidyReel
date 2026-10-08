import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_library.dart';

class CatalogMetadataSettings extends StatefulWidget {
  const CatalogMetadataSettings({required this.library, super.key});
  final CatalogLibrary library;
  @override
  State<CatalogMetadataSettings> createState() =>
      _CatalogMetadataSettingsState();
}

class _CatalogMetadataSettingsState extends State<CatalogMetadataSettings> {
  final token = TextEditingController();
  bool saving = false;
  Future<void> save(String value) async {
    setState(() => saving = true);
    await widget.library.setMetadataToken(value);
    if (!mounted) return;
    if (widget.library.settingsError == null) token.clear();
    setState(() => saving = false);
  }

  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Movie & TV matching',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Files are grouped automatically by title, season and episode. TMDB adds official names and helps identify shows and movies.',
        ),
        const SizedBox(height: 12),
        Text(
          widget.library.metadataConfigured
              ? 'TMDB matching is enabled. Your token is stored securely.'
              : 'Local grouping is active. Connect TMDB for online matching.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('tmdb-token'),
          controller: token,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'TMDB Read Access Token',
            helperText: 'Paste the token from your TMDB account settings.',
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Online matching sends title names and release years to TMDB. Video contents and storage paths stay on your device.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: saving
              ? null
              : () {
                  if (token.text.trim().isNotEmpty) unawaited(save(token.text));
                },
          child: Text(
            saving
                ? 'Saving…'
                : widget.library.metadataConfigured
                ? 'Replace TMDB token'
                : 'Enable TMDB matching',
          ),
        ),
        if (widget.library.metadataConfigured) ...[
          TextButton(
            onPressed: saving ? null : () => unawaited(save('')),
            child: const Text('Turn off online matching'),
          ),
          OutlinedButton.icon(
            onPressed: widget.library.matcher.busy
                ? null
                : () => unawaited(widget.library.retryMatching()),
            icon: const Icon(Icons.sync),
            label: const Text('Retry metadata matching'),
          ),
        ],
        if (widget.library.matcher.busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const Text('Matching titles in the background…'),
        ],
        if (widget.library.settingsError != null)
          Text(
            widget.library.settingsError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 12),
        const SelectableText(
          'Get your token: https://www.themoviedb.org/settings/api',
          style: TextStyle(fontSize: 12),
        ),
        TextButton(
          onPressed: () async {
            try {
              await CatalogLibrary.channel.invokeMethod<void>(
                'openMetadataHelp',
              );
            } on Object {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Open themoviedb.org/settings/api in your browser.',
                    ),
                  ),
                );
              }
            }
          },
          child: const Text('Open TMDB account settings'),
        ),
        const Divider(height: 32),
        const Text(
          'Metadata credits',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Image.asset(
            'assets/branding/tmdb.png',
            width: 180,
            semanticLabel: 'The Movie Database',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This product uses the TMDB API but is not endorsed or certified by TMDB.',
          style: TextStyle(fontSize: 12),
        ),
        const SelectableText(
          'https://www.themoviedb.org',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}

Future<void> reviewCatalogMatch(
  BuildContext context,
  CatalogLibrary library,
  CatalogTitle displayed,
) {
  final locals = library.localTitles
      .where((t) => displayed.localIds.contains(t.id))
      .toList();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
          ),
          child: ListenableBuilder(
            listenable: library,
            builder: (_, _) => ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Review ${displayed.name}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose the correct title. Episode numbers and names that conflict with TMDB stay visible for review.',
                ),
                if (!library.matcher.enabled)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Enable TMDB in Library Settings to search for title matches.',
                    ),
                  ),
                for (final local in locals) ...[
                  const SizedBox(height: 16),
                  Text(
                    local.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (library.matcher.enabled)
                    TextField(
                      key: ValueKey('review-match-search-${local.id}'),
                      decoration: const InputDecoration(
                        labelText: 'Search another title',
                        hintText: 'Enter a title and press Search',
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (value) => unawaited(
                        library.matcher.search(
                          local,
                          library.catalogScope,
                          value,
                        ),
                      ),
                    ),
                  if (library.matcher.failures[library.matcher.key(
                        library.catalogScope,
                        local,
                      )] !=
                      null)
                    Text(
                      library.matcher.failures[library.matcher.key(
                        library.catalogScope,
                        local,
                      )]!,
                    ),
                  for (final candidate
                      in library.matcher.candidates[library.matcher.key(
                            library.catalogScope,
                            local,
                          )] ??
                          [])
                    ListTile(
                      title: Text(
                        '${candidate.name}${candidate.year == null ? '' : ' (${candidate.year})'}',
                      ),
                      subtitle: Text(
                        candidate.overview ??
                            'TMDB title ${candidate.providerId}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.check_circle_outline),
                      onTap: () {
                        unawaited(
                          library.matcher.select(
                            local,
                            library.catalogScope,
                            candidate,
                          ),
                        );
                        Navigator.pop(sheetContext);
                      },
                    ),
                  if ((library.matcher.candidates[library.matcher.key(
                                library.catalogScope,
                                local,
                              )] ??
                              [])
                          .isEmpty &&
                      library.matcher.enabled)
                    const Text(
                      'No title candidates yet. Retry matching to search again.',
                    ),
                ],
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    library.matcher.forget(displayed, library.catalogScope);
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Use local names'),
                ),
                if (library.matcher.enabled)
                  TextButton(
                    onPressed: library.matcher.busy
                        ? null
                        : () => unawaited(library.retryMatching()),
                    child: const Text('Retry matching'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
