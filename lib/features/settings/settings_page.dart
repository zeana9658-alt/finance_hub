import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/rule_providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/features/settings/backup_page.dart';
import 'package:finance_hub/features/settings/category_rules_page.dart';
import 'package:finance_hub/features/settings/merchant_rules_page.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置页 —— 隐私承诺 + 数据 + 分类规则 + 外观 + 功能进度。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final count = ref.watch(transactionCountProvider);
    final earliest = ref.watch(earliestTransactionProvider);
    final ruleCount = ref.watch(categoryRulesProvider).value?.length;
    final merchantCount = ref.watch(merchantRulesProvider).value?.length;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          0,
          AppDimens.pagePadding,
          AppDimens.gapXl,
        ),
        children: <Widget>[
          // ─────────────── 隐私承诺（固定置顶） ───────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppDimens.gapS),
                    Text('你的账单只属于你', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: AppDimens.gapM),
                const _Bullet('不需要注册账号'),
                const _Bullet('飞行模式也能完整使用'),
                const _Bullet('账单不会上传到任何服务器'),
                const _Bullet('AI 分析（可选、默认关闭）只发送汇总数字，不含商户与订单信息'),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapL),

          // ─────────────── 数据 ───────────────
          SectionHeader('数据'),
          AppCard(
            child: count.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (Object error, StackTrace stack) =>
                  Text('读取失败：$error', style: theme.textTheme.bodySmall),
              data: (int total) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _InfoRow(label: '交易记录', value: '$total 条'),
                  const SizedBox(height: AppDimens.gapS),
                  _InfoRow(
                    label: '最早一笔',
                    value: earliest.value == null
                        ? '—'
                        : '${earliest.value!.year}-'
                            '${earliest.value!.month.toString().padLeft(2, '0')}-'
                            '${earliest.value!.day.toString().padLeft(2, '0')}',
                  ),
                  const SizedBox(height: AppDimens.gapM),
                  Text(
                    total == 0
                        ? '还没有数据。导入账单后这里会显示统计。'
                        : '数据保存在本机应用目录的 SQLite 数据库中，卸载应用即删除。',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: AppDimens.gapM),
                  OutlinedButton.icon(
                    onPressed: () => _push(context, const BackupPage()),
                    icon: const Icon(Icons.backup_outlined, size: 18),
                    label: const Text('备份与恢复'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppDimens.gapL),

          // ─────────────── 分类与规则 ───────────────
          SectionHeader('分类与规则'),
          AppListCard(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.gapS),
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.rule_folder_outlined, size: 20),
                title: const Text('分类规则'),
                subtitle: Text(
                  ruleCount == null
                      ? '加载中…'
                      : '共 $ruleCount 条 · 可修改并重跑历史账单',
                  style: theme.textTheme.labelSmall,
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _push(context, const CategoryRulesPage()),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.storefront_outlined, size: 20),
                title: const Text('商户记忆'),
                subtitle: Text(
                  merchantCount == null
                      ? '加载中…'
                      : merchantCount == 0
                          ? '还没有记忆 · 在导入预览里改一次分类就会记住'
                          : '共 $merchantCount 个商户',
                  style: theme.textTheme.labelSmall,
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _push(context, const MerchantRulesPage()),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapL),

          // ─────────────── 外观 ───────────────
          SectionHeader('外观'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('主题', style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppDimens.gapM),
                SegmentedButton<ThemeMode>(
                  segments: const <ButtonSegment<ThemeMode>>[
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text('浅色'),
                      icon: Icon(Icons.light_mode_outlined, size: 16),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      label: Text('跟随系统'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text('深色'),
                      icon: Icon(Icons.dark_mode_outlined, size: 16),
                    ),
                  ],
                  selected: <ThemeMode>{themeMode},
                  onSelectionChanged: (selection) => ref
                      .read(themeModeProvider.notifier)
                      .select(selection.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapL),

          // ─────────────── 功能进度（诚实标注） ───────────────
          SectionHeader('功能进度'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const <Widget>[
                _StatusRow(label: '微信 / 支付宝账单导入（CSV / XLSX / 粘贴）', done: true),
                _StatusRow(label: '导入预览、逐条勾选与来源识别', done: true),
                _StatusRow(label: '指纹去重（跨平台不误判）', done: true),
                _StatusRow(label: '三级分类引擎（商户记忆 → 平台分类 → 关键词）', done: true),
                _StatusRow(label: '导入预览里手动改分类 + 自动记住商户', done: true),
                _StatusRow(label: '分类规则可视化管理', done: true),
                _StatusRow(label: '一键重跑历史账单（不覆盖手动分类）', done: true),
                _StatusRow(label: '商户记忆管理', done: true),
                _StatusRow(label: '首页 Dashboard 与月度趋势图', done: true),
                _StatusRow(label: '分类占比与三级下钻（分类 → 二级 → 商户）', done: true),
                _StatusRow(label: '消费日历与消费时段分布', done: true),
                _StatusRow(label: '商户分析（累计 / 次数 / 均值 / 趋势）', done: true),
                _StatusRow(label: '账单搜索与多条件筛选', done: true),
                _StatusRow(label: '预算设置与进度追踪', done: true),
                _StatusRow(label: '备份导出（JSON / CSV）与恢复', done: true),
                _StatusRow(label: '快速记账表单', done: false),
                _StatusRow(label: 'AI 消费分析 / 自然语言查询', done: false),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapL),

          // ─────────────── 关于 ───────────────
          SectionHeader('关于'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _InfoRow(label: '应用', value: '聚账 · FinanceHub'),
                const SizedBox(height: AppDimens.gapS),
                const _InfoRow(label: '版本', value: '0.1.0'),
                const SizedBox(height: AppDimens.gapS),
                const _InfoRow(label: '数据库版本', value: 'v2'),
                const SizedBox(height: AppDimens.gapM),
                Text(
                  '本地优先 · 金额以「分」为单位存储 · 默认不联网',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppDimens.gapS),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              done ? Icons.check_circle_outline : Icons.radio_button_unchecked,
              size: 16,
              color: done
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppDimens.gapS),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: done
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (!done)
            Text(
              '暂未实现',
              style: theme.textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}
