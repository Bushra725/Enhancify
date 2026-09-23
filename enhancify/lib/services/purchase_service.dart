import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'app_state.dart';

/// Google Play / App Store subscriptions.
///
/// Create these subscription products in the Play Console / App Store
/// Connect with the ids from [AppConfig.productIds]. Put the "2-week free
/// trial" as an introductory offer on [AppConfig.proWeekly].
///
/// Note: for production, verify receipts on your server. This client-side
/// check is the standard starting point.
class PurchaseService extends ChangeNotifier {
  PurchaseService(this._state, this._prefs);

  final AppState _state;
  final SharedPreferences _prefs;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  static const _kSource = 'tier_source'; // 'store' | 'debug'

  bool available = false;
  bool loading = true;
  bool purchasing = false;
  String? lastError;
  /// Regular (base plan) product per id.
  final Map<String, ProductDetails> products = {};

  /// Android: the free-trial offer of a subscription, when one is configured.
  final Map<String, ProductDetails> trialOffers = {};
  bool _sawActivePurchase = false;

  Future<void> init() async {
    try {
      available = await _iap.isAvailable();
    } catch (_) {
      available = false;
    }
    if (available) {
      _sub = _iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) {
          lastError = e.toString();
          purchasing = false;
          notifyListeners();
        },
      );
      try {
        final resp = await _iap.queryProductDetails(AppConfig.productIds);
        // On Android each subscription offer (base plan, free trial...) comes
        // back as its own ProductDetails with the same id.
        for (final p in resp.productDetails) {
          if (_hasFreeTrial(p)) {
            trialOffers.putIfAbsent(p.id, () => p);
          } else {
            products.putIfAbsent(p.id, () => p);
          }
        }
        trialOffers.forEach((id, p) => products.putIfAbsent(id, () => p));
      } catch (e) {
        lastError = e.toString();
      }
      // iOS re-delivers expired transactions on restore and may prompt for
      // the Apple ID, so only auto-refresh on Android.
      if (!kIsWeb && Platform.isAndroid) unawaited(_refreshEntitlements());
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _refreshEntitlements() async {
    _sawActivePurchase = false;
    try {
      await _iap.restorePurchases();
    } catch (_) {
      return;
    }
    // Active subscriptions are re-delivered as `restored` events. If none
    // arrive, a store-granted tier has expired.
    await Future<void>.delayed(const Duration(seconds: 10));
    if (!_sawActivePurchase &&
        _prefs.getString(_kSource) == 'store' &&
        _state.tier != SubscriptionTier.free) {
      await _state.setTier(SubscriptionTier.free);
    }
  }

  SubscriptionTier _tierFor(String productId) {
    if (productId == AppConfig.proWeekly || productId == AppConfig.proYearly) {
      return SubscriptionTier.pro;
    }
    if (productId == AppConfig.liteWeekly ||
        productId == AppConfig.liteYearly) {
      return SubscriptionTier.lite;
    }
    return SubscriptionTier.free;
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final pd in list) {
      switch (pd.status) {
        case PurchaseStatus.pending:
          purchasing = true;
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final t = _tierFor(pd.productID);
          if (t != SubscriptionTier.free) {
            _sawActivePurchase = true;
            // Never downgrade pro -> lite because of an older lite receipt.
            if (!(_state.isPro && t == SubscriptionTier.lite)) {
              await _state.setTier(t);
            }
            await _prefs.setString(_kSource, 'store');
          }
          purchasing = false;
          break;
        case PurchaseStatus.error:
          lastError = pd.error?.message ?? 'Purchase failed.';
          purchasing = false;
          break;
        case PurchaseStatus.canceled:
          purchasing = false;
          break;
      }
      if (pd.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(pd);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  /// True when [p] includes a free introductory phase.
  ///
  /// Android splits each Play offer into its own [ProductDetails]. iOS keeps
  /// the intro offer on the product (StoreKit 1 spells the mode `freeTrail`).
  bool _hasFreeTrial(ProductDetails p) =>
      _androidFreeTrial(p) || _storeKitFreeTrial(p);

  bool _androidFreeTrial(ProductDetails p) {
    try {
      final dynamic d = p;
      final int? index = d.subscriptionIndex as int?;
      final List? offers = d.productDetails.subscriptionOfferDetails as List?;
      if (index == null || offers == null || index < 0 || index >= offers.length) {
        return false;
      }
      final List phases = offers[index].pricingPhases as List;
      return phases.any((dynamic ph) {
        final micros = ph.priceAmountMicros;
        return micros is num && micros == 0;
      });
    } catch (_) {
      return false;
    }
  }

  bool _storeKitFreeTrial(ProductDetails p) {
    try {
      final dynamic d = p;
      final intro = d.skProduct?.introductoryPrice;
      if (intro != null &&
          '${intro.paymentMode}'.toLowerCase().contains('free')) {
        return true;
      }
    } catch (_) {}
    try {
      final dynamic d = p;
      final List? offers =
          d.sk2Product?.subscription?.promotionalOffers as List?;
      if (offers == null) return false;
      for (final dynamic offer in offers) {
        final mode = '${offer.paymentMode}'.toLowerCase();
        final type = '${offer.type}'.toLowerCase();
        final price = offer.price;
        final free = mode.contains('free') || (price is num && price == 0);
        if (free && type.contains('introductory')) return true;
      }
    } catch (_) {}
    return false;
  }

  bool hasTrialOffer(String productId) => trialOffers.containsKey(productId);

  String priceFor(String productId) =>
      products[productId]?.price ?? AppConfig.fallbackPrices[productId] ?? '';

  /// Starts a purchase. Returns an error message, or null when the store
  /// sheet was opened (the result arrives on the purchase stream).
  Future<String?> buy(String productId, {bool trial = false}) async {
    lastError = null;
    final product =
        (trial ? trialOffers[productId] : null) ?? products[productId];
    if (!available || product == null) {
      if (kDebugMode) {
        // Lets you test Pro flows before the store products exist.
        await _state.setTier(_tierFor(productId));
        await _prefs.setString(_kSource, 'debug');
        notifyListeners();
        return null;
      }
      return 'Store is not available right now. Please try again later.';
    }
    purchasing = true;
    notifyListeners();
    try {
      final ok = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!ok) {
        purchasing = false;
        notifyListeners();
        return 'Could not start the purchase.';
      }
      return null;
    } catch (e) {
      purchasing = false;
      notifyListeners();
      return e.toString();
    }
  }

  Future<String> restore() async {
    if (!available) return 'Store is not available right now.';
    _sawActivePurchase = false;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      return 'Restore failed: $e';
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    return _sawActivePurchase
        ? 'Your subscription has been restored.'
        : 'No active subscription found for this account.';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
