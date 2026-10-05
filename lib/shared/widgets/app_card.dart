import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 统一卡片容器。
///
/// 设计约束（docs/ARCHITECTURE.md §7.3）：
/// - 圆角 16
/// - **仅一级极轻阴影**，不堆叠
/// - 优先用 1px 边框表达层次
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppDimens.gapL),
    this.onTap,
    this.useBorder = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool useBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: useBorder
            ? Border.all(color: theme.colorScheme.outlineVariant)
            : null,
        boxShadow: softShadow(isDark: isDark),
      ),
      child: child,
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: content,
      ),
    );
  }
}

/// 区块标题。
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppDimens.gapXs,
        right: AppDimens.gapXs,
        bottom: AppDimens.gapM,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 空状态。
///
/// 所有页面在 0 条数据时都必须走这里，不允许出现 NaN / Infinity / 崩溃。
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    super.key,
    this.description,
    this.action,
  });

  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppDimens.gapM),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (description != null) ...<Widget>[
              const SizedBox(height: AppDimens.gapS),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: AppDimens.gapL),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 「暂未实现」占位。
///
/// brief 第 33 条明确禁止把未完成的功能伪装成已实现。
/// 因此未完成的阶段统一用这个组件**显式声明**，而不是放假图表或假数据。
class NotImplementedView extends StatelessWidget {
  const NotImplementedView({
    required this.phase,
    required this.description,
    super.key,
  });

  /// 对应 docs/ARCHITECTURE.md §10 的阶段号。
  final String phase;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '暂未实现 · $phase',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.gapM),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// 用来装 [ListTile] 的卡片。
///
/// **为什么不能直接用 [AppCard]**：[AppCard] 用 `Container + BoxDecoration`
/// 画背景，而 `ListTile` 把背景与水波纹画在**最近的 Material 祖先**上，
/// 中间夹一个带背景色的 `DecoratedBox` 会让水波纹被盖住 ——
/// Flutter 会直接抛断言：
/// `ListTile background color or ink splashes may be invisible`。
///
/// 这里改用 `Material` 承载背景与形状，既满足 ListTile 的要求，
/// 外观又与 [AppCard] 保持一致（同圆角、同边框、同极轻阴影）。
class AppListCard extends StatelessWidget {
  const AppListCard({
    required this.children,
    super.key,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        boxShadow: softShadow(isDark: isDark),
      ),
      child: Material(
        color: theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}
