import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/emoji_data.dart';
import '../theme/app_theme.dart';

/// Full emoji keyboard (1,800+ emoji in 9 categories, search, recents and
/// skin tones). Returns the chosen emoji.
Future<String?> showEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.72 -
            MediaQuery.viewInsetsOf(ctx).bottom * 0.5,
        child: const _EmojiPicker(),
      ),
    ),
  );
}

class _EmojiPicker extends StatefulWidget {
  const _EmojiPicker();

  @override
  State<_EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<_EmojiPicker> {
  static const _recentKey = 'emoji_recent_v1';
  static const _tones = ['', '\u{1F3FB}', '\u{1F3FC}', '\u{1F3FD}', '\u{1F3FE}', '\u{1F3FF}'];
  static const _toneSwatches = ['✋', '✋🏻', '✋🏼', '✋🏽', '✋🏾', '✋🏿'];

  final _search = TextEditingController();
  List<String> _recent = [];
  int _tone = 0;
  int _tab = 0; // 0 = recent, 1.. = categories

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final r = p.getStringList(_recentKey) ?? [];
      if (!mounted) return;
      setState(() {
        _recent = r;
        _tab = r.isEmpty ? 1 : 0;
      });
    } catch (_) {}
  }

  Future<void> _pick(String e) async {
    final list = [e, ..._recent.where((x) => x != e)].take(40).toList();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_recentKey, list);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(e);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _applyTone(EmojiItem item) {
    if (!item.tones || _tone == 0) return item.emoji;
    final runes = item.emoji.runes.toList();
    if (runes.isEmpty) return item.emoji;
    final rest = runes.skip(1).toList();
    if (rest.isNotEmpty && rest.first == 0xFE0F) rest.removeAt(0);
    return String.fromCharCodes([runes.first, ..._tones[_tone].runes, ...rest]);
  }

  List<String> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final out = <String>[];
      for (final c in emojiCategories) {
        for (final e in c.items) {
          if (e.name.contains(q)) out.add(_applyTone(e));
        }
      }
      return out;
    }
    if (_tab == 0) return _recent;
    return emojiCategories[_tab - 1].items.map(_applyTone).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search emoji',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: palette.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _tabButton(0, Icons.history, null),
              for (var i = 0; i < emojiCategories.length; i++)
                _tabButton(i + 1, null, emojiCategories[i].icon),
              const SizedBox(width: 8),
              for (var t = 0; t < _toneSwatches.length; t++)
                GestureDetector(
                  onTap: () => setState(() => _tone = t),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t == _tone ? AppColors.blush : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_toneSwatches[t], style: const TextStyle(fontSize: 20)),
                  ),
                ),
            ],
          ),
        ),
        if (_search.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _tab == 0 ? 'Recently used' : emojiCategories[_tab - 1].name,
                style: TextStyle(
                    color: palette.textSecondary, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    _search.text.isEmpty ? 'No recent emoji yet' : 'No emoji found',
                    style: TextStyle(color: palette.textMuted),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 48,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _pick(items[i]),
                    child: Center(
                      child: Text(items[i], style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _tabButton(int index, IconData? icon, String? emoji) {
    final selected = _tab == index && _search.text.trim().isEmpty;
    return GestureDetector(
      onTap: () {
        _search.clear();
        setState(() => _tab = index);
      },
      child: Container(
        width: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.blush : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent, width: 1.5),
        ),
        child: icon != null
            ? Icon(icon, size: 20, color: AppColors.primary)
            : Text(emoji!, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
