import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/app_state.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../paywall/paywall_screen.dart';

/// Swipeable viewer for generated photos with save / share.
class AiResultsScreen extends StatefulWidget {
  const AiResultsScreen({
    super.key,
    required this.files,
    this.initialIndex = 0,
    this.title = 'AI Photos',
  });

  final List<File> files;
  final int initialIndex;
  final String title;

  @override
  State<AiResultsScreen> createState() => _AiResultsScreenState();
}

class _AiResultsScreenState extends State<AiResultsScreen> {
  late final PageController _pc =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _saving = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _save(List<File> files) async {
    final state = context.read<AppState>();
    final left = state.remaining(UsageKeys.save, AppConfig.freeSavesPerDay);
    if (left == 0 || (left > 0 && files.length > left)) {
      final ok = await openPaywall(context);
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    String? err;
    for (final f in files) {
      err = await MediaService.saveToGallery(f);
      if (err != null) break;
      await state.incrementUsage(UsageKeys.save);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showSnack(context,
        err ?? (files.length > 1 ? 'All photos saved ✨' : 'Saved to your gallery ✨'));
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title}  ${_index + 1}/${files.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => MediaService.shareFiles([files[_index]]),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: files.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image.file(files[i], fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          if (files.length > 1)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _pc.animateToPage(i,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: i == _index ? AppColors.red : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(files[i],
                          width: 56, height: 68, fit: BoxFit.cover, cacheWidth: 200),
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'Save',
                      kind: ButtonStyleKind.brand,
                      loading: _saving,
                      onPressed: () => _save([files[_index]]),
                    ),
                  ),
                  if (files.length > 1) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        label: 'Save all',
                        kind: ButtonStyleKind.outline,
                        onPressed: _saving ? null : () => _save(files),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
