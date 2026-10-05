# ARCHITECTURE.md — 系统架构设计

> 项目代号：**聚账 · FinanceHub**
> 定位：个人财务数据中枢（Personal Finance Data Hub）
> 一句话：把支付宝和微信账单扔进去，App 帮你把消费生活讲清楚。

---

## 1. 架构总原则

| # | 原则 | 落地方式 |
|---|---|---|
| 1 | **LOCAL FIRST** | 无服务端、无账号、无网络依赖。账单文件 → 本地解析 → 本地 SQLite → 本地统计 |
| 2 | **单一统一模型** | 微信/支付宝/银行卡/信用卡/京东全部归一化为 `NormalizedTransaction`，不允许各来源各有一套表 |
| 3 | **金额永不用浮点** | 全链路 `int`（单位：分）。展示层才格式化 |
| 4 | **解析不落库** | 解析 → 预览 → 用户确认 → 才写库。绝不"选完文件直接写" |
| 5 | **分类可重跑** | 分类是独立纯函数阶段，规则变更后可全量重跑，且**不覆盖用户手动分类** |
| 6 | **错误必须可见** | 任何解析失败都不崩、不静默丢弃，逐行记录行号 + 原文 + 原因 |
| 7 | **依赖倒置** | domain 层不依赖 Flutter、不依赖 sqflite；data 层实现 domain 定义的接口 |

---

## 2. 分层架构

```
┌──────────────────────────────────────────────────────────────┐
│  presentation（features/*）                                   │
│  Widget · Page · Riverpod Notifier · 图表渲染                  │
└───────────────────────────┬──────────────────────────────────┘
                            │ 只依赖 domain 实体 + Notifier
┌───────────────────────────▼──────────────────────────────────┐
│  domain（纯 Dart，零 Flutter 依赖）                            │
│  Entity · Enum · Service（去重/分类/聚合/导入编排）              │
│  ← 单元测试的主战场，可在无 Flutter 环境下跑                    │
└───────────────────────────┬──────────────────────────────────┘
                            │ 依赖抽象接口（Repository / Parser）
┌───────────────────────────▼──────────────────────────────────┐
│  data（持久化实现）                                            │
│  AppDatabase · Migration · RepositoryImpl · Record(Map 映射)   │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  import（账单解析，独立子系统）                                 │
│  decode → table → detect → parsers → models(ParseResult)      │
│  只依赖 domain 实体；不依赖 data / presentation                 │
└──────────────────────────────────────────────────────────────┘
```

### 2.1 为什么把 `import` 独立成顶层模块

账单解析是本项目**最复杂、最容易出 bug、最需要单独测试**的部分（编码、表头定位、金额清洗、方向判断、去重）。
把它从 `data` 里拆出来，好处：

- 可对 `test/fixtures/` 里的样例文件直接跑测试，**不需要数据库**
- 新增来源（京东/银行卡）只需加一个 Parser + 注册，零侵入
- 与参考项目 `lemon970/jizhang-app` 的 `decode/parse-*/normalize` 模块切分范式一致

---

## 3. 核心数据流

### 3.1 导入链路（最重要）

