# TESTING.md — 测试策略

> brief 第 31 条：**这是强制要求。不要只写代码。**
> 每完成一个模块：`dart analyze` → `flutter test` → 跑功能 → 查 UI → 修问题 → 再测。

---

## 1. 测试金字塔

```
        ┌──────────────────┐
        │  integration_test │  少量：端到端关键路径（导入→看板）
        ├──────────────────┤
        │   widget test     │  中等：页面渲染、交互、空态、暗色模式
        ├──────────────────┤
        │   unit test       │  ★ 大量：解析、去重、分类、金额、聚合
        └──────────────────┘
```

**投资重点在 unit test**：本项目 90% 的 bug 风险集中在解析与去重，而非 UI。

---

## 2. 目录结构

```
test/
├── fixtures/                       # ★ 全虚构测试数据
│   ├── mock_wechat.csv
│   ├── mock_wechat.xlsx
│   ├── mock_alipay.csv
│   ├── mock_alipay_gbk.csv
│   ├── mock_alipay_v2.csv
│   ├── mock_invalid.csv
│   ├── mock_refund.csv
│   ├── mock_transfer.csv
│   ├── mock_duplicate.csv
│   ├── mock_cross_platform.csv
│   ├── mock_backup_v1.json
│   └── fixture_loader.dart          # 统一加载器（含 GBK 版读取）
├── core/
│   ├── money_test.dart              # ★ 金额精度
│   └── date_range_test.dart
├── import/
│   ├── text_decoder_test.dart       # ★ 编码回退
│   ├── csv_reader_test.dart         # ★ RFC 4180（引号/内嵌逗号）
│   ├── xlsx_reader_test.dart
│   ├── header_locator_test.dart
│   ├── header_normalizer_test.dart
│   ├── wechat_parser_test.dart      # ★
│   ├── alipay_parser_test.dart      # ★
│   └── source_detector_test.dart
├── domain/
│   ├── duplicate_detector_test.dart # ★
│   ├── categorization_engine_test.dart  # ★
│   └── aggregator_test.dart
├── data/
│   ├── migration_test.dart
│   ├── transaction_repository_test.dart
│   └── rule_repository_test.dart
├── consistency/                     # 借鉴 beancount-auto-bookkeeping 的校验脚本
│   ├── direction_consistency_test.dart   # 收入支出方向是否自洽
│   ├── period_continuity_test.dart       # 期间是否连续无空洞
│   └── amount_integrity_test.dart        # 金额分无浮点污染
├── performance/
│   └── bulk_import_test.dart        # 10000 条导入 + 聚合耗时
└── widget/
    ├── dashboard_page_test.dart
    ├── import_preview_page_test.dart
    ├── bill_list_page_test.dart
    └── theme_test.dart              # 亮/暗模式均无溢出
integration_test/
└── end_to_end_test.dart             # 导入 → 预览 → 确认 → 看板
```

---

## 3. 必测清单（对应 brief 第 32 条）

| 场景 | 测试文件 | 关键断言 |
|---|---|---|
| 正常导入（微信 CSV） | `wechat_parser_test` | 条数、方向、金额分、商户 |
| 正常导入（微信 XLSX） | `xlsx_reader_test` + `wechat_parser_test` | 与 CSV 版**逐字段一致** |
| 正常导入（支付宝 CSV） | `alipay_parser_test` | 条数、方向、金额分 |
| **GBK 编码** | `text_decoder_test` + `alipay_parser_test` | `mock_alipay_gbk.csv` 与 `mock_alipay.csv` 结果**完全一致** |
| **乱码** | `text_decoder_test` | 不抛异常；无法解码时降级并标记 |
| **空金额** | `alipay_parser_test` | 进错误列表，`reason` 含"金额" |
| **退款** | `alipay_parser_test` / `wechat_parser_test` | `status = refunded`，方向正确 |
| **收入** | 两个 parser | `direction = income`，`amount_cents` 为正 |
| **支出** | 两个 parser | `direction = expense` |
| **转账** | 两个 parser | `direction = transfer`，默认不勾选 |
| **重复** | `duplicate_detector_test` | 第二次导入全部判 duplicate |
| **跨平台同额同商户** | `duplicate_detector_test` | **不判 duplicate**，仅 advisory |
| **错误行** | `mock_invalid.csv` | 行号准确、原文保留、原因可读 |
| **表头不在第 1 行** | `header_locator_test` | 正确跳过说明文字 |
| **全角/半角金额列名** | `header_normalizer_test` | `金额(元)` 与 `金额（元）` 均归一为 `金额` |

---

## 4. 关键测试用例（示例）

