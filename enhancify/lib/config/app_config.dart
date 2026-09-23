import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Central app configuration. Everything you are likely to change before
/// publishing lives here.
///
/// Secrets are passed at build time with --dart-define, e.g.
///   flutter run --dart-define=BACKEND_URL=https://your-server.example.com
/// or, for quick local testing only (never ship this):
///   flutter run --dart-define=REPLICATE_API_TOKEN=r8_xxx
class AppConfig {
  AppConfig._();

  // ---------------------------------------------------------------- branding
  static const String appName = 'Enhancify';
  static const String proName = 'Enhancify Pro';
  static const String supportEmail = 'support@theoccess.com';
  static const String helpCenterUrl = 'https://theoccess.com/enhancify/help';
  static const String termsUrl = 'https://theoccess.com/enhancify/terms';
  static const String privacyUrl = 'https://theoccess.com/enhancify/privacy';
  static const String instagramUrl = 'https://instagram.com/';
  static const String facebookUrl = 'https://facebook.com/';
  static const String tiktokUrl = 'https://tiktok.com/';
  static const String androidPackage = 'com.theoccess.enhancify';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$androidPackage';
  static const String appStoreUrl = 'https://apps.apple.com/app/id0000000000';

  // -------------------------------------------------------------- AI backend
  /// Your proxy server (see /server). Recommended for production because it
  /// keeps the Replicate token off the device.
  static const String backendUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: '');

  /// Optional shared secret sent to your proxy as `x-app-key`.
  static const String backendAppKey =
      String.fromEnvironment('BACKEND_APP_KEY', defaultValue: '');

  /// Direct Replicate token. Used for video enhance.
  static const String replicateToken =
      String.fromEnvironment('REPLICATE_API_TOKEN', defaultValue: '');

  /// Optional build-time OpenAI key. A key saved in Settings overrides this.
  static const String openAiApiKey =
      String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');

  /// True only when no OpenAI key was baked in and no Replicate backend exists.
  /// The live key from Settings is checked separately by [AiService].
  static bool get isDemoMode =>
      openAiApiKey.isEmpty && backendUrl.isEmpty && replicateToken.isEmpty;

  // ------------------------------------------------------- free-tier limits
  static const int freeEnhancementsPerDay = 3;
  static const int freeSavesPerDay = 5;
  static const int freeFiltersPerDay = 2;
  static const int freeAiPhotosPerGeneration = 1;
  static const int proAiPhotosPerGeneration = 4;
  static const int maxSelfies = 8;
  static const int maxVideoSeconds = 60;

  // ---------------------------------------------------------- subscriptions
  static const String liteWeekly = 'enhancify_lite_weekly';
  static const String liteYearly = 'enhancify_lite_yearly';
  static const String proWeekly = 'enhancify_pro_weekly';
  static const String proYearly = 'enhancify_pro_yearly';
  static const Set<String> productIds = {
    liteWeekly,
    liteYearly,
    proWeekly,
    proYearly,
  };

  /// Fallback prices shown while the store is loading / unavailable.
  static const Map<String, String> fallbackPrices = {
    liteWeekly: '\$2.99',
    liteYearly: '\$29.99',
    proWeekly: '\$6.99',
    proYearly: '\$49.99',
  };

  // --------------------------------------------------------------- AdMob
  // These are Google's official TEST ids. Replace with your own before
  // release (and also the APPLICATION_ID in AndroidManifest / Info.plist).
  static const bool adsEnabled = true;

  static String get interstitialAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return 'ca-app-pub-3940256099942544/1033173712';
    return 'ca-app-pub-3940256099942544/4411468910';
  }

  static String get rewardedAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return 'ca-app-pub-3940256099942544/5224354917';
    return 'ca-app-pub-3940256099942544/1712485313';
  }

  static String get storeUrl {
    if (!kIsWeb && Platform.isIOS) return appStoreUrl;
    return playStoreUrl;
  }
}
