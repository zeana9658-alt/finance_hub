import 'dart:io';

import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/core/logger/app_logger.dart';
import 'package:finance_hub/data/database/migrations/m001_initial.dart';
import 'package:finance_hub/data/database/migrations/m002_seed_categories.dart';
import 'package:finance_hub/data/database/migrations/migration.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
// 隐藏 sqflite 自带的 DatabaseException，避免与本项目的同名异常冲突。
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide DatabaseException;

/// 数据库门面 —— 负责打开、迁移、关闭。
///
/// 设计要点（见 docs/DATABASE.md §7）：
/// - 不使用 sqflite 的 `onCreate`/`onUpgrade` 内联 SQL，而是**版本化 [Migration] 列表**
/// - 每条迁移在 `schema_migrations` 留台账，便于排查
/// - 已发布迁移永不修改，只追加
class AppDatabase {
  AppDatabase({this.databasePath, List<Migration>? migrations})
      : migrations = migrations ?? defaultMigrations;

  /// 显式指定数据库文件路径。测试时传入临时路径；生产环境为 `null`（用应用数据目录）。
  final String? databasePath;

  final List<Migration> migrations;

  sqflite.Database? _db;

  /// 正在进行中的打开操作。
  ///
  /// **必须缓存这个 Future**：多个 Provider 会在同一帧内并发调用 [open]
  /// （首页同时读汇总、分类、最近交易…）。若不合并，会发起多次
  /// `openDatabase`，导致迁移事务互相等待、数据库被锁死。
  Future<sqflite.Database>? _opening;

  /// 全部已注册迁移，按版本升序。
  static const List<Migration> defaultMigrations = <Migration>[
    M001Initial(),
    M002SeedCategories(),
  ];

  /// 当前 schema 版本 = 最大迁移版本号。
  static int get schemaVersion {
    var maxVersion = 0;
    for (final migration in defaultMigrations) {
      if (migration.version > maxVersion) {
        maxVersion = migration.version;
      }
    }
    return maxVersion;
  }

