import 'package:finance_hub/domain/entities/category.dart';

/// 分类仓储接口（由 data 层实现）。
///
/// 分类树在导入预览、分类下钻、预算设置、分类重跑里都要用，
/// 且需要频繁的 `id → name` 映射（预览列表要显示中文名）。
abstract class CategoryRepository {
  /// 全部启用的分类（一级 + 二级），按 `level, sort_order` 排序。
  Future<List<Category>> loadAll();

  /// 只取一级分类。
  Future<List<Category>> topLevel({CategoryKind? kind});

  /// 取某个一级分类下的二级分类。
  Future<List<Category>> childrenOf(int parentId);

  /// `id → name` 映射，供列表渲染与导入预览使用。
  Future<Map<int, String>> nameMap();

  /// 新增分类，返回新 id。
  Future<int> create(Category category);

  /// 更新分类。
  Future<void> update(Category category);

  /// 停用（软删）分类。内置分类不允许物理删除。
  Future<void> deactivate(int id);

  /// 是否存在同名的一级分类。
  Future<bool> topLevelNameExists(String name);
}
