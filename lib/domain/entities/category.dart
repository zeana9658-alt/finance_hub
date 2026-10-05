/// 分类的收支属性。
///
/// 取值与 `transactions.transaction_type` 保持一致，因为用户在编辑某类交易时，
/// 分类选择器要按这个属性过滤（编辑「转账」时应该看到「转账」分类）。
enum CategoryKind {
  income('income', '收入'),
  expense('expense', '支出'),
  transfer('transfer', '转账'),
  refund('refund', '退款');

  const CategoryKind(this.code, this.label);

  final String code;
  final String label;

  static CategoryKind? fromCode(String? code) {
    if (code == null) {
      return null;
    }
    for (final value in CategoryKind.values) {
      if (value.code == code) {
        return value;
      }
    }
    return null;
  }

  @override
  String toString() => label;
}

/// 分类实体 —— 支持两级（一级 / 二级）。
///
/// 第三级不是分类，而是**商户记忆规则**（见 [MerchantRule]），
/// 这对应 brief 第 9 条要求的「一级分类 → 二级分类 → 商户记忆规则」三级结构。
class Category {
  const Category({
    this.id,
    required this.name,
    this.parentId,
    required this.level,
    required this.kind,
    this.icon,
    this.color,
    this.sortOrder = 0,
    this.isSystem = false,
    this.isActive = true,
  });

  final int? id;
  final String name;
  final int? parentId;

  /// 1 = 一级分类，2 = 二级分类。
  final int level;

  final CategoryKind kind;

  /// 图标标识（emoji 或图标名）。
  final String? icon;

  /// 展示色（十六进制字符串，如 `#3D6B5C`）。
  final String? color;

  final int sortOrder;

  /// 是否系统内置（内置分类不可删除，只能禁用）。
  final bool isSystem;

  final bool isActive;

  bool get isTopLevel => level == 1;

  Category copyWith({
    int? id,
    String? name,
    int? parentId,
    int? level,
    CategoryKind? kind,
    String? icon,
    String? color,
    int? sortOrder,
    bool? isSystem,
    bool? isActive,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      level: level ?? this.level,
      kind: kind ?? this.kind,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      isSystem: isSystem ?? this.isSystem,
      isActive: isActive ?? this.isActive,
    );
  }

  factory Category.fromMap(Map<String, Object?> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      parentId: map['parent_id'] as int?,
      level: map['level'] as int? ?? 1,
      kind: CategoryKind.fromCode(map['kind'] as String?) ?? CategoryKind.expense,
      icon: map['icon'] as String?,
      color: map['color'] as String?,
      sortOrder: map['sort_order'] as int? ?? 0,
      isSystem: (map['is_system'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'parent_id': parentId,
      'level': level,
      'kind': kind.code,
      'icon': icon,
      'color': color,
      'sort_order': sortOrder,
      'is_system': isSystem ? 1 : 0,
      'is_active': isActive ? 1 : 0,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == id &&
          other.name == name &&
          other.parentId == parentId &&
          other.level == level &&
          other.kind == kind);

  @override
  int get hashCode => Object.hash(id, name, parentId, level, kind);

  @override
  String toString() => 'Category($name, level=$level, kind=${kind.code})';
}
