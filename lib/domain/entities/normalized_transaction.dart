import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/category_source.dart';
import 'package:finance_hub/domain/enums/transaction_status.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';

/// 统一交易实体 —— 所有账单来源最终都归一化到这个模型。
///
/// 这是 brief 第 4 条「所有账单必须进入统一数据模型」的落地。
/// 微信、支付宝、银行卡、信用卡、京东、手动记账全部产出一个
/// [NormalizedTransaction]，不存在各来源各有一套结构的情况。
///
/// 金额约定：[amountCents] **恒为非负**（单位：分）。
/// 「收入还是支出」由 [transactionType] 表达，不要用金额正负号表达方向。
/// 需要带符号金额时用 [signedCents]。
class NormalizedTransaction {
  const NormalizedTransaction({
    this.id,
    required this.source,
    this.sourceTransactionId,
    required this.uniqueKey,
    required this.transactionTime,
    required this.transactionTimeRaw,
    required this.transactionType,
    required this.transactionTypeRaw,
    this.platformCategory = '',
    required this.amountCents,
    this.currency = 'CNY',
    required this.merchant,
    required this.description,
    this.categoryId,
    this.subcategoryId,
    this.categorySource = CategorySource.fallback,
    this.accountId,
    required this.paymentMethod,
    this.status = TransactionStatus.success,
    this.location,
    this.note = '',
    this.rawData,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 数据库主键。导入预览阶段尚未落库，为 `null`。
  final int? id;

  final BillSource source;

  /// 平台交易单号（微信「交易单号」/ 支付宝「交易订单号」）。可能为空。
  final String? sourceTransactionId;

  /// 去重指纹。由 `TransactionFingerprint.compute()` 生成，落库后不可变。
  final String uniqueKey;

  /// 交易时间（本地时间）。
  final DateTime transactionTime;

  /// 原始时间字符串，仅用于排查（见 docs/DATABASE.md §6）。
  final String transactionTimeRaw;

  final TransactionType transactionType;

  /// 平台原始类型文本，如微信的「商户消费」、支付宝的「即时到账」。
  final String transactionTypeRaw;

  /// 平台自带的分类文本，如支付宝新版的「交易分类」（餐饮美食 / 交通出行 …）。
  ///
  /// 用于分类引擎的**第二优先级**：平台原始分类映射
  /// （见 brief 第 10 条、docs/ARCHITECTURE.md §3.1）。
  final String platformCategory;

  /// 金额，单位「分」，**恒为非负**。
  final int amountCents;

  final String currency;

  final String merchant;

  final String description;

  final int? categoryId;

  final int? subcategoryId;

  /// 分类来源 —— 决定重新分类时是否跳过（见 [CategorySource]）。
  final CategorySource categorySource;

  final int? accountId;

  final String paymentMethod;

  final TransactionStatus status;

  final String? location;

  final String note;

  /// 原始行 JSON，仅本地留档用于排查；导出备份时默认剔除（见 docs/PRIVACY.md §4.2）。
  final String? rawData;

  /// 软删除时间戳。非空表示已删除。
  final DateTime? deletedAt;

  final DateTime createdAt;

  final DateTime updatedAt;

  /// 是否已被软删除。
  bool get isDeleted => deletedAt != null;

  /// 带符号金额：支出为负、收入为正、退款为正、转账为 0（不参与净额）。
  int get signedCents => switch (transactionType) {
        TransactionType.income => amountCents,
        TransactionType.expense => -amountCents,
        TransactionType.refund => amountCents,
        TransactionType.transfer => 0,
      };

  /// 是否应计入统计口径（收入/支出/分类占比/日历）。
  ///
  /// 转账与已关闭/失败/处理中的交易不计入。
  bool get countsInStatistics =>
      !isDeleted &&
      status != TransactionStatus.closed &&
      status != TransactionStatus.failed &&
      status != TransactionStatus.pending &&
      transactionType != TransactionType.transfer;

  /// 导入预览中该行默认是否勾选。
  bool get defaultSelectedInImport =>
      status.defaultSelected && transactionType.defaultSelectedInImport;

  /// 分类是否已被用户手动锁定（重新分类时跳过）。
  bool get isCategoryLocked => categorySource.isUserLocked;

  NormalizedTransaction copyWith({
    int? id,
    BillSource? source,
    String? sourceTransactionId,
    String? uniqueKey,
    DateTime? transactionTime,
    String? transactionTimeRaw,
    TransactionType? transactionType,
    String? transactionTypeRaw,
    String? platformCategory,
    int? amountCents,
    String? currency,
    String? merchant,
    String? description,
    int? categoryId,
    int? subcategoryId,
    CategorySource? categorySource,
    int? accountId,
    String? paymentMethod,
    TransactionStatus? status,
    String? location,
    String? note,
    String? rawData,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    bool clearCategory = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NormalizedTransaction(
      id: id ?? this.id,
      source: source ?? this.source,
      sourceTransactionId: sourceTransactionId ?? this.sourceTransactionId,
      uniqueKey: uniqueKey ?? this.uniqueKey,
      transactionTime: transactionTime ?? this.transactionTime,
      transactionTimeRaw: transactionTimeRaw ?? this.transactionTimeRaw,
      transactionType: transactionType ?? this.transactionType,
      transactionTypeRaw: transactionTypeRaw ?? this.transactionTypeRaw,
      platformCategory: platformCategory ?? this.platformCategory,
      amountCents: amountCents ?? this.amountCents,
      currency: currency ?? this.currency,
      merchant: merchant ?? this.merchant,
      description: description ?? this.description,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      subcategoryId: clearCategory ? null : (subcategoryId ?? this.subcategoryId),
      categorySource: categorySource ?? this.categorySource,
      accountId: accountId ?? this.accountId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      location: location ?? this.location,
      note: note ?? this.note,
      rawData: rawData ?? this.rawData,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory NormalizedTransaction.fromMap(Map<String, Object?> map) {
    return NormalizedTransaction(
      id: map['id'] as int?,
      source: BillSource.fromCode(map['source'] as String?) ?? BillSource.manual,
      sourceTransactionId: map['source_transaction_id'] as String?,
      uniqueKey: map['unique_key'] as String? ?? '',
      transactionTime: DateTime.fromMillisecondsSinceEpoch(
        map['transaction_time'] as int? ?? 0,
      ),
      transactionTimeRaw: map['transaction_time_raw'] as String? ?? '',
      transactionType: TransactionType.fromCode(
            map['transaction_type'] as String?,
          ) ??
          TransactionType.expense,
      transactionTypeRaw: map['transaction_type_raw'] as String? ?? '',
      platformCategory: map['platform_category'] as String? ?? '',
      amountCents: map['amount_cents'] as int? ?? 0,
      currency: map['currency'] as String? ?? 'CNY',
      merchant: map['merchant'] as String? ?? '',
      description: map['description'] as String? ?? '',
      categoryId: map['category_id'] as int?,
      subcategoryId: map['subcategory_id'] as int?,
      categorySource:
          CategorySource.fromCode(map['category_source'] as String?) ??
              CategorySource.fallback,
      accountId: map['account_id'] as int?,
      paymentMethod: map['payment_method'] as String? ?? '',
      status: TransactionStatus.fromCode(map['status'] as String?) ??
          TransactionStatus.success,
      location: map['location'] as String?,
      note: map['note'] as String? ?? '',
      rawData: map['raw_data'] as String?,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int? ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at'] as int? ?? 0,
      ),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'source': source.code,
      'source_transaction_id': sourceTransactionId,
      'unique_key': uniqueKey,
      'transaction_time': transactionTime.millisecondsSinceEpoch,
      'transaction_time_raw': transactionTimeRaw,
      'transaction_type': transactionType.code,
      'transaction_type_raw': transactionTypeRaw,
      'platform_category': platformCategory,
      'amount_cents': amountCents,
      'currency': currency,
      'merchant': merchant,
      'description': description,
      'category_id': categoryId,
      'subcategory_id': subcategoryId,
      'category_source': categorySource.code,
      'account_id': accountId,
      'payment_method': paymentMethod,
      'status': status.code,
      'location': location,
      'note': note,
      'raw_data': rawData,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// 落库用 Map —— 去掉主键，交给 AUTOINCREMENT 生成。
  Map<String, Object?> toInsertMap() {
    final map = toMap();
    map.remove('id');
    return map;
  }

  @override
  String toString() =>
      'NormalizedTransaction(${source.code}, ${transactionType.code}, '
      '$amountCents 分, $merchant, $transactionTime)';
}
