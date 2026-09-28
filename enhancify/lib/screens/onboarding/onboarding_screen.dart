import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'discover_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  static const _pages = [
    (Icons.auto_awesome, 'onb1Title', 'onb1Body', Color(0xFFFF4F97)),
    (Icons.brush_outlined, 'onb2Title', 'onb2Body', Color(0xFFB892FF)),
    (Icons.grid_view_rounded, 'onb3Title', 'onb3Body', Color(0xFFEA026A)),
  ];

  void _goDiscover() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'discover'),
        builder: (_) => const DiscoverScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.blushGradient),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _goDiscover,
                  child: Text(context.tr('skip')),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            key: ValueKey(i),
                            tween: Tween(begin: 0.8, end: 1),
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutBack,
                            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: page.$4.withValues(alpha: 0.28),
                                    blurRadius: 28,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Icon(page.$1, size: 72, color: page.$4),
                            ),
                          ),
                          const SizedBox(height: 36),
                          Text(
                            context.tr(page.$2),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 30,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2A0A1A),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            context.tr(page.$3),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, height: 1.4, color: Color(0xFF6B4658)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? AppColors.primary : const Color(0xFFE7B7CB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                child: PillButton(
                  label: last ? context.tr('getStarted') : context.tr('next'),
                  kind: ButtonStyleKind.brand,
                  onPressed: () {
                    if (last) {
                      _goDiscover();
                    } else {
                      _page.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
                    }
                  },
                  trailing: const Icon(Icons.arrow_forward_ios_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
