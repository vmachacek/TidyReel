import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/background_refresh_scheduler.dart';

void main() {
  testWidgets('protects startup and resets quiet time after activity', (
    tester,
  ) async {
    var scans = 0;
    var due = true;
    final scheduler = BackgroundRefreshScheduler(
      needsRefresh: () => due,
      refresh: () async {
        scans++;
        due = false;
      },
      defer: () {},
    );
    addTearDown(scheduler.dispose);
    scheduler.setAvailable(true);
    await tester.pump(const Duration(seconds: 14));
    expect(scans, 0);
    scheduler.activity();
    await tester.pump(const Duration(seconds: 4));
    expect(scans, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(scans, 1);
    scheduler.dispose();
  });

  testWidgets('unavailable screen yields and waits for quiet return', (
    tester,
  ) async {
    var scans = 0;
    var due = true;
    Completer<void>? scan;
    final scheduler = BackgroundRefreshScheduler(
      needsRefresh: () => due,
      refresh: () {
        scans++;
        return (scan = Completer<void>()).future;
      },
      defer: () {
        scan?.complete();
        scan = null;
      },
    );
    addTearDown(scheduler.dispose);
    scheduler.setAvailable(true);
    await tester.pump(const Duration(seconds: 15));
    expect(scans, 1);
    scheduler.setAvailable(false);
    await tester.pump(const Duration(minutes: 2));
    expect(scans, 1);
    scheduler.setAvailable(true);
    await tester.pump(const Duration(seconds: 4));
    expect(scans, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(scans, 2);
    due = false;
    scan!.complete();
    scan = null;
    await tester.pump();
    scheduler.dispose();
  });

  testWidgets('fresh cache is rechecked during a long quiet session', (
    tester,
  ) async {
    var scans = 0;
    var due = false;
    final scheduler = BackgroundRefreshScheduler(
      needsRefresh: () => due,
      refresh: () async {
        scans++;
        due = false;
      },
      defer: () {},
    );
    addTearDown(scheduler.dispose);
    scheduler.setAvailable(true);
    await tester.pump(const Duration(seconds: 15));
    expect(scans, 0);
    due = true;
    await tester.pump(const Duration(minutes: 1));
    expect(scans, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(scans, 1);
    scheduler.dispose();
  });

  testWidgets('folder change and disposal invalidate pending timers', (
    tester,
  ) async {
    var scans = 0;
    final scheduler = BackgroundRefreshScheduler(
      needsRefresh: () => true,
      refresh: () async {
        scans++;
      },
      defer: () {},
    );
    scheduler.setAvailable(true);
    await tester.pump(const Duration(seconds: 14));
    scheduler.reset();
    scheduler.setAvailable(true);
    await tester.pump(const Duration(seconds: 14));
    expect(scans, 0);
    scheduler.dispose();
    await tester.pump(const Duration(minutes: 2));
    expect(scans, 0);
  });

  testWidgets('unexpected refresh failure waits for a bounded retry', (
    tester,
  ) async {
    var scans = 0;
    final scheduler = BackgroundRefreshScheduler(
      needsRefresh: () => true,
      refresh: () async {
        scans++;
        throw StateError('Transient error');
      },
      defer: () {},
    );
    scheduler.setAvailable(true);
    await tester.pump(const Duration(seconds: 15));
    expect(scans, 1);
    await tester.pump(const Duration(seconds: 59));
    expect(scans, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(scans, 2);
    scheduler.dispose();
  });
}
