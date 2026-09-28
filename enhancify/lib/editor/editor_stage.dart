import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'draw.dart';
import 'layer_stage.dart';
import 'overlay_controller.dart';

/// A photo (or collage board) with drawing and movable layers on top.
/// Wrap-in-RepaintBoundary is done here so the whole thing can be exported.
class EditorStage extends StatefulWidget {
  const EditorStage({
    super.key,
    required this.controller,
    required this.boundaryKey,
    required this.child,
  });

  final OverlayController controller;
  final GlobalKey boundaryKey;

  /// The base: photo or collage board. Must fill the stage.
  final Widget child;

  @override
  State<EditorStage> createState() => _EditorStageState();
}

class _EditorStageState extends State<EditorStage> {
  DrawStroke? _current;

  OverlayController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        Offset norm(Offset p) => Offset(
            (p.dx / w).clamp(0.0, 1.0), (p.dy / h).clamp(0.0, 1.0));
        return RepaintBoundary(
          key: widget.boundaryKey,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => c.select(null),
                child: c.hideBase ? const SizedBox.expand() : widget.child,
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: StrokesPainter(c.strokes, revision: c.strokes.length),
                ),
              ),
              LayerStage(
                layers: c.layers,
                selectedId: c.selectedId,
                onSelect: c.select,
                onChanged: c.changed,
                onEditText: (l) => c.editText(context, l),
                interactive: !c.drawing,
              ),
              if (c.drawing)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    _current = DrawStroke(
                      color: c.draw.color,
                      width: c.draw.width,
                      kind: c.draw.kind,
                      points: [norm(d.localPosition)],
                    );
                    c.strokes.add(_current!);
                    c.changed();
                  },
                  onPanUpdate: (d) {
                    _current?.points.add(norm(d.localPosition));
                    c.changed();
                  },
                  onPanEnd: (_) => _current = null,
                ),
            ],
          ),
        );
      }),
    );
  }
}

/// Renders the stage to PNG bytes at roughly [targetWidth] pixels wide.
/// Deselects layers first so the selection frame isn't exported.
/// With [overlayOnly] the base photo is hidden, giving a transparent PNG of
/// just the text/stickers/drawing (see [compositeOverlay]).
Future<Uint8List?> captureStage(
  GlobalKey key,
  OverlayController controller, {
  double targetWidth = 2160,
  bool overlayOnly = false,
}) async {
  final wasDrawing = controller.drawing;
  controller.select(null);
  if (wasDrawing) controller.setDrawing(false);
  controller.hideBase = overlayOnly;
  controller.changed();
  try {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize || boundary.size.width <= 0) {
      return null;
    }
    final ratio = (targetWidth / boundary.size.width).clamp(1.0, 8.0);
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } finally {
    controller.hideBase = false;
    if (wasDrawing) controller.setDrawing(true);
    controller.changed();
  }
}

/// Draws [overlayPng] (transparent) on top of [base] at the base's full
/// resolution and returns a PNG.
Future<Uint8List> compositeOverlay(Uint8List base, Uint8List overlayPng) async {
  final baseCodec = await ui.instantiateImageCodec(base);
  final baseImg = (await baseCodec.getNextFrame()).image;
  final overCodec = await ui.instantiateImageCodec(overlayPng);
  final overImg = (await overCodec.getNextFrame()).image;
  try {
    final w = baseImg.width.toDouble(), h = baseImg.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImage(baseImg, Offset.zero, paint);
    canvas.drawImageRect(
      overImg,
      Rect.fromLTWH(0, 0, overImg.width.toDouble(), overImg.height.toDouble()),
      Rect.fromLTWH(0, 0, w, h),
      paint,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(baseImg.width, baseImg.height);
    picture.dispose();
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (data == null) throw StateError('Could not encode the image.');
    return data.buffer.asUint8List();
  } finally {
    baseImg.dispose();
    overImg.dispose();
    baseCodec.dispose();
    overCodec.dispose();
  }
}
