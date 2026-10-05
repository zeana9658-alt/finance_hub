# DATABASE.md — 数据库设计

> 引擎：SQLite（Android 走 `sqflite` 原生，Windows 走 `sqflite_common_ffi`）
> 金额单位：**分（INTEGER）**。绝对禁止浮点。
> 时间存储：**epoch 毫秒（INTEGER）**，另存原始字符串用于排查。
> 迁移：版本化 `Migration` 列表，见 §7。

---

## 1. 表清单

| # | 表名 | 用途 | 关键约束 |
|---|---|---|---|
| 1 | `transactions` | 统一交易流水 | `unique_key` 部分唯一索引 |
| 2 | `categories` | 一级/二级分类（自引用） | `UNIQUE(parent_id, name)` |
| 3 | `category_rules` | 关键词分类规则（可重跑） | `priority` 决定顺序 |
| 4 | `merchant_rules` | 商户记忆（第一优先级） | `UNIQUE(merchant_key, source)` |
| 5 | `accounts` | 账户（支付宝/微信/储蓄卡/信用卡/现金） | 只存卡号掩码 |
| 6 | `budgets` | 分类预算 | 每分类每周期唯一 |
| 7 | `financial_goals` | 储蓄目标 | |
| 8 | `import_records` | 每次导入的审计记录 | |
| 9 | `app_settings` | 键值设置 | |
| 10 | `backup_records` | 备份历史 | |
| — | `schema_migrations` | 迁移版本台账 | |

---

## 2. 完整 DDL（v1）

### 2.1 transactions —— 核心表

```sql
CREATE TABLE transactions (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,

  -- 来源
  source                TEXT    NOT NULL
                        CHECK (source IN ('wechat','alipay','bank','credit_card','jd','manual')),
  source_transaction_id TEXT,                          -- 微信交易单号 / 支付宝交易订单号
  unique_key            TEXT    NOT NULL,              -- ★ 去重指纹，见 §3

  -- 时间
  transaction_time      INTEGER NOT NULL,              -- epoch ms（本地时间）
  transaction_time_raw  TEXT    NOT NULL DEFAULT '',   -- 原始字符串，排查用

  -- 类型与金额
  transaction_type      TEXT    NOT NULL
                        CHECK (transaction_type IN ('income','expense','transfer','refund')),
  transaction_type_raw  TEXT    NOT NULL DEFAULT '',   -- 平台原始类型文本（如"商户消费"）
  amount_cents          INTEGER NOT NULL CHECK (amount_cents >= 0),  -- ★ 单位：分
  currency              TEXT    NOT NULL DEFAULT 'CNY',

  -- 描述
  merchant              TEXT    NOT NULL DEFAULT '',
  description           TEXT    NOT NULL DEFAULT '',

  -- 分类
  category_id           INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  subcategory_id        INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  category_source       TEXT    NOT NULL DEFAULT 'fallback'
                        CHECK (category_source IN
                          ('manual','merchant_memory','platform','keyword','ai','fallback')),

  -- 账户与支付
  account_id            INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
  payment_method        TEXT    NOT NULL DEFAULT '',

  -- 状态
  status                TEXT    NOT NULL DEFAULT 'success'
                        CHECK (status IN ('success','closed','failed','pending','refunded')),

  -- 其他
  location              TEXT,
  note                  TEXT    NOT NULL DEFAULT '',
  raw_data              TEXT,                          -- 原始行 JSON（完整留档）

  -- 软删除 + 审计
  deleted_at            INTEGER,
  created_at            INTEGER NOT NULL,
  updated_at            INTEGER NOT NULL
);
```

> `category_source = 'manual'` 是**分类重跑时必须跳过的行**（brief 第 11 条）。
> 参考自 `bill-aggregator` 的 `is_manual_category`，升级为可区分 6 种来源的枚举。

### 2.2 索引

