import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';

import 'risk_spike_controller_test.dart' as fixture;

class DelayedProbe implements MediaProbe {
  final completion = Completer<AppResult<MediaProbeResult>>();
  int calls = 0;

  @override
  Future<AppResult<MediaProbeResult>> probe({
    required LibraryRootLocator root,
    required String storageKey,
    required CancellationToken cancellationToken,
  }) {
    calls++;
    return completion.future;
  }
}

RiskSpikeState readyState() => RiskSpikeState(
  phase: RiskSpikePhase.filesAvailable,
  root: fixture.root,
  entries: [fixture.videoEntry],
  selectedFile: fixture.videoEntry,
  scanCompleted: true,
  lastScanCompletedAt: DateTime.utc(2026, 10, 12),
);

Future<void> expectLockedOperationsIgnored(
  RiskSpikeController controller,
  fixture.FakeStorageGateway storage,
  fixture.FakePlaybackSession playback,
  DelayedProbe probe,
) async {
  final selected = controller.state.selectedFile;
  final probeResult = controller.state.probeResult;
  final openCalls = storage.openCount;
  final probeCalls = probe.calls;

  expect(controller.libraryOrganizationActive, isTrue);
  expect(controller.canOrganizeLibrary, isFalse);
  expect(controller.needsBackgroundRefresh, isFalse);
  controller.selectFile(fixture.subtitleEntry);
  await controller.playSelected();
  await controller.play(fixture.root, fixture.subtitleEntry);
  await controller.probeSelected();
  await controller.togglePlayPause();
  await controller.seekBy(const Duration(seconds: 10));
  await controller.seekToStart();
  // The fake throws if either root operation reaches the storage provider.
  await controller.chooseRoot();
  await controller.releaseRoot();
  await controller.scan(fixture.root);
  await controller.refreshInBackground();

  expect(controller.state.root, same(fixture.root));
  expect(controller.state.selectedFile, same(selected));
  expect(controller.state.probeResult, same(probeResult));
  expect(storage.openCount, openCalls);
  expect(probe.calls, probeCalls);
  expect(storage.scanCount, 0);
  expect(playback.controlCalls, isEmpty);
}

void main() {
  test(
    'a delayed source open excludes organization after close changes phase',
    () async {
      final opening = Completer<void>();
      final storage = fixture.FakeStorageGateway(
        lease: fixture.directLease,
        onOpen: () => opening.future,
      );
      final playback = fixture.FakePlaybackSession(
        allowStop: true,
        allowControls: true,
      );
      final probe = DelayedProbe();
      final controller = RiskSpikeController(
        storage: storage,
        probe: probe,
        playback: playback,
        initialState: readyState(),
        clock: () => DateTime.utc(2026, 10, 13),
      );
      addTearDown(controller.dispose);

      expect(controller.canOrganizeLibrary, isTrue);
      final playing = controller.playSelected();
      expect(controller.state.phase, RiskSpikePhase.openingPlayback);
      expect(controller.beginLibraryOrganization(), isFalse);

      await controller.closePlayer();
      expect(controller.state.phase, RiskSpikePhase.fileReady);
      expect(controller.state.canRescan, isTrue);
      expect(controller.canOrganizeLibrary, isFalse);
      expect(controller.beginLibraryOrganization(), isFalse);
      expect(storage.openCount, 1);
      expect(playback.openCount, 0);

      opening.complete();
      await playing;
      expect(playback.openCount, 1);
      expect(controller.canOrganizeLibrary, isTrue);
      expect(controller.beginLibraryOrganization(), isTrue);
      await expectLockedOperationsIgnored(controller, storage, playback, probe);

      controller.endLibraryOrganization();
      expect(controller.canOrganizeLibrary, isTrue);
      expect(controller.needsBackgroundRefresh, isTrue);
    },
  );

  test(
    'a delayed probe excludes organization until its result completes',
    () async {
      final storage = fixture.FakeStorageGateway();
      final playback = fixture.FakePlaybackSession(
        allowStop: true,
        allowControls: true,
      );
      final probe = DelayedProbe();
      final controller = RiskSpikeController(
        storage: storage,
        probe: probe,
        playback: playback,
        initialState: readyState(),
        clock: () => DateTime.utc(2026, 10, 13),
      );
      addTearDown(controller.dispose);

      final probing = controller.probeSelected();
      expect(controller.state.phase, RiskSpikePhase.probing);
      expect(controller.beginLibraryOrganization(), isFalse);
      await controller.closePlayer();
      expect(controller.state.canRescan, isTrue);
      expect(controller.state.phase, RiskSpikePhase.fileReady);
      expect(controller.canOrganizeLibrary, isFalse);
      expect(controller.beginLibraryOrganization(), isFalse);

      const facts = MediaProbeResult(
        streamCount: 2,
        duration: Duration(minutes: 20),
      );
      probe.completion.complete(const Success<MediaProbeResult>(facts));
      await probing;
      expect(controller.state.probeResult, same(facts));
      expect(controller.canOrganizeLibrary, isTrue);
      expect(controller.beginLibraryOrganization(), isTrue);
      await expectLockedOperationsIgnored(controller, storage, playback, probe);

      controller.endLibraryOrganization();
      expect(controller.canOrganizeLibrary, isTrue);
    },
  );
}
