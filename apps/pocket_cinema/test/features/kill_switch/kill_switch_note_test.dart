import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/kill_switch/kill_switch_note.dart';

const _noteKey = Key('kill-switch-info');
const _graphicKey = Key('kill-switch-info-graphic');
const _recoveryKey = Key('kill-switch-info-recovery');

Future<void> _openNote(
  WidgetTester tester, {
  Size size = const Size(320, 480),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: KillSwitchNote(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'note fits a 320px screen and stays readable at ${scale}x text',
      (tester) async {
        await _openNote(tester, textScale: scale);
        final note = find.byKey(_noteKey);
        final graphic = find.byKey(_graphicKey);
        final noteRect = tester.getRect(note);
        final graphicRect = tester.getRect(graphic);
        expect(graphicRect.left, greaterThanOrEqualTo(noteRect.left));
        expect(graphicRect.right, lessThanOrEqualTo(noteRect.right));
        for (final text
            in find
                .descendant(of: note, matching: find.byType(Text))
                .evaluate()) {
          final bounds = tester.getRect(find.byWidget(text.widget));
          expect(bounds.left, greaterThanOrEqualTo(24));
          expect(bounds.right, lessThanOrEqualTo(296));
        }
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.byKey(_recoveryKey),
          200,
          maxScrolls: 40,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_recoveryKey).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'graphic exposes the phone-to-tablet explanation to accessibility',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _openNote(tester, size: const Size(720, 1200));
        final data = tester
            .getSemantics(find.byKey(_graphicKey))
            .getSemanticsData();
        expect(data.flagsCollection.isImage, isTrue);
        expect(data.label, contains('phone'));
        expect(data.label, contains('Bluetooth'));
        expect(data.label, contains('tablet'));
        expect(data.label.toLowerCase(), contains('paus'));
        expect(data.label, contains('Loading'));
        expect(data.actions, 0);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('note is passive information with no controls or animation', (
    tester,
  ) async {
    await _openNote(tester);
    final note = find.byKey(_noteKey);
    expect(
      find.descendant(
        of: note,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ButtonStyleButton ||
              widget is IconButton ||
              widget is Switch ||
              widget is TextField ||
              widget is GestureDetector ||
              widget is InkWell,
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: note,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: note,
        matching: find.byWidgetPredicate((widget) => widget is AnimatedWidget),
      ),
      findsNothing,
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