```
用户选择文件 (file_picker) 或粘贴文本
        │
        ▼
[1] TextDecoder          字节 → String
    utf-8-sig → utf-8 → gb18030 → gbk → latin1(兜底)
        │
        ▼
[2] TableReader          文本/字节 → RawTable（统一二维表）
    ├─ CsvReader        RFC 4180 兼容（处理引号、内嵌逗号换行）
    ├─ XlsxReader       excel 包解析第一个 sheet
    └─ TextTableReader  \t 分隔的粘贴表格
        │
        ▼
[3] HeaderLocator        扫描前 30 行，定位「同时含时间列 + 金额列」的行
        │
        ▼
[4] SourceDetector       判定来源
    ① 表头特征优先（支付宝有"交易分类/商品说明"，微信有"当前状态/商品"）
    ② 文件名/前 8 行文本兜底
    ③ 无法判定 → source = unknown，UI 提示用户手动选择
        │
        ▼
[5] BillParser.parse()   按来源选择 Parser → List<RawBillRow>
    逐行 try/catch，失败进 ParseError，不中断
        │
        ▼
[6] RowNormalizer        RawBillRow → NormalizedTransaction
    金额清洗(去¥/￥/,/空格) → 转分 → 方向判定 → 时间解析 → 排除规则
        │
        ▼
[7] DuplicateDetector    逐条判定
    ① unique_key 命中库中已有 → duplicate
    ② 批内 unique_key 重复    → duplicate（防同一次导入的重复行）
    ③ 否则 → valid
        │
        ▼
[8] CategorizationEngine 三级优先级分类
    商户记忆 → 平台原始分类映射 → 关键词规则 → (AI) → 其他
        │
        ▼
[9] ImportPreview        统计 + 候选列表
    ✓ 可导入 N  ↻ 重复 M  ! 异常 K
    收入 ¥x  支出 ¥y
        │
        ▼
[10] 用户确认（可逐条改分类、可取消勾选）
        │
        ▼
[11] TransactionRepository.insertBatch()
    单事务 + INSERT OR IGNORE（unique_key 唯一索引兜底）
    同时写 import_records
        │
        ▼
      SQLite
```

**关键设计**：第 1–8 步**完全不碰数据库写入**，只读 `unique_key` 做判重查询。用户点"取消"时零副作用。

### 3.2 查询链路

```
UI 请求 → Notifier → Repository（SQL 聚合）
                          │
                          ├─ 月度趋势：GROUP BY strftime('%Y-%m', ...)
                          ├─ 分类占比：GROUP BY category_id
                          ├─ 消费日历：GROUP BY date
                          ├─ 时段分布：按 hour 分桶
                          └─ 商户分析：GROUP BY merchant
```

聚合一律**下推到 SQL**，不在 Dart 侧全表遍历 —— 这是支撑 10000+ 条交易的关键。

### 3.3 自然语言查询链路（Phase 13）

```
自然语言 "我今年在咖啡上花了多少钱？"
        │
        ▼
[IntentParser]  →  结构化 Intent
    { metric: sum, dimension: category, filter: {category: 咖啡, year: 2026} }
        │
        ▼
[QueryBuilder]  →  SQL（白名单模板，参数化，绝不用 LLM 生成 SQL 字符串）
        │
        ▼
[SQLite]  →  真实数字   ← ★ 数据查询必须由本地数据库完成
        │
        ▼
[LLM]  只负责把数字组织成人话（可选，离线时直接展示数字）
```

**铁律**：LLM 只做"理解问题"和"解释结果"，**不做数据查询**。

---

## 4. 目录结构（完整）

