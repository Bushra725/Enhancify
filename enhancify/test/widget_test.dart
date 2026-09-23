import 'package:enhancify/data/catalog.dart';
import 'package:enhancify/screens/onboarding/welcome_screen.dart';
import 'package:enhancify/screens/paywall/paywall_screen.dart';
import 'package:enhancify/services/app_state.dart';
import 'package:enhancify/services/purchase_service.dart';
import 'package:enhancify/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('free users get the daily quota, paid users unlimited', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(prefs);
    expect(state.remaining(UsageKeys.enhance, 3), 3);
    await state.incrementUsage(UsageKeys.enhance);
    expect(state.remaining(UsageKeys.enhance, 3), 2);
    await state.setTier(SubscriptionTier.pro);
    expect(state.remaining(UsageKeys.enhance, 3), -1);
  });

  test('preset prompts mention the chosen subject', () {
    final shot = presetPacks.first.shots.first;
    expect(buildPresetPrompt(shot, Gender.male), contains('the man'));
    expect(buildPresetPrompt(shot, Gender.female), contains('the woman'));
    expect(buildPresetPrompt(shot, Gender.other), contains('the person'));
  });

  test('catalog matches the product: 6 packs of 6 and 12 filters', () {
    expect(presetPacks, hasLength(6));
    for (final pack in presetPacks) {
      expect(pack.shots, hasLength(6), reason: pack.title);
    }
    expect(aiFilters, hasLength(12));
    expect(aiFilters.where((f) => f.pro), hasLength(4));
  });

  test('enhancer preferences round-trip', () {
    const prefs = EnhancerPrefs(
      faceFidelity: 0.2,
      upscale: 4,
      backgroundEnhance: false,
      faceUpsample: false,
      autoSave: true,
    );
    expect(EnhancerPrefs.fromJson(prefs.toJson()).upscale, 4);
    expect(EnhancerPrefs.fromJson(prefs.toJson()).autoSave, isTrue);
  });

  testWidgets('welcome and paywall build on a phone', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const WelcomeScreen(),
    ));
    expect(find.text('Get Started'), findsOneWidget);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(prefs);
    final purchases = PurchaseService(state, prefs);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: purchases),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const PaywallScreen(),
      ),
    ));
    await tester.pump();
    expect(find.text('Lite'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