```sql
-- ★ 去重核心：部分唯一索引（软删除后允许重新导入）
CREATE UNIQUE INDEX ux_transactions_unique_key
  ON transactions(unique_key) WHERE deleted_at IS NULL;

CREATE INDEX ix_transactions_time        ON transactions(transaction_time DESC);
CREATE INDEX ix_transactions_active_time ON transactions(deleted_at, transaction_time DESC);
CREATE INDEX ix_transactions_type        ON transactions(transaction_type);
CREATE INDEX ix_transactions_source      ON transactions(source);
CREATE INDEX ix_transactions_category    ON transactions(category_id);
CREATE INDEX ix_transactions_subcategory ON transactions(subcategory_id);
CREATE INDEX ix_transactions_merchant    ON transactions(merchant);
CREATE INDEX ix_transactions_src_txnid   ON transactions(source, source_transaction_id);
CREATE INDEX ix_transactions_amount      ON transactions(amount_cents DESC);
```

**为什么用部分唯一索引而不是普通唯一索引**：
普通唯一索引下，用户删除一笔交易后重新导入同一文件会被永久阻断。
`WHERE deleted_at IS NULL` 让"已删除的历史行"不参与唯一性判定，既防重复导入、又允许用户反悔。

### 2.3 categories —— 自引用两级分类

```sql
CREATE TABLE categories (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  parent_id   INTEGER REFERENCES categories(id) ON DELETE CASCADE,
  level       INTEGER NOT NULL CHECK (level IN (1,2)),   -- 第三级是 merchant_rules
  name        TEXT    NOT NULL,
  kind        TEXT    NOT NULL CHECK (kind IN ('income','expense')),
  icon        TEXT,
  color       TEXT,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  is_system   INTEGER NOT NULL DEFAULT 0,
  is_active   INTEGER NOT NULL DEFAULT 1,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  UNIQUE(parent_id, name)
);
CREATE INDEX ix_categories_parent ON categories(parent_id, sort_order);
CREATE INDEX ix_categories_kind   ON categories(kind, level, sort_order);
```

> `UNIQUE(parent_id, name)`：SQLite 中 `NULL` 不参与唯一性比较，因此**一级分类（`parent_id IS NULL`）不会被去重**。
> 因此一级分类唯一性由 **seed 时判重 + 应用层校验** 保证（见 `m002_seed_categories.dart`）。

### 2.4 category_rules —— 可重跑的关键词规则

```sql
CREATE TABLE category_rules (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  name                  TEXT    NOT NULL,
  enabled               INTEGER NOT NULL DEFAULT 1,
  priority              INTEGER NOT NULL DEFAULT 100,   -- 越小越先匹配
  source                TEXT    NOT NULL DEFAULT 'any'
                        CHECK (source IN ('wechat','alipay','bank','credit_card','jd','manual','any')),
  merchant_contains     TEXT,                           -- JSON 字符串数组
  description_contains  TEXT,                           -- JSON 字符串数组
  amount_min_cents      INTEGER,
  amount_max_cents      INTEGER,
  direction             TEXT    NOT NULL DEFAULT 'any'
                        CHECK (direction IN ('income','expense','transfer','refund','any')),
  match_mode            TEXT    NOT NULL DEFAULT 'any'
                        CHECK (match_mode IN ('any','all','merchant_and_description')),
  target_category_id    INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  target_subcategory_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  hit_count             INTEGER NOT NULL DEFAULT 0,
  is_builtin            INTEGER NOT NULL DEFAULT 0,
  created_at            INTEGER NOT NULL,
  updated_at            INTEGER NOT NULL
);
CREATE INDEX ix_rules_order ON category_rules(enabled, priority);
```

`match_mode` 借鉴自 `cxy0714/beancount-auto-bookkeeping` 的 `rules.yaml`：
- `any`：任一条件命中即可
- `all`：所有已设置条件都需命中
- `merchant_and_description`：商户与描述必须同时命中（防止"会员"这类泛词误伤）

### 2.5 merchant_rules —— 商户记忆（分类第一优先级）

