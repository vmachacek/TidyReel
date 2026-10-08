import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/jukebox_carousel.dart';

Widget _app({
  int count = 5,
  int initialIndex = 0,
  ValueChanged<int>? onSelected,
  ValueChanged<int>? onActivated,
}) => MaterialApp(
  home: Scaffold(
    body: JukeboxCarousel(
      key: const Key('carousel'),
      initialIndex: initialIndex,
      covers: [
        for (var index = 0; index < count; index++)
          ColoredBox(
            color: Colors.primaries[index % Colors.primaries.length],
            child: Center(child: Text('Cover $index')),
          ),
      ],
      labels: [for (var index = 0; index < count; index++) 'Title $index'],
      onSelected: onSelected ?? (_) {},
      onActivated: onActivated,
    ),
  ),
);

Future<void> _surface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Finder get _stage => find.byKey(const Key('jukebox-stage'));
Finder get _previous => find.byKey(const Key('jukebox-previous'));
Finder get _next => find.byKey(const Key('jukebox-next'));

Finder _selection(int position, int count) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.value == '$position of $count: Title ${position - 1}',
);

RenderBox _faceBox(WidgetTester tester, int index) {
  final transform = tester.widget<Transform>(
    find.byKey(Key('jukebox-cover-$index')),
  );
  return tester.renderObject<RenderBox>(find.byWidget(transform.child!));
}

Rect _projectedBounds(RenderBox box) =>
    Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)),
    ).expandToInclude(
      Rect.fromPoints(
        box.localToGlobal(box.size.topRight(Offset.zero)),
        box.localToGlobal(box.size.bottomLeft(Offset.zero)),
      ),
    );

