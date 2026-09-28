import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'draw.dart';
import 'fonts.dart';
import 'layers.dart';
import 'text_templates.dart';
import 'text_view.dart';

/// What the text sheet returns.
class TextSheetResult {
  TextSheetResult.text(this.spec) : photoSticker = false;
  TextSheetResult.photoSticker()
      : spec = null,
        photoSticker = true;
  final TextSpec? spec;
  final bool photoSticker;
}

/// Add / edit text: templates, fonts, colors, styles and curved text.
Future<TextSheetResult?> showTextSheet(BuildContext context, {TextSpec? initial}) {
  return showModalBottomSheet<TextSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final keyboard = mq.viewInsets.bottom;
      final h = math.max(
          360.0,
          math.min(mq.size.height * 0.8,
              mq.size.height - keyboard - mq.padding.top - 24));
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(height: h, child: _TextSheet(initial: initial)),
      );
    },
  );
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({this.initial});
  final TextSpec? initial;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late TextSpec _spec = widget.initial?.copy() ?? TextSpec(text: '');
  late final TextEditingController _ctrl = TextEditingController(text: _spec.text);
  int _tab = 0;

  static const _tabs = ['Templates', 'Font', 'Color', 'Style', 'Curve'];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _tab = 1;
    _ctrl.addListener(() => setState(() => _spec.text = _ctrl.text));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _done() {
    if (_spec.text.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(TextSheetResult.text(_spec));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final darkPreview = _spec.color.computeLuminance() > 0.6 &&
        _spec.bg != TextBg.label &&
        _spec.bg != TextBg.tiles;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text('Text',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(TextSheetResult.photoSticker()),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Photo sticker'),
              ),
              TextButton(
                onPressed: _done,
                child: const Text('Done',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.primary)),
              ),
            ],
          ),
        ),
        // Live preview
        Container(
          height: keyboard ? 64 : 118,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: darkPreview ? const Color(0xFF3A2430) : AppColors.blush,
            borderRadius: BorderRadius.circular(18),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: TextLayerView(
              spec: _spec.text.isEmpty ? (_spec.copy()..text = 'Your text') : _spec,
              fontSize: 30,
              maxWidth: 320,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: _ctrl,
            autofocus: widget.initial == null,
            minLines: 1,
            maxLines: keyboard ? 2 : 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Type something...',
              filled: true,
              fillColor: palette.surfaceHigh,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _tabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text(_tabs[i]),
              selected: _tab == i,
              showCheckmark: false,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                  color: _tab == i ? Colors.white : palette.textPrimary,
                  fontWeight: FontWeight.w600),
              onSelected: (_) => setState(() => _tab = i),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: _body()),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: PillButton(
              label: widget.initial == null ? 'Add text' : 'Update text',
              kind: ButtonStyleKind.brand,
              onPressed: _spec.text.trim().isEmpty ? null : _done,
            ),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    final palette = context.palette;
    switch (_tab) {
      case 0:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
          ),
          itemCount: textTemplates.length,
          itemBuilder: (_, i) {
            final spec = textTemplates[i].build();
            final light = spec.color.computeLuminance() > 0.6 &&
                spec.bg != TextBg.label &&
                spec.bg != TextBg.tiles;
            return GestureDetector(
              onTap: () {
                final keepText = _ctrl.text.trim().isNotEmpty && widget.initial != null;
                setState(() {
                  _spec = spec;
                  if (keepText) _spec.text = _ctrl.text;
                });
                if (!keepText) _ctrl.text = spec.text;
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: light ? const Color(0xFF8C6B7A) : palette.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.border),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: TextLayerView(spec: spec, fontSize: 18, maxWidth: 260),
                ),
              ),
            );
          },
        );
      case 1:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
          ),
          itemCount: editorFonts.length,
          itemBuilder: (_, i) {
            final f = editorFonts[i];
            final sel = f.family == _spec.font;
            return GestureDetector(
              onTap: () => setState(() => _spec.font = f.family),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? AppColors.blush : palette.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: sel ? AppColors.primary : palette.border,
                      width: sel ? 2 : 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Aa',
                        style: TextStyle(
                            fontFamily: f.family,
                            fontWeight: f.weight,
                            fontSize: 22,
                            color: palette.textPrimary)),
                    Text(f.label,
                        style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                  ],
                ),
              ),
            );
          },
        );
      case 2:
        final needsBg = _spec.bg == TextBg.label ||
            _spec.bg == TextBg.outline ||
            _spec.bg == TextBg.highlight ||
            _spec.bg == TextBg.tiles;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          children: [
            const Text('Text color', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ColorRow(selected: _spec.color, onPick: (c) => setState(() => _spec.color = c)),
            if (needsBg) ...[
              const SizedBox(height: 14),
              Text(
                  _spec.bg == TextBg.outline ? 'Outline color' : 'Background color',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ColorRow(selected: _spec.bgColor, onPick: (c) => setState(() => _spec.bgColor = c)),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Tip: pick Label, Outline or Highlight in Style to add a background color.',
                    style: TextStyle(fontSize: 12, color: palette.textMuted)),
              ),
          ],
        );
      case 3:
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in TextBg.values)
                  ChoiceChip(
                    label: Text(switch (b) {
                      TextBg.none => 'Plain',
                      TextBg.shadow => 'Shadow',
                      TextBg.outline => 'Outline',
                      TextBg.label => 'Label',
                      TextBg.highlight => 'Highlight',
                      TextBg.tiles => 'Letter tiles',
                    }),
                    selected: _spec.bg == b,
                    onSelected: (_) => setState(() => _spec.bg = b),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final a in const [TextAlign.left, TextAlign.center, TextAlign.right])
                  IconButton(
                    isSelected: _spec.align == a,
                    color: _spec.align == a ? AppColors.primary : null,
                    onPressed: () => setState(() => _spec.align = a),
                    icon: Icon(switch (a) {
                      TextAlign.left => Icons.format_align_left,
                      TextAlign.right => Icons.format_align_right,
                      _ => Icons.format_align_center,
                    }),
                  ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Italic'),
                  selected: _spec.italic,
                  onSelected: (v) => setState(() => _spec.italic = v),
                ),
              ],
            ),
            Row(
              children: [
                const Text('Spacing'),
                Expanded(
                  child: Slider(
                    value: _spec.letterSpacing.clamp(-0.05, 0.4),
                    min: -0.05,
                    max: 0.4,
                    onChanged: (v) => setState(() => _spec.letterSpacing = v),
                  ),
                ),
              ],
            ),
          ],
        );
      default:
        final multiline = _spec.text.contains('\n');
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          children: [
            Text(
              multiline
                  ? 'Curved text works on a single line. Remove line breaks to curve it.'
                  : 'Bend your text into an arch or a smile.',
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.sentiment_satisfied_alt, size: 20),
                Expanded(
                  child: Slider(
                    value: _spec.curve.clamp(-1.0, 1.0),
                    min: -1,
                    max: 1,
                    divisions: 40,
                    label: _spec.curve == 0
                        ? 'Straight'
                        : (_spec.curve > 0 ? 'Arch' : 'Smile'),
                    onChanged: multiline ? null : (v) => setState(() => _spec.curve = v),
                  ),
                ),
                const Icon(Icons.architecture, size: 20),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final (label, value) in const [
                  ('Straight', 0.0),
                  ('Soft arch', 0.3),
                  ('Arch', 0.6),
                  ('Circle', 1.0),
                  ('Smile', -0.5),
                ])
                  ActionChip(
                    label: Text(label),
                    onPressed: multiline
                        ? null
                        : () => setState(() => _spec.curve = value),
                  ),
              ],
            ),
          ],
        );
    }
  }
}