```sql
CREATE TABLE merchant_rules (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  merchant_key     TEXT    NOT NULL,          -- 归一化键（小写、去空格、去符号）
  merchant_display TEXT    NOT NULL,          -- 展示名
  source           TEXT    NOT NULL DEFAULT 'any'
                   CHECK (source IN ('wechat','alipay','bank','credit_card','jd','manual','any')),
  category_id      INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  subcategory_id   INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  confidence       INTEGER NOT NULL DEFAULT 100,
  applied_count    INTEGER NOT NULL DEFAULT 0,
  last_applied_at  INTEGER,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,
  UNIQUE(merchant_key, source)
);
CREATE INDEX ix_merchant_rules_key ON merchant_rules(merchant_key);
```

> 用户在预览页把「Lawson」改成「餐饮/便利店」→ 写入本表。
> 之后所有 Lawson 交易自动归类，`category_source = 'merchant_memory'`。

### 2.6 accounts

```sql
CREATE TABLE accounts (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT    NOT NULL UNIQUE,
  type          TEXT    NOT NULL
                CHECK (type IN ('alipay','wechat','debit_card','credit_card','cash','other')),
  masked_number TEXT,                    -- ★ 只存掩码，如 "**** 1234"
  issuer        TEXT,
  currency      TEXT    NOT NULL DEFAULT 'CNY',
  is_default    INTEGER NOT NULL DEFAULT 0,
  is_active     INTEGER NOT NULL DEFAULT 1,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
```

### 2.7 budgets

```sql
CREATE TABLE budgets (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  category_id    INTEGER REFERENCES categories(id) ON DELETE CASCADE,
  subcategory_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  amount_cents   INTEGER NOT NULL CHECK (amount_cents > 0),
  period         TEXT    NOT NULL CHECK (period IN ('daily','weekly','monthly','yearly')),
  start_date     INTEGER NOT NULL,
  end_date       INTEGER,
  rollover       INTEGER NOT NULL DEFAULT 0,
  is_active      INTEGER NOT NULL DEFAULT 1,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
-- 同一分类同一周期只允许一条启用预算
CREATE UNIQUE INDEX ux_budgets_category_period
  ON budgets(category_id, period) WHERE is_active = 1 AND category_id IS NOT NULL;
```

### 2.8 financial_goals

```sql
CREATE TABLE financial_goals (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT    NOT NULL,
  target_cents  INTEGER NOT NULL CHECK (target_cents > 0),
  current_cents INTEGER NOT NULL DEFAULT 0 CHECK (current_cents >= 0),
  deadline      INTEGER,
  status        TEXT    NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','achieved','archived')),
  note          TEXT    NOT NULL DEFAULT '',
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
```

### 2.9 import_records —— 导入审计

```sql
CREATE TABLE import_records (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  file_name       TEXT    NOT NULL,
  file_size       INTEGER,
  file_hash       TEXT,                    -- 文件内容 sha1，用于提示"该文件已导入过"
  source          TEXT    NOT NULL,
  detected_by     TEXT,                    -- 'header' | 'filename' | 'manual'
  import_method   TEXT    NOT NULL CHECK (import_method IN ('file','paste','restore')),
  imported_at     INTEGER NOT NULL,
  total_rows      INTEGER NOT NULL DEFAULT 0,
  success_count   INTEGER NOT NULL DEFAULT 0,
  duplicate_count INTEGER NOT NULL DEFAULT 0,
  error_count     INTEGER NOT NULL DEFAULT 0,
  income_cents    INTEGER NOT NULL DEFAULT 0,
  expense_cents   INTEGER NOT NULL DEFAULT 0,
  status          TEXT    NOT NULL
                  CHECK (status IN ('preview','completed','cancelled','failed')),
  error_detail    TEXT,                    -- JSON: [{row, raw, reason}]
  created_at      INTEGER NOT NULL
);
CREATE INDEX ix_import_records_time ON import_records(imported_at DESC);
CREATE INDEX ix_import_records_hash ON import_records(file_hash);
```

### 2.10 app_settings

