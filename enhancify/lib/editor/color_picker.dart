import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Colors picked recently (this session), newest first.
final List<Color> recentColors = [];

void rememberColor(Color c) {
  recentColors.removeWhere((x) => x.toARGB32() == c.toARGB32());
  recentColors.insert(0, c);
  if (recentColors.length > 10) recentColors.removeLast();
}

/// Full color picker: saturation/brightness square + hue bar + hex code.
Future<Color?> showColorPickerSheet(BuildContext context, Color initial) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ColorPickerSheet(initial: initial),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.initial});
  final Color initial;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  String get _hex => '#${(_color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.border, width: 2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(_hex, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: () {
                    rememberColor(_color);
                    Navigator.pop(context, _color);
                  },
                  child: const Text('Use color'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AspectRatio(
              aspectRatio: 1.6,
              child: LayoutBuilder(builder: (context, box) {
                void pick(Offset p) {
                  final s = (p.dx / box.maxWidth).clamp(0.0, 1.0);
                  final v = 1 - (p.dy / box.maxHeight).clamp(0.0, 1.0);
                  setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
                }

                return GestureDetector(
                  onPanDown: (d) => pick(d.localPosition),
                  onPanUpdate: (d) => pick(d.localPosition),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Colors.white,
                                HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                              ]),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: _hsv.saturation * box.maxWidth - 11,
                          top: (1 - _hsv.value) * box.maxHeight - 11,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 30,
              child: LayoutBuilder(builder: (context, box) {
                void pick(double dx) =>
                    setState(() => _hsv = _hsv.withHue((dx / box.maxWidth).clamp(0.0, 1.0) * 359.9));
                return GestureDetector(
                  onPanDown: (d) => pick(d.localPosition.dx),
                  onPanUpdate: (d) => pick(d.localPosition.dx),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            gradient: LinearGradient(colors: [
                              for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                            ]),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (_hsv.hue / 360 * box.maxWidth - 9).clamp(0.0, box.maxWidth - 18),
                        top: 2,
                        child: Container(
                          width: 18,
                          height: 26,
                          decoration: BoxDecoration(
                            color: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            if (recentColors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Recent', style: TextStyle(color: palette.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in recentColors)
                      GestureDetector(
                        onTap: () => setState(() => _hsv = HSVColor.fromColor(c)),
                        child: Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: palette.border),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
