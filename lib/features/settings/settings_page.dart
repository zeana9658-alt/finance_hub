import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置页 —— 隐私承诺 + 数据规模 + 外观。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final count = ref.watch(transactionCountProvider);

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

          // ─────────────── 数据规模 ───────────────
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
                  Text(
                    total == 0
                        ? '还没有数据。导入账单后这里会显示统计。'
                        : '数据保存在本机应用目录的 SQLite 数据库中，卸载应用即删除。',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
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

          // ─────────────── 开发状态（诚实标注） ───────────────
          SectionHeader('功能进度'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _StatusRow(label: '微信 / 支付宝账单导入', done: true),
                _StatusRow(label: '导入预览与逐条勾选', done: true),
                _StatusRow(label: '指纹去重（不跨平台误判）', done: true),
                _StatusRow(label: '三级分类引擎', done: true),
                _StatusRow(label: '首页 Dashboard / 消费日历 / 时段分布', done: true),
                _StatusRow(label: '账单搜索与筛选', done: true),
                _StatusRow(label: '分类下钻页面', done: false),
                _StatusRow(label: '预算系统', done: false),
                _StatusRow(label: '数据备份导出 / 恢复', done: false),
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
                _InfoRow(label: '应用', value: '聚账 · FinanceHub'),
                const SizedBox(height: AppDimens.gapS),
                _InfoRow(label: '版本', value: '0.1.0'),
                const SizedBox(height: AppDimens.gapS),
                _InfoRow(label: '数据库版本', value: 'v2'),
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
        children: <Widget>[
          Icon(
            done ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 16,
            color: done
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
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