```sql
CREATE TABLE app_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

### 2.11 backup_records

```sql
CREATE TABLE backup_records (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  file_name         TEXT    NOT NULL,
  file_path         TEXT    NOT NULL,
  format            TEXT    NOT NULL CHECK (format IN ('json','csv','xlsx')),
  size_bytes        INTEGER NOT NULL DEFAULT 0,
  transaction_count INTEGER NOT NULL DEFAULT 0,
  includes          TEXT    NOT NULL,     -- JSON 数组
  created_at        INTEGER NOT NULL
);
```

### 2.12 schema_migrations

```sql
CREATE TABLE schema_migrations (
  version    INTEGER PRIMARY KEY,
  name       TEXT    NOT NULL,
  applied_at INTEGER NOT NULL
);
```

---

## 3. ★ 去重指纹（unique_key）设计

这是全项目最关键的算法，brief 第 8 条有硬约束。

### 3.1 生成规则（按优先级）

```
① source_transaction_id 非空
   unique_key = "src:" + source + ":" + normalize(source_transaction_id)

② 否则 —— fallback 指纹
   unique_key = "fp:" + sha1( join("|", [
        source,
        transaction_time,      // epoch ms
        amount_cents,
        merchant,
        description,
        payment_method,
   ]))
```

字段顺序与内容**严格对齐 brief 第 8 条**：`source / transaction_time / amount / merchant / description / payment_method`。

### 3.2 为什么 `source` 必须在指纹里（跨平台安全）

brief 明确要求：微信「麦当劳 ¥38」与支付宝「麦当劳 ¥38」可能是**两笔不同交易**。

因为 `source` 参与指纹计算：

| 交易 | source | 指纹 | 结果 |
|---|---|---|---|
| 微信 麦当劳 ¥38 | wechat | `fp:a1b2...` | 不同 key |
| 支付宝 麦当劳 ¥38 | alipay | `fp:c3d4...` | 不同 key |

→ **天然不会跨平台误判**。这与 `FamilyFinanceManager` / `lizhang` 的 4 字段哈希（不含 source）有本质区别。

### 3.3 两级判重

| 级别 | 判定 | 行为 |
|---|---|---|
| **强重复（blocking）** | `unique_key` 命中库中已有行，或本批次内重复 | 标记 `duplicate`，**默认不勾选** |
| **疑似跨平台重复（advisory）** | 同一天 + 同金额 + 同商户，但 `source` 不同 | 标记 `suspectedCrossPlatform`，**仍默认勾选导入**，UI 显示黄色提示让用户自己决定 |

### 3.4 写入时的兜底

即使预览阶段判重有漏，写入时仍用 `INSERT OR IGNORE` + 部分唯一索引兜底：

```sql
INSERT OR IGNORE INTO transactions (...) VALUES (...);
```
返回 `rowid = 0` 表示被唯一索引拦截，计入"实际跳过"数并如实反馈给用户。

### 3.5 归一化细节

- `source_transaction_id`：去掉首尾空格、去掉 `\t`、全角转半角、统一大写
- `merchant`：去首尾空格、内部连续空白折叠为单个空格（**不转小写** —— 商户名大小写有语义）
- `description`：同上
- `payment_method`：同上
- `transaction_time`：必须用**解析后的 epoch ms**，不能用原始字符串（`2026/10/05` 与 `2026-10-05` 应视为同一时刻）

---

## 4. 分类种子数据

### 4.1 一级分类（17 个，按 brief 第 9 条）

| 一级分类 | kind | 二级分类 |
|---|---|---|
| 餐饮 | expense | 正餐 / 快餐 / 外卖 / 咖啡茶饮 / 零食 / 便利店 |
| 交通 | expense | 公共交通 / 地铁 / 公交 / 打车 / 火车 / 飞机 / 加油 |
| 购物 | expense | 电商 / 日用品 / 服饰 / 数码 / 其他 |
| 娱乐 | expense | 影音会员 / 游戏 / 演出展览 / 旅游景点 / 运动健身 |
| 居住 | expense | 房租 / 物业 / 水电燃气 / 家具家电 |
| 生活缴费 | expense | 话费流量 / 宽带 / 快递 / 其他缴费 |
| 医疗健康 | expense | 门诊 / 药品 / 体检 / 保险 |
| 学习教育 | expense | 课程培训 / 书籍文具 / 考试报名 |
| 通讯 | expense | 手机话费 / 流量充值 / 宽带 |
| 旅行 | expense | 机票 / 酒店 / 门票 / 当地交通 |
| 工资 | income | — |
| 奖金 | income | — |
| 投资 | income | 理财收益 / 分红 |
| 转账 | transfer | 转出 / 转入 |
| 退款 | refund | — |
| 报销 | income | — |
| 其他 | expense | 其他支出 / 其他收入 |

### 4.2 内置关键词规则种子（示例）

```json
[
  { "name":"快餐连锁",   "priority":20, "merchant_contains":["麦当劳","肯德基","汉堡王","华莱士"],
    "target":["餐饮","快餐"] },
  { "name":"咖啡茶饮",   "priority":20, "merchant_contains":["瑞幸","星巴克","喜茶","奈雪","蜜雪冰城","库迪"],
    "target":["餐饮","咖啡茶饮"] },
  { "name":"外卖平台",   "priority":25, "merchant_contains":["美团","饿了么"],
    "description_contains":["外卖"], "match_mode":"merchant_and_description",
    "target":["餐饮","外卖"] },
  { "name":"网约车",     "priority":20, "merchant_contains":["滴滴","高德打车","曹操出行","T3出行"],
    "target":["交通","打车"] },
  { "name":"电商平台",   "priority":30, "merchant_contains":["淘宝","天猫","京东","拼多多","唯品会","苏宁"],
    "target":["购物","电商"] },
  { "name":"便利店",     "priority":25, "merchant_contains":["罗森","Lawson","全家","FamilyMart","7-ELEVEN","便利蜂"],
    "target":["餐饮","便利店"] },
  { "name":"公共交通",   "priority":20, "merchant_contains":["地铁","公交","一卡通","交通卡"],
    "target":["交通","公共交通"] }
]
```

> 所有种子规则 `is_builtin = 1`，用户可禁用但不可删除（删除按钮置灰），避免误删后无法恢复。

---

## 5. 典型查询

```sql
-- 月度收支合计
SELECT transaction_type, SUM(amount_cents) AS total
FROM transactions
WHERE deleted_at IS NULL
  AND transaction_time >= ? AND transaction_time < ?
  AND transaction_type IN ('income','expense')
