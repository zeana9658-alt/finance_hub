import 'package:finance_hub/app/app.dart';
import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/data/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 启动闸门的测试。
///
/// 背景（2026-10-05）：手机端数据库打开失败时，界面只剩 Flutter 的红色错误屏，
/// 用户拿不到任何可读原因，只能去别处问「为什么报错」。
/// 这个测试锁住"失败时必须说人话 + 给出可复制的错误原文 + 能重试"。
///
/// ## 为什么这里 override 的是 `databaseHealthProvider`，而不是塞一个坏路径的 AppDatabase
///
/// 试过后者，结论是**不可行**：只要 `HomeShell` 被构建、同时 `AppDatabase.open()`
/// 真实失败，widget 测试就会永久挂起（`did not complete`）——
/// 与闸门无关，把 `StartupGate` 整个去掉、直接渲染 `HomeShell` 同样挂。
/// 这是"真实异步 I/O 失败 + widget 测试"的组合限制，属于既有问题，
/// 本测试不背这个锅，改从闸门真正的输入（健康检查的 AsyncError）切入。
///
/// 生产环境不存在这个问题：失败时各 Provider 只是各自进入 AsyncError，
/// 界面显示错误态 —— 用户当时看到的就是"打不开"，而不是卡死。
///
/// 「数据库正常时照常渲染主界面」由 `test/widget/app_shell_test.dart` 覆盖 ——
/// 闸门要是把 child 吞了，那 8 个用例会一起红。
void main() {
  testWidgets('数据库打不开时显示可读原因与错误原文，而不是红色错误屏', (
    WidgetTester tester,
  ) async {
    // 用真实事故里的错误原文，让这个测试读起来就是那次故障的复现。
    const detail =
        'DatabaseException(Queries can be performed using SQLiteDatabase '
        'query or rawQuery methods only.)';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseHealthProvider.overrideWith(
            (Ref ref) => Future<AppDatabase>.error(
              const DatabaseException('数据库打开失败', detail: detail),
            ),
          ),
        ],
        child: const FinanceHubApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);

    // 1) 说人话
    expect(find.text('数据库打开失败'), findsOneWidget);
    // 2) 给出可复制的底层错误原文 —— 否则又回到"只能靠猜"
    expect(find.text(detail), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    // 3) 能重试，不用卸载重装
    expect(find.text('重试'), findsOneWidget);
    // 4) 闸门接管后不再渲染主界面
    expect(find.text('还没有任何账单'), findsNothing);
  });
}
