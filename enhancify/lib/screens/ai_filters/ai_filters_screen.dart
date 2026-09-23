import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../data/catalog.dart';
import '../../l10n/l10n.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../paywall/paywall_screen.dart';
import '../tools/quick_tool.dart';

class AiFiltersScreen extends StatelessWidget {
  const AiFiltersScreen({super.key});

  Future<void> _use(BuildContext context, AiFilter f) async {
    final state = context.read<AppState>();
    if (f.pro && !state.isPaid) {
      await openPaywall(context);
      if (!context.mounted || !state.isPaid) return;
    }
    await runQuickTool(context,
        title: f.name, prompt: f.prompt, demoLook: f.demoLook);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final left = state.remaining(UsageKeys.filter, AppConfig.freeFiltersPerDay);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('aiFilters'))),
      body: Column(
        children: [
          if (left >= 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: DarkCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, color: AppColors.gold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('$left free AI filter${left == 1 ? '' : 's'} left today',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    GestureDetector(
                      onTap: () => openPaywall(context),
                      child: const ProBadge(),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: aiFilters.length,
              itemBuilder: (context, i) {
                final f = aiFilters[i];
                return GestureDetector(
                  onTap: () => _use(context, f),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GradientThumb(colors: f.colors, icon: f.icon, radius: 20),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Text(f.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      if (f.pro && !state.isPaid)
                        const Positioned(top: 10, right: 10, child: ProBadge()),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
