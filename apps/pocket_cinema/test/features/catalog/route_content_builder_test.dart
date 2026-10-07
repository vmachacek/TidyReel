import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/route_content_builder.dart';

void main() {
  testWidgets(
    'Playback notifications do not rebuild covered catalog and return refreshes latest data',
    (tester) async {
      final value = ValueNotifier<int>(0);
      var builds = 0;
      late BuildContext routeContext;
      await tester.pumpWidget(
        MaterialApp(
          home: RouteContentBuilder(
            animation: value,
            builder: (context) {
              routeContext = context;
              builds++;
              return Scaffold(body: Text('Progress ${value.value}'));
            },
          ),
        ),
      );
      Navigator.of(routeContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Playing')),
        ),
      );
      await tester.pumpAndSettle();
      final before = builds;
      for (var i = 1; i <= 20; i++) {
        value.value = i;
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(builds, before);
      Navigator.of(routeContext).pop();
      await tester.pumpAndSettle();
      expect(find.text('Progress 20'), findsOneWidget);
      expect(builds, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      value.dispose();
    },
  );
}
