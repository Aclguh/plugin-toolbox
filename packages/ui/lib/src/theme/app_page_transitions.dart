import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// 全局页面转场：淡入 + 轻微上移 + 微缩放。
///
/// 相比平台默认的整屏横向滑动，这种"轻推"转场在深色品牌主题下更克制，
/// 也能同时覆盖 Android / iOS / 桌面，避免三端观感不一致。
class AppPageTransitions {
  AppPageTransitions._();

  static Widget fadeThrough(
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entering = CurvedAnimation(
      parent: animation,
      curve: AppMotion.decelerate,
      reverseCurve: AppMotion.exit,
    );
    // 淡入在前 60% 完成，避免长转场中文字长时间发虚
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.02),
      end: Offset.zero,
    ).animate(entering);
    final scale = Tween<double>(begin: 0.992, end: 1).animate(entering);

    // 被覆盖页轻微退后，形成层次感而非生硬替换
    final leaving = Tween<double>(begin: 1, end: 0.985).animate(
      CurvedAnimation(parent: secondaryAnimation, curve: AppMotion.emphasized),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(
          scale: scale,
          child: ScaleTransition(scale: leaving, child: child),
        ),
      ),
    );
  }

  /// 供 GoRouter 的 `CustomTransitionPage` 复用
  static Widget builder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      fadeThrough(animation, secondaryAnimation, child);
}

/// 将统一转场注入 [PageTransitionsTheme]
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      AppPageTransitions.fadeThrough(animation, secondaryAnimation, child);
}

const PageTransitionsTheme appPageTransitionsTheme = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: AppPageTransitionsBuilder(),
    TargetPlatform.iOS: AppPageTransitionsBuilder(),
    TargetPlatform.macOS: AppPageTransitionsBuilder(),
    TargetPlatform.windows: AppPageTransitionsBuilder(),
    TargetPlatform.linux: AppPageTransitionsBuilder(),
    TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
  },
);
