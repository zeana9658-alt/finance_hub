import 'package:finance_hub/domain/entities/budget.dart';

/// 预算仓储接口（由 data 层实现）。
abstract class BudgetRepository {
  /// 全部启用的预算。
  Future<List<Budget>> loadActive();

  /// 新增或更新（有 id 则更新），返回 id。
  Future<int> upsert(Budget budget);

  /// 物理删除（预算是用户自己设的，删除是合理操作）。
  Future<void> remove(int id);

  /// 启用/停用。
  Future<void> setActive(int id, bool active);
}
