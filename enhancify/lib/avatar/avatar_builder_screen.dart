import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'avatar_model.dart';
import 'avatar_painter.dart';

/// Snapchat-style avatar creator. Pops the saved [AvatarConfig].
class AvatarBuilderScreen extends StatefulWidget {
  const AvatarBuilderScreen({super.key, this.initial});
  final AvatarConfig? initial;

  static Future<AvatarConfig?> open(BuildContext context, {AvatarConfig? initial}) =>
      Navigator.of(context).push<AvatarConfig>(
        MaterialPageRoute(builder: (_) => AvatarBuilderScreen(initial: initial)),
      );

  @override
  State<AvatarBuilderScreen> createState() => _AvatarBuilderScreenState();
}

class _Tab {
  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _AvatarBuilderScreenState extends State<AvatarBuilderScreen> {
  late AvatarConfig _c = widget.initial?.copy() ?? AvatarConfig();
  int _tab = 0;
  int _poseIndex = 0;
  bool _saving = false;

  static const _tabs = [
    _Tab('Face', Icons.face_outlined),
    _Tab('Skin', Icons.palette_outlined),
    _Tab('Hair', Icons.content_cut),
    _Tab('Hair color', Icons.format_color_fill),
    _Tab('Eyes', Icons.remove_red_eye_outlined),
    _Tab('Brows', Icons.horizontal_rule),
    _Tab('Nose', Icons.air),
    _Tab('Lips', Icons.favorite_border),
    _Tab('Beard', Icons.face_retouching_natural),
    _Tab('Glasses', Icons.visibility_outlined),
    _Tab('Earrings', Icons.circle_outlined),
    _Tab('Headwear', Icons.emoji_events_outlined),
    _Tab('Outfit', Icons.checkroom_outlined),
    _Tab('Outfit color', Icons.color_lens_outlined),
  ];

  static const _previewPoses = ['happy', 'wink', 'love', 'laugh', 'cool'];

  /// Boys get Beard first-class and no Lips tab; girls skip Beard.
  List<int> get _visibleTabs => [
        for (var i = 0; i < _tabs.length; i++)
          if (!(_c.gender == 'boy' && i == 7) && !(_c.gender == 'girl' && i == 8)) i,
      ];

  void _update(void Function(AvatarConfig c) f) => setState(() => f(_c));

  Future<void> _save() async {
    setState(() => _saving = true);
    await AvatarStore.save(_c);
    if (!mounted) return;
    Navigator.of(context).pop(_c);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Avatar'),
        actions: [
          IconButton(
            tooltip: 'Shuffle',
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: () => setState(() => _c = AvatarConfig.random(gender: _c.gender)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.primary,
                selectedForegroundColor: Colors.white,
              ),
              segments: const [
                ButtonSegment(value: 'girl', icon: Icon(Icons.face_3), label: Text('Girl')),
                ButtonSegment(value: 'boy', icon: Icon(Icons.face_6), label: Text('Boy')),
              ],
              selected: {_c.gender},
              onSelectionChanged: (v) => setState(() {
                final g = v.first;
                if (g == _c.gender) return;
                // Keep skin, eye and hair color; switch the style to match.
                final next = g == 'boy' ? AvatarConfig.boy() : AvatarConfig.girl();
                next
                  ..skin = _c.skin
                  ..eyeColor = _c.eyeColor
                  ..hairColor = _c.hairColor;
                _c = next;
                _tab = 0;
              }),
            ),
          ),
          GestureDetector(
            onTap: () => setState(
                () => _poseIndex = (_poseIndex + 1) % _previewPoses.length),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: AppColors.blushGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, box) {
                      final h = MediaQuery.sizeOf(context).height;
                      final w = (h * 0.26).clamp(120.0, 220.0);
                      return AvatarView(
                          config: _c, pose: _previewPoses[_poseIndex], width: w);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text('Tap to see expressions',
                      style: TextStyle(fontSize: 12, color: palette.textMuted)),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _visibleTabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, j) {
                final i = _visibleTabs[j];
                return ChoiceChip(
                  avatar: Icon(_tabs[i].icon,
                      size: 16,
                      color: i == _tab ? Colors.white : palette.textSecondary),
                  label: Text(_tabs[i].label),
                  selected: i == _tab,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                      color: i == _tab ? Colors.white : palette.textPrimary,
                      fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _tab = i),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: _panel()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: PillButton(
                label: 'Save avatar',
                kind: ButtonStyleKind.brand,
                loading: _saving,
                onPressed: _save,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel() {
    switch (_tab) {
      case 0:
        return _styles('face', AvatarOptions.facesFor(_c.gender), _c.face, (v) => _c.face = v);
      case 1:
        return _colors(AvatarOptions.skinTones, _c.skin, (v) => _c.skin = v);
      case 2:
        return _styles('hair', AvatarOptions.hairFor(_c.gender), _c.hairStyle, (v) => _c.hairStyle = v);
      case 3:
        return _colors(AvatarOptions.hairColors, _c.hairColor, (v) => _c.hairColor = v);
      case 4:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _styles('eyes', AvatarOptions.eyes, _c.eyes, (v) => _c.eyes = v, shrink: true),
            const _Label('Eye color'),
            _colors(AvatarOptions.eyeColors, _c.eyeColor, (v) => _c.eyeColor = v, shrink: true),
          ],
        );
      case 5:
        return _styles('brows', AvatarOptions.brows, _c.brows, (v) => _c.brows = v);
      case 6:
        return _styles('nose', AvatarOptions.noses, _c.nose, (v) => _c.nose = v);
      case 7:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lip color'),
              value: _c.lipstick,
              onChanged: (v) => _update((c) => c.lipstick = v),
            ),
            _colors(AvatarOptions.lipColors, _c.lipColor, (v) {
              _c.lipColor = v;
              _c.lipstick = true;
            }, shrink: true),
          ],
        );
      case 8:
        return _styles('facial', AvatarOptions.facial, _c.facial, (v) => _c.facial = v);
      case 9:
        return _styles('glasses', AvatarOptions.glasses, _c.glasses, (v) => _c.glasses = v);
      case 10:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _styles('earrings', AvatarOptions.earrings, _c.earrings, (v) => _c.earrings = v, shrink: true),
            const _Label('Accessory color'),
            _colors(AvatarOptions.accentColors, _c.accentColor, (v) => _c.accentColor = v, shrink: true),
          ],
        );
      case 11:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _styles('hat', AvatarOptions.hats, _c.hat, (v) => _c.hat = v, shrink: true),
            const _Label('Bow & flower color'),
            _colors(AvatarOptions.accentColors, _c.accentColor, (v) => _c.accentColor = v, shrink: true),
          ],
        );
      case 12:
        return _styles('outfit', AvatarOptions.outfitsFor(_c.gender), _c.outfitStyle, (v) => _c.outfitStyle = v);
      default:
        return _colors(AvatarOptions.outfitColors, _c.outfitColor, (v) => _c.outfitColor = v);
    }
  }

  /// Grid of mini avatars, one per option.
  Widget _styles(String kind, List<String> options, String current, void Function(String) set,
      {bool shrink = false}) {
    return GridView.builder(
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      padding: shrink ? const EdgeInsets.only(top: 4) : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemCount: options.length,
      itemBuilder: (context, i) {
        final key = options[i];
        final preview = _c.copy();
        _apply(preview, kind, key);
        final selected = key == current;
        return GestureDetector(
          onTap: () => _update((_) => set(key)),
          child: Container(
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: FittedBox(child: AvatarView(config: preview, width: 90)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(AvatarOptions.label(key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Applies option [key] of [kind] to a preview copy.
  void _apply(AvatarConfig c, String kind, String key) {
    switch (kind) {
      case 'face':
        c.face = key;
      case 'hair':
        c.hairStyle = key;
      case 'eyes':
        c.eyes = key;
      case 'brows':
        c.brows = key;
      case 'nose':
        c.nose = key;
      case 'facial':
        c.facial = key;
      case 'glasses':
        c.glasses = key;
      case 'earrings':
        c.earrings = key;
      case 'hat':
        c.hat = key;
      case 'outfit':
        c.outfitStyle = key;
    }
  }

  Widget _colors(List<Color> colors, Color current, void Function(Color) set,
      {bool shrink = false}) {
    return GridView.builder(
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      padding: shrink ? const EdgeInsets.only(top: 4, bottom: 12) : const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: colors.length,
      itemBuilder: (context, i) {
        final col = colors[i];
        final selected = col.toARGB32() == current.toARGB32();
        return GestureDetector(
          onTap: () => _update((_) => set(col)),
          child: Container(
            decoration: BoxDecoration(
              color: col,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.primary : context.palette.border,
                width: selected ? 3.5 : 1.5,
              ),
            ),
            child: selected
                ? Icon(Icons.check,
                    color: col.computeLuminance() > 0.6 ? Colors.black : Colors.white)
                : null,
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      );
}
