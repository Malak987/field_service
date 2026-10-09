import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A touch drawing surface for capturing the customer's signature.
///
/// Deliberately dependency-free: strokes collected from pan gestures are
/// painted by a [CustomPaint], and [exportPng] rasterizes the drawing via a
/// [RepaintBoundary] into a transparent PNG — the exact bytes the offline
/// job-file pipeline stores, queues and uploads.
///
/// The widget is purely presentational: the parent decides what happens
/// with the drawing (clear/confirm) and owns all business logic.
///
/// ## Drawing inside a scrollable page
///
/// The pad lives inside the scrollable Job Details page. Without help, a
/// vertical finger movement would race the page's scroll gesture — the page
/// moves instead of (or while) the customer signs. The pad therefore
/// reports touch-down/touch-up through [onDrawingChanged]; the hosting page
/// freezes its own scrolling for exactly that window, so EVERY touch inside
/// the pad becomes ink and the page only scrolls again once the finger
/// lifts. Outside the pad nothing changes — normal scrolling stays intact.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, this.height = 220, this.onDrawingChanged});

  /// Height of the drawing area — large enough to sign comfortably on a
  /// phone or tablet screen.
  final double height;

  /// Notified with `true` when a finger touches the pad and `false` when it
  /// lifts again. The hosting scrollable page uses this to disable its own
  /// scrolling while the customer draws (see class docs). Optional — a pad
  /// used outside a scrollable simply passes nothing.
  final ValueChanged<bool>? onDrawingChanged;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final GlobalKey _boundaryKey = GlobalKey();

  /// Completed strokes plus the one currently in progress.
  ///
  /// Updated IMMUTABLY: every gesture event assigns a NEW list (a new outer
  /// list and a new list for the stroke that grew). This is required for
  /// painting: [_SignaturePainter.shouldRepaint] compares list identity, so
  /// mutating the same list in place would silently skip every repaint and
  /// the customer would draw on a blank surface while the exported PNG
  /// stayed empty.
  List<List<Offset>> _strokes = const <List<Offset>>[];

  /// Whether nothing has been drawn (drives the placeholder hint and the
  /// parent's empty-signature validation).
  bool get isEmpty => _strokes.isEmpty;

  /// Clears the drawing so the customer can start over.
  void clear() {
    if (_strokes.isEmpty) {
      return;
    }
    setState(() {
      _strokes = const <List<Offset>>[];
    });
  }

  /// Rasterizes the current drawing into a transparent PNG (pixel ratio 2
  /// for a crisp upload). Must not be called while [isEmpty].
  Future<Uint8List> exportPng() async {
    final BuildContext? boundaryContext = _boundaryKey.currentContext;
    if (boundaryContext == null) {
      throw StateError('The signature pad is not built; nothing to export.');
    }
    final RenderRepaintBoundary boundary =
        boundaryContext.findRenderObject()! as RenderRepaintBoundary;

    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) {
        throw StateError('The signature could not be rendered as an image.');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _panStart(DragStartDetails details) {
    // `localPosition` is relative to the gesture detector, which fills the
    // exact same rectangle as the painted canvas — the strokes, the visible
    // painting and the exported PNG all share this coordinate space.
    setState(() {
      _strokes = <List<Offset>>[
        ..._strokes,
        <Offset>[details.localPosition],
      ];
    });
  }

  void _panUpdate(DragUpdateDetails details) {
    if (_strokes.isEmpty) {
      return;
    }
    setState(() {
      // A fresh outer list AND a fresh list for the growing stroke: the
      // painter sees a new object and repaints with every touch move.
      final List<List<Offset>> strokes = _strokes.toList();
      strokes.last = <Offset>[...strokes.last, details.localPosition];
      _strokes = strokes;
    });
  }

  void _notifyDrawing(bool drawing) {
    widget.onDrawingChanged?.call(drawing);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    // The Listener sees the RAW touch events (it never competes in the gesture
    // arena) and brackets every contact with the pad: finger down → the
    // page freezes its scrolling; finger up/cancelled → scrolling returns.
    return Semantics(
      container: true,
      label: l10n.customerSignatureTitle,
      hint: l10n.signatureHint,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _notifyDrawing(true),
        onPointerUp: (_) => _notifyDrawing(false),
        onPointerCancel: (_) => _notifyDrawing(false),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: AppRadius.control,
              border: Border.all(color: context.colors.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: AppRadius.control,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // A soft baseline the customer signs above. Painted OUTSIDE
                  // the RepaintBoundary below, so it guides the eye on screen
                  // but never ends up in the exported PNG.
                  CustomPaint(
                    painter: _SignatureBaselinePainter(
                      color: context.colors.outlineVariant,
                    ),
                  ),
                  RepaintBoundary(
                    key: _boundaryKey,
                    child: CustomPaint(
                      painter: _SignaturePainter(strokes: _strokes),
                    ),
                  ),
                  if (_strokes.isEmpty)
                    IgnorePointer(
                      child: Center(
                        child: Text(
                          l10n.signatureHint,
                          style: context.textStyles.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _panStart,
                      onPanUpdate: _panUpdate,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The subtle sign-above line. Drawn at ~72% of the pad height — where a
/// natural signature sits — in a hairline tone so ink stays the focus.
class _SignatureBaselinePainter extends CustomPainter {
  _SignatureBaselinePainter({required this.color});

  final Color color;

  static const double _baselineFraction = 0.72;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height * _baselineFraction;
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(16, y), Offset(size.width - 16, y), paint);
  }

  @override
  bool shouldRepaint(_SignatureBaselinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Paints the collected strokes as smooth, round-capped ink lines.
class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  static final Paint _ink = Paint()
    ..color = AppColors.primary
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    for (final List<Offset> stroke in strokes) {
      if (stroke.isEmpty) {
        continue;
      }
      if (stroke.length == 1) {
        // A single touch point becomes a small dot.
        canvas.drawCircle(stroke.single, 1.5, _ink);
        continue;
      }
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, _ink);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) =>
      // Stroke updates always assign a NEW list instance (see
      // [SignaturePadState]), so identity comparison reliably detects every
      // change — including `clear()` — and the canvas repaints immediately
      // while the customer draws.
      !identical(oldDelegate.strokes, strokes);
}
