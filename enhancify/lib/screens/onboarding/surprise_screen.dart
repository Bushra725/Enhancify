import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/app_state.dart';
import '../../services/purchase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/illustrations.dart';
import '../home/home_screen.dart';

/// "We've got a surprise for you" -> gift opens -> 2-week trial offer.
class SurpriseScreen extends StatefulWidget {
  const SurpriseScreen({super.key});

  @override
  State<SurpriseScreen> createState() => _SurpriseScreenState();
}

class _SurpriseScreenState extends State<SurpriseScreen> {
  int _stage = 0; // 0 = closed card, 1 = opening, 2 = offer
  bool _finished = false;
  bool _buying = false;

  Future<void> _open() async {
    setState(() => _stage = 1);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (mounted) setState(() => _stage = 2);
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    await context.read<AppState>().completeOnboarding();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  Future<void> _continue() async {
    setState(() => _buying = true);
    final err = await context
        .read<PurchaseService>()
        .buy(AppConfig.proWeekly, trial: true);
    if (!mounted) return;
    setState(() => _buying = false);
    if (err != null) showSnack(context, err);
  }

  Future<void> _restore() async {
    final msg = await context.read<PurchaseService>().restore();
    if (mounted) showSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final purchases = context.watch<PurchaseService>();
    if (state.isPaid && !_finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
    final price = purchases.priceFor(AppConfig.proWeekly);

    final trial = !purchases.available ||
        purchases.hasTrialOffer(AppConfig.proWeekly);

    return PopScope(
      canPop: false,
      child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.giftGradient),
        child: Stack(
          children: [
            if (_stage >= 1) const Positioned.fill(child: Confetti()),
            SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: switch (_stage) {
                  0 => _closedCard(),
                  1 => const Center(key: ValueKey(1), child: GiftBox(open: true)),
                  _ => _offer(price, purchases.purchasing || _buying, trial),
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _closedCard() {
    return Center(
      key: const ValueKey(0),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 36),
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [Color(0xFFB0123A), Color(0xFF4A0B3A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GiftBox(size: 110),
            const SizedBox(height: 14),
            const Text.rich(
              TextSpan(children: [
                TextSpan(text: "We've Got a\n"),
                TextSpan(
                    text: 'Surprise',
                    style: TextStyle(color: AppColors.gold)),
                TextSpan(text: ' for You!'),
              ]),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            const Text(
              'A special gift is waiting inside.\nOpen now to see what it is! 👀',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            PillButton(label: 'Open Surprise', onPressed: _open),
          ],
        ),
      ),
    );
  }

  Widget _offer(String price, bool busy, bool trial) {
    return LayoutBuilder(
      key: const ValueKey(2),
      builder: (context, c) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _finish,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
              const Spacer(),
              TextButton(
                onPressed: _restore,
                child: const Text('Restore Purchases',
                    style: TextStyle(
                        color: Colors.white,
                        decoration: TextDecoration.underline)),
              ),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
          const Spacer(),
          const GiftBox(open: true, size: 150),
          const SizedBox(height: 20),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: trial ? 'Congrats! You got\na ' : 'Congrats! You unlocked\n'),
              TextSpan(
                  text: trial ? '2-week trial' : 'Pro access',
                  style: const TextStyle(color: AppColors.gold)),
              const TextSpan(text: '!'),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (!trial)
            const Text(
              'Unlimited enhancements, AI photo packs, video enhance and '
              'no ads. Renews automatically, cancel anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
            )
          else
          const Text.rich(
            TextSpan(children: [
              TextSpan(text: 'We want to offer you all '),
              TextSpan(
                  text: AppConfig.proName,
                  style: TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: ' features for '),
              TextSpan(
                  text: 'two extra weeks',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(
                  text: ' at the best price! Renews automatically after '
                      'the trial period.'),
            ]),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 26),
          PillButton(label: 'Continue', loading: busy, onPressed: _continue),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: trial ? '2 weeks free, then ' : 'Only '),
              TextSpan(
                  text: '$price/week',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: '\nCancel anytime in your store account.'),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),
        ],
            ),
          ),
        ),
      ),
    );
  }
}
