import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
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

  AdRequest get _request =>
      AdRequest(nonPersonalizedAds: !_state.personalizedAdsConsent);

  Future<void> init() async {
    if (!_supported || !AppConfig.adsEnabled || _initialized) return;
    try {
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
      request: _request,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          if (done != null && !done.isCompleted) done.complete();
        },
        onAdFailedToLoad: (err) {
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
      request: _request,
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
      await c.future.timeout(const Duration(seconds: 6), onTimeout: () {});
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
