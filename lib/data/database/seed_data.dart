import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';

/// 种子二级分类。
class SeedSubcategory {
  const SeedSubcategory(this.name, {this.keywords = const <String>[]});

  final String name;

  /// 关键词仅用于内置规则生成，不直接参与匹配。
  final List<String> keywords;
}

/// 种子一级分类。
class SeedCategory {
  const SeedCategory({
    required this.name,
    required this.kind,
    required this.icon,
    required this.color,
    this.subcategories = const <SeedSubcategory>[],
  });

  final String name;
  final CategoryKind kind;
  final String icon;
  final String color;
  final List<SeedSubcategory> subcategories;
}

/// 种子关键词规则。
///
/// [targetPath] 为 `[一级分类名, 二级分类名]`，二级可为空。
class SeedRule {
  const SeedRule({
    required this.name,
    required this.priority,
    required this.targetPath,
    this.merchantContains = const <String>[],
    this.descriptionContains = const <String>[],
    this.matchMode = RuleMatchMode.any,
    this.direction,
  });

  final String name;
  final int priority;
  final List<String> targetPath;
  final List<String> merchantContains;
  final List<String> descriptionContains;
  final RuleMatchMode matchMode;
  final TransactionType? direction;
}

/// 一级分类（17 个）—— 严格对齐 brief 第 9 条。
///
/// 顺序即 UI 展示顺序。
const List<SeedCategory> seedCategories = <SeedCategory>[
  SeedCategory(
    name: '餐饮',
    kind: CategoryKind.expense,
    icon: '🍜',
    color: '#C67B5C',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('正餐'),
      SeedSubcategory('快餐'),
      SeedSubcategory('外卖'),
      SeedSubcategory('咖啡茶饮'),
      SeedSubcategory('零食'),
      SeedSubcategory('便利店'),
    ],
  ),
  SeedCategory(
    name: '交通',
    kind: CategoryKind.expense,
    icon: '🚇',
    color: '#7B8FA3',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('公共交通'),
      SeedSubcategory('地铁'),
      SeedSubcategory('公交'),
      SeedSubcategory('打车'),
      SeedSubcategory('火车'),
      SeedSubcategory('飞机'),
      SeedSubcategory('加油'),
    ],
  ),
  SeedCategory(
    name: '购物',
    kind: CategoryKind.expense,
    icon: '🛍️',
    color: '#A39BB0',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('电商'),
      SeedSubcategory('日用品'),
      SeedSubcategory('服饰'),
      SeedSubcategory('数码'),
      SeedSubcategory('其他'),
    ],
  ),
  SeedCategory(
    name: '娱乐',
    kind: CategoryKind.expense,
    icon: '🎬',
    color: '#9CAF88',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('影音会员'),
      SeedSubcategory('游戏'),
      SeedSubcategory('演出展览'),
      SeedSubcategory('旅游景点'),
      SeedSubcategory('运动健身'),
    ],
  ),
  SeedCategory(
    name: '居住',
    kind: CategoryKind.expense,
    icon: '🏠',
    color: '#8FA9A0',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('房租'),
      SeedSubcategory('物业'),
      SeedSubcategory('水电燃气'),
      SeedSubcategory('家具家电'),
    ],
  ),
  SeedCategory(
    name: '生活缴费',
    kind: CategoryKind.expense,
    icon: '🧾',
    color: '#B5A48B',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('话费流量'),
      SeedSubcategory('宽带'),
      SeedSubcategory('快递'),
      SeedSubcategory('其他缴费'),
    ],
  ),
  SeedCategory(
    name: '医疗健康',
    kind: CategoryKind.expense,
    icon: '🏥',
    color: '#C08C8C',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('门诊'),
      SeedSubcategory('药品'),
      SeedSubcategory('体检'),
      SeedSubcategory('保险'),
    ],
  ),
  SeedCategory(
    name: '学习教育',
    kind: CategoryKind.expense,
    icon: '📚',
    color: '#9C9BAF',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('课程培训'),
      SeedSubcategory('书籍文具'),
      SeedSubcategory('考试报名'),
    ],
  ),
  SeedCategory(
    name: '通讯',
    kind: CategoryKind.expense,
    icon: '📱',
    color: '#87A2B5',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('手机话费'),
      SeedSubcategory('流量充值'),
      SeedSubcategory('宽带'),
    ],
  ),
  SeedCategory(
    name: '旅行',
    kind: CategoryKind.expense,
    icon: '✈️',
    color: '#8CA6A0',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('机票'),
      SeedSubcategory('酒店'),
      SeedSubcategory('门票'),
      SeedSubcategory('当地交通'),
    ],
  ),
  SeedCategory(
    name: '工资',
    kind: CategoryKind.income,
    icon: '💰',
    color: '#5B8C6E',
  ),
  SeedCategory(
    name: '奖金',
    kind: CategoryKind.income,
    icon: '🎁',
    color: '#6E9C7A',
  ),
  SeedCategory(
    name: '投资',
    kind: CategoryKind.income,
    icon: '📈',
    color: '#6C8C9C',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('理财收益'),
      SeedSubcategory('分红'),
    ],
  ),
  SeedCategory(
    name: '转账',
    kind: CategoryKind.transfer,
    icon: '🔁',
    color: '#9A9A94',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('转出'),
      SeedSubcategory('转入'),
    ],
  ),
  SeedCategory(
    name: '退款',
    kind: CategoryKind.refund,
    icon: '↩️',
    color: '#8C9C8C',
  ),
  SeedCategory(
    name: '报销',
    kind: CategoryKind.income,
    icon: '🧮',
    color: '#7E9C86',
  ),
  SeedCategory(
    name: '其他',
    kind: CategoryKind.expense,
    icon: '🏷️',
    color: '#A0A0A0',
    subcategories: <SeedSubcategory>[
      SeedSubcategory('其他支出'),
      SeedSubcategory('其他收入'),
    ],
  ),
];

