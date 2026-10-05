import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:flutter/material.dart';

/// 金额文本。
///
/// **唯一**允许把「分」渲染成展示字符串的地方（走 [formatCents]）。
/// 收入/支出/退款/转账各有自己的语义色，颜色随亮/暗模式自动切换，
/// 业务代码不硬编码颜色。
class AmountText extends StatelessWidget {
  const AmountText({
    required this.cents,
    super.key,
    this.type,
    this.fontSize = 15,
    this.fontWeight = FontWeight.w600,
    this.withSymbol = true,
    this.showSign = false,
  });

  /// 金额（分）。
  final int cents;

  /// 交易类型，决定颜色。
  final TransactionType? type;

  final double fontSize;
  final FontWeight fontWeight;
  final bool withSymbol;
  final bool showSign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Text(
      formatCents(cents, withSymbol: withSymbol, showSign: showSign),
      style: TextStyle(
        color: _colorFor(type, isDark, theme.colorScheme.onSurfaceVariant,
            theme.colorScheme.onSurface),
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        letterSpacing: -0.2,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 语义色映射。
  ///
  /// 收入：低饱和绿；支出：低饱和暖赭；退款：低饱和蓝灰；转账：次级文本色。
  static Color _colorFor(
    TransactionType? type,
    bool isDark,
    Color secondary,
    Color primary,
  ) {
    switch (type) {
      case TransactionType.income:
        return isDark ? const Color(0xFF8FBFA0) : const Color(0xFF5B8C6E);
      case TransactionType.expense:
        return isDark ? const Color(0xFFD99B7E) : const Color(0xFFC67B5C);
      case TransactionType.refund:
        return isDark ? const Color(0xFF9DB0C4) : const Color(0xFF7B8FA3);
      case TransactionType.transfer:
        return secondary;
      case null:
        return primary;
    }
  }
}
