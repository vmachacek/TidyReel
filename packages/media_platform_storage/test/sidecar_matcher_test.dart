import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:test/test.dart';

void main() {
  test('matches one exact sibling SRT after language suffix removal', () {
    final video = entry('Bluey S01E01 - The Magic Xylophone.mp4');
    final subtitle = entry('Bluey S01E01 - The Magic Xylophone.en.srt');
    final unrelated = entry('Bluey S01E02 - Hospital.en.srt');

    final match = const SidecarMatcher().matchSrt(video, [subtitle, unrelated]);

    expect(match?.entry.storageKey, subtitle.storageKey);
    expect(match?.languageTag, 'en');
  });

  test('ambiguous generic subtitle does not attach', () {
    final match = const SidecarMatcher().matchSrt(entry('Movie.mp4'), [
      entry('subtitle.srt'),
    ]);
    expect(match, isNull);
  });
}

StorageEntrySnapshot entry(String name) => StorageEntrySnapshot(
  storageKey: 'provider|$name',
  parentStorageKey: 'provider|folder',
  relativePath: 'Folder/$name',
  displayName: name,
  isDirectory: false,
  mimeType: null,
  sizeBytes: 1024,
  modifiedAtUtc: DateTime.utc(2026, 1, 1),
  flags: const <StorageEntryFlag>{StorageEntryFlag.supportsRead},
);
