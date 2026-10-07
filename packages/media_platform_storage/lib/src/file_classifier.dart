import 'storage_models.dart';

final class FileClassification {
  const FileClassification(this.kind, this.reasonCode);

  final LibraryFileKind kind;
  final String reasonCode;
}

final class FileClassifier {
  const FileClassifier();

  FileClassification classify(String displayName, {required bool isDirectory}) {
    if (isDirectory) {
      return const FileClassification(
        LibraryFileKind.directory,
        'DIRECTORY_ENTRY',
      );
    }
    final lower = displayName.toLowerCase();
    if (lower.startsWith('._')) {
      return const FileClassification(
        LibraryFileKind.systemArtifact,
        'APPLEDOUBLE_RESOURCE_FORK',
      );
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv')) {
      return const FileClassification(LibraryFileKind.video, 'VIDEO_EXTENSION');
    }
    if (lower.endsWith('.srt')) {
      return const FileClassification(
        LibraryFileKind.subtitle,
        'SUBTITLE_SIDECAR',
      );
    }
    return const FileClassification(
      LibraryFileKind.ignoredOther,
      'UNSUPPORTED_EXTENSION',
    );
  }
}
