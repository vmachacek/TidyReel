import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../risk_spike_controller.dart';
import '../risk_spike_state.dart';

final class MediaList extends StatelessWidget {
  const MediaList({required this.state, required this.controller, super.key});

  final RiskSpikeState state;
  final RiskSpikeController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          key: const Key('media-list'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.mediaSectionTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (state.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l10n.noPlayableMedia),
              )
            else
              for (final (index, entry) in state.entries.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: state.selectedFile?.storageKey == entry.storageKey
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: Key('media-row-$index'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => controller.selectFile(entry),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.movie_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