GROUP BY transaction_type;

-- 分类占比（带二级下钻）
SELECT c.id, c.name, SUM(t.amount_cents) AS total, COUNT(*) AS cnt
FROM transactions t
JOIN categories c ON c.id = t.category_id
WHERE t.deleted_at IS NULL
  AND t.transaction_type = 'expense'
  AND t.transaction_time >= ? AND t.transaction_time < ?
GROUP BY c.id
ORDER BY total DESC;

-- 消费日历（按天聚合）
SELECT date(transaction_time / 1000, 'unixepoch', 'localtime') AS day,
       SUM(CASE WHEN transaction_type='income'  THEN amount_cents ELSE 0 END) AS income,
       SUM(CASE WHEN transaction_type='expense' THEN amount_cents ELSE 0 END) AS expense
FROM transactions
WHERE deleted_at IS NULL AND transaction_time >= ? AND transaction_time < ?
GROUP BY day ORDER BY day;

-- 消费时段分布（7 个时段分桶）
SELECT
  CASE
    WHEN CAST(strftime('%H', transaction_time/1000, 'unixepoch','localtime') AS INTEGER) < 6  THEN 0
    WHEN CAST(strftime('%H', transaction_time/1000, 'unixepoch','localtime') AS INTEGER) < 9  THEN 1
    WHEN CAST(strftime('%H', transaction_time/1000, 'unixepoch','localtime') AS INTEGER) < 12 THEN 2
    WHEN CAST(strftime('%H', transaction_time/1000, 'unixepoch','localtime') AS INTEGER) < 15 THEN 3
    WHEN CAST(strftime('%H', transaction_time/1000, 'unixepoch','localtime') AS INTEGER) < 18 THEN 4
    WHEN CAST(strftime('%H', transaction_time/1000, 'unixepoch','localtime') AS INTEGER) < 21 THEN 5
    ELSE 6
  END AS bucket,
  SUM(amount_cents) AS total, COUNT(*) AS cnt
