import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'l10n/l10n.dart';
import 'screens/onboarding/splash_screen.dart';
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
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  late final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Could not open the app.\n$e', textAlign: TextAlign.center)),
      ),
    ));
    return;
  }
  final state = AppState(prefs);
  final purchases = PurchaseService(state, prefs);
  final ads = AdsService(state);
  final ai = AiService();
  ai.attachKey(() =>
      state.openAiKey.isNotEmpty ? state.openAiKey : AppConfig.openAiApiKey);

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
  unawaited(ads.init());
}

class EnhancifyApp extends StatefulWidget {
  const EnhancifyApp({super.key, required this.startOnboarded});
  final bool startOnboarded;

  @override
  State<EnhancifyApp> createState() => _EnhancifyAppState();
}

class _EnhancifyAppState extends State<EnhancifyApp> {
  late final ExitAdObserver _exitAds;

  @override
  void initState() {
    super.initState();
    _exitAds = ExitAdObserver(context.read<AdsService>());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rtl = Tr.isRtl(state.languageCode);
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: state.themeMode,
      locale: Locale(state.languageCode),
      supportedLocales: [for (final code in Tr.codes) Locale(code)],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        _MaterialFallback(),
        _WidgetsFallback(),
        _CupertinoFallback(),
      ],
      navigatorObservers: [_exitAds],
      builder: (context, child) {
        final palette = context.palette;
        final light = state.themeMode != ThemeMode.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: light ? const Color(0xFFFFC8E0) : palette.background,
            systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: light ? AppColors.screenGradient : AppColors.screenGradientDark,
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      home: SplashScreen(onboarded: widget.startOnboarded),
    );
  }
}

class _MaterialFallback extends LocalizationsDelegate<MaterialLocalizations> {
  const _MaterialFallback();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    final usable = GlobalMaterialLocalizations.delegate.isSupported(locale) ? locale : const Locale('en');
    return GlobalMaterialLocalizations.delegate.load(usable);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<MaterialLocalizations> old) => false;
}

class _WidgetsFallback extends LocalizationsDelegate<WidgetsLocalizations> {
  const _WidgetsFallback();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    final usable = GlobalWidgetsLocalizations.delegate.isSupported(locale) ? locale : const Locale('en');
    return GlobalWidgetsLocalizations.delegate.load(usable);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<WidgetsLocalizations> old) => false;
}

class _CupertinoFallback extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoFallback();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    final usable = GlobalCupertinoLocalizations.delegate.isSupported(locale) ? locale : const Locale('en');
    return GlobalCupertinoLocalizations.delegate.load(usable);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<CupertinoLocalizations> old) => false;
}
