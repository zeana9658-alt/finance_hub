# GITHUB_RESEARCH.md — 参考项目调研报告

> 调研日期：2026-10-05
> 调研方式：通过 GitHub 连接器读取各仓库的真实目录结构与源码文件（非二手描述）
> 调研结论：**研究设计 → 理解原理 → 重新实现**，未复制任何项目的大段代码

---

## 0. 调研范围与结论速览

| # | 仓库 | 语言/栈 | 形态 | 对本项目的价值 |
|---|---|---|---|---|
| 1 | `MageGojo/lizhang`（璃账） | Flutter + SQLite | 本地优先记账 App（macOS/Win/Android） | ★★★★★ 技术栈与产品定位**高度重合**，是主要架构参照 |
| 2 | `zalexrose/FamilyFinanceManager` | Python + pandas | 账单解析脚本集 | ★★★★☆ Adapter 抽象与编码回退策略 |
| 3 | `changdaye/bill-aggregator` | Next.js + better-sqlite3 | Web 账单聚合平台 | ★★★★☆ SQLite schema 与 GBK 处理 |
| 4 | `lemon970/jizhang-app` | 原生 JS PWA | 前端纯本地记账 | ★★★★☆ **模块切分范式** + 自动记账技术调研 |
| 5 | `dtsola/xiaoyaoprivatebill` | Flask + Vue + Docker | 前后端分离分析工具 | ★★★☆☆ 分析维度分类学（架构不采用） |
| 6 | `cxy0714/beancount-auto-bookkeeping` | Python → Beancount | 复式记账流水线 | ★★★☆☆ 声明式规则格式 |

**一句话总结**：没有任何一个项目同时满足「Flutter 移动端 + 三级分类体系 + 规则可重跑 + 指纹去重 + 完整可视化 + 本地优先」。
`lizhang` 解决了"技术栈与本地优先"，`bill-aggregator` 解决了"schema 与分类"，`jizhang-app` 解决了"模块边界"，`beancount-*` 解决了"规则可重跑"。
本项目要做的是**把这些局部最优组合成一个完整系统**。

---

## 1. MageGojo/lizhang（璃账）

### 1.1 它解决了什么问题

一个 Flutter 编写的、面向 macOS/Windows/Android 的**本地优先记账本**。核心链路：
`选择文件 → 解析 → 预览（有效/重复/错误）→ 用户确认 → 写入 SQLite`。
产品定位与本项目最接近，是唯一一个「Flutter + 微信/支付宝导入 + 本地优先」的完整实现。

### 1.2 实际读到的源码结构

```
lib/
├── main.dart                     # 52 KB 单文件，UI 全在这里
├── models/
│   ├── ledger_entry.dart         # LedgerEntry / BalanceAnchor / DayArchive / LedgerSnapshot
│   └── import_models.dart        # ImportPreview / ImportCandidate / ImportMethod
└── services/
    ├── bill_importer.dart        # 解析 + 来源识别 + 预览构建
    ├── ledger_database.dart      # sqflite/sqflite_common_ffi 双栈
    └── money.dart                # 金额工具
test/  { bill_importer_test.dart, ledger_database_test.dart, widget_test.dart }
integration_test/
```

### 1.3 值得借鉴的设计

1. **金额以"分"存整数**（`amount_cents INTEGER`），`LedgerEntry.signedAmountCents` 用 `type` 决定正负号，存储时 `amountCents.abs()`。
   → 与 brief 的"绝对禁止浮点数"要求一致，直接采纳。

2. **软删除 + 撤销**：`deleted_at_ms` 列，查询一律带 `deleted_at_ms IS NULL`；删除只写时间戳，可 `restoreEntry`。
   → 采纳。比物理删除安全，且天然支持"撤销导入"。

3. **两段式去重**（`hasPotentialDuplicate`）：
   - 第一段：`source + external_id` 精确命中 → 重复
   - 第二段：`occurred_at_ms + amount_cents + type + merchant + note` 全等 → 重复
   → **第二段是反模式**（见 1.5），但第一段的分层思路采纳。

4. **表头智能定位**：`_findHeaderIndex()` 逐行扫描，只要某行同时含"时间"类与"金额"类列就认定是表头。
   → 完美解决微信/支付宝账单"前几行是说明文字"的问题，采纳。

