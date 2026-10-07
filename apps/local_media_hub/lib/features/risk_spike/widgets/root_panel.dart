import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../risk_spike_controller.dart';
import '../risk_spike_state.dart';

final class RootPanel extends StatelessWidget {
  const RootPanel({required this.state, required this.controller, super.key});

  final RiskSpikeState state;
  final RiskSpikeController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final root = state.root;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.folderSectionTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              root?.displayName ?? l10n.noFolderSelected,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.localOnly)),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (root == null)
                  FilledButton.icon(
                    key: const Key('choose-root-button'),
                    onPressed: state.phase == RiskSpikePhase.choosingRoot
                        ? null
                        : controller.chooseRoot,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.chooseFolder),
                  )
                else
                  OutlinedButton.icon(
                    key: const Key('release-root-button'),
                    onPressed: controller.releaseRoot,
                    icon: const Icon(Icons.link_off),
                    label: Text(l10n.releaseTestAccess),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