FROM transactions
WHERE deleted_at IS NULL AND transaction_type = 'expense' AND transaction_time >= ?
GROUP BY bucket;

-- 大额支出 TOP 5
SELECT id, merchant, description, amount_cents, transaction_time
FROM transactions
WHERE deleted_at IS NULL AND transaction_type = 'expense'
  AND transaction_time >= ? AND transaction_time < ?
ORDER BY amount_cents DESC LIMIT 5;

-- 商户分析
SELECT merchant, SUM(amount_cents) AS total, COUNT(*) AS cnt,
       AVG(amount_cents) AS avg_cents, MAX(transaction_time) AS last_at
FROM transactions
WHERE deleted_at IS NULL AND transaction_type = 'expense' AND merchant = ?
GROUP BY merchant;
```

> 注意：`date()/strftime()` 的 `'localtime'` 修饰符依赖 SQLite 的本地时区解析。
> 若跨时区表现不一致，改为**在 Dart 侧传入月份边界 epoch 毫秒**做范围过滤，再在 SQL 里按 `strftime` 分组（本项目采用后者，见 §6）。

---

## 6. 时间与时区策略

| 决策 | 说明 |
|---|---|
| 存储 | `transaction_time` 存 **epoch 毫秒**（由本地时间构造） |
| 保留原文 | `transaction_time_raw` 保留平台原始字符串，排查时对照 |
| 解析 | 账单里的时间视为**用户本地时间**（账单本身就是本地时间） |
| 分组 | 月度/日历分组时，由 Dart 侧计算月份/日期边界 epoch，SQL 只做范围过滤 |
| 禁止 | 不使用 `DateTime.now()` 兜底填充解析失败的时间 —— 解析失败必须记为错误行 |

---

## 7. 迁移机制

不使用 `sqflite` 的 `onCreate`/`onUpgrade` 内联 SQL，而是**版本化 Migration 列表**：

```dart
abstract class Migration {
  int get version;
  String get name;
  Future<void> up(DatabaseExecutor db);
}

const migrations = <Migration>[
  M001Initial(),          // 建表 + 索引
  M002SeedCategories(),   // 种子分类 + 内置规则
  // 后续：M003AddXxx()
];
```

`AppDatabase.open()` 流程：

```
1. 读取 PRAGMA user_version
2. 建 schema_migrations 表（若不存在）
3. 对所有 version > user_version 的 Migration 依次执行（各自包在事务里）
4. 每条成功后在 schema_migrations 落一条记录
5. 更新 PRAGMA user_version = 最大 version
```

**铁律**：已发布的 Migration 文件**永不修改**，只追加新文件。修改历史迁移会导致老用户与新用户 schema 分叉。

### 7.1 ★ PRAGMA 的平台差异（Android 不能执行 `PRAGMA journal_mode`）

`AppDatabase.configurePragmas()` 是唯一设置 PRAGMA 的地方，它**必须区分平台**：

```dart
await execute('PRAGMA foreign_keys = ON');   // 两个平台都安全
if (isAndroid) return;                        // Android 到此为止
await execute('PRAGMA journal_mode = WAL');   // 只有桌面
```

**原因**：sqflite 在 Android 上把 `execute()` 映射到 `SQLiteDatabase.execSQL()`：

```
execSQL → executeSql → SQLiteStatement.executeUpdateDelete()
        → SQLiteSession.executeForChangedRowCount
        → nativeExecuteForChangedRowCount(..., isPragmaStmt = false)
        → executeNonQuery(..., isPragmaStmt = false)
