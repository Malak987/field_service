import 'package:field_service/core/theme/app_theme.dart';
import 'package:field_service/features/jobs/presentation/widgets/signature_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for "the page moves while the customer signs".
///
/// The Job Details page is a scrollable and the signature pad lives inside it,
/// so a vertical stroke is also a scroll gesture. Two mechanisms keep the page
/// still, and each is asserted separately here:
///
/// * the pad's own gesture recognizers win the arena — asserted with the
///   scroll-freeze backstop switched OFF, so a regression to a pan recognizer
///   (which surrenders every vertical stroke to the page's `Scrollable`)
///   fails this test on its own;
/// * the hosting page freezes its physics while a finger is on the pad — the
///   production wiring, asserted with the backstop ON.
///
/// The last test guards the other direction: normal scrolling outside the pad
/// must keep working, so the fix cannot simply be "disable scrolling".
void main() {
  Future<ScrollController> pumpHost(
    WidgetTester tester, {
    required bool freezeWhileDrawing,
  }) async {
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _PadHost(
          controller: controller,
          freezeWhileDrawing: freezeWhileDrawing,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Signs with a *realistic* stroke: many small pointer moves, not one jump.
  ///
  /// This detail is what makes the test able to fail. A single 180px move
  /// clears even a pan recognizer's larger `kPanSlop` (~36px) in one event, so
  /// it would pass against the buggy code too. Real fingers arrive as a stream
  /// of small moves, and the bug only shows up in the window where the page's
  /// scroll recognizer has passed `kTouchSlop` (~18px) while a pan recognizer
  /// has not yet reached 36px. Ten-pixel steps land squarely in that window.
  Future<void> _stroke(
    WidgetTester tester,
    Finder finder,
    Offset offset, {
    int steps = 18,
  }) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(finder),
    );
    final Offset step = Offset(offset.dx / steps, offset.dy / steps);
    for (int i = 0; i < steps; i++) {
      await gesture.moveBy(step);
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
  }

  testWidgets(
    'a vertical stroke draws ink and leaves the page where it was '
    '(pad gesture recognizers alone, no scroll-freeze backstop)',
    (tester) async {
      final ScrollController controller = await pumpHost(
        tester,
        freezeWhileDrawing: false,
      );
      expect(controller.offset, 0);

      await _stroke(tester, find.byType(SignaturePad), const Offset(0, -180));
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        0,
        reason:
            'the list must not scroll while a finger is drawing inside the pad',
      );
      expect(
        tester.state<SignaturePadState>(find.byType(SignaturePad)).isEmpty,
        isFalse,
        reason: 'the same stroke must land as ink on the pad',
      );
    },
  );

  testWidgets(
    'the same stroke is captured with the production scroll freeze wired in',
    (tester) async {
      final ScrollController controller = await pumpHost(
        tester,
        freezeWhileDrawing: true,
      );

      await _stroke(tester, find.byType(SignaturePad), const Offset(0, -180));
      await tester.pumpAndSettle();

      expect(controller.offset, 0);
      expect(
        tester.state<SignaturePadState>(find.byType(SignaturePad)).isEmpty,
        isFalse,
      );
    },
  );

  testWidgets('a horizontal stroke is ink too', (tester) async {
    final ScrollController controller = await pumpHost(
      tester,
      freezeWhileDrawing: false,
    );

    await _stroke(tester, find.byType(SignaturePad), const Offset(140, 0));
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
    expect(
      tester.state<SignaturePadState>(find.byType(SignaturePad)).isEmpty,
      isFalse,
    );
  });

  testWidgets('scrolling outside the pad still scrolls the page', (
    tester,
  ) async {
    final ScrollController controller = await pumpHost(
      tester,
      freezeWhileDrawing: true,
    );
    expect(controller.offset, 0);

    await _stroke(
      tester,
      find.byKey(const Key('pad_host_filler')),
      const Offset(0, -150),
      steps: 15,
    );
    await tester.pumpAndSettle();

    expect(
      controller.offset,
      greaterThan(0),
      reason: 'the freeze must apply to the pad only, never to the whole page',
    );
  });
}

/// Mirrors how `JobDetailsPage` hosts the pad: a scrollable tall enough to
/// scroll, the pad in the middle, and (optionally) the physics swap driven by
/// [SignaturePad.onDrawingChanged].
class _PadHost extends StatefulWidget {
  const _PadHost({
    required this.controller,
    required this.freezeWhileDrawing,
  });

  final ScrollController controller;
  final bool freezeWhileDrawing;

  @override
  State<_PadHost> createState() => _PadHostState();
}

class _PadHostState extends State<_PadHost> {
  bool _drawing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        controller: widget.controller,
        physics: widget.freezeWhileDrawing && _drawing
            ? const NeverScrollableScrollPhysics()
            : null,
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Container(
            key: const Key('pad_host_filler'),
            height: 200,
            color: const Color(0xFFE5DDD2),
          ),
          const SizedBox(height: 16),
          SignaturePad(
            height: 400,
            onDrawingChanged: widget.freezeWhileDrawing
                ? (bool drawing) => setState(() => _drawing = drawing)
                : null,
          ),
          const SizedBox(height: 16),
          Container(height: 900, color: const Color(0xFFE5DDD2)),
        ],
      ),
    );
  }
}
