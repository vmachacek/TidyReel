import 'package:flutter_test/flutter_test.dart';
import 'package:local_media_hub/infrastructure/playback/media_kit_playback_engine.dart';

void main() {
  test('source failure redacts the raw content URI', () {
    final failure = mapMediaKitFailure(
      Exception(
        'Could not open content://com.example.provider/tree/private/video.mkv',
      ),
      operation: MediaKitOperation.open,
    );

    expect(failure.code, 'PLAYBACK_SOURCE_FAILED');
    expect(failure.safeDetail, isNot(contains('content://')));
    expect(failure.safeDetail, isNot(contains('private')));
  });

  test('codec evidence maps to unsupported playback', () {
    final failure = mapMediaKitFailure(
      StateError('Decoder failed: unsupported codec h265'),
      operation: MediaKitOperation.open,
    );

    expect(failure.code, 'PLAYBACK_UNSUPPORTED');
    expect(failure.messageKey, 'playbackUnsupported');
  });

  test('seek errors have a dedicated safe code', () {
    final failure = mapMediaKitFailure(
      Exception('seek failed for file:///private/movie.mkv'),
      operation: MediaKitOperation.seek,
    );

    expect(failure.code, 'PLAYBACK_SEEK_FAILED');
    expect(failure.safeDetail, isNot(contains('file:///')));
  });
}
