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
  static const String supportEmail = 'MobAppsInc11@gmail.com';
  /// Legal pages hosted by the publisher (Mob Apps Inc).
  static const String privacyUrl =
      'https://sites.google.com/view/mob-apps-inc/privacy-policy';
  /// No separate Terms page is published yet — Privacy Policy covers use.
  static const String termsUrl = privacyUrl;
  static const String helpCenterUrl = privacyUrl;
  static const String appVersionLabel = '1.8.0';
  static const String instagramUrl = 'https://instagram.com/';
  static const String facebookUrl = 'https://facebook.com/';
  static const String tiktokUrl = 'https://tiktok.com/';
  static const String androidPackage =
      'com.mai.photo.editor.app.picture.face.art.lab';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$androidPackage';
  static const String appStoreUrl = 'https://apps.apple.com/app/id0000000000';

  // ---------------------------------------------------- FREE AI (default)
  /// Cloudflare Worker URL (see /cloudflare). The model key stays on
  /// Cloudflare. When set, this provider is used for all photo features.
  static const String cfWorkerUrl =
      String.fromEnvironment('CF_WORKER_URL', defaultValue: '');

  /// Shared secret for the Worker (sent as `x-app-key`).
  static const String cfAppKey =
      String.fromEnvironment('CF_APP_KEY', defaultValue: '');

  static bool get useCloudflare => cfWorkerUrl.isNotEmpty;

  /// Video enhance needs the paid Replicate provider.
  static bool get supportsVideo => !useCloudflare;

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

  /// Build-time OpenAI key. End users never enter this.
  static const String openAiApiKey =
      String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');

  /// Gemini image key. Edits the selected photo. End users never enter this.
  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  /// True only when no OpenAI key was baked in and no Replicate backend exists.
  /// The live key from Settings is checked separately by [AiService].
  static bool get isDemoMode =>
      !useCloudflare &&
      openAiApiKey.isEmpty &&
      geminiApiKey.isEmpty &&
      backendUrl.isEmpty &&
      replicateToken.isEmpty;

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
  static const String proMonthly = 'enhancify_pro_monthly';
  static const String proYearly = 'enhancify_pro_yearly';
  static const Set<String> productIds = {
    liteWeekly,
    liteYearly,
    proWeekly,
    proMonthly,
    proYearly,
  };

  /// Fallback prices shown while the store is loading / unavailable.
  static const Map<String, String> fallbackPrices = {
    liteWeekly: '\$2.99',
    liteYearly: '\$29.99',
    proWeekly: '\$6.99',
    proMonthly: '\$1.99',
    proYearly: '\$49.99',
  };

  // --------------------------------------------------------------- AdMob
  // Production AdMob units (Mob Apps Inc). Used in release / Play builds.
  // Debug uses Google's sample units so ads always load on device while
  // new production units still return "no fill" (error 3).
  static const bool adsEnabled = true;
  static const String androidAdMobAppId =
      'ca-app-pub-9297250663056879~7232608900';

  /// True in local debug installs. Release AAB/APK always uses production IDs.
  static bool get useSampleAdUnits => kDebugMode;

  static String get interstitialAdUnitId {
    if (kIsWeb) return '';
    if (useSampleAdUnits) {
      return 'ca-app-pub-3940256099942544/1033173712';
    }
    return 'ca-app-pub-9297250663056879/2467163463';
  }

  static String get rewardedAdUnitId {
    if (kIsWeb) return '';
    if (useSampleAdUnits) {
      return 'ca-app-pub-3940256099942544/5224354917';
    }
    return 'ca-app-pub-9297250663056879/4654343100';
  }

  static String get bannerAdUnitId {
    if (kIsWeb) return '';
    if (useSampleAdUnits) {
      return 'ca-app-pub-3940256099942544/6300978111';
    }
    return 'ca-app-pub-9297250663056879/7719490148';
  }

  static String get appOpenAdUnitId {
    if (kIsWeb) return '';
    if (useSampleAdUnits) {
      return 'ca-app-pub-3940256099942544/9257395921';
    }
    return 'ca-app-pub-9297250663056879/1914884724';
  }

  static String get nativeAdUnitId {
    if (kIsWeb) return '';
    if (useSampleAdUnits) {
      return 'ca-app-pub-3940256099942544/2247696110';
    }
    return 'ca-app-pub-9297250663056879/7788074228';
  }

  static String get storeUrl {
    if (!kIsWeb && Platform.isIOS) return appStoreUrl;
    return playStoreUrl;
  }
}
