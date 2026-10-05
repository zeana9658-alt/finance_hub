import 'dart:io';

import 'package:finance_hub/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 模拟 Android 框架 `SQLiteDatabase.execSQL()` 的语义。
///
/// AOSP `android_database_SQLiteConnection.cpp` 的
/// `executeNonQuery(..., isPragmaStmt)` **只在 `isPragmaStmt == true` 时**
/// 排空结果行；而 `execSQL` 走的是
/// `nativeExecuteForChangedRowCount` → `executeNonQuery(..., false)`。
/// 于是任何**会返回结果集**的语句都会抛：
///
/// ```
/// Queries can be performed using SQLiteDatabase query or rawQuery methods only.
/// ```
///
/// 这个假 executor 就是把这条规则搬进测试里 —— 它让"手机端打不开数据库"
/// 这个 bug 可以在 Windows 上被单元测试抓住。
/// 只记录、不做任何校验的 executor —— 对应桌面端（FFI）的行为：
/// 原生 sqlite3 能正常处理返回结果行的 PRAGMA。
class _RecordingExecutor {
  final List<String> statements = <String>[];

  Future<void> execute(String sql) async {
    statements.add(sql);
  }
}

/// 在 [_RecordingExecutor] 之上叠加 Android 的 `execSQL` 限制。
class _AndroidExecSqlExecutor extends _RecordingExecutor {
  static final RegExp _pragmaPattern = RegExp(
    r'^\s*PRAGMA\s+([a-z_]+)\s*(?:\(\s*([a-z_]+)\s*\)|=|;|$)',
    caseSensitive: false,
  );

  /// 会返回结果集的 PRAGMA（取自 SQLite 官方 pragma 文档）。
  /// 本项目只会踩到 `journal_mode` 这一个，其余留着防止以后引入同类问题。
  static const Set<String> _rowReturningPragmas = <String>{
    'journal_mode',
    'page_count',
    'page_size',
    'user_version',
    'schema_version',
    'foreign_key_check',
    'integrity_check',
    'quick_check',
  };

  @override
  Future<void> execute(String sql) async {
    statements.add(sql);
    final match = _pragmaPattern.firstMatch(sql);
    if (match == null) {
      return;
    }
    final name = (match.group(2) ?? match.group(1))!.toLowerCase();
    if (_rowReturningPragmas.contains(name)) {
      throw _AndroidSqlException(
        'Queries can be performed using SQLiteDatabase query or '
        'rawQuery methods only.',
      );
    }
  }
}

class _AndroidSqlException implements Exception {
  _AndroidSqlException(this.message);

  final String message;

  @override
  String toString() => 'SQLiteException: $message';
}

void main() {
  group('configurePragmas —— Android 与桌面的 PRAGMA 差异', () {
    test('假 executor 本身有效：它确实会拒绝 journal_mode', () async {
      // 这是"对测试的测试"。没有这一条，下面两个用例可能只是假绿灯：
      // 如果假 executor 什么都不拦，Android 用例就会无意义地通过。
      final executor = _AndroidExecSqlExecutor();

      await expectLater(
        executor.execute('PRAGMA journal_mode = WAL'),
        throwsA(isA<_AndroidSqlException>()),
      );
    });

    test('Android：只设置 foreign_keys，不触碰 journal_mode', () async {
      final executor = _AndroidExecSqlExecutor();

      // 这是回归断言的核心：修复前这里会抛异常，整个 openDatabase 失败。
      await AppDatabase.configurePragmas(executor.execute, isAndroid: true);

      expect(executor.statements, <String>['PRAGMA foreign_keys = ON']);
      expect(
        executor.statements.any((String s) => s.contains('journal_mode')),
        isFalse,
        reason: 'Android 上执行 PRAGMA journal_mode 会让 openDatabase 直接抛异常',
      );
    });

    test('桌面：foreign_keys 与 WAL 都设置', () async {
      final executor = _RecordingExecutor();

      await AppDatabase.configurePragmas(executor.execute, isAndroid: false);

      expect(executor.statements, <String>[
        'PRAGMA foreign_keys = ON',
        'PRAGMA journal_mode = WAL',
      ]);
    });
  });

  group('桌面端真实打开数据库（FFI）', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('桌面仍启用 WAL，且外键约束为 ON', () async {
      final tempDir = await Directory.systemTemp.createTemp('fh_pragma_');
      final database = AppDatabase(
        databasePath: p.join(tempDir.path, 'pragma.sqlite'),
      );
      addTearDown(() async {
        await database.close();
      });

      final db = await database.open();

      final journalMode = await db.rawQuery('PRAGMA journal_mode');
      expect(
        (journalMode.first.values.first as String).toLowerCase(),
        'wal',
        reason: '桌面端（FFI）应保持 WAL，行为不能因为本次修复而回退',
      );

      final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
      expect(foreignKeys.first.values.first, 1);

      // 迁移确实跑完了 —— 证明"打开数据库"这条链路整体是通的。
      final ledger = await db.rawQuery('SELECT COUNT(*) AS n FROM schema_migrations');
      expect(ledger.first['n'], greaterThan(0));
    });
  });
}
