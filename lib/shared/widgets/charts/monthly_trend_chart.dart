import 'dart:math' as math;

import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/domain/entities/statistics.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// 月度收支趋势图（近 12 个月）。
///
/// 用 `fl_chart` 的柱状图：每个月一组，两根柱子分别是收入与支出。
///
/// ⚠️ 说明：图表内部用 `double`（像素坐标），这是**展示层**的浮点，
/// 不参与任何金额计算 —— 金额始终来自 `MonthlyTotal` 的整数分字段。
class MonthlyTrendChart extends StatelessWidget {
  const MonthlyTrendChart({required this.data, super.key});

  final List<MonthlyTotal> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (data.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text('暂无数据', style: theme.textTheme.bodySmall),
        ),
      );
    }

    final incomeColor = isDark ? AppColors.darkIncome : AppColors.lightIncome;
    final expenseColor = isDark ? AppColors.darkExpense : AppColors.lightExpense;

    // 取最大值用于 Y 轴上限（分 → 元的 double，仅用于画图）
    var maxCents = 0;
    for (final item in data) {
      maxCents = math.max(maxCents, math.max(item.incomeCents, item.netExpenseCents));
    }
    final maxY = maxCents == 0 ? 100.0 : maxCents / 100 * 1.18;
    final interval = maxY / 3;

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          barGroups: <BarChartGroupData>[
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 3,
                barRods: <BarChartRodData>[
                  BarChartRodData(
                    toY: data[i].incomeCents / 100,
                    color: incomeColor,
                    width: 5,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                  BarChartRodData(
                    toY: data[i].netExpenseCents / 100,
                    color: expenseColor,
                    width: 5,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ],
              ),
          ],
          // 关闭触摸提示，避免与整体克制的视觉风格冲突
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) {
                    return const SizedBox.shrink();
                  }
                  // 12 个月全标会拥挤，隔一个标一个
                  if (index.isOdd) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      data[index].shortLabel,
                      style: theme.textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (double value) => FlLine(
              color: theme.colorScheme.outlineVariant,
              strokeWidth: 1,
              dashArray: const <int>[4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  /// 图例（收入 / 支出）。
  static Widget legend(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      children: <Widget>[
        _LegendDot(
          color: isDark ? AppColors.darkIncome : AppColors.lightIncome,
          label: '收入',
        ),
        const SizedBox(width: 16),
        _LegendDot(
          color: isDark ? AppColors.darkExpense : AppColors.lightExpense,
          label: '净支出',
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// 月度趋势卡片（首页/统计页共用）。
class MonthlyTrendCard extends StatelessWidget {
  const MonthlyTrendCard({required this.data, super.key});

  final List<MonthlyTotal> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 找出支出最高的月份，给一句洞察
    MonthlyTotal? peak;
    for (final item in data) {
      if (item.netExpenseCents == 0) {
        continue;
      }
      if (peak == null || item.netExpenseCents > peak.netExpenseCents) {
        peak = item;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('近 12 个月趋势', style: theme.textTheme.titleMedium),
            ),
            MonthlyTrendChart.legend(context),
          ],
        ),
        const SizedBox(height: AppDimens.gapXs),
        Text(
          peak == null
              ? '暂无足够数据'
              : '支出最高：${peak.fullLabel}（${formatCents(peak.netExpenseCents, withSymbol: true)}）',
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: AppDimens.gapL),
        MonthlyTrendChart(data: data),
      ],
    );
  }
}
