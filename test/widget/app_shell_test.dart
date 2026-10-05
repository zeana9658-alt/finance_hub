import 'dart:io';

import 'package:finance_hub/app/app.dart';
import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/data/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Widget 测试。
///
/// 关注点（docs/TESTING.md §7）：
/// - 空数据时不崩溃、不显示 NaN/Infinity
/// - 小屏（360×640）无溢出
/// - 暗色模式正常渲染
/// - 大字体（textScaleFactor 1.5）无溢出
/// - 未实现的功能必须显式声明，不能伪装
///
/// ⚠️ 关键点：`flutter_test` 默认在 **假时钟** 下运行，
/// 而 SQLite 查询是**真实异步 I/O**，在假时钟下永远不会完成
/// （`pumpAndSettle` 会一直等动画结束而超时）。
/// 因此这里统一用 `tester.runAsync` 让真实异步跑完，再用 `pump` 渲染。
void main() {
  late Directory tempDir;
  late AppDatabase database;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('finance_hub_widget_');
    database = AppDatabase(databasePath: p.join(tempDir.path, 'widget.sqlite'));
    // 预先把数据库打开，避免首帧还在建表
    await database.open();
  });

  tearDown(() async {
    await database.close();
  });

  Widget harness() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const FinanceHubApp(),
    );
  }

  /// 挂载 App 并等待真实数据库查询完成。
  Future<void> pumpApp(WidgetTester tester, {Widget? wrapper}) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(wrapper ?? harness());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('空数据时首页展示引导文案而不是崩溃', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('还没有任何账单'), findsOneWidget);
    expect(find.textContaining('账单不会离开你的设备'), findsOneWidget);
  });

  testWidgets('小屏 360×640 无溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('首页'), findsWidgets);
  });

  testWidgets('大字体 1.5 倍无溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(
      tester,
      wrapper: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: harness(),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('暗色模式（系统偏好）正常渲染', (WidgetTester tester) async {
    await pumpApp(
      tester,
      wrapper: MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: harness(),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('还没有任何账单'), findsOneWidget);
  });

  testWidgets('五个底部导航项都存在', (WidgetTester tester) async {
    await pumpApp(tester);

    for (final label in <String>['首页', '账单', '统计', '预算', '设置']) {
      expect(find.text(label), findsWidgets, reason: '缺少导航项 $label');
    }
  });

  testWidgets('切到预算页展示真实空态而不是假进度条', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('预算').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 预算已实现：空库时应展示引导文案，而不是「暂未实现」占位
    expect(find.text('还没有设置预算'), findsOneWidget);
    // 没有预算时不应出现进度条（那是「假装已有数据」的信号）
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
