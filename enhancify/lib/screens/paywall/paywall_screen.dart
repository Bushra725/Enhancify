import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/app_state.dart';
import '../../services/purchase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

enum _Plan { lite, pro }

enum _Period { monthly, yearly }

/// Opens the paywall. Returns true if the user is subscribed afterwards.
Future<bool> openPaywall(BuildContext context, {bool preferPro = true}) async {
  final state = context.read<AppState>();
  if (state.isPro) return true;
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      // Lite users can only upgrade to Pro.
      builder: (_) => PaywallScreen(preferPro: preferPro || state.isPaid),
    ),
  );
  if (!context.mounted) return false;
  return context.read<AppState>().isPaid;
}

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.preferPro = true});
  final bool preferPro;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late _Plan _plan = widget.preferPro ? _Plan.pro : _Plan.lite;
  _Period _period = _Period.monthly;
  bool _trial = false;
  bool _closing = false;
  late final bool _wasPaid = context.read<AppState>().isPaid;
  late final PageController _pages =
      PageController(viewportFraction: 0.86, initialPage: _pageFor(_plan));

  /// Paid (Lite) users only see the Pro card.
  List<_Plan> get _visiblePlans =>
      _wasPaid ? const [_Plan.pro] : const [_Plan.lite, _Plan.pro];
  int _pageFor(_Plan p) {
    final i = _visiblePlans.indexOf(p);
    return i < 0 ? 0 : i;
  }

  static const _features = <(IconData, String, bool)>[
    (Icons.auto_awesome_outlined, 'Unlimited Photo Enhancements', false),
    (Icons.block_outlined, 'No Ads', false),
    (Icons.branding_watermark_outlined, 'Remove Watermark', false),
    (Icons.filter_vintage_outlined, 'All AI Filters', false),
    (Icons.download_outlined, 'Unlimited Saves', false),
    (Icons.face_retouching_natural, 'AI Photo Full Packs', true),
    (Icons.hd_outlined, 'Ultra HD (4x) Enhance', true),
    (Icons.videocam_outlined, 'Video Enhance', true),
  ];

  String get _productId => switch ((_plan, _period)) {
        (_Plan.lite, _Period.monthly) => AppConfig.liteWeekly,
        (_Plan.lite, _Period.yearly) => AppConfig.liteYearly,
        (_Plan.pro, _Period.monthly) => AppConfig.proMonthly,
        (_Plan.pro, _Period.yearly) => AppConfig.proYearly,
      };

  @override
  void initState() {
    super.initState();
    if (_wasPaid) _plan = _Plan.pro; // capture tier at open time
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _setPlan(_Plan p, {bool fromPage = false}) {
    setState(() {
      _plan = p;
      if (p == _Plan.lite) _trial = false;
    });
    if (fromPage || !_pages.hasClients) return;
    final target = _pageFor(p);
    if (_pages.page?.round() == target) return;
    _pages.animateToPage(target,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _buy() async {
    final err = await context
        .read<PurchaseService>()
        .buy(_productId, trial: _trial && _plan == _Plan.pro);
    if (!mounted) return;
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

    final reachedTarget =
        _plan == _Plan.pro ? state.isPro : (state.isPaid && !_wasPaid);
    if (reachedTarget && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSnack(context, 'Welcome to ${AppConfig.appName} ${_plan == _Plan.pro ? 'Pro' : 'Lite'}!');
        Navigator.of(context).pop();
      });
    }

    final price = purchases.priceFor(_productId);
    final periodWord = _period == _Period.monthly ? 'month' : 'year';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.black),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _restore,
                  child: const Text('Restore Purchases',
                      style: TextStyle(
                          color: Colors.black54,
                          decoration: TextDecoration.underline)),
                ),
                const Spacer(),
                const SizedBox(width: 48),
              ],
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  SizedBox(
                    height: 200,
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (i) =>
                          _setPlan(_visiblePlans[i], fromPage: true),
                      children: [for (final p in _visiblePlans) _planCard(p)],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        for (final f in _features)
                          _featureRow(f.$1, f.$2,
                              included: !f.$3 || _plan == _Plan.pro),
                        if (_plan == _Plan.lite) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => _setPlan(_Plan.pro),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                side: const BorderSide(color: Colors.black26),
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 12),
                              ),
                              icon: const Icon(Icons.lock_outline, size: 18),
                              label: const Text('Unlock All',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: PillButton(
                label: _trial ? 'Start Free Trial' : 'Continue',
                kind: ButtonStyleKind.dark,
                loading: purchases.purchasing,
                onPressed: _buy,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                _trial
                    ? '2 weeks free, then $price/$periodWord. Cancel anytime.'
                    : '$price for 1 $periodWord, renews automatically. Cancel anytime.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(_Plan p) {
    final isPro = p == _Plan.pro;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: isPro
                ? const [AppColors.red, AppColors.maroon]
                : const [Color(0xFFB85C7A), Color(0xFF5A1A33)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: _plan == p ? Colors.black : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -8,
              top: -8,
              child: Icon(
                isPro ? Icons.workspace_premium : Icons.auto_awesome,
                size: 110,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isPro ? 'Pro' : 'Lite',
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  isPro
                      ? '${AppConfig.appName}\'s full experience:\nphotos, AI packs and videos.'
                      : 'Photo enhancement only.\nNo video, no AI packs.',
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: _periodDropdown(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_Period>(
          value: _period,
          isDense: true,
          dropdownColor: Colors.black,
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          items: const [
            DropdownMenuItem(value: _Period.monthly, child: Text('Monthly')),
            DropdownMenuItem(value: _Period.yearly, child: Text('Yearly')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _period = v;
              if (v == _Period.yearly) _trial = false;
            });
          },
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String text, {required bool included}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: included ? Colors.black87 : Colors.black38, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: TextStyle(
                  color: included ? Colors.black : Colors.black38,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                )),
          ),
          Icon(included ? Icons.check : Icons.close,
              color: included ? AppColors.success : AppColors.red, size: 20),
        ],
      ),
    );
  }
}
