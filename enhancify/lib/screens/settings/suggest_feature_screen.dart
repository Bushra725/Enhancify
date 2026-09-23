import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class SuggestFeatureScreen extends StatefulWidget {
  const SuggestFeatureScreen({super.key});

  @override
  State<SuggestFeatureScreen> createState() => _SuggestFeatureScreenState();
}

class _SuggestFeatureScreenState extends State<SuggestFeatureScreen> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final uri = Uri.parse('mailto:${AppConfig.supportEmail}'
        '?subject=${Uri.encodeComponent('Feature idea for ${AppConfig.appName}')}'
        '&body=${Uri.encodeComponent(_text.text.trim())}');
    final ok = await launchUrl(uri);
    if (!mounted) return;
    if (ok) {
      showSnack(context, 'Thanks for your idea! 💡');
      Navigator.of(context).pop();
    } else {
      showSnack(context, 'No email app found. Write to ${AppConfig.supportEmail}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suggest A Feature')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'What should we build next? Tell us what would make '
                '${AppConfig.appName} better for you.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  maxLength: 1000,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: 'I would love to...',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PillButton(
                label: 'Send',
                onPressed: _text.text.trim().length < 5 ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
