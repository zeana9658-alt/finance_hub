import 'package:flutter/material.dart';

/// 语义化颜色 token。
///
/// 设计语言：Minimal · Premium · Calm · Japanese Minimalism · Soft UI
/// 见 docs/ARCHITECTURE.md §7.2。
///
/// 核心约束：
/// - **只用一种强调色**（低饱和墨绿），不搞五颜六色
/// - 收入用低饱和绿、支出用低饱和暖赭
/// - 预算预警用琥珀而非刺眼的红
/// - 浅色模式背景是极浅暖灰（`#FAFAF8`）而不是纯白，降低视觉刺激
class AppColors {
  AppColors._();

  // ─────────────── 浅色模式 ───────────────
  static const Color lightBackground = Color(0xFFFAFAF8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF4F4F1);
  static const Color lightAccent = Color(0xFF3D6B5C);
  static const Color lightIncome = Color(0xFF5B8C6E);
  static const Color lightExpense = Color(0xFFC67B5C);
  static const Color lightWarning = Color(0xFFC9A227);
  static const Color lightTextPrimary = Color(0xFF1F2421);
  static const Color lightTextSecondary = Color(0xFF6B7370);
  static const Color lightDivider = Color(0xFFE8E8E4);

  // ─────────────── 深色模式 ───────────────
  static const Color darkBackground = Color(0xFF14161A);
  static const Color darkSurface = Color(0xFF1C1F24);
  static const Color darkSurfaceVariant = Color(0xFF23272D);
  static const Color darkAccent = Color(0xFF7FB69F);
  static const Color darkIncome = Color(0xFF8FBFA0);
  static const Color darkExpense = Color(0xFFD99B7E);
  static const Color darkWarning = Color(0xFFD9BC63);
  static const Color darkTextPrimary = Color(0xFFE8EAE8);
  static const Color darkTextSecondary = Color(0xFF9AA3A0);
  static const Color darkDivider = Color(0xFF2C3037);

  /// 图表辅助色（低饱和，5–8 色）。
  static const List<Color> chartPalette = <Color>[
    Color(0xFF3D6B5C),
    Color(0xFF8FA9A0),
    Color(0xFFC67B5C),
    Color(0xFFD9B48F),
    Color(0xFF7B8FA3),
    Color(0xFFA39BB0),
    Color(0xFF9CAF88),
    Color(0xFFC9A227),
  ];

  /// 深色模式下的图表色（提亮）。
  static const List<Color> chartPaletteDark = <Color>[
    Color(0xFF7FB69F),
    Color(0xFFA8C4BB),
    Color(0xFFD99B7E),
    Color(0xFFE6C9A8),
    Color(0xFF9DB0C4),
    Color(0xFFBFB8CC),
    Color(0xFFB7C9A3),
    Color(0xFFD9BC63),
  ];

  /// 按索引取图表色（自动取模）。
  static Color chartColor(int index, {required bool isDark}) {
    final palette = isDark ? chartPaletteDark : chartPalette;
    return palette[index % palette.length];
  }

  /// 按分类色字符串（如 `#3D6B5C`）解析，失败返回兜底色。
  static Color parseHex(String? hex, {required Color fallback}) {
    if (hex == null) {
      return fallback;
    }
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) {
      return fallback;
    }
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) {
      return fallback;
    }
    return Color(0xFF000000 | value);
  }
}

/// 圆角与间距 token。
class AppDimens {
  AppDimens._();

  static const double radiusCard = 16;
  static const double radiusSmall = 12;
  static const double radiusButton = 14;
  static const double radiusSheet = 20;

  static const double gapXs = 4;
  static const double gapS = 8;
  static const double gapM = 12;
  static const double gapL = 16;
  static const double gapXl = 24;

  static const double pagePadding = 16;

  /// 桌面端最大内容宽度（超出后居中，避免宽屏拉伸）。
  static const double maxContentWidth = 720;
}

/// 唯一的阴影 —— 极轻微的一级层次，不堆叠阴影。
List<BoxShadow> softShadow({required bool isDark}) => <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.04),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
    ];