### 4.1 金额精度（`money_test.dart`）

```dart
test('绝不使用浮点导致的分位误差', () {
  expect(parseMoneyToCents('38.52'), 3852);
  expect(parseMoneyToCents('0.1'), 10);
  expect(parseMoneyToCents('0.07'), 7);
  expect(parseMoneyToCents('1234.5'), 123450);
  expect(parseMoneyToCents('1,234.56'), 123456);
  expect(parseMoneyToCents('¥38'), 3800);
  expect(parseMoneyToCents('￥ 38.5'), 3850);
  expect(parseMoneyToCents('38.567'), 3856);   // 截断到分
  expect(parseMoneyToCents(''), isNull);
  expect(parseMoneyToCents('待确认'), isNull);
});

test('浮点陷阱回归', () {
  // 若用 double: 38.52 * 100 = 3851.9999999999995 → toInt() = 3851
  expect(parseMoneyToCents('38.52'), isNot(3851));
  expect(parseMoneyToCents('38.52'), 3852);
});

test('分转展示字符串', () {
  expect(formatCents(3852), '38.52');
  expect(formatCents(0), '0.00');
  expect(formatCents(-3852), '-38.52');
  expect(formatCents(5), '0.05');
});
```

### 4.2 GBK 一致性（`text_decoder_test.dart`）

```dart
test('GBK 与 UTF-8 版本解析结果必须完全一致', () async {
  final utf8Preview  = await pipeline.previewFile('test/fixtures/mock_alipay.csv');
  final gbkPreview   = await pipeline.previewFile('test/fixtures/mock_alipay_gbk.csv');

  expect(gbkPreview.validCount, utf8Preview.validCount);
  expect(gbkPreview.duplicateCount, utf8Preview.duplicateCount);
  expect(gbkPreview.errorCount, utf8Preview.errorCount);

  for (var i = 0; i < utf8Preview.candidates.length; i++) {
    final a = utf8Preview.candidates[i];
    final b = gbkPreview.candidates[i];
    expect(b.entry.merchant, a.entry.merchant);
    expect(b.entry.description, a.entry.description);
    expect(b.entry.amountCents, a.entry.amountCents);
    expect(b.entry.transactionTime, a.entry.transactionTime);
  }
});
```

### 4.3 去重（`duplicate_detector_test.dart`）

```dart
test('同平台同交易单号 → 重复', () async { ... });

test('无交易单号时指纹判重', () async { ... });

test('跨平台同额同商户 → 不判重复，仅 advisory', () async {
  final wechat = tx(source: BillSource.wechat, amount: 3800, merchant: '示例餐厅');
  final alipay = tx(source: BillSource.alipay, amount: 3800, merchant: '示例餐厅');
  final result = await detector.detectBatch([wechat, alipay], existing: []);
  expect(result.where((r) => r.isDuplicate), isEmpty);
  expect(result.where((r) => r.isSuspectedCrossPlatform).length, 2);
});

test('批内重复（同一文件里出现两次）', () async { ... });

test('删除后重新导入应允许（部分唯一索引）', () async { ... });
```

### 4.4 分类优先级（`categorization_engine_test.dart`）

```dart
test('商户记忆优先于关键词规则', () async {
  // 用户手动把 Lawson 设为 餐饮/便利店
  await ruleRepo.rememberMerchant('Lawson', subcategory: '便利店');
  final r = await engine.categorize(tx(merchant: 'Lawson 罗森'));
  expect(r.categorySource, CategorySource.merchantMemory);
  expect(r.subcategoryName, '便利店');
});

test('关键词规则命中', () async {
  final r = await engine.categorize(tx(merchant: '示例咖啡'));
  expect(r.categorySource, CategorySource.keyword);
  expect(r.categoryName, '餐饮');
});

test('重跑不覆盖用户手动分类', () async {
  final t = await repo.insert(tx(merchant: 'X', categorySource: manual, category: '购物'));
  await engine.recategorizeAll();
  final after = await repo.findById(t.id);
  expect(after.categoryName, '购物');            // 未被改写
  expect(after.categorySource, CategorySource.manual);
});
```

### 4.5 一致性校验（借鉴 `beancount-auto-bookkeeping`）

```dart
// direction_consistency_test.dart
test('支出金额必须为正，方向由 transaction_type 表达', () async {
  final rows = await repo.findAll();
  for (final t in rows) {
    expect(t.amountCents, greaterThanOrEqualTo(0));
    expect(t.transactionType, isIn(TransactionType.values));
  }
});

// period_continuity_test.dart
test('导入的账单期间内无异常空洞（提示级）', () async { ... });

// amount_integrity_test.dart
test('数据库内所有金额均为整数分，无浮点残留', () async {
  final raw = await db.rawQuery('SELECT amount_cents FROM transactions');
  for (final r in raw) {
    expect(r['amount_cents'], isA<int>());
  }
});
```

