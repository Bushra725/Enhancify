import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'consent_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const _none = 'None of these options';
  static const _options = [
    'Facebook',
    'TikTok',
    'Snapchat',
    'Instagram',
    'YouTube',
    'Friends or family',
    _none,
  ];

  String? _selected;
  bool _busy = false;
  final _other = TextEditingController();

  @override
  void initState() {
    super.initState();
    _other.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selected != null && (_selected != _none || _other.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (_busy) return;
    _busy = true;
    final value = _selected == _none ? 'Other: ${_other.text.trim()}' : _selected!;
    await context.read<AppState>().setDiscoverSource(value);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConsentScreen()),
    );
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: 24),
                    Center(
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.brandGradient,
                        ),
                        child: const Icon(Icons.send_rounded,
                            size: 56, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Where did you discover\n${AppConfig.appName}?',
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    const SizedBox(height: 22),
                    for (final o in _options) ...[
                      _OptionTile(
                        label: o,
                        selected: _selected == o,
                        onTap: () => setState(() => _selected = o),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_selected == _none)
                      TextField(
                        controller: _other,
                        maxLines: 4,
                        maxLength: 200,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Write your answer here...',
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 8),
                  child: SizedBox(
                    width: 150,
                    child: PillButton(
                      label: 'Submit',
                      onPressed: _canSubmit ? _submit : null,
                      trailing: const Icon(Icons.arrow_forward_ios_rounded),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: selected ? AppColors.maroon.withValues(alpha: 0.35) : null,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? AppColors.red : AppColors.border,
            width: selected ? 2 : 1.4,
          ),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