void main() {
  testWidgets('tapping the center opens the currently selected title', (
    tester,
  ) async {
    await _surface(tester, const Size(390, 844));
    final activations = <int>[];
    await tester.pumpWidget(_app(onActivated: activations.add));
    await tester.pumpAndSettle();

    await tester.tap(_stage);
    await tester.pumpAndSettle();
    expect(activations, [0]);

    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(activations, [0]);
    await tester.tap(_stage);
    await tester.pumpAndSettle();
    expect(activations, [0, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessibility activation opens the selected title', (
    tester,
  ) async {
    await _surface(tester, const Size(390, 844));
    final semantics = tester.ensureSemantics();
    try {
      final activations = <int>[];
      await tester.pumpWidget(
        _app(initialIndex: 2, onActivated: activations.add),
      );
      await tester.pumpAndSettle();

      final node = tester.getSemantics(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Browse your library',
        ),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(activations, [2]);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('arrows select titles and stop at both ends of the library', (
    tester,
  ) async {
    await _surface(tester, const Size(390, 844));
    final selections = <int>[];
    await tester.pumpWidget(_app(count: 3, onSelected: selections.add));
    await tester.pumpAndSettle();

    expect(_selection(1, 3), findsOneWidget);
    expect(find.text('Start of library'), findsNothing);
    expect(find.text('1 / 3'), findsNothing);
    expect(tester.widget<IconButton>(_previous).onPressed, isNull);

    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(_selection(2, 3), findsOneWidget);
    expect(find.text('Flick to browse'), findsNothing);
    expect(selections.last, 1);

    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(_selection(3, 3), findsOneWidget);
    expect(find.text('End of library'), findsNothing);
    expect(tester.widget<IconButton>(_next).onPressed, isNull);
    expect(selections.last, 2);

    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(_selection(3, 3), findsOneWidget);
    await tester.tap(_previous);
    await tester.pumpAndSettle();
    await tester.tap(_previous);
    await tester.pumpAndSettle();
    expect(_selection(1, 3), findsOneWidget);
    expect(tester.widget<IconButton>(_previous).onPressed, isNull);
    expect(selections, [1, 2, 1, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a finger drag moves covers before release then snaps to a title',
    (tester) async {
      await _surface(tester, const Size(390, 844));
      final selections = <int>[];
      final activations = <int>[];
      await tester.pumpWidget(
        _app(onSelected: selections.add, onActivated: activations.add),
      );
      await tester.pumpAndSettle();
      final pageView = tester.widget<PageView>(find.byType(PageView));
      final controller = pageView.controller!;
      final pageWidth =
          tester.getSize(_stage).width * controller.viewportFraction;
      final initialTransform = tester
          .widget<Transform>(find.byKey(const Key('jukebox-cover-0')))
          .transform
          .storage
          .toList();
      final gesture = await tester.startGesture(tester.getCenter(_stage));

      await gesture.moveBy(Offset(-pageWidth * .12, 0));
      await tester.pump();
      await gesture.moveBy(Offset(-pageWidth * .28, 0));
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.page, greaterThan(0));
      expect(controller.page, lessThan(1));
      expect(
        tester
            .widget<Transform>(find.byKey(const Key('jukebox-cover-0')))
            .transform
            .storage,
        isNot(equals(initialTransform)),
      );

      await gesture.moveBy(Offset(-pageWidth * .30, 0));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_selection(2, 5), findsOneWidget);
      expect(selections.last, 1);
      expect(controller.page, closeTo(1, .001));
      expect(activations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet shows eleven covers with side sleeves turned toward each other',
    (tester) async {
      await _surface(tester, const Size(1200, 900));
      await tester.pumpWidget(_app(count: 15, initialIndex: 7));
      await tester.pumpAndSettle();

      final covers = find.byWidgetPredicate(
        (widget) =>
            widget is Transform &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'jukebox-cover-',
            ),
      );
      expect(covers, findsNWidgets(11));

      final stageBounds = tester.getRect(_stage);
      for (var index = 2; index <= 12; index++) {
        expect(
          _projectedBounds(_faceBox(tester, index)).overlaps(stageBounds),
          isTrue,
          reason: 'Neighbor $index should remain within the browsing stage',
        );
      }

      double edgeHeight(RenderBox box, double x) =>
          box.localToGlobal(Offset(x, box.size.height)).dy -
          box.localToGlobal(Offset(x, 0)).dy;

      final left = _faceBox(tester, 6);
      final right = _faceBox(tester, 8);
      expect(
        edgeHeight(left, 0),
        greaterThan(edgeHeight(left, left.size.width)),
      );
      expect(
        edgeHeight(right, right.size.width),
        greaterThan(edgeHeight(right, 0)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone exposes a second neighboring cover on both sides', (
    tester,
  ) async {
    await _surface(tester, const Size(390, 844));
    await tester.pumpWidget(_app(count: 15, initialIndex: 7));
    await tester.pumpAndSettle();

    final stageBounds = tester.getRect(_stage);
    Rect visibleBounds(int index) {
      final projected = _projectedBounds(_faceBox(tester, index));
      expect(projected.overlaps(stageBounds), isTrue);
      return projected.intersect(stageBounds);
    }

    final firstLeft = visibleBounds(6);
    final secondLeft = visibleBounds(5);
    final firstRight = visibleBounds(8);
    final secondRight = visibleBounds(9);
    expect(firstLeft.left - secondLeft.left, greaterThanOrEqualTo(20));
    expect(secondRight.right - firstRight.right, greaterThanOrEqualTo(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('flicking beyond an endpoint never wraps the library', (
    tester,
  ) async {
    await _surface(tester, const Size(390, 844));
    final selections = <int>[];
    await tester.pumpWidget(_app(count: 3, onSelected: selections.add));
    await tester.pumpAndSettle();

    await tester.fling(_stage, const Offset(260, 0), 1800);
    await tester.pumpAndSettle();
    expect(_selection(1, 3), findsOneWidget);
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.fling(_stage, const Offset(-260, 0), 1800);
      await tester.pumpAndSettle();
    }
    expect(_selection(3, 3), findsOneWidget);
    expect(find.text('End of library'), findsNothing);
    expect(tester.widget<IconButton>(_next).onPressed, isNull);
    expect(selections, isNotEmpty);
    expect(selections.every((index) => index >= 0 && index < 3), isTrue);

    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.fling(_stage, const Offset(260, 0), 1800);
      await tester.pumpAndSettle();
    }
    expect(_selection(1, 3), findsOneWidget);
    expect(find.text('Start of library'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a visible side cover brings that title to the center', (
    tester,
  ) async {
    await _surface(tester, const Size(1200, 900));
    final selections = <int>[];
    final activations = <int>[];
    await tester.pumpWidget(
      _app(
        initialIndex: 2,
        onSelected: selections.add,
        onActivated: activations.add,
      ),
    );
    await tester.pumpAndSettle();

    // The transformed artwork is decorative; the stage receives this tap.
    await tester.tap(find.text('Cover 3'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_selection(4, 5), findsOneWidget);
    expect(selections.last, 3);
    expect(activations, isEmpty);
    await tester.tap(_stage);
    await tester.pumpAndSettle();
    expect(activations, [3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancelled gesture leaves browsing usable', (tester) async {
    await _surface(tester, const Size(390, 844));
    final activations = <int>[];
    await tester.pumpWidget(
      _app(count: 3, initialIndex: 1, onActivated: activations.add),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(_stage));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(_selection(2, 3), findsOneWidget);
    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(_selection(3, 3), findsOneWidget);
    expect(activations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single title has no navigable neighbors', (tester) async {
    await _surface(tester, const Size(390, 844));
    final selections = <int>[];
    await tester.pumpWidget(_app(count: 1, onSelected: selections.add));
    await tester.pumpAndSettle();
    expect(_selection(1, 1), findsOneWidget);
    expect(find.text('Only title'), findsNothing);
    expect(tester.widget<IconButton>(_previous).onPressed, isNull);
    expect(tester.widget<IconButton>(_next).onPressed, isNull);

    await tester.fling(_stage, const Offset(-260, 0), 1800);
    await tester.pumpAndSettle();
    expect(_selection(1, 1), findsOneWidget);
    expect(selections, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty library builds without a selected title', (
    tester,
  ) async {
    await tester.pumpWidget(_app(count: 0));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
    expect(find.byKey(const Key('jukebox-position')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing preserves selection and shrinking titles clamps it', (
    tester,
  ) async {
    await _surface(tester, const Size(1200, 900));
    await tester.pumpWidget(_app(initialIndex: 4));
    await tester.pumpAndSettle();
    expect(_selection(5, 5), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    expect(_selection(5, 5), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_app(count: 2, initialIndex: 4));
    await tester.pumpAndSettle();
    expect(_selection(2, 2), findsOneWidget);
    expect(find.text('End of library'), findsNothing);
    expect(tester.widget<IconButton>(_next).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
