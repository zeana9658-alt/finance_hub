import 'package:finance_hub/data/database/migrations/migration.dart';
import 'package:sqflite/sqflite.dart';

/// v1 —— 建表与索引。
///
/// 完整 DDL 说明见 docs/DATABASE.md §2。
class M001Initial extends Migration {
  const M001Initial();

  @override
  int get version => 1;

  @override
  String get name => 'initial_schema';

  @override
  Future<void> up(DatabaseExecutor db) async {
    for (final statement in _statements) {
      await db.execute(statement);
    }
  }

  static const List<String> _statements = <String>[
    // ───────────────────────── 交易流水 ─────────────────────────
    '''
    CREATE TABLE transactions (
      id                    INTEGER PRIMARY KEY AUTOINCREMENT,
      source                TEXT    NOT NULL
                            CHECK (source IN ('wechat','alipay','bank','credit_card','jd','manual')),
      source_transaction_id TEXT,
      unique_key            TEXT    NOT NULL,
      transaction_time      INTEGER NOT NULL,
      transaction_time_raw  TEXT    NOT NULL DEFAULT '',
      transaction_type      TEXT    NOT NULL
                            CHECK (transaction_type IN ('income','expense','transfer','refund')),
      transaction_type_raw  TEXT    NOT NULL DEFAULT '',
      platform_category     TEXT    NOT NULL DEFAULT '',
      amount_cents          INTEGER NOT NULL CHECK (amount_cents >= 0),
      currency              TEXT    NOT NULL DEFAULT 'CNY',
      merchant              TEXT    NOT NULL DEFAULT '',
      description           TEXT    NOT NULL DEFAULT '',
      category_id           INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      subcategory_id        INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      category_source       TEXT    NOT NULL DEFAULT 'fallback'
                            CHECK (category_source IN
                              ('manual','merchant_memory','platform','keyword','ai','fallback')),
      account_id            INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
      payment_method        TEXT    NOT NULL DEFAULT '',
      status                TEXT    NOT NULL DEFAULT 'success'
                            CHECK (status IN ('success','closed','failed','pending','refunded')),
      location              TEXT,
      note                  TEXT    NOT NULL DEFAULT '',
      raw_data              TEXT,
      deleted_at            INTEGER,
      created_at            INTEGER NOT NULL,
      updated_at            INTEGER NOT NULL
    )
    ''',

    // ───────────────────────── 分类 ─────────────────────────
    '''
    CREATE TABLE categories (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_id   INTEGER REFERENCES categories(id) ON DELETE CASCADE,
      level       INTEGER NOT NULL CHECK (level IN (1,2)),
      name        TEXT    NOT NULL,
      kind        TEXT    NOT NULL
                  CHECK (kind IN ('income','expense','transfer','refund')),
      icon        TEXT,
      color       TEXT,
      sort_order  INTEGER NOT NULL DEFAULT 0,
      is_system   INTEGER NOT NULL DEFAULT 0,
      is_active   INTEGER NOT NULL DEFAULT 1,
      created_at  INTEGER NOT NULL,
      updated_at  INTEGER NOT NULL,
      UNIQUE(parent_id, name)
    )
    ''',

    // ───────────────────────── 关键词规则 ─────────────────────────
    '''
    CREATE TABLE category_rules (
      id                    INTEGER PRIMARY KEY AUTOINCREMENT,
      name                  TEXT    NOT NULL,
      enabled               INTEGER NOT NULL DEFAULT 1,
      priority              INTEGER NOT NULL DEFAULT 100,
      source                TEXT    NOT NULL DEFAULT 'any'
                            CHECK (source IN
                              ('wechat','alipay','bank','credit_card','jd','manual','any')),
      merchant_contains     TEXT,
      description_contains  TEXT,
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
    )
    ''',

    // ───────────────────────── 商户记忆 ─────────────────────────
    '''
    CREATE TABLE merchant_rules (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      merchant_key     TEXT    NOT NULL,
      merchant_display TEXT    NOT NULL,
      source           TEXT    NOT NULL DEFAULT 'any'
                       CHECK (source IN
                         ('wechat','alipay','bank','credit_card','jd','manual','any')),
      category_id      INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
      subcategory_id   INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      confidence       INTEGER NOT NULL DEFAULT 100,
      applied_count    INTEGER NOT NULL DEFAULT 0,
      last_applied_at  INTEGER,
      created_at       INTEGER NOT NULL,
      updated_at       INTEGER NOT NULL,
      UNIQUE(merchant_key, source)
    )
    ''',

    // ───────────────────────── 账户 ─────────────────────────
    '''
    CREATE TABLE accounts (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      name          TEXT    NOT NULL UNIQUE,
      type          TEXT    NOT NULL
                    CHECK (type IN ('alipay','wechat','debit_card','credit_card','cash','other')),
      masked_number TEXT,
      issuer        TEXT,
      currency      TEXT    NOT NULL DEFAULT 'CNY',
      is_default    INTEGER NOT NULL DEFAULT 0,
      is_active     INTEGER NOT NULL DEFAULT 1,
      sort_order    INTEGER NOT NULL DEFAULT 0,
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL
    )
    ''',

    // ───────────────────────── 预算 ─────────────────────────
    '''
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
    )
    ''',

    // ───────────────────────── 财务目标 ─────────────────────────
    '''
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
    )
    ''',

    // ───────────────────────── 导入记录 ─────────────────────────
    '''
    CREATE TABLE import_records (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      file_name       TEXT    NOT NULL,
      file_size       INTEGER,
      file_hash       TEXT,
      source          TEXT    NOT NULL,
      detected_by     TEXT,
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
      error_detail    TEXT,
      created_at      INTEGER NOT NULL
    )
    ''',

    // ───────────────────────── 设置 ─────────────────────────
    '''
    CREATE TABLE app_settings (
      key        TEXT PRIMARY KEY,
      value      TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',

    // ───────────────────────── 备份记录 ─────────────────────────
    '''
    CREATE TABLE backup_records (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      file_name         TEXT    NOT NULL,
      file_path         TEXT    NOT NULL,
      format            TEXT    NOT NULL CHECK (format IN ('json','csv','xlsx')),
      size_bytes        INTEGER NOT NULL DEFAULT 0,
      transaction_count INTEGER NOT NULL DEFAULT 0,
      includes          TEXT    NOT NULL,
      created_at        INTEGER NOT NULL
    )
    ''',

    // ───────────────────────── 索引 ─────────────────────────
    // ★ 去重核心：部分唯一索引 —— 软删除后允许重新导入同一笔
    '''
    CREATE UNIQUE INDEX ux_transactions_unique_key
      ON transactions(unique_key) WHERE deleted_at IS NULL
    ''',
    'CREATE INDEX ix_transactions_time        ON transactions(transaction_time DESC)',
    'CREATE INDEX ix_transactions_active_time ON transactions(deleted_at, transaction_time DESC)',
    'CREATE INDEX ix_transactions_type        ON transactions(transaction_type)',
    'CREATE INDEX ix_transactions_source      ON transactions(source)',
    'CREATE INDEX ix_transactions_category    ON transactions(category_id)',
    'CREATE INDEX ix_transactions_subcategory ON transactions(subcategory_id)',
    'CREATE INDEX ix_transactions_merchant    ON transactions(merchant)',
    'CREATE INDEX ix_transactions_src_txnid   ON transactions(source, source_transaction_id)',
    'CREATE INDEX ix_transactions_amount      ON transactions(amount_cents DESC)',
    'CREATE INDEX ix_categories_parent        ON categories(parent_id, sort_order)',
    'CREATE INDEX ix_categories_kind          ON categories(kind, level, sort_order)',
    'CREATE INDEX ix_rules_order              ON category_rules(enabled, priority)',
    'CREATE INDEX ix_merchant_rules_key       ON merchant_rules(merchant_key)',
    'CREATE INDEX ix_import_records_time      ON import_records(imported_at DESC)',
    'CREATE INDEX ix_import_records_hash      ON import_records(file_hash)',
    // 同一分类同一周期只允许一条启用预算
    '''
    CREATE UNIQUE INDEX ux_budgets_category_period
      ON budgets(category_id, period) WHERE is_active = 1 AND category_id IS NOT NULL
    ''',
  ];
}
