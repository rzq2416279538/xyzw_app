import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 实色顶栏。
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.largeTitle = false,
    this.centerTitle = true,
  });

  final Widget title;
  final Widget? leading;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final bool largeTitle;
  final bool centerTitle;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ClipRect(
      child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            border: Border(
              bottom: BorderSide(
                color: AppTheme.separator.withValues(alpha: 0.45),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: top),
              SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    ?leading,
                    Expanded(
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                        child: Align(
                          alignment: centerTitle
                              ? Alignment.center
                              : Alignment.centerLeft,
                          child: title,
                        ),
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
              ?bottom,
            ],
          ),
        ),
    );
  }
}

/// 圆角卡片。列表里不用实时模糊，避免滑动掉帧。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: const Border.fromBorderSide(
            BorderSide(color: Color(0xFFE5E5EA)),
          ),
        ),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(14),
          child: child,
        ),
      ),
    );
  }
}

/// iOS 风格圆形操作按钮。
class IosIconButton extends StatelessWidget {
  const IosIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = AppTheme.blue,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      minimumSize: const Size(32, 36),
      onPressed: onPressed,
      child: Icon(icon, size: 22, color: color),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

/// 纯色页面底。
class SoftBackdrop extends StatelessWidget {
  const SoftBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.bg,
      child: child,
    );
  }
}