5. **列名归一化 + 别名表**：`_normalizeHeader()` 去掉 `空格/括号/斜杠/下划线/冒号/连字符` 和 `人民币/元`，再用别名数组匹配：
   - 时间 → `['交易时间','付款时间','创建时间','时间']`
   - 金额 → `['金额','金额元','交易金额']`
   - 商户 → `['交易对方','对方','商户','商家','商品','商品名称','商品说明']`
   → 一套代码吃下微信与支付宝两种表头，采纳并扩充。

6. **来源自动识别**：对"文件名 + 前 8 行拼接文本"做小写化后 `contains('支付宝')/contains('微信')`。
   → 采纳，但需增强为"表头特征优先"（见 3.2）。

7. **解析失败降级为候选行而非抛异常**：单行出错产出 `ImportCandidate(error: ...)`，`rowNumber` 保留，整体不崩。
   → 与 brief「三十、错误处理」完全一致，采纳。

8. **粘贴表格文本导入**：`previewText()` 与文件导入共用同一套 `_previewRows()`，`\t` 分隔优先、否则走 CSV 解析器。
   → 采纳，一个入口覆盖三种输入形态。

9. **跨平台数据库工厂**：`Platform.isWindows || isLinux → sqfliteFfiInit(); databaseFactory = databaseFactoryFfi`。
   → 本项目要跑 Windows 桌面，采纳。

### 1.4 不适合本项目的设计

| 设计 | 为什么不采用 |
|---|---|
| `main.dart` 52 KB 单文件 | 不可维护。本项目按 feature 分层，UI 拆到 `features/*/presentation/` |
| `category` 是自由文本字符串 | brief 要求**三级分类**（一级/二级/商户记忆），必须建表 |
| 无分类规则表、无规则重跑 | brief 第 11 条硬要求，`lizhang` 完全没有 |
| 无 Dashboard / 图表 / 预算 | 首版聚焦"记准"，本项目核心价值恰恰在可视化 |
| `balance_anchor`（余额锚点） | 是"记账本"概念；本项目是"账单聚合器"，用户不关心实时余额 |
| 无 schema 迁移（`version: 1` + `CREATE TABLE IF NOT EXISTS`） | brief 第 28 条要求迁移机制，必须做 `onUpgrade` |
| `_decodeText` 只试 UTF-8 | **不支持 GBK**，而支付宝 CSV 默认就是 GBK —— 这是致命缺口 |

### 1.5 明确要避开的坑（反面教材）

`hasPotentialDuplicate` 的第二段判断用 `merchant + note` 全等来判重。
**这会把两笔真实的、同商户同金额的交易误判为重复**（例如同一天在同一家便利店买两次同样的东西）。
brief 第 8 条明确禁止这种粗糙判重。本项目改为**指纹哈希 + 平台内约束**，且**不做跨平台判重**。

---

## 2. zalexrose/FamilyFinanceManager

### 2.1 它解决了什么问题

用 Python + pandas 把微信/支付宝账单转换成统一 `StandardTransaction` 模型，做家庭财务汇总。

### 2.2 实际读到的源码结构

```
adapters/
├── base_adapter.py        # ABC: parse(file_path) -> List[StandardTransaction]
├── alipay_adapter.py
└── wechat_adapter.py
core/        config/        rules/        database/finance.db   main.py
```

### 2.3 值得借鉴的设计

1. **Adapter 抽象基类**：`BaseAdapter(ABC)` 定义 `parse()` 契约，每个平台一个 Adapter。
   → 采纳为 `BillParser` 抽象类，但升级为**返回 `ParseResult`（含错误行）**而不是只返回成功列表。

2. **表头行扫描有上限**：`for i in range(min(20, len(df)))` —— 防止在畸形文件里无限扫描。
   → 采纳，上限设为 30 行。

3. **编码回退链**：`for encoding in ["utf-8", "utf-8-sig", "gbk"]`，逐个 try。
   → 采纳并扩展：`utf-8-sig → utf-8 → gbk → gb18030`（`gb18030` 是 GBK 超集，能救更多生僻字）。

4. **表头前导行剥离**：CSV 分支里找到 `line.strip().startswith("交易时间")` 作为起始行，`csv.DictReader(lines[start_idx:])`。
   → 采纳思路，但本项目用「扫描前 N 行找同时含时间+金额的行」更鲁棒。

