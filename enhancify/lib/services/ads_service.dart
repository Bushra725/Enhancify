import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' hide AppState;

import '../config/app_config.dart';
import 'app_state.dart';

/// Interstitial + rewarded ads for free users. Every call is failure-safe:
/// if an ad can't load, the user simply continues.
class AdsService {
  AdsService(this._state);

  final AppState _state;
  bool _initialized = false;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  AdRequest get request =>
      AdRequest(nonPersonalizedAds: !_state.personalizedAdsConsent);

  Future<void> ensureReady() => _ensureReady();

  Future<void> init() async {
    if (!_supported || !AppConfig.adsEnabled || _initialized) return;
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: const []),
      );
      await MobileAds.instance.initialize();
      _initialized = true;
      if (_state.showAds) {
        _loadInterstitial();
        _loadRewarded();
      }
    } catch (e) {
      debugPrint('Ads init failed: $e');
    }
  }

  void _loadInterstitial({Completer<void>? done}) {
    if (!_initialized) {
      done?.complete();
      return;
    }
    InterstitialAd.load(
      adUnitId: AppConfig.interstitialAdUnitId,
      request: request,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          if (done != null && !done.isCompleted) done.complete();
        },
        onAdFailedToLoad: (err) {
          debugPrint('Interstitial failed to load: $err');
          _interstitial = null;
          if (done != null && !done.isCompleted) done.complete();
        },
      ),
    );
  }

  void _loadRewarded({Completer<void>? done}) {
    if (!_initialized) {
      done?.complete();
      return;
    }
    RewardedAd.load(
      adUnitId: AppConfig.rewardedAdUnitId,
      request: request,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          if (done != null && !done.isCompleted) done.complete();
        },
        onAdFailedToLoad: (err) {
          _rewarded = null;
          if (done != null && !done.isCompleted) done.complete();
        },
      ),
    );
  }

  Future<void> _ensureReady() async {
    if (!_initialized) await init();
  }

  /// Shows an interstitial for free users. Completes when it's closed.
  Future<void> showInterstitial() async {
    if (!_state.showAds) return;
    await _ensureReady();
    if (!_initialized) return;
    if (_interstitial == null) {
      final c = Completer<void>();
      _loadInterstitial(done: c);
      await c.future.timeout(const Duration(seconds: 8), onTimeout: () {});
    }
    final ad = _interstitial;
    if (ad == null) return;
    _interstitial = null;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.show();
    await closed.future;
    _loadInterstitial();
  }

  /// Shows a rewarded ad. Returns true if the reward was earned — or if ads
  /// are unavailable (so users are never blocked by a missing ad).
  Future<bool> showRewarded() async {
    if (!_state.showAds) return true;
    await _ensureReady();
    if (!_initialized) return true;
    if (_rewarded == null) {
      final c = Completer<void>();
      _loadRewarded(done: c);
      await c.future.timeout(const Duration(seconds: 8), onTimeout: () {});
    }
    final ad = _rewarded;
    if (ad == null) return true;
    _rewarded = null;
    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        earned = true;
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    await closed.future;
    _loadRewarded();
    return earned;
  }
}

/// Shows a full-screen ad when the user leaves a feature screen.
class ExitAdObserver extends NavigatorObserver {
  ExitAdObserver(this.ads);

  final AdsService ads;
  bool _busy = false;

  /// Edit, restore, enhance, collage, and the other full-screen tools.
  static const features = {
    'edit',
    'restore',
    'enhance',
    'collage',
    'remove',
    'passport',
    'gif',
    'beauty',
    'bg',
    'music',
  };

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! PageRoute) return;
    final name = route.settings.name;
    if (name == null || !features.contains(name)) return;
    if (_busy) return;
    _busy = true;
    // Wait until the screen underneath is visible, or Android drops the ad.
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      ads.showInterstitial().whenComplete(() => _busy = false);
    });
  }
}
