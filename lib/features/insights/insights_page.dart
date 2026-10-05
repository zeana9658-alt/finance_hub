import 'package:finance_hub/app/insight_providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/domain/entities/financial_summary.dart';
import 'package:finance_hub/domain/entities/query_intent.dart';
import 'package:finance_hub/domain/services/insight_generator.dart';
import 'package:finance_hub/domain/services/intent_parser.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 消费分析页 —— brief 第 21 / 22 条。
///
/// 分两块：
/// 1. **本地消费洞察**：规则驱动的分析，完全离线，不需要 API Key
/// 2. **自然语言查询**：本地解析问题 → 本地白名单 SQL → 本地数据库出数
///
/// 两块都遵守同一条红线：**问题与数据都不出设备**。
/// 「数据去向预览」按钮会把唯一允许外发的 `FinancialSummary` 原文摊开给用户看。
class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  final TextEditingController _questionController = TextEditingController();
  QueryOutcome? _outcome;
  String? _askedQuestion;
  bool _asking = false;

  static const List<String> _examples = <String>[
    '我今年在餐饮上花了多少钱',
    '上个月最大的支出是什么',
    '今年哪个月花钱最多',
    '这个月比上个月多花了多少',
    '今年收入多少',
  ];

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insights = ref.watch(insightsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('消费分析'),
        actions: <Widget>[
          IconButton(
            tooltip: '数据去向预览',
            onPressed: _showPayloadPreview,
            icon: const Icon(Icons.privacy_tip_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapS,
          AppDimens.pagePadding,
          AppDimens.gapXl,
        ),
        children: <Widget>[
          // ─────────────── 本地洞察 ───────────────
          SectionHeader('消费洞察'),
          insights.when(
            loading: () => const AppCard(
              child: SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (Object error, StackTrace stack) =>
                AppCard(child: Text('读取失败：$error')),
            data: (List<Insight> items) => Column(
              children: <Widget>[
                for (final insight in items) ...<Widget>[
                  _InsightCard(insight: insight),
                  const SizedBox(height: AppDimens.gapM),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapS),

          // ─────────────── 自然语言查询 ───────────────
          SectionHeader('问一句话'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _questionController,
                  decoration: InputDecoration(
                    hintText: '例如：我今年在咖啡上花了多少钱',
                    prefixIcon: const Icon(Icons.help_outline, size: 20),
                    suffixIcon: IconButton(
                      tooltip: '提问',
                      onPressed: _asking ? null : _askCurrent,
                      icon: _asking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined, size: 18),
                    ),
                  ),
                  onSubmitted: (_) => _askCurrent(),
                ),
                const SizedBox(height: AppDimens.gapM),
                Wrap(
                  spacing: AppDimens.gapS,
                  runSpacing: AppDimens.gapS,
                  children: <Widget>[
                    for (final example in _examples)
                      ActionChip(
                        label: Text(example),
                        onPressed: _asking ? null : () => _ask(example),
                      ),
                  ],
                ),
                if (_outcome != null) ...<Widget>[
                  const SizedBox(height: AppDimens.gapL),
                  const Divider(height: 1),
                  const SizedBox(height: AppDimens.gapL),
                  _AnswerCard(
                    question: _askedQuestion ?? '',
                    outcome: _outcome!,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapL),

          // ─────────────── 隐私说明 ───────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text('这些分析在哪里跑的', style: theme.textTheme.bodyMedium),
                  ],
                ),
                const SizedBox(height: AppDimens.gapS),
                Text(
                  '· 上面的洞察与问答**全部在本机完成**，飞行模式下照样能用\n'
                  '· 问题不会离开设备；数据查询由本地 SQLite 执行\n'
                  '· 唯一可能外发的是「数据去向预览」里那份**聚合数字**，'
                  '而且需要你在设置里显式开启 AI 增强\n'
                  '· 那份摘要里没有商户名、没有订单号、没有逐笔记录',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: AppDimens.gapM),
                Row(
                  children: <Widget>[
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'AI 增强（把摘要交给大模型润色成一段话）暂未接入 —— '
                        '需要在设置里填 API Key，本机环境无法验证真实调用，'
                        '因此不伪装成已实现。',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 问答 ─────────────────────────

  void _askCurrent() => _ask(_questionController.text);

  Future<void> _ask(String question) async {
    final text = question.trim();
    if (text.isEmpty) {
      return;
    }
    _questionController.text = text;
    setState(() {
      _asking = true;
      _askedQuestion = text;
      _outcome = null;
    });

    final engine = ref.read(insightQueryEngineProvider);
    final intent = IntentParser.parse(text);
    final outcome = await engine.execute(intent);

    if (!mounted) {
      return;
    }
    setState(() {
      _asking = false;
      _outcome = outcome;
    });
  }

  // ───────────────────────── 数据去向预览 ─────────────────────────

  Future<void> _showPayloadPreview() async {
    final summary = await ref.read(financialSummaryProvider.future);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _PayloadPreviewDialog(summary: summary),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color accent;
    final IconData icon;
    switch (insight.severity) {
      case InsightSeverity.positive:
        accent = isDark ? AppColors.darkIncome : AppColors.lightIncome;
        icon = Icons.trending_down;
      case InsightSeverity.attention:
        accent = isDark ? AppColors.darkWarning : AppColors.lightWarning;
        icon = Icons.priority_high_outlined;
      case InsightSeverity.info:
        accent = theme.colorScheme.primary;
        icon = Icons.insights_outlined;
    }

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: AppDimens.gapM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(insight.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppDimens.gapXs),
                Text(insight.body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.question, required this.outcome});

  final String question;
  final QueryOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!outcome.intent.isUnderstood) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(question, style: theme.textTheme.labelSmall),
          const SizedBox(height: AppDimens.gapS),
          Text(outcome.answer, style: theme.textTheme.bodySmall),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(question, style: theme.textTheme.labelSmall),
        const SizedBox(height: AppDimens.gapS),
        Text(
          outcome.answer,
          style: theme.textTheme.titleMedium?.copyWith(
            color: isDark ? AppColors.darkAccent : AppColors.lightAccent,
            height: 1.5,
          ),
        ),
        if (outcome.amountCents != 0) ...<Widget>[
          const SizedBox(height: AppDimens.gapS),
          Text(
            '金额：${formatCents(outcome.amountCents, withSymbol: true)}',
            style: theme.textTheme.labelSmall,
          ),
        ],
        const SizedBox(height: AppDimens.gapS),
        Text(
          '（由本地数据库查询得出，未联网）',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

/// 「数据去向预览」—— 把唯一允许外发的 payload 原文摊开。
class _PayloadPreviewDialog extends StatefulWidget {
  const _PayloadPreviewDialog({required this.summary});

  final FinancialSummary summary;

  @override
  State<_PayloadPreviewDialog> createState() => _PayloadPreviewDialogState();
}

class _PayloadPreviewDialogState extends State<_PayloadPreviewDialog> {
  bool _categories = true;
  bool _daily = false;
  bool _buckets = true;
  bool _budgets = true;
  bool _trend = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.summary
        .toJson(
          includeCategories: _categories,
          includeDaily: _daily,
          includeTimeBuckets: _buckets,
          includeBudgets: _budgets,
          includeTrend: _trend,
        )
        .entries
        .map((entry) => '  "${entry.key}": ${_inline(entry.value)}')
        .join(',\n');

    return AlertDialog(
      title: const Text('数据去向预览'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '如果开启 AI 增强，发给模型的**只有下面这些内容**。'
                '你可以逐项取消勾选。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppDimens.gapM),
              Wrap(
                spacing: AppDimens.gapS,
                runSpacing: AppDimens.gapS,
                children: <Widget>[
                  FilterChip(
                    label: const Text('分类占比'),
                    selected: _categories,
                    onSelected: (value) =>
                        setState(() => _categories = value),
                  ),
                  FilterChip(
                    label: const Text('每日明细'),
                    selected: _daily,
                    onSelected: (value) => setState(() => _daily = value),
                  ),
                  FilterChip(
                    label: const Text('时段分布'),
                    selected: _buckets,
                    onSelected: (value) => setState(() => _buckets = value),
                  ),
                  FilterChip(
                    label: const Text('预算状态'),
                    selected: _budgets,
                    onSelected: (value) => setState(() => _budgets = value),
                  ),
                  FilterChip(
                    label: const Text('环比趋势'),
                    selected: _trend,
                    onSelected: (value) => setState(() => _trend = value),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.gapM),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDimens.gapM),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
                ),
                child: SelectableText(
                  '{\n$text\n}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.gapM),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '没有商户名、没有订单号、没有卡号、没有逐笔记录。',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }

  static String _inline(Object? value) {
    if (value is List) {
      return '[${value.length} 项]';
    }
    if (value is Map) {
      return '{${value.keys.join(', ')}}';
    }
    return '$value';
  }
}