```
finance_hub/
├── lib/
│   ├── main.dart                          # 入口：初始化 FFI、runApp
│   ├── app/
│   │   ├── app.dart                       # MaterialApp.router + ProviderScope
│   │   ├── router/app_router.dart         # 路由表
│   │   └── theme/
│   │       ├── app_theme.dart             # light/dark ThemeData
│   │       ├── app_colors.dart            # 语义化颜色 token
│   │       └── app_typography.dart
│   ├── core/
│   │   ├── money/money.dart               # ★ 金额值对象（分）
│   │   ├── money/money_formatter.dart
│   │   ├── result/result.dart             # Result<T, E>
│   │   ├── errors/app_error.dart
│   │   ├── utils/date_range.dart          # 今天/本周/本月/今年/自定义
│   │   ├── utils/hash_utils.dart          # sha1 指纹
│   │   └── constants/app_constants.dart
│   ├── domain/
│   │   ├── enums/
│   │   │   ├── bill_source.dart           # wechat/alipay/bank/credit_card/jd/manual
│   │   │   ├── transaction_type.dart      # income/expense/transfer/refund
│   │   │   ├── transaction_status.dart    # success/closed/failed/pending/refunded
│   │   │   └── category_source.dart       # manual/merchant_memory/platform/keyword/ai/fallback
│   │   ├── entities/
│   │   │   ├── normalized_transaction.dart  # ★ 统一交易实体
│   │   │   ├── category.dart
│   │   │   ├── category_rule.dart
│   │   │   ├── merchant_rule.dart
│   │   │   ├── account.dart
│   │   │   ├── budget.dart
│   │   │   ├── import_record.dart
│   │   │   ├── merchant_profile.dart        # 商户聚合视图
│   │   │   └── financial_summary.dart       # ★ AI 隐私边界载体
│   │   ├── repositories/                    # 接口（由 data 实现）
│   │   │   ├── transaction_repository.dart
│   │   │   ├── category_repository.dart
│   │   │   ├── rule_repository.dart
│   │   │   ├── budget_repository.dart
│   │   │   ├── import_repository.dart
│   │   │   └── settings_repository.dart
│   │   └── services/
│   │       ├── duplicate_detector.dart      # ★ 指纹去重
│   │       ├── categorization_engine.dart   # ★ 三级分类
│   │       ├── aggregator.dart              # 统计聚合
│   │       └── import_pipeline.dart         # 导入编排
│   ├── import/
│   │   ├── decode/text_decoder.dart
│   │   ├── table/
│   │   │   ├── raw_table.dart
│   │   │   ├── csv_reader.dart
│   │   │   ├── xlsx_reader.dart
│   │   │   ├── text_table_reader.dart
│   │   │   ├── header_locator.dart
│   │   │   └── header_normalizer.dart
│   │   ├── detect/source_detector.dart
│   │   ├── parsers/
│   │   │   ├── bill_parser.dart             # 抽象基类
│   │   │   ├── wechat_parser.dart
│   │   │   ├── alipay_parser.dart
│   │   │   └── parser_registry.dart
│   │   └── models/
│   │       ├── raw_bill_row.dart
│   │       ├── parse_result.dart
│   │       ├── parse_error.dart
│   │       ├── import_preview.dart
│   │       └── import_candidate.dart
│   ├── data/
│   │   ├── database/
│   │   │   ├── app_database.dart            # 打开 + 迁移调度
│   │   │   └── migrations/
│   │   │       ├── migration.dart           # Migration 抽象
│   │   │       ├── m001_initial.dart
│   │   │       └── m002_seed_categories.dart
│   │   ├── records/                         # 表 ↔ Map 映射
│   │   └── repositories/                    # 接口实现
│   ├── features/
│   │   ├── dashboard/       { presentation/, application/ }
│   │   ├── bills/
│   │   ├── stats/
│   │   ├── budget/
│   │   ├── import/
│   │   ├── quick_entry/
│   │   ├── merchant/
│   │   └── settings/
│   └── shared/widgets/
│       ├── app_card.dart
│       ├── amount_text.dart
│       ├── empty_state.dart
│       ├── section_header.dart
│       └── charts/                          # fl_chart 封装 + 自绘日历/热力图
├── test/
│   ├── fixtures/                            # ★ 全虚构测试数据
│   ├── core/
│   ├── import/
│   ├── domain/
│   ├── data/
│   ├── consistency/                         # 方向/期间/完整性校验
│   └── widget/
├── integration_test/
├── docs/
└── android/  windows/  pubspec.yaml  analysis_options.yaml
```

---

## 5. 技术选型与理由

