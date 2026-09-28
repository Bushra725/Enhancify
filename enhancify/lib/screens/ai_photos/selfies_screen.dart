import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/app_state.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// "Your selfies": builds the AI profile used by AI Photos.
/// Pops `true` when saved.
class SelfiesScreen extends StatefulWidget {
  const SelfiesScreen({super.key});

  @override
  State<SelfiesScreen> createState() => _SelfiesScreenState();
}

class _SelfiesScreenState extends State<SelfiesScreen> {
  late List<File> _files = context
      .read<AppState>()
      .selfies
      .map(File.new)
      .where((f) => f.existsSync())
      .toList();
  bool _saving = false;

  Future<void> _add() async {
    final left = AppConfig.maxSelfies - _files.length;
    if (left <= 0) return;
    final picked = await MediaService.pickImages(limit: left);
    if (picked.isEmpty || !mounted) return;
    setState(() => _files = [..._files, ...picked].take(AppConfig.maxSelfies).toList());
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      final dir = Directory(p.join(
          (await getApplicationDocumentsDirectory()).path, 'enhancify', 'selfies'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final saved = <String>[];
      for (var i = 0; i < _files.length; i++) {
        final src = _files[i];
        if (p.isWithin(dir.path, src.path)) {
          saved.add(src.path);
          continue;
        }
        final ext = p.extension(src.path).isEmpty ? '.jpg' : p.extension(src.path);
        final dest = p.join(
            dir.path, 'selfie_${DateTime.now().millisecondsSinceEpoch}_$i$ext');
        saved.add((await src.copy(dest)).path);
      }
      // Remove selfies that were deleted from the profile.
      for (final f in dir.listSync().whereType<File>()) {
        if (!saved.contains(f.path)) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
      if (!mounted) return;
      await context.read<AppState>().setSelfies(saved);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Could not save selfies: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your AI profile')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Center(
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.maroon,
                      child: Icon(Icons.face_retouching_natural,
                          size: 46, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text('Generated with AI ✨',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 18),
                  DarkCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.download_for_offline_outlined,
                                size: 18),
                            const SizedBox(width: 6),
                            Text(
                                'Your selfies (${_files.length}/${AppConfig.maxSelfies})',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Add up to 8 clear selfies: different angles, good '
                          'light, only you in the photo. Your best selfie goes first.',
                          style: TextStyle(
                              color: context.palette.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                          itemCount: AppConfig.maxSelfies,
                          itemBuilder: (context, i) {
                            if (i < _files.length) {
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(_files[i],
                                        fit: BoxFit.cover, cacheWidth: 300),
                                  ),
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: GestureDetector(
                                      onTap: () => setState(
                                          () => _files = List.of(_files)..removeAt(i)),
                                      child: const CircleAvatar(
                                        radius: 11,
                                        backgroundColor: Colors.black87,
                                        child: Icon(Icons.close,
                                            size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return InkWell(
                              onTap: _add,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: context.palette.border),
                                ),
                                child: const Icon(Icons.add, size: 30),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'By tapping "Continue", you declare that you have all necessary '
                    'rights and permissions to share these images with us and that '
                    'you will use the photos generated lawfully.\n\n'
                    'If you upload images that include minors, by tapping "Continue" '
                    'you declare that you have parental responsibility for them and '
                    'the necessary rights to share the images.',
                    style: TextStyle(color: context.palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: PillButton(
                label: 'Continue',
                loading: _saving,
                onPressed: _files.isEmpty ? null : _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
