import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_theme.dart';
import 'package:finance_hub/features/home/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用根组件。
class FinanceHubApp extends ConsumerWidget {
  const FinanceHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: '聚账 · FinanceHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const HomeShell(),
    );
  }
}
