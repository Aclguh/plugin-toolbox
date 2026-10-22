import 'package:flutter/material.dart';

/// 全局间距令牌：以 4dp 为基准的 8 阶栅格。
///
/// 所有页面与组件统一从这里取值，避免各处出现 6 / 7 / 10 / 14 等随手数值，
/// 造成同类页面视觉节奏不一致；调整密度时只需改动此处一处。
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// 页面主体统一横向留白
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: lg);

  /// 普通卡片内边距
  static const EdgeInsets card = EdgeInsets.all(lg);

  /// 紧凑卡片内边距（网格卡片、列表项）
  static const EdgeInsets cardCompact = EdgeInsets.symmetric(
    horizontal: md,
    vertical: md,
  );
}

/// 圆角令牌：同心圆角体系，外大内小，保证嵌套时不出现视觉断层。
class AppRadius {
  AppRadius._();

  /// 徽标 / 小标签
  static const double xs = 6;

  /// 输入框内嵌元素、图标底衬
  static const double sm = 8;

  /// 次级容器
  static const double md = 10;

  /// 按钮 / 输入框
  static const double lg = 12;

  /// 卡片（与既有主题契约一致，勿随意调整）
  static const double xl = 16;

  /// 弹窗
  static const double xxl = 20;

  /// 底部抽屉
  static const double sheet = 24;

  /// 胶囊
  static const double pill = 999;

  static BorderRadius circular(double value) => BorderRadius.circular(value);
}

/// 动效令牌：统一时长与缓动曲线。
///
/// 交互反馈（快速）与页面转场（慢速）分档，杜绝同一应用内
/// 出现 100ms / 350ms / 500ms 混用导致的"手感漂移"。
class AppMotion {
  AppMotion._();

  /// 按压缩放的即时反馈
  static const Duration instant = Duration(milliseconds: 90);

  /// 悬停 / 聚焦 / 颜色过渡
  static const Duration fast = Duration(milliseconds: 140);

  /// 展开 / 折叠 / 状态切换
  static const Duration normal = Duration(milliseconds: 220);

  /// 页面转场
  static const Duration slow = Duration(milliseconds: 320);

  /// Material 3 强调型减速曲线，用于入场
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// 出场 / 反向动画
  static const Curve exit = Cubic(0.3, 0.0, 0.8, 0.15);

  /// 通用减速曲线
  static const Curve decelerate = Curves.easeOutCubic;
}

/// 层级令牌：本项目为扁平化品牌风格，阴影仅在悬浮 / 拖拽时出现。
class AppElevation {
  AppElevation._();

  static const double flat = 0;
  static const double hover = 2;
  static const double floating = 4;
  static const double drag = 8;
}

/// 尺寸与响应式断点令牌。
class AppLayout {
  AppLayout._();

  /// 移动端最小可点击区域（无障碍要求 44~48dp）
  static const double minTouchTarget = 48;

  /// 顶部导航栏高度
  static const double appBarHeight = 60;

  /// 平板 / 折叠屏上的正文最大宽度，避免超宽行导致阅读困难
  static const double maxContentWidth = 720;

  /// 网格列数断点
  static const double compactBreakpoint = 600;
  static const double mediumBreakpoint = 900;

  /// 列表底部为悬浮按钮预留的滚动空档
  static const double listBottomInset = 96;

  /// 依据可用宽度决定网格列数：手机竖屏 3 列、横屏/小平板 4 列、
  /// 平板 5 列、桌面 6 列，横竖屏切换时自适应。
  static int gridColumnsFor(double width, {bool portrait = true}) {
    if (width >= 1120) return 6;
    if (width >= mediumBreakpoint) return 5;
    if (width >= compactBreakpoint) return portrait ? 3 : 4;
    return portrait ? 3 : 4;
  }
}
