import 'package:finance_hub/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 主题冒烟测试 —— 确认亮/暗两套主题都能构建且语义色正确。
void main() {
  test('浅色主题构建正常', () {
    final theme = AppTheme.light();
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, isTrue);
    // 背景应为极浅暖灰而非纯白
    expect(theme.scaffoldBackgroundColor, const Color(0xFFFAFAF8));
  });

  test('暗色主题构建正常', () {
    final theme = AppTheme.dark();
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF14161A));
  });

  testWidgets('亮/暗主题下最小页面均可渲染', (WidgetTester tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Center(child: Text('聚账'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('聚账'), findsOneWidget);
    }
  });
}