/// 内置关键词规则（`is_builtin = 1`，用户可禁用但不可删除）。
///
/// 全部使用**虚构商户名**之外的通用品牌词（这些是真实存在的连锁品牌，
/// 但规则本身不含任何用户隐私数据）。
const List<SeedRule> seedRules = <SeedRule>[
  SeedRule(
    name: '快餐连锁',
    priority: 20,
    merchantContains: <String>['麦当劳', '肯德基', '汉堡王', '华莱士', '德克士'],
    targetPath: <String>['餐饮', '快餐'],
  ),
  SeedRule(
    name: '咖啡茶饮',
    priority: 20,
    merchantContains: <String>[
      '瑞幸', '星巴克', '喜茶', '奈雪', '蜜雪冰城', '库迪', '茶百道', '古茗',
    ],
    targetPath: <String>['餐饮', '咖啡茶饮'],
  ),
  SeedRule(
    name: '外卖平台',
    priority: 25,
    merchantContains: <String>['美团', '饿了么'],
    descriptionContains: <String>['外卖'],
    matchMode: RuleMatchMode.merchantAndDescription,
    targetPath: <String>['餐饮', '外卖'],
  ),
  SeedRule(
    name: '便利店',
    priority: 25,
    merchantContains: <String>[
      '罗森', 'Lawson', '全家', 'FamilyMart', '7-ELEVEN', '便利蜂', '美宜佳',
    ],
    targetPath: <String>['餐饮', '便利店'],
  ),
  SeedRule(
    name: '网约车',
    priority: 20,
    merchantContains: <String>['滴滴', '高德打车', '曹操出行', 'T3出行', '首汽约车'],
    targetPath: <String>['交通', '打车'],
  ),
  SeedRule(
    name: '公共交通',
    priority: 20,
    merchantContains: <String>['地铁', '公交', '一卡通', '交通卡', '乘车码'],
    targetPath: <String>['交通', '公共交通'],
  ),
  SeedRule(
    name: '铁路出行',
    priority: 22,
    merchantContains: <String>['铁路', '12306', '火车票'],
    targetPath: <String>['交通', '火车'],
  ),
  SeedRule(
    name: '航空出行',
    priority: 22,
    merchantContains: <String>['航空', '机场', '航班'],
    targetPath: <String>['交通', '飞机'],
  ),
  SeedRule(
    name: '加油',
    priority: 22,
    merchantContains: <String>['加油', '石油', '石化', '壳牌'],
    targetPath: <String>['交通', '加油'],
  ),
  SeedRule(
    name: '电商平台',
    priority: 30,
    merchantContains: <String>[
      '淘宝', '天猫', '京东', '拼多多', '唯品会', '苏宁', '抖音商城', '得物',
    ],
    targetPath: <String>['购物', '电商'],
  ),
  SeedRule(
    name: '影音会员',
    priority: 35,
    descriptionContains: <String>['会员', '订阅', '续费', '包月', '包年'],
    matchMode: RuleMatchMode.merchantAndDescription,
    merchantContains: <String>[
      '腾讯视频', '爱奇艺', '优酷', '芒果TV', '哔哩哔哩', 'B站', '网易云音乐',
      'QQ音乐', 'Spotify', 'Netflix',
    ],
    targetPath: <String>['娱乐', '影音会员'],
  ),
  SeedRule(
    name: '游戏充值',
    priority: 30,
    merchantContains: <String>['Steam', '腾讯游戏', '网易游戏', '米哈游', '游戏'],
    targetPath: <String>['娱乐', '游戏'],
  ),
  SeedRule(
    name: '房租',
    priority: 15,
    descriptionContains: <String>['房租', '租金'],
    targetPath: <String>['居住', '房租'],
  ),
  SeedRule(
    name: '水电燃气',
    priority: 20,
    merchantContains: <String>['国家电网', '水务', '燃气', '自来水'],
    targetPath: <String>['居住', '水电燃气'],
  ),
  SeedRule(
    name: '话费充值',
    priority: 20,
    merchantContains: <String>['中国移动', '中国联通', '中国电信', '话费'],
    targetPath: <String>['通讯', '手机话费'],
  ),
  SeedRule(
    name: '药品医疗',
    priority: 20,
    merchantContains: <String>['药房', '大药房', '医院', '诊所', '卫生院'],
    targetPath: <String>['医疗健康', '药品'],
  ),
  SeedRule(
    name: '酒店住宿',
    priority: 25,
    merchantContains: <String>['酒店', '民宿', '携程', '去哪儿', '飞猪', '华住', '如家'],
    targetPath: <String>['旅行', '酒店'],
  ),
  SeedRule(
    name: '工资收入',
    priority: 10,
    descriptionContains: <String>['工资', '薪资', '代发'],
    direction: TransactionType.income,
    targetPath: <String>['工资'],
  ),
];