5. **业务性过滤规则显式声明**：
   - 支付宝：`交易状态` 含"交易关闭" → 丢弃
   - 微信：`交易类型` 命中 `["零钱提现","零钱充值","转入零钱通","零钱通转出","转账","信用卡还款","理财通"]` → 丢弃
   → **高价值**。这些是"资金搬运"而非"消费"，计入支出会严重虚高。采纳为可配置的排除规则。

6. **金额清洗**：`str(amount).replace("¥","").replace(",","")`。
   → 采纳，并扩充去掉全角 `￥`、空格。

### 2.4 不适合本项目的设计

| 设计 | 为什么不采用 |
|---|---|
| `database/finance.db` **被提交进仓库**（397 KB 二进制） | 严重隐私事故。本项目 `.gitignore` 必须排除 `*.db` / `database/` |
| 依赖 pandas（`pd.read_excel` / `pd.isna`） | Flutter 端无等价物，需自研；且 pandas 对 `.xlsx` 的宽松解析会掩盖坏数据 |
| `generate_unique_id(source, date, amount, payee)` | **仅 4 字段哈希**，同日同店同价的真实两笔会被误判重复 —— 与 brief 第 8 条冲突 |
| `if amount == 0: return None` 直接丢 | 0 元交易应作为**错误行**呈现给用户，而非静默丢弃（brief 第 30 条要求可查看） |
| 支付宝用 `else: amount = Decimal(amount_str)` 把非"支出"一律当正数 | "不计收支"类交易会被误记成收入，方向判断有漏洞 |

---

## 3. changdaye/bill-aggregator

### 3.1 它解决了什么问题

Next.js + SQLite 的 Web 端账单聚合平台，覆盖导入、智能分类、看板、预算、财务目标、搜索、导出。

### 3.2 实际读到的源码结构

```
lib/
├── db/{schema.ts, transactions.ts}
├── parsers/{alipay-parser.ts, wechat-parser.ts}
└── types/
app/api/{parse,db/import,categories,budgets,goals,dashboard,timeline,search,export}
```

### 3.3 值得借鉴的设计

1. **SQLite schema 设计成熟**，直接可借鉴的点：
   - `db.pragma('journal_mode = WAL')` + `foreign_keys = ON`（WAL 提升并发读性能）
   - 用 `CHECK(platform IN ('wechat','alipay'))` 和 `CHECK(type IN ('income','expense','neutral'))` 做**数据库层枚举约束**
   - 索引组合：`idx_transactions_time`、`idx_transactions_type`、`idx_transactions_category`、`idx_transactions_platform`，以及 `UNIQUE INDEX idx_transactions_no ON transactions(transaction_no, platform)`
   - → 全部采纳，并升级为 brief 要求的 `unique_key` 唯一索引

2. **`is_manual_category INTEGER DEFAULT 0` 标志位** —— 这是 brief 第 11 条「重新分类时必须保留用户手动修改」的**关键实现机制**。
   → 高价值采纳：`is_category_locked` / `category_source` 字段。

3. **`categories` + `subcategories` 双表**，`subcategories.keywords` 以 JSON 数组存关键词，`UNIQUE(category_id, name)`。
   → 采纳两级结构，第三级"商户记忆"用独立表实现（`merchant_rules`）。

4. **默认分类内置 9 个支出类 + 5 个收入类，每类带关键词数组**（如餐饮含 `外卖/餐厅/咖啡/星巴克/肯德基/麦当劳/海底捞`）。
   → 采纳为**种子数据**，但按 brief 第 9 条扩到 17 个一级分类。

5. **GBK 处理**：`iconv.decode(buffer, 'GBK')`，且注释明确写了支付宝格式「第 5 行是表头（逗号分隔），第 6 行开始是数据」。
   → 印证了支付宝 CSV 的真实结构，采纳该认知。

6. **交易关闭的记录金额置 0 但不立即丢弃**，先标记状态再决定是否统计。
   → 采纳为 `status = closed` + `is_counted` 分离。

### 3.4 不适合本项目的设计

