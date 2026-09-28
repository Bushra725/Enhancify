import 'package:flutter/material.dart';

import '../data/sticker_data.dart';
import '../theme/app_theme.dart';

/// Result of the sticker sheet: an asset sticker, or "make one from my photo".
class StickerPick {
  const StickerPick.asset(this.asset) : fromPhoto = false;
  const StickerPick.fromPhoto()
      : asset = null,
        fromPhoto = true;
  final String? asset;
  final bool fromPhoto;
}

int get stickerCount => stickerCategories.fold(0, (a, c) => a + c.assets.length);

Future<StickerPick?> showStickerPicker(BuildContext context) {
  return showModalBottomSheet<StickerPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.7,
      child: const _StickerSheet(),
    ),
  );
}

class _StickerSheet extends StatefulWidget {
  const _StickerSheet();

  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  int _cat = -1; // -1 = all

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final assets = _cat < 0
        ? [for (final c in stickerCategories) ...c.assets]
        : stickerCategories[_cat].assets;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Stickers ($stickerCount)',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => Navigator.of(context).pop(const StickerPick.fromPhoto()),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('From my photo'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _chip('All', -1),
              for (var i = 0; i < stickerCategories.length; i++)
                _chip(stickerCategories[i].name, i),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 88,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: assets.length,
            itemBuilder: (_, i) => InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).pop(StickerPick.asset(assets[i])),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Image.asset(assets[i], fit: BoxFit.contain, cacheWidth: 180),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, int index) {
    final sel = _cat == index;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
            color: sel ? Colors.white : context.palette.textPrimary,
            fontWeight: FontWeight.w600),
        onSelected: (_) => setState(() => _cat = index),
      ),
    );
  }
}
