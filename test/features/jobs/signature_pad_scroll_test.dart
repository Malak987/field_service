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

  testWidgets(
    'a vertical stroke draws ink and leaves the page where it was '
    '(pad gesture recognizers alone, no scroll-freeze backstop)',
    (tester) async {
      final ScrollController controller = await pumpHost(
        tester,
        freezeWhileDrawing: false,
      );
      expect(controller.offset, 0);

      await tester.drag(find.byType(SignaturePad), const Offset(0, -180));
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

      await tester.drag(find.byType(SignaturePad), const Offset(0, -180));
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

    await tester.drag(find.byType(SignaturePad), const Offset(140, 0));
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

    await tester.drag(find.byKey(const Key('pad_host_filler')), const Offset(0, -150));
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