| 设计 | 为什么不采用 |
|---|---|
| `amount REAL NOT NULL` | **浮点存金额**，与 brief 第 4 条直接冲突。本项目用 `INTEGER` 存"分" |
| 解析用 `line.split(',')` 朴素切分 | 商品名里一旦出现英文逗号就错位。必须用**符合 RFC 4180 的 CSV 解析器**（处理引号包裹） |
| `values.length !== headers.length → 直接 continue` | 静默丢行，用户永远不知道丢了多少。本项目要记入错误列表 |
| 表头硬编码在 `lines[4]` | 支付宝不同导出版本行号会变，应扫描而非硬编码 |
| 全栈 Web + 服务端 SQLite | 与 LOCAL FIRST 冲突。本项目是纯本地 App，**不设服务端** |
| 无跨平台 | 只面向浏览器 |

---

## 4. lemon970/jizhang-app

### 4.1 它解决了什么问题

纯前端（原生 JS PWA）的本地记账应用，且仓库内附带一份**《安卓自动记账 App 技术调研与可行性》**文档。

### 4.2 实际读到的源码结构 —— 模块切分极具参考价值

```
js/
├── decode.js       # 473 B   —— 编码解码
├── parse-alipay.js # 1012 B  —— 支付宝解析
├── parse-wechat.js # 924 B   —— 微信解析
├── normalize.js    # 1458 B  —— 归一化到统一模型
├── dedup.js        # 521 B   —— 去重
├── classify.js     # 3171 B  —— 分类
├── aggregate.js    # 4100 B  —— 聚合统计
├── charts.js       # 2668 B  —— 图表渲染
├── storage.js      # 2820 B  —— 本地存储
├── icons.js / app.js
tests/
自动记账-技术调研与可行性.md
```

### 4.3 值得借鉴的设计

1. **单一职责的极小模块**：`decode / parse-* / normalize / dedup / classify / aggregate / charts / storage` 每个文件几百字节到几 KB。
   → **本项目 Dart 侧的目录切分直接对齐这套命名**（见 ARCHITECTURE.md），可读性和可测试性都最优。

2. **`normalize.js` 独立于解析器**：解析器只管"把行变成字段"，归一化只管"把字段变成统一模型"。
   → 采纳为 `RawBillRow → NormalizedTransaction` 两段式，便于新增银行卡/京东来源时零改动复用。

3. **技术调研文档的结论（对未来 Phase 极有价值）** —— 安卓上"自动拿到交易数据"的 5 条路线：

   | 路线 | 能拿到什么 | 是否需 root | 结论 |
   |---|---|---|---|
   | 无障碍服务 | 支付成功页/账单详情页的金额、对方、商品 | 否 | 页面规则易碎，微信/支付宝改版即失效；纯鸿蒙走不通 |
   | 通知监听 | 部分通知里的金额 | 否 | 多数支付通知不带金额；Android 15+ 限制 OTP 通知 |
   | 读短信 | 银行卡消费/到账短信 | 否 | 个人 sideload 不受 Play 政策限制，适合做银行卡兜底 |
   | Xposed/LSPosed | 最完整的进程内数据 | **是** | 门槛高、有风控风险 |
   | **账单文件导入** | **全量历史账单** | **否** | **最可靠，本项目采用** |

   **关键结论**：调研明确指出「账单文件导入」是唯一"低难度 + 高可靠 + 免 root"的路线。
   这**验证了本项目的技术选型是正确的**，同时也说明"自动抓取"应作为后续可选增强，而非 v1 范围。

4. **`sw.js` + `manifest.webmanifest`**：说明它走 PWA 离线缓存。
   → 思路可借鉴（离线可用是硬需求），但 Flutter 侧由 SQLite 本地存储天然满足。

### 4.4 不适合本项目的设计

| 设计 | 为什么不采用 |
|---|---|
| 原生 JS，无类型系统 | 账单解析的字段极易出错，需要 Dart 的强类型 + 编译期检查 |
| PWA（依赖浏览器） | 无法获得 Android 原生文件选择、分享入口、后台任务能力 |
| 无数据库（`storage.js` 走 localStorage/IndexedDB） | 无法支撑 10000+ 条交易的复杂聚合查询 |
| `dedup.js` 仅 521 B | 去重过于简陋，是本项目要重点加强的模块 |

---

## 5. dtsola/xiaoyaoprivatebill

### 5.1 它解决了什么问题