---

## 5. 测试数据规范（隐私）

**所有 fixtures 必须虚构**，且遵守：

| 项 | 规范 |
|---|---|
| 商户名 | 一律 `示例*` 前缀：`示例咖啡`、`示例超市`、`示例餐厅`、`示例地铁` |
| 交易单号 | 一律 `TEST-` 前缀：`TEST-WX-0001`、`TEST-ALI-0001` |
| 账号 | `示例账号` |
| 昵称 | `示例用户` |
| 金额 | 任意，但需覆盖 0.01 / 0.1 / 整数 / 大额 等边界 |
| 手机号 | 不出现 |
| 银行卡号 | 如需测试脱敏，用 `6222 0000 0000 1234`（明显的测试号） |

> 参考 `cxy0714/beancount-auto-bookkeeping` 的做法：其 `rules.yaml` 全部使用"示例咖啡/示例超市"。

---

## 6. 性能测试

```dart
// performance/bulk_import_test.dart
test('10000 条交易批量导入 < 5 秒', () async {
  final sw = Stopwatch()..start();
  await repo.insertBatch(buildFakeTransactions(10000));
  sw.stop();
  expect(sw.elapsedMilliseconds, lessThan(5000));
});

test('10000 条下月度聚合 < 200ms', () async {
  final sw = Stopwatch()..start();
  await aggregator.monthlyTrend(year: 2026);
  sw.stop();
  expect(sw.elapsedMilliseconds, lessThan(200));
});

test('10000 条下账单列表首屏分页 < 100ms', () async { ... });
```

---

## 7. UI 测试关注点

| 关注 | 断言 |
|---|---|
| 空数据 | 所有页面在 0 条交易时显示 `EmptyState`，不报错、不显示 NaN/Infinity |
| 小屏 | 360×640 逻辑像素下无 `RenderFlex overflow` |
| Dark Mode | 亮/暗两套主题下文字对比度达标，无硬编码浅色文字 |
| 大字体 | `textScaleFactor = 1.5` 下无溢出 |
| 金额展示 | 大额（¥1,234,567.89）不截断、不换行错乱 |
| 导入预览筛选 | 全部/可导入/重复/错误 四个 Tab 计数与列表一致 |
| 图表空态 | 无数据时显示占位而非崩溃 |

```dart
testWidgets('小屏无溢出', (tester) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const ProviderScope(child: FinanceHubApp()));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
});
```

---

## 8. 每阶段自检清单（brief 第 39 条）

Phase 完成后逐项确认：

- [ ] `dart analyze` —— **零 error**，warning 全部处理
- [ ] `flutter test` —— 全绿
- [ ] 有无编译错误
- [ ] 有无 analyzer warning
- [ ] 有无空指针风险（可空值是否都被处理）
- [ ] 有无金额精度问题（是否出现 `double` 参与金额运算）
- [ ] 有无重复导入（同一文件导入两次的行为是否符合预期）
- [ ] 有无日期时区问题（跨月边界、`DateTime.now()` 兜底）
- [ ] 有无 GBK 乱码（GBK fixtures 是否覆盖）
- [ ] 有无退款处理错误（`refunded` 状态与方向）
- [ ] 有无收入支出方向错误（`不计收支` 是否被误判）
- [ ] 有无 UI 溢出（小屏 + 大字体）
- [ ] Android 小屏幕是否正常（360dp）
- [ ] Dark Mode 是否正常
- [ ] 空数据是否正常
- [ ] 10000+ 条交易是否还能正常运行

---

## 9. 运行命令

```bash
flutter pub get
dart analyze                       # 必须零 error
flutter test                       # 单元 + widget 测试
flutter test test/import/          # 只跑解析测试
flutter test test/performance/     # 性能测试
flutter test integration_test/     # 端到端（需设备/桌面）
flutter build apk --release        # Android 产物
flutter build windows --release    # Windows 产物（可选）
```

---

## 10. 禁止事项（brief 第 33 条）

❌ 禁止 TODO 假功能
❌ 禁止假的图表（写死数据）
❌ 禁止点击没反应
❌ 禁止按钮只有 UI 没逻辑
❌ 禁止用随机数字假装真实数据
❌ 禁止为了通过测试删除功能
❌ 禁止用大量 placeholder

**若某功能暂时无法完成，必须在 UI 与文档中明确标注「暂未实现」，不得伪装成已实现。**