  /// 配置数据库工厂。
  ///
  /// Android/iOS 用 sqflite 原生实现；Windows/Linux 需要 FFI。
  /// 借鉴 `MageGojo/lizhang` 的 `configureDatabaseFactory`。
  static void configureFactory() {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      sqflite.databaseFactory = databaseFactoryFfi;
    }
  }

  bool get isOpen => _db != null;

  /// 打开数据库时需要应用的全部 PRAGMA。
  ///
  /// **抽成独立方法是为了可测试**：`test/data/database_pragma_test.dart`
  /// 用一个"模拟 Android 语义"的假 executor 断言这里不会发出 Android 框架
  /// 无法执行的语句。真实调用点见 [_doOpen] 的 `onConfigure`。
  ///
  /// ## 为什么必须区分平台（这是"手机端打不开账本"的根因）
  ///
  /// sqflite 在 Android 上把 `execute()` 映射到
  /// `SQLiteDatabase.execSQL()`，其内部链路是：
  ///
  /// ```
  /// execSQL → executeSql → SQLiteStatement.executeUpdateDelete()
  ///         → SQLiteSession.executeForChangedRowCount
  ///         → nativeExecuteForChangedRowCount(..., isPragmaStmt = false)
  ///         → executeNonQuery(..., isPragmaStmt = false)
  /// ```
  ///
  /// 而 AOSP `android_database_SQLiteConnection.cpp` 的 `executeNonQuery`
  /// **只在 `isPragmaStmt == true` 时排空结果行**：
  ///
  /// ```c
  /// int rc = sqlite3_step(statement);
  /// if (isPragmaStmt) { while (rc == SQLITE_ROW) rc = sqlite3_step(statement); }
  /// if (rc == SQLITE_ROW) {
  ///     throw_sqlite3_exception(env,
  ///         "Queries can be performed using SQLiteDatabase query or rawQuery methods only.");
  /// }
  /// ```
  ///
  /// `PRAGMA journal_mode = WAL` **会返回一行**（值为 `'wal'`），于是 Android
  /// 直接抛 `SQLiteException`，整个 `openDatabase` 失败 —— 应用表现为
  /// 「数据库打开失败」，首页、账单页、统计页全部读不到数据。
  ///
  /// 桌面（Windows/Linux）走 `sqflite_common_ffi`，`execute` 直接落到原生
  /// sqlite3 C API，会正常步进并丢弃结果行，所以**这个错误在桌面上完全看不到**。
  /// 这就是「Windows 构建能跑、手机一装就报错」的全部原因。
  ///
  /// ## 为什么 Android 上干脆不启用 WAL
  ///
  /// 1. 想启用只能走 sqflite 的 `AndroidManifest` 开关
  ///    （`com.tekartik.sqflite.wal_enabled`），因为 Android 侧的
  ///    `journal_mode` 由 `SQLiteDatabase` 自己管理 —— 官方明确要求
  ///    "do not set journal_mode using PRAGMA ... if your app is using
  ///    enableWriteAheadLogging()"。
  /// 2. 更重要的是**外键**：`PRAGMA foreign_keys` 是 **per-connection** 的。
  ///    非 WAL 时 Android 连接池只有 1 条连接
  ///    （`SQLiteDatabase.setMaxConnectionPoolSizeLocked()`），
  ///    本方法设置的 ON 能覆盖全部操作；一旦启用 WAL，连接池变成最多 4 条，
  ///    外键约束会变成「时有时无」—— 而本项目 schema 大量依赖
  ///    `ON DELETE CASCADE / SET NULL`（见 m001_initial.dart），
  ///    这种不确定性比失去 WAL 危险得多。
  /// 3. sqflite 自身在 `Database.java` 里也写着
  ///    `WAL_ENABLED_BY_DEFAULT = false`，注释是
  ///    "2022-09-14 experiments show several corruption issue"。
  ///
  /// 结论：Android 保持系统默认日志模式（单连接），桌面保留 WAL。
  /// 见 docs/DATABASE.md §7.1。
  @visibleForTesting
  static Future<void> configurePragmas(
    Future<void> Function(String sql) execute, {
    required bool isAndroid,
  }) async {
    // 不返回结果集 → Android 的 execSQL 可以安全执行。
    await execute('PRAGMA foreign_keys = ON');

    if (isAndroid) {
      // 见上方长注释：在 Android 上执行 PRAGMA journal_mode 会让
      // openDatabase 直接抛异常。这里必须是 return，不是 try/catch ——
      // 吞掉异常只会把「打不开数据库」变成「静默没有 WAL」，掩盖真正的问题。
      return;
    }

    // 桌面（FFI）：原生 sqlite3 能正常处理返回结果行的 PRAGMA。
    await execute('PRAGMA journal_mode = WAL');
  }

  /// 打开（或复用）数据库。并发调用会共享同一个 Future。
  Future<sqflite.Database> open() {
    final existing = _db;
    if (existing != null) {
      return Future<sqflite.Database>.value(existing);
    }
    final inFlight = _opening;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _doOpen();
    _opening = future;
    return future;
  }

  Future<sqflite.Database> _doOpen() async {
    try {
      final path = databasePath ?? await _defaultDatabasePath();
      final directory = Directory(p.dirname(path));
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }

      final ordered = List<Migration>.of(migrations)
        ..sort((a, b) => a.version.compareTo(b.version));

      final db = await sqflite.openDatabase(
        path,
        version: _maxVersionOf(ordered),
        onConfigure: (db) => configurePragmas(
          // PRAGMA 必须在任何事务之前执行，因此放在 onConfigure 而不是 onOpen。
          db.execute,
          isAndroid: Platform.isAndroid,
        ),
        onCreate: (db, version) async {
          await _ensureLedger(db);
          for (final migration in ordered) {
            await migration.up(db);
            await _record(db, migration);
            AppLogger.info('迁移已应用：v${migration.version} ${migration.name}');
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _ensureLedger(db);
          for (final migration in ordered) {
            if (migration.version <= oldVersion) {
              continue;
            }
            await migration.up(db);
            await _record(db, migration);
            AppLogger.info(
              '迁移已应用：v${migration.version} ${migration.name}'
              '（$oldVersion → $newVersion）',
            );
          }
        },
      );

      _db = db;
      return db;
    } on AppException {
      _opening = null;
      rethrow;
    } on Object catch (error) {
      _opening = null;
      throw DatabaseException('数据库打开失败', detail: '$error');
    }
  }

  /// 关闭数据库。
  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    await db?.close();
  }

  /// 应用数据目录下的默认路径。
  Future<String> _defaultDatabasePath() async {
    try {
      final directory = await getApplicationSupportDirectory();
      return p.join(directory.path, 'finance_hub.sqlite');
    } on Exception catch (error) {
      throw DatabaseException('无法确定数据库目录', detail: '$error');
    }
  }

  Future<void> _ensureLedger(sqflite.DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version    INTEGER PRIMARY KEY,
        name       TEXT    NOT NULL,
        applied_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _record(sqflite.DatabaseExecutor db, Migration migration) async {
    await db.insert('schema_migrations', <String, Object?>{
      'version': migration.version,
      'name': migration.name,
      'applied_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  int _maxVersionOf(List<Migration> ordered) {
    var maxVersion = 0;
    for (final migration in ordered) {
      if (migration.version > maxVersion) {
        maxVersion = migration.version;
      }
    }
    return maxVersion;
  }
}