```

AOSP `android_database_SQLiteConnection.cpp` 的 `executeNonQuery` **只在
`isPragmaStmt == true` 时排空结果行**；否则一旦 `sqlite3_step` 返回
`SQLITE_ROW` 就抛：

```
SQLiteException: Queries can be performed using SQLiteDatabase query or rawQuery methods only.
```

`PRAGMA journal_mode = WAL` 会返回一行（`'wal'`），所以在 Android 上这一句会让
**整个 `openDatabase` 失败** —— 表现为「数据库打开失败」，首页/账单/统计全部读不到数据。

桌面走 `sqflite_common_ffi`，`execute` 直接落到原生 sqlite3 C API，会正常步进并丢弃结果行，
因此**这个错误在桌面上完全看不到** —— 这正是「Windows 构建能跑、手机一装就报错」的原因。

**为什么 Android 上不启用 WAL（三个理由）**：

1. Android 的 `journal_mode` 由 `SQLiteDatabase` 自己管理。AOSP `SQLiteConnection.setJournalMode()`
   的做法是 `executeForString("PRAGMA journal_mode=" + newValue, ...)` —— **走查询通道**，
   并且把返回的模式读回来校验；同时它只接受 `DELETE` / `TRUNCATE` / `PERSIST` / `WAL` 四个值
   （`SQLiteDatabase.JournalMode`）。源码里还有一句关键注释：

   > Because we always disable WAL mode when a database is first opened
   > (even if we intend to re-enable it)...

   也就是说 **Android 每次打开数据库都会先把日志模式压回 DELETE，再由框架自己决定要不要开 WAL**。
   应用层去 `PRAGMA journal_mode = WAL` 是在和框架抢方向盘 —— 官方文档也明确要求
   "do not set journal_mode using PRAGMA ... if your app is using `enableWriteAheadLogging()`"。
   要启用只能走 sqflite 的 `AndroidManifest` 开关
   （`<meta-data android:name="com.tekartik.sqflite.wal_enabled" android:value="true"/>`）。
2. **外键一致性**：`PRAGMA foreign_keys` 是 **per-connection** 的。非 WAL 时 Android
   连接池只有 1 条连接（`SQLiteDatabase.setMaxConnectionPoolSizeLocked()`），ON 能覆盖全部操作；
   一旦启用 WAL，连接池变成最多 4 条，外键约束会「时有时无」—— 而本 schema 大量依赖
   `ON DELETE CASCADE / SET NULL`，这种不确定性比失去 WAL 危险得多。
3. sqflite 自身 `Database.java` 里写着 `WAL_ENABLED_BY_DEFAULT = false`，
   注释是 "2022-09-14 experiments show several corruption issue"。

> **已中招的设备会自愈**：`setJournalMode()` 内部把 `SQLiteDatabaseLockedException`
> （`SQLITE_BUSY`，"一条连接是 WAL、另一条想改成非 WAL"）当作可预期情况吞掉并重试。
> 所以手机上前一次启动留下的 WAL 模式与 `.wal` / `.shm` 文件，会在修复后的第一次打开时
> 被框架压回 `DELETE` 并清理掉，不需要用户卸载重装（重装是最后的兜底手段）。

**回归测试**：`test/data/database_pragma_test.dart` 用一个模拟 Android `execSQL`
语义的假 executor 断言 `configurePragmas(isAndroid: true)` 不会发出 `journal_mode`，
并在真 FFI 上断言桌面端仍然启用 WAL —— 桌面行为不因本次修复回退。

---

## 8. 隐私约束（数据库层）

| 约束 | 实现 |
|---|---|
| 不存完整银行卡号 | `accounts.masked_number` 只存 `**** 1234`；导入时正则剥离 `\d{12,19}` |
| 不存身份证 | 导入清洗阶段过滤 18 位身份证模式 |
| `raw_data` 字段 | 保留原始行用于排查，**但导出备份时默认剔除**（可在设置里开启） |
| 日志 | 禁止打印 `raw_data` 与完整交易列表 |
| `.gitignore` | `imports/` `database/` `backups/` `*.db` `*.sqlite` `*.xlsx` `*.xls` `*.csv` `*.json`（`pubspec.lock` 等必要文件除外） |
| 测试数据 | `test/fixtures/` 全部虚构，商户名用 `示例*` 前缀，单号用 `TEST-*` |
