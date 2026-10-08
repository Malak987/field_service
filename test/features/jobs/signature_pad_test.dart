import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/jobs/presentation/widgets/signature_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendering tests of the [SignaturePad] itself — the fix for the
/// "blank pad" defect: strokes mutated in place were invisible because the
/// painter never repainted. These tests verify the strokes are VISIBLY
/// painted (pixel-checked through the same `RepaintBoundary.toImage` path
/// the app uses for the upload) and that Clear/redraw/export keep working.

/// Decodes a PNG and counts pixels with visible ink (alpha above the
/// anti-aliasing noise floor). Runs inside real async — image decoding is
/// engine work.
Future<int> countInkPixels(Uint8List png) async {
  final ui.Codec codec = await ui.instantiateImageCodec(png);
  final ui.FrameInfo frame = await codec.getNextFrame();
  codec.dispose();
  final ui.Image image = frame.image;
  try {
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(data, isNotNull);
    final Uint8List bytes = data!.buffer.asUint8List();
    int ink = 0;
    for (int i = 3; i < bytes.length; i += 4) {
      if (bytes[i] > 16) {
        ink++;
      }
    }
    return ink;
  } finally {
    image.dispose();
  }
}

void main() {
  late GlobalKey<SignaturePadState> padKey;

  setUp(() => padKey = GlobalKey<SignaturePadState>());

  Future<void> pumpPad(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: SignaturePad(key: padKey)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Draws one stroke from the pad center along [moves].
  Future<void> drawStroke(WidgetTester tester, {Offset? start}) async {
    final Offset from =
        start ??
        tester.getCenter(find.byType(SignaturePad)) + const Offset(-120, 0);
    final TestGesture gesture = await tester.startGesture(from);
    for (int i = 0; i < 12; i++) {
      await gesture.moveBy(Offset(20, (i % 2 == 0) ? 6 : -6));
    }
    await gesture.up();
    await tester.pump();
  }

  /// Exports the current drawing and counts its ink pixels (real async).
  Future<int> inkPixels(WidgetTester tester) async {
    final SignaturePadState state = padKey.currentState!;
    final Uint8List png = (await tester.runAsync<Uint8List>(
      () => state.exportPng(),
    ))!;
    expect(png, isNotEmpty);
    // PNG magic — the export format never changed.
    expect(png.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
    final int ink = (await tester.runAsync<int>(() => countInkPixels(png)))!;
    return ink;
  }

  // 1 — the pad renders its drawing surface: sized, decorated, with the
  // placeholder hint, an empty canvas and zero ink.
  testWidgets('renders the drawing surface in a clean empty state', (
    tester,
  ) async {
    await pumpPad(tester);

    expect(find.byType(SignaturePad), findsOneWidget);
    expect(find.text('Customer signs here'), findsOneWidget);

    final Size size = tester.getSize(find.byType(SignaturePad));
    expect(size.height, 220); // comfortably large, not a tiny box
    expect(size.width, greaterThan(400));

    expect(padKey.currentState!.isEmpty, isTrue);

    // The empty canvas rasterizes to a fully transparent PNG — no ink.
    expect(await inkPixels(tester), 0);
  });

  // 2 — a pan gesture produces a stroke that is VISIBLE immediately:
  // ink pixels exist without ever pressing Save.
  testWidgets('a pan gesture produces a visible stroke', (tester) async {
    await pumpPad(tester);

    await drawStroke(tester);

    expect(padKey.currentState!.isEmpty, isFalse);
    // The hint clears as soon as ink exists…
    expect(find.text('Customer signs here'), findsNothing);
    // …and the canvas actually shows the stroke (no Save needed).
    final int ink = await inkPixels(tester);
    expect(ink, greaterThan(100), reason: 'the drawn stroke must be visible');
  });

  // 3 — multiple pan updates accumulate into a growing visible stroke.
  testWidgets('multiple pan updates remain visible', (tester) async {
    await pumpPad(tester);

    await drawStroke(tester);
    final int inkAfterFirst = await inkPixels(tester);

    // A second, longer stroke over a different region.
    await drawStroke(
      tester,
      start:
          tester.getCenter(find.byType(SignaturePad)) + const Offset(-120, 60),
    );
    final int inkAfterSecond = await inkPixels(tester);

    expect(inkAfterSecond, greaterThan(inkAfterFirst));
  });

  // 4 — Clear removes the visible strokes.
  testWidgets('Clear removes the visible strokes', (tester) async {
    await pumpPad(tester);

    await drawStroke(tester);
    expect(await inkPixels(tester), greaterThan(0));

    padKey.currentState!.clear();
    await tester.pump();

    expect(padKey.currentState!.isEmpty, isTrue);
    expect(find.text('Customer signs here'), findsOneWidget);
    expect(await inkPixels(tester), 0);
  });

  // 5 — redrawing after Clear works again.
  testWidgets('redrawing after Clear works', (tester) async {
    await pumpPad(tester);

    await drawStroke(tester);
    padKey.currentState!.clear();
    await tester.pump();
    expect(await inkPixels(tester), 0);

    await drawStroke(tester);

    expect(padKey.currentState!.isEmpty, isFalse);
    expect(await inkPixels(tester), greaterThan(100));
  });

  // 6 — the exported PNG is a non-blank signature: what the user sees is
  // exactly what `RepaintBoundary.toImage` stores.
  testWidgets('exportPng returns a non-blank PNG of the visible drawing', (
    tester,
  ) async {
    await pumpPad(tester);

    await drawStroke(tester);

    final SignaturePadState state = padKey.currentState!;
    final Uint8List png = (await tester.runAsync<Uint8List>(
      () => state.exportPng(),
    ))!;

    expect(png.length, greaterThan(100)); // a real rasterized image
    expect(png.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
    final int ink = (await tester.runAsync<int>(() => countInkPixels(png)))!;
    expect(
      ink,
      greaterThan(100),
      reason:
          'the exported PNG must contain the visible signature, '
          'never a blank capture',
    );
  });
}