| 层 | 选型 | 版本 | 理由 |
|---|---|---|---|
| 框架 | Flutter / Dart | 3.47.6 / 3.12 | brief 指定；单代码库覆盖 Android + Windows |
| 状态管理 | `flutter_riverpod` | ^3.4.3 | 编译期安全、无 BuildContext 耦合、`ProviderScope` override 让 widget test 极简 |
| 本地库 | `sqflite` + `sqflite_common_ffi` | ^2.4.4 / ^2.4.3 | Android 用原生，Windows/Linux 用 FFI；参考 `lizhang` 已验证该组合 |
| 文件选择 | `file_picker` | ^13.1.0 | 支持 Android 原生选择器与 Windows 桌面对话框 |
| XLSX | `excel` | ^4.0.6 | 纯 Dart，无原生依赖，Windows/Android 一致 |
| CSV | `csv` | ^8.0.0 | 符合 RFC 4180，正确处理引号与内嵌逗号（**修正参考项目的 `split(',')` 缺陷**） |
| **GBK 解码** | **`charset`** | **^2.0.1** | **纯 Dart，支持 gbk/gb18030/big5，Android 与 Windows 均可。不选 `charset_converter`（平台通道，Windows 不可靠），不选 `fast_gbk`（SDK 约束 `<3.0.0`，Dart 3 不可用）** |
| 图表 | `fl_chart` | ^1.2.0 | 覆盖折线/柱状/饼图；日历热力图与时段热力图自绘（`CustomPainter`，逻辑简单且可控） |
| 金额 | 自研 `Money` | — | 无第三方依赖，避免精度陷阱 |
| 指纹 | `crypto` | ^3.0.7 | sha1 |
| 日期 | `intl` | ^0.20.3 | 本地化格式化 |
| 导出分享 | `share_plus` | ^13.3.1 | 备份文件分享到其他 App |
| 测试 | `flutter_test` + `integration_test` | SDK | brief 强制要求 |

### 5.1 明确排除的选型

| 排除 | 原因 |
|---|---|
| `charset_converter` | 平台通道插件，Windows 支持不可靠；且需要原生代码 |
| `fast_gbk` / `gbk_codec` / `gbk2utf8` | SDK 约束 `>=2.12.0 <3.0.0`，**Dart 3 无法解析** |
| `syncfusion_flutter_charts` | 商业授权限制 |
| 任何云同步 / Firebase | 违反 LOCAL FIRST |
| `get_it` / `provider` | 与 Riverpod 功能重叠，单一状态方案更清晰 |

---

## 6. 状态管理设计

### 6.1 Provider 分层

```
基础层（Provider）
  databaseProvider          → AppDatabase（单例）
  transactionRepoProvider   → TransactionRepository
  categoryRepoProvider      → CategoryRepository
  ...

服务层（Provider）
  duplicateDetectorProvider → DuplicateDetector
  categorizationProvider    → CategorizationEngine
  importPipelineProvider    → ImportPipeline

状态层（AsyncNotifier / Notifier）
  dashboardNotifierProvider → 当前月份 + 聚合结果
  billListNotifierProvider  → 筛选条件 + 分页结果
  importSessionProvider     → ★ 导入会话（预览态、候选勾选、分类修改）
  budgetNotifierProvider    → 预算 + 进度
  themeNotifierProvider     → 亮/暗模式

派生层（Provider 自动缓存）
  monthlyTrendProvider      → 依赖 dashboardNotifierProvider
  categoryBreakdownProvider
```

### 6.2 `importSessionProvider` —— 导入会话状态机

这是全 App 最复杂的状态，显式建模为状态机：

```
idle
 └─ pickFile() ──▶ parsing
                    ├─ 成功 ──▶ previewing ──┬─ 用户取消 ──▶ idle
                    │                        ├─ 改分类 ──▶ previewing（原地更新）
                    │                        └─ 确认 ──▶ importing ──▶ done
                    └─ 失败 ──▶ failed(错误详情)
```

关键：`previewing` 状态下**未写入任何数据**，用户可自由往返。

---

## 7. UI / 视觉系统

### 7.1 设计语言

关键词：Minimal · Premium · Calm · Japanese Minimalism · Soft UI · Data-first

### 7.2 颜色 token（`app_colors.dart`）

**浅色模式（主）**

