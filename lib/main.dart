import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_log.dart';
import 'data/account_store.dart';
import 'data/script_store.dart';
import 'ui/app_theme.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    AppLog.e('flutter', '${details.exceptionAsString()}\n${details.stack}');
    FlutterError.presentError(details);
  };

  await AppLog.ensureBootHeader(appVersion: '1.0.0+1');

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  final store = AccountStore();
  final scripts = ScriptStore();
  runApp(YukeApp(store: store, scripts: scripts));
}

class YukeApp extends StatelessWidget {
  const YukeApp({super.key, required this.store, required this.scripts});

  final AccountStore store;
  final ScriptStore scripts;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '咸强之王',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) {
        return ScrollConfiguration(
          behavior: const _IosScrollBehavior(),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomePage(store: store, scripts: scripts),
    );
  }
}

class _IosScrollBehavior extends ScrollBehavior {
  const _IosScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
