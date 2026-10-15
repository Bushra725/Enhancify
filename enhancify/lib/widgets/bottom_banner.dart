import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' hide AppState;
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/app_state.dart';

/// Fixed 320×50 banner for free users. Kept short so it sits above the
/// phone navigation bar without covering the app's own bottom bar.
class BottomBannerAd extends StatefulWidget {
  const BottomBannerAd({super.key});

  @override
  State<BottomBannerAd> createState() => _BottomBannerAdState();
}

class _BottomBannerAdState extends State<BottomBannerAd> {
  BannerAd? _ad;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final state = context.read<AppState>();
    if (!state.showAds || AppConfig.bannerAdUnitId.isEmpty) return;
    _ad?.dispose();
    final ad = BannerAd(
      size: AdSize.banner,
      adUnitId: AppConfig.bannerAdUnitId,
      request: AdRequest(nonPersonalizedAds: !state.personalizedAdsConsent),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _ready = true);
        },
        onAdFailedToLoad: (a, e) {
          a.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _ready = false;
            });
            Future<void>.delayed(const Duration(seconds: 10), () {
              if (mounted && !_ready) _load();
            });
          }
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_ready || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
