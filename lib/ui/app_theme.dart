import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// iOS 风格：系统分组灰底 + SF Blue，顶栏和卡片都是实色。
abstract final class AppTheme {
  static const bg = Color(0xFFF2F2F7);
  static const card = Color(0xFFFFFFFF);
  static const text = Color(0xFF000000);
  static const textSecondary = Color(0xFF8E8E93);
  static const separator = Color(0xFFC6C6C8);
  static const blue = Color(0xFF007AFF);
  static const green = Color(0xFF34C759);
  static const orange = Color(0xFFFF9500);
  static const teal = Color(0xFF5AC8FA);
  static const danger = Color(0xFFFF3B30);
  static const fill = Color(0xFF787880);
  static const glass = Color(0xFFF2F2F7);
  static const glassBorder = Color(0x33FFFFFF);

  // 兼容旧引用
  static const accent = green;
  static const search = blue;
  static const sort = orange;
  static const grid = teal;
  static const badgeBg = Color(0x14787880);
  static const divider = separator;

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: const Color(0x14787880),
      colorScheme: const ColorScheme.light(
        primary: blue,
        onPrimary: Colors.white,
        secondary: green,
        onSecondary: Colors.white,
        surface: card,
        onSurface: text,
        error: danger,
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: blue,
        barBackgroundColor: glass,
        scaffoldBackgroundColor: bg,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: bg,
        foregroundColor: text,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xE61C1C1E),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFF2F2F7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          height: 1.1,
          color: text,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: text,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: text,
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          height: 1.35,
          letterSpacing: -0.2,
          color: text,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          height: 1.3,
          letterSpacing: -0.1,
          color: textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: blue,
        ),
      ),
    );
  }
}
