import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

enum Gender { female, male, other }

enum SubscriptionTier { free, lite, pro }

/// User-facing enhancement settings (Settings > Enhancer Preferences).
class EnhancerPrefs {
  final double faceFidelity; // 0 = strongest enhancement, 1 = most faithful
  final int upscale; // 1, 2 or 4
  final bool backgroundEnhance;
  final bool faceUpsample;
  final bool autoSave;

  const EnhancerPrefs({
    this.faceFidelity = 0.7,
    this.upscale = 2,
    this.backgroundEnhance = true,
    this.faceUpsample = true,
    this.autoSave = false,
  });

  EnhancerPrefs copyWith({
    double? faceFidelity,
    int? upscale,
    bool? backgroundEnhance,
    bool? faceUpsample,
    bool? autoSave,
  }) =>
      EnhancerPrefs(
        faceFidelity: faceFidelity ?? this.faceFidelity,
        upscale: upscale ?? this.upscale,
        backgroundEnhance: backgroundEnhance ?? this.backgroundEnhance,
        faceUpsample: faceUpsample ?? this.faceUpsample,
        autoSave: autoSave ?? this.autoSave,
      );

  Map<String, dynamic> toJson() => {
        'faceFidelity': faceFidelity,
        'upscale': upscale,
        'backgroundEnhance': backgroundEnhance,
        'faceUpsample': faceUpsample,
        'autoSave': autoSave,
      };

  factory EnhancerPrefs.fromJson(Map<String, dynamic> j) => EnhancerPrefs(
        faceFidelity: (j['faceFidelity'] as num?)?.toDouble() ?? 0.7,
        upscale: (j['upscale'] as num?)?.toInt() ?? 2,
        backgroundEnhance: j['backgroundEnhance'] as bool? ?? true,
        faceUpsample: j['faceUpsample'] as bool? ?? true,
        autoSave: j['autoSave'] as bool? ?? false,
      );
}

