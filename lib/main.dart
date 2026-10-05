import 'package:finance_hub/app/app.dart';
import 'package:finance_hub/core/logger/app_logger.dart';
import 'package:finance_hub/data/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 入口。
///
/// 启动顺序：
/// 1. 绑定 Flutter 引擎
/// 2. 配置数据库工厂（Windows/Linux 需要 sqflite FFI）
/// 3. 设置日志级别（release 下只保留 WARN 及以上，避免把账单信息写进日志）
/// 4. 挂载 ProviderScope
///
/// **注意**：这里不做任何网络初始化 —— 本应用是 LOCAL FIRST，
/// 见 docs/PRIVACY.md。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  AppDatabase.configureFactory();

  const bool isRelease = bool.fromEnvironment('dart.vm.product');
  AppLogger.minLevel = isRelease ? LogLevel.warn : LogLevel.debug;

  runApp(const ProviderScope(child: FinanceHubApp()));
}
