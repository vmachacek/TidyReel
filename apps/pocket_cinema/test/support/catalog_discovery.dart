import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';

CatalogLibrary catalogLibrary(WidgetTester tester) {
  // The screen owns its library; use its state without making that state public
  // solely for tests.
  final dynamic state = tester.state(
    find.byType(CatalogScreen, skipOffstage: false),
  );
  return state.library as CatalogLibrary;
}

Future<void> settleCatalog(WidgetTester tester) async {
  final screen = find.byType(CatalogScreen, skipOffstage: false);
  if (screen.evaluate().isNotEmpty) {
    final library = catalogLibrary(tester);
    await tester.runAsync(() async {
      // Isolate messages use real time; their continuations may be queued in
      // the fake clock where the screen started discovery. Pump that queue too.
      await tester.pump();
      final elapsed = Stopwatch()..start();
      while (library.isDiscovering) {
        if (elapsed.elapsed > const Duration(seconds: 30)) {
          throw TestFailure('Catalog discovery did not finish.');
        }
        await Future<void>.delayed(Duration.zero);
        await tester.pump();
      }
    });
  }
  await tester.pumpAndSettle();
}
