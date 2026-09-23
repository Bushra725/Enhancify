import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'ai_photos_flow.dart';
import 'ai_results_screen.dart';
import 'preset_detail_screen.dart';

class PickPresetScreen extends StatefulWidget {
  const PickPresetScreen({super.key});

  @override
  State<PickPresetScreen> createState() => _PickPresetScreenState();
}

class _PickPresetScreenState extends State<PickPresetScreen> {
  final _keys = {for (final p in presetPacks) p.id: GlobalKey()};
  String _activeChip = presetPacks.first.id;
  bool _showTip = false;

  @override
  void initState() {
    super.initState();
    _showTip = !context.read<AppState>().genderTipSeen;
  }

  void _jump(PresetPack p) {
    setState(() => _activeChip = p.id);
    final ctx = _keys[p.id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  Future<void> _changeGender() async {
    final state = context.read<AppState>();
    final g = await showModalBottomSheet<Gender>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Generate photos as',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            for (final (gender, emoji, label) in const [
              (Gender.female, '👩', 'Female'),
              (Gender.male, '👨', 'Male'),
              (Gender.other, '⭐', 'Other'),
            ])
              ListTile(
                leading: Text(emoji, style: const TextStyle(fontSize: 22)),
                title: Text(label),
                trailing: state.gender == gender
                    ? const Icon(Icons.check, color: AppColors.red)
                    : null,
                onTap: () => Navigator.pop(ctx, gender),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (g != null) await state.setGender(g);
  }

  String _genderEmoji(Gender g) => switch (g) {
        Gender.female => '👩',
        Gender.male => '👨',
        Gender.other => '⭐',
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history =
        state.aiHistory.where((p) => File(p).existsSync()).take(20).toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Pick Preset'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _changeGender,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.palette.surfaceHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_genderEmoji(state.gender)),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final p in presetPacks)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: _activeChip == p.id,
                          onSelected: (_) => _jump(p),
                          showCheckmark: false,
                          shape: const StadiumBorder(),
                          side: BorderSide.none,
                          selectedColor: Colors.white,
                          backgroundColor: context.palette.surface,
                          label: Text(
                            '${p.title} ${p.emoji}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _activeChip == p.id
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  child: Column(
                    children: [
                      if (history.isNotEmpty) _historyStrip(history),
                      for (final p in presetPacks)
                        _PackSection(key: _keys[p.id], pack: p),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_showTip)
            Positioned(
              right: 12,
              top: 0,
              child: _Tip(onClose: () {
                setState(() => _showTip = false);
                context.read<AppState>().markGenderTipSeen();
              }),
            ),
        ],
      ),
    );
  }

  Widget _historyStrip(List<String> history) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DarkCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My AI Photos',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: history.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AiResultsScreen(
                      files: history.map(File.new).toList(),
                      initialIndex: i,
                      title: 'My AI Photos',
                    ),
                  )),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(history[i]),
                        width: 84,
                        height: 110,
                        fit: BoxFit.cover,
                        cacheWidth: 250),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackSection extends StatelessWidget {
  const _PackSection({super.key, required this.pack});
  final PresetPack pack;

  @override
  Widget build(BuildContext context) {
    final isPro = context.watch<AppState>().isPro;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DarkCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${pack.title} ${pack.emoji}',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('${pack.shots.length} PHOTOS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: context.palette.textSecondary)),
                if (pack.trending) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.trending_up,
                        size: 14, color: Colors.white),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            PillButton(
              label: 'Get Full Pack',
              expand: false,
              height: 44,
              fontSize: 14,
              trailing: isPro ? null : const ProBadge(small: true),
              onPressed: () => generatePack(context, pack),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 0.75,
              ),
              itemCount: pack.shots.length,
              itemBuilder: (context, i) {
                final s = pack.shots[i];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PresetDetailScreen(pack: pack, shot: s),
                  )),
                  child: GradientThumb(
                    colors: s.colors,
                    icon: s.icon,
                    label: s.title,
                    imageUrl: s.imageUrl,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text.rich(
              TextSpan(
                style: TextStyle(color: Colors.black87, fontSize: 13),
                children: [
                  TextSpan(text: 'You can always update\nthe '),
                  TextSpan(
                      text: 'gender',
                      style: TextStyle(
                          color: AppColors.red, fontWeight: FontWeight.w700)),
                  TextSpan(text: ' here.'),
                ],
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              child: const Text('Got It'),
            ),
          ],
        ),
      ),
    );
  }
}