Flask + Vue3 + ECharts 的**隐私优先**账单分析工具，Docker 一键部署，主打"数据完全本地处理，不上传服务器"。

### 5.2 实际读到的源码结构

```
backend/  { api/, services/, parsers/, utils/, app.py, config.py }
frontend/ { src/{api,views,components,stores,utils}, nginx.conf }
docs/     { 00-mrd.md, 01-prd.md, 接口文档.md, 03-技术方案文档.md, 部署文档.md }
docker-compose.yml
```

### 5.3 值得借鉴的设计

1. **分析维度的完整分类学**（这是本项目 Dashboard/统计页的设计蓝本）：
   - 年度总览（收入/支出/趋势/年度故事）
   - 月度分析（收支趋势、**日历视图**、环比同比）
   - 分类分析（占比、排行、明细）
   - **时间分析（消费时段分布 + 时段热力图）**
   - 消费洞察（习惯分析、异常消费提醒、消费建议）
   → 与 brief 第 13/15/16/17 条几乎一一对应，**确认了需求方向的正确性**。

2. **账单来源支持矩阵**（明确写出）：支付宝 CSV、微信 CSV、微信 XLSX。
   → 印证本项目第一阶段的三类输入。

3. **`docs/` 文档体系**（MRD → PRD → 接口文档 → 技术方案 → 部署文档）。
   → 采纳其"文档先行"的工程习惯，本项目建立 `docs/` 六件套。

4. **隐私承诺写进 README 顶部并作为卖点**，还提供"手动清除账单数据"入口。
   → 采纳，并升级为 brief 第 24 条 + 第 21 条的 `FinancialSummary` 隐私边界设计。

5. **前端图表用 ECharts**，包含热力图能力。
   → 提示本项目 Flutter 侧需选一个支持热力图的图表方案（见 ARCHITECTURE.md 选型）。

### 5.4 不适合本项目的设计

| 设计 | 为什么不采用 |
|---|---|
| **前后端分离 + 服务端** | 与 LOCAL FIRST 直接冲突。哪怕是 localhost 服务端，也引入进程依赖与"数据离开 App 进程"的疑虑 |
| Docker 部署 | 移动端不可行；本项目目标是装到手机上的 APK |
| 前端技术栈 Vue3 + ECharts | 本项目是 Flutter，需 Dart 生态图表库 |
| 依赖 pandas/openpyxl 在服务端解析 | 解析必须在设备本地完成 |

---

## 6. cxy0714/beancount-auto-bookkeeping

### 6.1 它解决了什么问题

把支付宝/微信/银行卡/信用卡/京东账单，通过一系列 `processor_*.py` 转换并写入 **Beancount** 复式记账格式，配套 `reclassifier.py` 做重分类。

### 6.2 实际读到的源码结构

```
脚本/
├── processor_alipay.py / processor_alipay_yue.py
├── processor_wechat.py / processor_bank*.py
├── processor_creditcard.py / processor_jingdong.py
├── bean_edit_*.py            # 各来源写 beancount
├── reclassifier.py           # 重分类引擎（12 KB）
├── rules.yaml                # 声明式规则
├── suggest_rules.py          # 规则建议
├── check_direction.py        # 收支方向校验
├── verify_accounts.py / verify_period.py
└── 生成演示数据.py / 回溯记账说明.md
原始数据/  整理后数据/  bean_files/  reports/
```

### 6.3 值得借鉴的设计

1. **声明式规则文件 `rules.yaml`** —— 这是 brief 第 11 条「分类规则必须可以重新运行」的最佳格式参照：

   ```yaml
   rules:
     - desc: 虚拟规则 - 咖啡店
       payee_contains: [示例咖啡]
       new_account: Expenses:Food
     - desc: 虚拟规则 - 影音会员
       payee_contains: [示例影音]
       goods_contains: [会员, 订阅]
       match_mode: payee_AND_goods      # 关键：支持 AND / OR 组合
       new_account: Expenses:Entertainment
   ```

   → **高价值采纳**：本项目的 `category_rules` 采用同构设计（`payee_contains` / `description_contains` / `platform` / `match_mode` / `priority`）。

2. **`match_mode` 组合匹配**（`any` / `ALL` / `payee_AND_goods`）—— 单纯的关键词 OR 匹配会把"会员"误判（影音会员 vs 健身房会员）。
   → 采纳为 `RuleMatchMode { any, all, payeeAndDescription }`。

