import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'services/ads_service.dart';
import 'services/ai_service.dart';
import 'services/app_state.dart';
import 'services/purchase_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
  ));

  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs);
  final purchases = PurchaseService(state, prefs);
  final ads = AdsService(state);
  final ai = AiService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: purchases),
        Provider.value(value: ads),
        Provider.value(value: ai),
      ],
      child: EnhancifyApp(startOnboarded: state.onboarded),
    ),
  );

  unawaited(purchases.init());
  if (state.consentAsked) unawaited(ads.init());
}

class EnhancifyApp extends StatelessWidget {
  const EnhancifyApp({super.key, required this.startOnboarded});
  final bool startOnboarded;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: startOnboarded ? const HomeScreen() : const WelcomeScreen(),
    );
  }
}