| 语义 | 值 | 说明 |
|---|---|---|
| `background` | `#FAFAF8` | 极浅暖灰，非纯白，降低视觉刺激 |
| `surface` | `#FFFFFF` | 卡片 |
| `surfaceVariant` | `#F4F4F1` | 次级容器 |
| `accent` | `#3D6B5C` | **唯一强调色**：低饱和墨绿 |
| `income` | `#5B8C6E` | 低饱和绿 |
| `expense` | `#C67B5C` | 低饱和暖赭 |
| `warning` | `#C9A227` | 低饱和琥珀（预算预警，**不用刺眼红**） |
| `textPrimary` | `#1F2421` | |
| `textSecondary` | `#6B7370` | |
| `divider` | `#E8E8E4` | |

**深色模式**：`background #14161A` / `surface #1C1F24` / `accent #7FB69F` / 文本 `#E8EAE8`

**图表辅助色**（低饱和，5–8 色，用于分类占比）：
`#3D6B5C` `#8FA9A0` `#C67B5C` `#D9B48F` `#7B8FA3` `#A39BB0` `#9CAF88` `#C9A227`

### 7.3 形状与层次

- 圆角：卡片 `16px`，小组件 `12px`，按钮 `14px`，底部弹层顶部 `20px`
- 阴影：**仅一级**，`BoxShadow(blurRadius: 12, y: 2, color: black @ 4%)`
- 分隔优先用 `1px` 边框而非阴影
- 信息密度：单屏卡片数 ≤ 4，避免"堆满卡片"

### 7.4 底部导航（5 项 + FAB）

```
┌──────────────────────────────────────────┐
│  首页 | 账单 | 统计 | 预算 | 设置          │   ← NavigationBar
└──────────────────────────────────────────┘
                    ＋                         ← 首页/账单页的 FAB（导入账单）
```

**实际实现**（`lib/features/home/home_shell.dart`）：
- `NavigationBar` 五个目的地：首页 / 账单 / 统计 / 预算 / 设置
- 用 `IndexedStack` 保留各页状态（切回来不丢滚动位置与筛选条件）
- 快速入口做成**首页与账单页的 FAB**（`ImportEntry.open`），而不是挤进导航栏中间

**为什么不用「中间悬浮 +」**：5 个导航项 + 中间按钮共 6 个位置，
在 360dp 宽的小屏上每格只剩约 60dp，加上大字体（1.5×）会直接溢出。
做成 FAB 后导航项仍保持 ≥ 72dp 宽，触控目标达标。

> 该决策已被 Widget 测试验证：`test/widget/app_shell_test.dart`
> 在 360×640 与 1.5× 字体下均无 `RenderFlex overflow`。

---

## 8. 性能设计（目标：10000+ 条交易可用）

| 措施 | 说明 |
|---|---|
| SQL 侧聚合 | 所有统计用 `GROUP BY` + 索引，不把全表拉进 Dart |
| 必要索引 | `transaction_time`、`type`、`category_id`、`source`、`merchant`、`unique_key` |
| 分页 | 账单列表 `LIMIT/OFFSET`（或 keyset 分页），每页 50 |
| 批量写入 | 导入用单个事务 + `batch()`，10000 条 < 2 秒 |
| WAL 模式 | `journal_mode = WAL` 提升并发读 |
| 避免全表重建 | 分类重跑只 `UPDATE` 变化行，且跳过 `category_source = manual` |
| 图表数据点上限 | 日历/热力图按聚合值渲染，不逐笔绘制 |
| `const` 构造 | 大量静态 Widget 用 `const` 减少重建 |

---

## 9. 平台适配

| 关注点 | Android | Windows |
|---|---|---|
| 数据库工厂 | `sqflite` 原生 | `sqfliteFfiInit()` + `databaseFactoryFfi` |
| DB 路径 | `getApplicationSupportDirectory()` | 同左 |
| 文件选择 | 系统文件选择器 | 原生文件对话框 |
| 分享导出 | `share_plus` | 保存到文件 + 打开所在目录 |
| 窗口尺寸 | 手机竖屏优先，最小 360dp | 桌面宽度自适应（最大内容宽 720 居中） |
| 返回键 | 拦截返回做二次确认（未保存的导入预览） | 无 |

