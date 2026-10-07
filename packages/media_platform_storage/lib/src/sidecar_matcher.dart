import 'storage_models.dart';

final class SidecarMatch {
  const SidecarMatch({required this.entry, required this.languageTag});

  final StorageEntrySnapshot entry;
  final String? languageTag;
}

final class SidecarMatcher {
  const SidecarMatcher();

  SidecarMatch? matchSrt(
    StorageEntrySnapshot video,
    Iterable<StorageEntrySnapshot> candidates,
  ) {
    final videoStem = _normalizeStem(_withoutExtension(video.displayName));
    final matches = <SidecarMatch>[];

    for (final candidate in candidates) {
      if (candidate.parentStorageKey != video.parentStorageKey ||
          !candidate.displayName.toLowerCase().endsWith('.srt')) {
        continue;
      }

      final parsed = _parseSubtitleStem(candidate.displayName);
      if (_normalizeStem(parsed.stem) == videoStem) {
        matches.add(
          SidecarMatch(entry: candidate, languageTag: parsed.languageTag),
        );
      }
    }

    return matches.length == 1 ? matches.single : null;
  }

  _ParsedSubtitleStem _parseSubtitleStem(String displayName) {
    var stem = _withoutExtension(displayName).toLowerCase();
    String? languageTag;

    var changed = true;
    while (changed) {
      changed = false;
      final marker = RegExp(r'[._-](forced|default)$').firstMatch(stem);
      if (marker != null) {
        stem = stem.substring(0, marker.start);
        changed = true;
        continue;
      }
      if (languageTag == null) {
        final language = RegExp(r'[._-](en(?:[-_]us)?|cs|cz|sk)$')
            .firstMatch(stem);
        if (language != null) {
          final raw = language.group(1)!.replaceAll('_', '-');
          languageTag = raw == 'cz' ? 'cs' : raw;
          stem = stem.substring(0, language.start);
          changed = true;
        }
      }
    }

    return _ParsedSubtitleStem(stem, languageTag);
  }

  String _withoutExtension(String displayName) {
    final dot = displayName.lastIndexOf('.');
    return dot < 0 ? displayName : displayName.substring(0, dot);
  }

  String _normalizeStem(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[._\-\s]+'), ' ').trim();
}

final class _ParsedSubtitleStem {
  const _ParsedSubtitleStem(this.stem, this.languageTag);

  final String stem;
  final String? languageTag;
}