3. **`reclassifier.py` 独立于写账流程** —— 分类是**可重跑的独立阶段**，不是解析的一部分。
   → **架构级采纳**：本项目把 `CategorizationEngine` 做成纯函数服务，输入交易列表 + 规则集，输出分类建议，可随时全量重跑。

4. **`check_direction.py` / `verify_period.py` / `verify_accounts.py`** —— 把"收支方向是否正确""期间是否连续""账户是否平衡"做成**独立可运行的校验脚本**。
   → 采纳为测试套件里的专门测试组（brief 第 39 条自检清单的"收入支出方向错误"项）。

5. **`生成演示数据.py` + `rules.yaml` 里全部使用"示例咖啡/示例超市"等虚构词** —— 演示与测试数据严格虚拟化。
   → 与 brief 第 24 条「测试数据必须全部虚构」一致，采纳（本项目 fixtures 用 `示例*` 前缀 + 明显的假单号）。

6. **多来源 processor 拆分**（`processor_jingdong.py` / `processor_creditcard.py` / `processor_bank.py`）
   → 证明"一个来源一个 processor"的扩展方式可行，本项目 Parser 层按此预留 `jd` / `bank` / `creditcard` 扩展位。

### 6.4 不适合本项目的设计

| 设计 | 为什么不采用 |
|---|---|
| **Beancount 复式记账模型** | 需要用户理解借贷方与科目树，与 brief「不是复杂会计系统」冲突。本项目用**单式流水 + 三级分类** |
| 纯脚本、无 UI | 无可视化，不符合核心价值 |
| 面向桌面命令行 | 目标是移动端 APK |
| 依赖 Beancount 生态 | 移动端无对应库 |

---

## 7. 最终采用方案（组合式设计）

### 7.1 采纳矩阵

| 能力 | 来源 | 本项目如何重新实现 |
|---|---|---|
| 金额以"分"存整数 | `lizhang` | `Money` 值对象，全链路 `int cents`，仅展示层格式化 |
| 软删除 + 撤销 | `lizhang` | `deleted_at` + 查询强制过滤 |
| 表头智能定位（扫前 N 行） | `lizhang` + `FamilyFinanceManager` | `HeaderLocator`，上限 30 行，需同时命中时间+金额 |
| 列名归一化 + 别名表 | `lizhang` | `HeaderNormalizer` + 可扩展 `columnAliases` |
| 编码回退链 | `FamilyFinanceManager` + `bill-aggregator` | `utf-8-sig → utf-8 → gb18030 → gbk` |
| 资金搬运类交易排除 | `FamilyFinanceManager` | `excludeRules` 配置化（零钱提现/信用卡还款/转账…） |
| Parser 抽象基类 | `FamilyFinanceManager` | `BillParser` ABC，返回 `ParseResult(rows, errors)` |
| SQLite CHECK 约束 + WAL | `bill-aggregator` | 全表加 CHECK，`journal_mode=WAL` |
| 手动分类保护标志位 | `bill-aggregator` | `category_source` 枚举 + `is_category_locked` |
| 两级分类 + 关键词种子 | `bill-aggregator` | 三级结构：一级/二级/`merchant_rules` |
| 极小单一职责模块切分 | `jizhang-app` | `decode/parse_*/normalize/dedup/categorize/aggregate` |
| 分析维度分类学 | `xiaoyaoprivatebill` | Dashboard / 统计 / 日历 / 时段热力图 |
| 声明式规则 + `match_mode` | `beancount-auto-bookkeeping` | `category_rules` 表 + YAML 导入导出 |
| 分类可重跑（独立阶段） | `beancount-auto-bookkeeping` | `CategorizationEngine` 纯函数服务 |
| 方向/期间/完整性校验脚本 | `beancount-auto-bookkeeping` | 专门的 `test/consistency/` 测试组 |

### 7.2 明确拒绝的设计（含理由）

