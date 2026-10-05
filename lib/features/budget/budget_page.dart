import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';

/// 预算页。
///
/// **状态：暂未实现（Phase 15）**。
///
/// 数据层已经就绪（`budgets` 表 + `ux_budgets_category_period` 唯一索引），
/// 但 UI 尚未实现。按 brief 第 33 条的要求，这里**明确声明未实现**，
/// 而不是放假进度条或假数字。
class BudgetPage extends StatelessWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预算')),
      body: const NotImplementedView(
        phase: 'Phase 15',
        description: '预算功能尚未实现。\n\n'
            '计划：按分类设置月度预算 → 进度条展示已用/剩余 → '
            '接近或超出时用低饱和琥珀色温和提示（不使用刺眼的红色警报）。\n\n'
            '数据库表 budgets 与唯一索引已建好，等待 UI 与业务逻辑接入。',
      ),
    );
  }
}
