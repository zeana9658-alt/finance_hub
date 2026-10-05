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
    await database.open();
  });

  tearDown(() async {
    await database.close();
  });

  /// 用临时文件数据库替换真实数据库，其余保持生产装配。
  Widget harness() {
    return ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const FinanceHubApp(),
    );
  }

  testWidgets('空数据时首页展示引导文案而不是崩溃', (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('还没有任何账单'), findsOneWidget);
    expect(find.textContaining('账单不会离开你的设备'), findsOneWidget);
  });

  testWidgets('小屏 360×640 无溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('首页'), findsWidgets);
  });

  testWidgets('大字体 1.5 倍无溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: harness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('暗色模式（系统偏好）正常渲染', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: harness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('还没有任何账单'), findsOneWidget);
  });

  testWidgets('五个底部导航项都存在', (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    for (final label in <String>['首页', '账单', '统计', '预算', '设置']) {
      expect(find.text(label), findsWidgets, reason: '缺少导航项 $label');
    }
  });

  testWidgets('切到预算页显示「暂未实现」而不是假进度条', (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('预算').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('暂未实现'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