| 拒绝项 | 出处 | 理由 |
|---|---|---|
| 浮点存金额（`REAL`） | `bill-aggregator` | brief 第 4 条：绝对禁止 |
| 4 字段哈希判重 | `FamilyFinanceManager` | 会误杀真实重复消费；brief 第 8 条禁止 |
| `merchant+note` 全等判重 | `lizhang` | 同上 |
| 朴素 `split(',')` 解析 CSV | `bill-aggregator` | 商品名含逗号即错位；改用 RFC 4180 解析器 |
| 跨平台自动判重 | —— | brief 第 8 条：微信 ¥38 与支付宝 ¥38 可能是两笔，**默认不跨平台判重** |
| 服务端 / 云数据库 | `xiaoyaoprivatebill`、`bill-aggregator` | brief 第一原则 LOCAL FIRST |
| 复式记账模型 | `beancount-*` | brief 第 37 条：不是复杂会计系统 |
| 把 `.db` 提交进 Git | `FamilyFinanceManager` | 隐私事故；`.gitignore` 强制排除 |
| 静默丢行 / 静默丢 0 元交易 | `bill-aggregator`、`FamilyFinanceManager` | brief 第 30 条：错误必须可见、可追溯 |

### 7.3 本项目相对所有参考项目的增量价值

1. **完整的三级分类体系**（一级 → 二级 → 商户记忆），且规则可重跑、手动分类受保护 —— 六个项目无一具备。
2. **指纹哈希去重 + 平台内唯一索引**，且默认不跨平台判重 —— 六个项目全部使用过于粗糙的判重。
3. **金额全链路整数分** + schema 迁移机制 —— `bill-aggregator` 用浮点，`lizhang` 无迁移。
4. **完整的可视化体系**（月度趋势/分类下钻/消费日历/时段热力图/大额 TOP5/商户分析）—— 只有 Web 项目有类似能力，移动端本地实现是空白。
5. **`FinancialSummary` 隐私边界 + 本地 SQL 执行的自然语言查询** —— 无任何参考项目涉及。

---

## 8. 调研过程中确认的关键事实（用于实现）

### 8.1 微信支付账单表头（CSV / XLSX）

```
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
```
- 金额列名可能是 `金额(元)`（半角括号）或 `金额（元）`（全角括号），**必须同时兼容**
- 前置若干行说明文字，真实表头不在第 1 行
- 导出文件常带 UTF-8 BOM
- `交易类型` 需排除：零钱提现、零钱充值、转入零钱通、零钱通转出、转账、信用卡还款、理财通
- `当前状态` 取值：支付成功 / 已全额退款 / 已关闭 等

### 8.2 支付宝账单表头（CSV / XLSX）

两个版本都要支持：

**旧版（网页导出，GBK 编码，前 4 行为说明）**
```
交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注,资金状态
```

**新版（App 导出，brief 中描述）**
```
交易时间,交易分类,交易对方,商品说明,收/支,金额,支付方式,交易状态,交易订单号,商家订单号,备注
```
- CSV 默认 **GBK** 编码，是最大的技术坑
- `交易状态` 含"交易关闭"需丢弃或标记
- `收/支` 取值：支出 / 收入 / 不计收支

### 8.3 环境事实（本机实测）

- Flutter / Dart / Java / Android SDK **均未安装**，需从零搭建
- `storage.googleapis.com`、`storage.flutter-io.cn`、`pub.dev`、`maven.aliyun.com` 可达（HTTP 200）
- `repo1.maven.org`（Maven Central）**不可达**，Gradle 需配置阿里云镜像
- 磁盘可用 174 GB

---

## 9. 参考项目清单（供后续查阅）

| 项目 | 地址 |
|---|---|
| MageGojo/lizhang | https://github.com/MageGojo/lizhang |
| zalexrose/FamilyFinanceManager | https://github.com/zalexrose/FamilyFinanceManager |
| changdaye/bill-aggregator | https://github.com/changdaye/bill-aggregator |
| lemon970/jizhang-app | https://github.com/lemon970/jizhang-app |
| dtsola/xiaoyaoprivatebill | https://github.com/dtsola/xiaoyaoprivatebill |
| cxy0714/beancount-auto-bookkeeping | https://github.com/cxy0714/beancount-auto-bookkeeping |
| （间接来源）Hessel2333/alipay_record_analysis | https://github.com/Hessel2333/alipay_record_analysis |
| （间接来源）AutoAccountingOrg/AutoAccounting | https://github.com/AutoAccountingOrg/AutoAccounting |