iOS / macOS 预留：`sqflite` 与 `file_picker` 均支持，只需 `flutter create --platforms ios,macos` 补平台目录。

---

## 10. 开发阶段划分（Vertical Slice）

每个 Phase 结束必须：`dart analyze` 零 error → `flutter test` 全绿 → 手动跑一遍 UI → 自检清单过一遍。

| Phase | 内容 | 交付物 | 状态 |
|---|---|---|---|
| 0 | GitHub 调研 | `docs/GITHUB_RESEARCH.md` | ✅ 完成 |
| 1 | 架构 + 数据库设计 | `ARCHITECTURE.md` `DATABASE.md` | ✅ 完成 |
| 2 | 项目骨架 + 工具链 | `flutter create` + pubspec + theme + 路由 + git | ⏳ |
| 3 | SQLite + 迁移 + Money | `AppDatabase`、`m001`、`Money`、测试 | ⏳ |
| 4 | Transaction 实体 + 仓储 | `NormalizedTransaction`、`TransactionRepository`、测试 | ⏳ |
| 5 | 解码 + 表格读取 | `TextDecoder`（含 GBK）、`Csv/Xlsx/TextTable Reader`、测试 | ⏳ |
| 6 | 微信解析 | `WechatParser` + fixtures + 测试 | ⏳ |
| 7 | 支付宝解析 | `AlipayParser`（含 GBK）+ fixtures + 测试 | ⏳ |
| 8 | 来源自动识别 | `SourceDetector` + 测试 | ⏳ |
| 9 | 去重 | `DuplicateDetector` + `unique_key` 唯一索引 + 测试 | ⏳ |
| 10 | 导入预览 UI | 导入页 + 预览页 + 筛选 + 确认写库 | ⏳ |
| 11 | 分类系统 | 三级分类 + 规则表 + 商户记忆 + 重跑 | ⏳ |
| 12 | Dashboard | 首页 + 月度趋势 + 分类占比 + 下钻 | ⏳ |
| 13 | 统计 | 消费日历 + 时段热力图 + 大额 TOP + 商户分析 | ⏳ |
| 14 | 账单明细 | 搜索/筛选/排序/按商户汇总 | ⏳ |
| 15 | 预算 | 预算 CRUD + 进度 + 温和预警 | ⏳ |
| 16 | 备份 | JSON/CSV/Excel 导出 + 导入预览确认 | ⏳ |
| 17 | AI（可选） | `FinancialSummary` + 自然语言查询 | ⏳ |
| 18 | 最终验收 | 24 条验收标准逐条验证 | ⏳ |

---

## 11. 风险登记册

| 风险 | 影响 | 缓解 |
|---|---|---|
| 本机无 Flutter/Android SDK | 无法构建 APK | 已确认可下载；优先保证 `dart analyze` + `flutter test` 通过，APK 构建作为增强目标 |
| Maven Central 不可达 | Gradle 依赖拉取失败 | 配置阿里云 Maven 镜像（`maven.aliyun.com` 已实测可达） |
| 沙箱删除守卫影响 Gradle | 构建中途失败 | Gradle 缓存与构建目录尽量放在 `%LOCALAPPDATA%\Temp` 附近；如受阻则明确标注"APK 未验证" |
| 支付宝 CSV 存在多个导出版本 | 解析失败 | 表头扫描（非硬编码行号）+ 列别名表 + 多编码回退 |
| 微信/支付宝改版导致格式变化 | 解析失效 | 表头驱动而非行号驱动；解析失败给出明确原因 |
| 浮点精度 | 金额错误 | 全链路 `int` 分；`Money` 值对象封装；专门测试 |
| 跨平台误判重 | 丢数据 | **默认不做跨平台判重**，仅平台内 `unique_key` |
| 时区问题 | 日期偏移 | 统一本地时间存储为 epoch 毫秒 + 保留原始字符串；展示用本地时区 |
