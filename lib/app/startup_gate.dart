import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/errors/app_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 启动闸门：数据库打开失败时，用可读的错误页替换主界面。
///
/// **为什么需要它**（2026-10-05 的真实教训）：
/// 手机端因为一句在 Android 上非法执行的 `PRAGMA journal_mode = WAL`，
/// `openDatabase` 每次启动都抛异常。当时应用没有启动闸门，各业务 Provider
/// 各自抛错，界面只剩 Flutter 的红色错误屏 —— 用户看不到任何可读原因，
/// 只能去别处问「为什么报错」。
///
/// 这个组件把「数据库打不开」变成一句人话 + 可复制的错误原文 + 重试按钮。
///
/// **设计约束：不阻塞首帧。** `loading` 时直接渲染 [child]，而不是转圈等待。
/// 原因是首帧必须尽快交给主界面，让它自己的异步查询开始跑 —— 若在闸门这里
/// 先等一次数据库打开，主界面的查询就被推迟了一帧，在 widget 测试里表现为
/// 固定等待窗口被吃掉（`test/widget/app_shell_test.dart` 因此全红）。
/// 而闸门要拦的场景（数据库打不开）是**启动即失败**，健康检查一定先于
/// 主界面的查询返回，所以 `error` 分支来得及在错误扩散前接管。
class StartupGate extends ConsumerWidget {
  const StartupGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(databaseHealthProvider);

    if (health.hasError) {
      return _StartupErrorView(
        error: health.error!,
        onRetry: () => ref.invalidate(databaseHealthProvider),
      );
    }
    return child;
  }
}

class _StartupErrorView extends StatelessWidget {
  const _StartupErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // AppException 会把「可读原因」和「底层细节」分开，两者都要给用户看：
    // 前者告诉他发生了什么，后者是能拿去搜索/上报的原文。
    final AppException? appError = error is AppException ? error as AppException : null;
    final String message = appError?.message ?? '应用启动失败';
    final String? detail = appError?.detail ?? (appError == null ? '$error' : null);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimens.gapXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(
                  Icons.storage_outlined,
                  size: 36,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: AppDimens.gapM),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppDimens.gapS),
                Text(
                  '本地数据库是这款应用的全部数据来源，打不开就无法继续。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: AppDimens.gapL),
                  // 可选中、可复制 —— 用户要能把原文发给开发者，
                  // 而不是靠截图复述。
                  Container(
                    padding: const EdgeInsets.all(AppDimens.gapM),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
                    ),
                    child: SelectableText(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppDimens.gapL),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                const SizedBox(height: AppDimens.gapM),
                Text(
                  '如果重试仍然失败，可以先卸载应用再重新安装'
                  '（数据库只在本机，卸载会清空已导入的账单）。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