/// Persistent app state: onboarding answers, consent, subscription tier,
/// daily usage counters, AI profile selfies and generated history.
class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static const _kOnboarded = 'onboarded';
  static const _kSource = 'discover_source';
  static const _kGender = 'gender';
  static const _kConsentAsked = 'consent_asked';
  static const _kAnalytics = 'consent_analytics';
  static const _kPersonalizedAds = 'consent_personalized_ads';
  static const _kTier = 'tier';
  static const _kUsageDay = 'usage_day';
  static const _kUsage = 'usage_counts';
  static const _kSelfies = 'ai_selfies';
  static const _kAiHistory = 'ai_history';
  static const _kEnhancer = 'enhancer_prefs';
  static const _kGenderTip = 'gender_tip_seen';

  bool onboarded = false;
  String? discoverSource;
  Gender gender = Gender.female;
  bool consentAsked = false;
  bool analyticsConsent = false;
  bool personalizedAdsConsent = false;
  SubscriptionTier tier = SubscriptionTier.free;
  EnhancerPrefs enhancerPrefs = const EnhancerPrefs();
  List<String> selfies = [];
  List<String> aiHistory = [];
  bool genderTipSeen = false;
  Map<String, int> _usage = {};

  bool get isPro => tier == SubscriptionTier.pro;
  bool get isPaid => tier != SubscriptionTier.free;
  bool get showAds => !isPaid && AppConfig.adsEnabled;

  void _load() {
    onboarded = _prefs.getBool(_kOnboarded) ?? false;
    discoverSource = _prefs.getString(_kSource);
    gender = Gender.values.firstWhere(
      (g) => g.name == _prefs.getString(_kGender),
      orElse: () => Gender.female,
    );
    consentAsked = _prefs.getBool(_kConsentAsked) ?? false;
    analyticsConsent = _prefs.getBool(_kAnalytics) ?? false;
    personalizedAdsConsent = _prefs.getBool(_kPersonalizedAds) ?? false;
    tier = SubscriptionTier.values.firstWhere(
      (t) => t.name == _prefs.getString(_kTier),
      orElse: () => SubscriptionTier.free,
    );
    selfies = _prefs.getStringList(_kSelfies) ?? [];
    aiHistory = _prefs.getStringList(_kAiHistory) ?? [];
    genderTipSeen = _prefs.getBool(_kGenderTip) ?? false;
    final ep = _prefs.getString(_kEnhancer);
    if (ep != null) {
      try {
        enhancerPrefs =
            EnhancerPrefs.fromJson(jsonDecode(ep) as Map<String, dynamic>);
      } catch (_) {}
    }
    _loadUsage();
  }

  // ------------------------------------------------------------ onboarding
  Future<void> setDiscoverSource(String source) async {
    discoverSource = source;
    await _prefs.setString(_kSource, source);
    notifyListeners();
  }

  Future<void> setGender(Gender g) async {
    gender = g;
    await _prefs.setString(_kGender, g.name);
    notifyListeners();
  }

  Future<void> setConsent({
    required bool analytics,
    required bool personalizedAds,
  }) async {
    consentAsked = true;
    analyticsConsent = analytics;
    personalizedAdsConsent = personalizedAds;
    await _prefs.setBool(_kConsentAsked, true);
    await _prefs.setBool(_kAnalytics, analytics);
    await _prefs.setBool(_kPersonalizedAds, personalizedAds);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    onboarded = true;
    await _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  Future<void> markGenderTipSeen() async {
    genderTipSeen = true;
    await _prefs.setBool(_kGenderTip, true);
    notifyListeners();
  }

  // --------------------------------------------------------- subscription
  Future<void> setTier(SubscriptionTier t) async {
    if (tier == t) return;
    tier = t;
    await _prefs.setString(_kTier, t.name);
    notifyListeners();
  }

  // ------------------------------------------------------ enhancer prefs
  Future<void> setEnhancerPrefs(EnhancerPrefs p) async {
    enhancerPrefs = p;
    await _prefs.setString(_kEnhancer, jsonEncode(p.toJson()));
    notifyListeners();
  }

  // ------------------------------------------------------- daily usage
  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  void _loadUsage() {
    if (_prefs.getString(_kUsageDay) != _today) {
      _usage = {};
      return;
    }
    try {
      final raw = jsonDecode(_prefs.getString(_kUsage) ?? '{}') as Map;
      _usage = raw.map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      _usage = {};
    }
  }

  int usageToday(String key) {
    if (_prefs.getString(_kUsageDay) != _today) _usage = {};
    return _usage[key] ?? 0;
  }

  Future<void> incrementUsage(String key) async {
    if (_prefs.getString(_kUsageDay) != _today) {
      _usage = {};
      await _prefs.setString(_kUsageDay, _today);
    }
    _usage[key] = (_usage[key] ?? 0) + 1;
    await _prefs.setString(_kUsage, jsonEncode(_usage));
    notifyListeners();
  }

  /// Remaining free uses today; paid tiers are unlimited (returns -1).
  int remaining(String key, int freeLimit, {bool liteUnlimited = true}) {
    if (isPro || (liteUnlimited && tier == SubscriptionTier.lite)) return -1;
    final left = freeLimit - usageToday(key);
    return left < 0 ? 0 : left;
  }

  // ------------------------------------------------------- AI profile
  Future<void> setSelfies(List<String> paths) async {
    selfies = List.of(paths);
    await _prefs.setStringList(_kSelfies, selfies);
    notifyListeners();
  }

  Future<void> addAiHistory(List<String> paths) async {
    aiHistory = [...paths, ...aiHistory];
    if (aiHistory.length > 200) aiHistory = aiHistory.sublist(0, 200);
    await _prefs.setStringList(_kAiHistory, aiHistory);
    notifyListeners();
  }

  Future<void> clearAiProfile() async {
    selfies = [];
    aiHistory = [];
    await _prefs.remove(_kSelfies);
    await _prefs.remove(_kAiHistory);
    notifyListeners();
  }
}

class UsageKeys {
  static const enhance = 'enhance';
  static const save = 'save';
  static const filter = 'filter';
}
