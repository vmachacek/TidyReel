import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:test/test.dart';

void main() {
  test('AppleDouble video is always a system artifact', () {
    final result = const FileClassifier().classify(
      '._Movie.MKV',
      isDirectory: false,
    );
    expect(result.kind, LibraryFileKind.systemArtifact);
    expect(result.reasonCode, 'APPLEDOUBLE_RESOURCE_FORK');
  });

  test('video and subtitle extensions are case insensitive', () {
    const classifier = FileClassifier();
    expect(
      classifier.classify('Movie.MP4', isDirectory: false).kind,
      LibraryFileKind.video,
    );
    expect(
      classifier.classify('Movie.En.SRT', isDirectory: false).kind,
      LibraryFileKind.subtitle,
    );
  });

  test('missing size and modified time remain valid snapshot values', () {
    const entry = StorageEntrySnapshot(
      storageKey: 'provider|opaque',
      parentStorageKey: null,
      relativePath: 'Movie.mkv',
      displayName: 'Movie.mkv',
      isDirectory: false,
      mimeType: null,
      sizeBytes: null,
      modifiedAtUtc: null,
      flags: <StorageEntryFlag>{},
    );
    expect(entry.sizeBytes, isNull);
    expect(entry.modifiedAtUtc, isNull);
  });
}
