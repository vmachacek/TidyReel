import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';
import 'package:test/test.dart';

void main() {
  test('playback request defaults to autoplay for its leased source', () {
    const lease = MediaSourceLease(
      leaseId: 'lease-1',
      sourceUri: 'content://fixture/video',
      strategy: PlaybackSourceStrategy.directContentUri,
    );

    const request = PlaybackRequest(sourceLease: lease);

    expect(request.sourceLease, same(lease));
    expect(request.autoplay, isTrue);
  });

  test('closed snapshot has inert playback state', () {
    const snapshot = PlaybackSnapshot.closed();

    expect(snapshot.isOpen, isFalse);
    expect(snapshot.isPlaying, isFalse);
    expect(snapshot.isBuffering, isFalse);
    expect(snapshot.position, Duration.zero);
    expect(snapshot.duration, Duration.zero);
    expect(snapshot.failure, isNull);
  });

  test('copyWith changes requested playback state and preserves the rest', () {
    const failure = AppFailure(
      code: 'PLAYBACK_SOURCE_FAILED',
      messageKey: 'playbackSourceFailed',
      retryable: true,
      safeDetail: 'The selected media source could not be opened.',
    );
    const snapshot = PlaybackSnapshot(
      isOpen: true,
      isPlaying: false,
      isBuffering: true,
      duration: Duration(minutes: 2),
      failure: failure,
    );

    final updated = snapshot.copyWith(
      isPlaying: true,
      isBuffering: false,
      position: const Duration(seconds: 30),
    );

    expect(updated.isOpen, isTrue);
    expect(updated.isPlaying, isTrue);
    expect(updated.isBuffering, isFalse);
    expect(updated.position, const Duration(seconds: 30));
    expect(updated.duration, const Duration(minutes: 2));
    expect(updated.failure, same(failure));
  });
}
