# IMPORT_FORMATS.md — 账单格式与解析规范

> 本文档定义微信支付 / 支付宝账单的**真实格式特征**与**解析规则**。
> 内容来自 GitHub 参考项目源码 + 实际导出格式核对，用于指导 `lib/import/` 的实现与测试。

---

## 1. 支持的输入形态

| 形态 | 扩展名 | 读取器 | 编码 |
|---|---|---|---|
| CSV | `.csv` | `CsvReader` | utf-8-sig / utf-8 / gb18030 / gbk |
| Excel | `.xlsx` | `XlsxReader` | 内部 UTF-8（zip+XML） |
| 粘贴表格文本 | — | `TextTableReader` | 由剪贴板提供，已是 String |
| 旧版 Excel | `.xls` | ❌ **暂未支持** | 二进制 OLE 格式，`excel` 包不支持；UI 明确提示用户改用 CSV/XLSX |

> `.xls` 的处理：检测到后不报错崩溃，而是给出明确提示
> 「旧版 .xls 暂未支持，请在微信/支付宝导出时选择 CSV 或 XLSX 格式」。

---

## 2. 编码处理（最大的坑）

### 2.1 回退链

```
1. utf-8-sig     ← 处理 BOM（微信 CSV 常见）
2. utf-8
3. gb18030       ← GBK 超集，能多救生僻字
4. gbk
5. latin1        ← 最后兜底，保证不抛异常
```

**判定成功的标准**：解码后不抛异常 **且** 文本中包含预期的中文表头关键词（如"交易时间"/"金额"）。
否则继续下一个编码 —— 这是关键，因为 `latin1` 对任何字节都不抛异常，若只看"是否抛异常"会误判成功。

### 2.2 选型

使用 **`charset: ^2.0.1`**（纯 Dart）：
- ✅ 支持 gbk / gb18030 / big5
- ✅ 纯 Dart，Android 与 Windows 行为一致
- ✅ 附带 charset 探测能力

❌ 不选 `charset_converter`：平台通道插件，Windows 支持不可靠
❌ 不选 `fast_gbk` / `gbk_codec` / `gbk2utf8`：SDK 约束 `>=2.12.0 <3.0.0`，Dart 3 无法解析

### 2.3 测试要求

`test/fixtures/` 必须包含**同一份内容的 UTF-8 与 GBK 两个版本**，断言解析结果**完全一致**：

```
mock_alipay.csv         (UTF-8)
mock_alipay_gbk.csv     (GBK)          ← 与上者内容相同，编码不同
```

---

## 3. 微信支付账单

### 3.1 文件结构

```
（第 1–3 行）说明文字，如：
微信支付账单明细
微信昵称：[示例用户]
起始时间：[2026-01-01 00:00:00] 终止时间：[2026-03-31 23:59:59]
导出类型：[全部]
（第 4 行）----------------------微信支付账单明细列表--------------------
（第 5 行）表头
（第 6 行起）数据
```

**真实表头（CSV / XLSX）**：
```
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
```

**列名变体（必须全部兼容）**：

| 语义 | 可能出现的列名 |
|---|---|
| 交易时间 | `交易时间` |
| 交易类型 | `交易类型` |
| 交易对方 | `交易对方` |
| 商品 | `商品` |
| 收/支 | `收/支` |
| **金额** | `金额(元)` / `金额（元）` / `金额 (元)` / `金额` |
| 支付方式 | `支付方式` |
| **状态** | `当前状态` / `交易状态` / `状态` |
| 交易单号 | `交易单号` |
| 商户单号 | `商户单号` |
| 备注 | `备注` |

> ⚠️ 金额列名的括号有**半角 `()` 与全角 `（）` 两种**，且可能带空格。
> `HeaderNormalizer` 统一去掉 `空格 / 括号 / 斜杠 / 下划线 / 冒号 / 连字符` 与 `人民币 / 元` 后再匹配，因此三种写法归一为 `金额`。

### 3.2 字段映射

| 目标字段 | 来源 | 处理 |
|---|---|---|
| `transaction_time` | `交易时间` | 格式 `yyyy-MM-dd HH:mm:ss` |
| `transaction_time_raw` | 同上 | 原文 |
| `transaction_type_raw` | `交易类型` | 原文 |
| `merchant` | `交易对方` | trim |
| `description` | `商品` | trim |
| `direction` | `收/支` | `支出`→expense，`收入`→income，`/` 或 `不计收支`→transfer |
| `amount_cents` | `金额(元)` | 去 `¥ ￥ , 空格` → 转分 |
| `payment_method` | `支付方式` | trim |
| `status` | `当前状态` | 见 3.4 |
| `source_transaction_id` | `交易单号` | 归一化 |
| `note` | `备注` | trim；`/` 视为空 |

### 3.3 排除规则（资金搬运，非消费）

`交易类型` 命中以下任一 → **不计入消费**，标记为 `transfer` 或直接排除：

```
零钱提现 / 零钱充值 / 转入零钱通 / 零钱通转出 / 转账 / 信用卡还款 / 理财通
```

> 来源：`FamilyFinanceManager/adapters/wechat_adapter.py` 的 `exclude_types`。
> **不直接丢弃**，而是标记 `transaction_type = 'transfer'` 并默认在预览中取消勾选 —— 用户仍可手动勾选导入（如需要追踪资金流向）。

### 3.4 状态映射

| `当前状态` 取值 | status | 默认勾选 |
|---|---|---|
| `支付成功` / `已转账` / `已存入零钱` / `对方已收钱` | `success` | ✅ |
| `已全额退款` | `refunded` | ✅（方向按 `收/支` 判定） |
| `已退还` | `refunded` | ✅ |
| `已关闭` / `已取消` | `closed` | ❌ |
| `支付失败` | `failed` | ❌ |
| `处理中` / `等待确认` | `pending` | ❌ |

---

## 4. 支付宝账单

### 4.1 两个版本都要支持

**版本 A：网页版导出（CSV，GBK 编码）**

```
（第 1–4 行）说明文字，如：
支付宝交易记录明细查询
账号：[示例账号]
起始日期：[2026-01-01 00:00:00]    终止日期：[2026-03-31 23:59:59]
---------------------------------交易记录明细列表------------------------------------
（第 5 行）表头
（第 6 行起）数据
（末尾）---------------------------------交易记录明细列表结束---------------------------------
```

表头：
```
交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注,资金状态
```

**版本 B：App 版导出（brief 中描述）**

```
交易时间,交易分类,交易对方,商品说明,收/支,金额,支付方式,交易状态,交易订单号,商家订单号,备注
```

### 4.2 列名变体

| 语义 | 可能出现的列名 |
|---|---|
| 交易时间 | `交易时间` / `交易创建时间` / `付款时间` |
| 交易分类 | `交易分类` / `类型` |
| 交易对方 | `交易对方` / `对方账号` |
| 商品说明 | `商品说明` / `商品名称` / `商品` |
| 收/支 | `收/支` |
| 金额 | `金额` / `金额（元）` / `金额(元)` |
| 支付方式 | `支付方式` / `收/付款方式` / `交易来源地` |
| 交易状态 | `交易状态` / `资金状态` |
| 交易订单号 | `交易订单号` / `交易号` |
| 商户单号 | `商家订单号` |
| 备注 | `备注` |

### 4.3 关键规则

| 规则 | 说明 |
|---|---|
| **编码** | CSV 默认 **GBK**，必须走 §2 的回退链 |
| **表头定位** | **禁止硬编码 `lines[4]`**（不同导出版本行号会变）→ 用 `HeaderLocator` 扫描前 30 行 |
| **CSV 切分** | **禁止 `line.split(',')`** → 商品名含英文逗号会错位。用 RFC 4180 兼容解析器 |
| **`交易状态` 含"交易关闭"** | 标记 `closed`，默认不勾选 |
| **`收/支` = `不计收支`** | 标记 `transfer`，默认不勾选 |
| **金额为 0** | 记为**错误行**（不是静默丢弃），原因："金额为 0" |
| **末尾分隔行** | `-----...-----` 行跳过（不是数据行） |

### 4.4 方向判定

```
收/支 == '支出'      → expense
收/支 == '收入'      → income
收/支 == '不计收支'  → transfer
收/支 为空           → 若 交易状态 含"退款" → refund；否则记为错误行
```

> ⚠️ 反面教材：`FamilyFinanceManager` 的写法是 `if "支出" in trans_type: 负数 else: 正数`，
> 会把"不计收支"误判为收入。本项目必须显式处理三分支。

---

## 5. 通用解析规则

### 5.1 表头定位算法

```
for rowIndex in 0..min(30, rows.length):
    normalized = row.map(HeaderNormalizer.normalize)
    hasTime   = findColumn(normalized, TIME_ALIASES)   != -1
    hasAmount = findColumn(normalized, AMOUNT_ALIASES) != -1
    if hasTime && hasAmount:
        return rowIndex
return NOT_FOUND   → 抛出「无法识别账单表头」，UI 提示用户手动选择来源
```

### 5.2 金额解析

```
输入 → 去首尾空白
     → 去掉 ¥ ￥ $ , 空格 全角空格
     → 处理负号（前置或括号表示负数）
     → 空字符串 或 非数字 → 错误行「金额字段无法解析」
     → 用 Decimal 语义解析到"分"（字符串切分，不经过 double）

正确： "38.52"  → 3852
正确： "1,234.5" → 123450
正确： "¥38"    → 3800
正确： "38.5"   → 3850
正确： "38"     → 3800
错误： ""       → 错误行
错误： "待确认"  → 错误行
```

**实现要点**：**绝不用 `double.parse` 再 `*100`**（`38.52 * 100 = 3851.9999...` → 截断成 3851）。
正确做法：按 `.` 切分，整数部分 × 100 + 小数部分补齐/截断到 2 位。

```dart
// 正确实现示意
int? parseMoneyToCents(String raw) {
  var s = raw.replaceAll(RegExp(r'[¥￥$,\s\u3000]'), '').trim();
  if (s.isEmpty) return null;
  final negative = s.startsWith('-');
  if (negative) s = s.substring(1);
  final parts = s.split('.');
  if (parts.length > 2) return null;
  final intPart = parts[0].isEmpty ? '0' : parts[0];
  if (!RegExp(r'^\d+$').hasMatch(intPart)) return null;
  var fracPart = parts.length == 2 ? parts[1] : '';
  if (!RegExp(r'^\d*$').hasMatch(fracPart)) return null;
  if (fracPart.length > 2) fracPart = fracPart.substring(0, 2);   // 截断
  fracPart = fracPart.padRight(2, '0');                           // 补齐
  final cents = int.parse(intPart) * 100 + int.parse(fracPart);
  return negative ? -cents : cents;
}
```

### 5.3 时间解析

支持格式（按顺序尝试）：

```
yyyy-MM-dd HH:mm:ss
yyyy-MM-dd HH:mm
yyyy/MM/dd HH:mm:ss
yyyy/MM/dd HH:mm
yyyy年MM月dd日 HH:mm:ss
yyyy年MM月dd日 HH:mm
yyyy-MM-dd
yyyy/MM/dd
yyyyMMddHHmmss
```

**解析失败** → 记为错误行「时间字段无法识别」，**禁止用 `DateTime.now()` 兜底**。

### 5.4 每行错误不中断

```dart
for (final row in dataRows) {
  try {
    result.add(parseRow(row));
  } on ParseException catch (e) {
    errors.add(ParseError(rowNumber: i + 1, raw: row.join(','), reason: e.message));
  }
}
```

`ParseError` 三元组：`{ rowNumber, raw, reason }` —— 对应 brief 第 30 条「第几行 / 原始内容 / 错误原因」。

---

## 6. 来源自动识别

### 6.1 优先级

```
① 表头特征（最可靠）
   含 "交易分类" 或 "商品说明" 或 "交易订单号"  → alipay
   含 "当前状态" 或 "交易单号" 或 "商户单号"    → wechat
   含 "商品"（且不含上述支付宝特征）            → wechat

② 文件名 / 前 8 行文本
   含 "支付宝" / "alipay"  → alipay
   含 "微信"   / "wechat"  → wechat

③ 无法判定
   source = unknown
   UI 显示：「无法自动识别，请选择账单来源」+ 微信 / 支付宝 二选一按钮
```

> 注意优先级顺序：**表头特征优先于文件名**。因为用户可能把支付宝账单重命名为 `微信账单.csv`。

### 6.2 记录识别方式

`import_records.detected_by` 记录是 `header` / `filename` / `manual`，便于排查识别准确率。

---

## 7. 导入预览的统计口径

```
总行数     = 数据区行数（不含表头与说明行）
✓ 可导入   = valid 候选数（默认勾选）
↻ 重复     = unique_key 命中（含批内重复），默认不勾选
! 数据异常 = 解析失败行数（可查看行号/原文/原因），不可勾选
收入 ¥x    = 候选（含默认勾选的）中 direction == income 的金额合计
支出 ¥y    = 候选（含默认勾选的）中 direction == expense 的金额合计
```

> 收入/支出合计**随用户勾选实时变化**，让用户在写库前就看清影响。

---

## 8. 测试矩阵（对应 `test/fixtures/`）

| 文件 | 用途 | 关键断言 |
|---|---|---|
| `mock_wechat.csv` | 微信 UTF-8 | 条数、方向、金额分、状态过滤 |
| `mock_wechat.xlsx` | 微信 XLSX | 与 CSV 版结果一致 |
| `mock_alipay.csv` | 支付宝 UTF-8 | 条数、方向、金额分 |
| `mock_alipay_gbk.csv` | 支付宝 GBK | **与 UTF-8 版结果逐字段一致** |
| `mock_alipay_v2.csv` | 支付宝新版表头 | 兼容版本 B |
| `mock_invalid.csv` | 畸形数据 | 空金额 / 乱码 / 时间无法识别 → 进错误列表 |
| `mock_refund.csv` | 退款场景 | `refunded` 状态、方向正确 |
| `mock_transfer.csv` | 转账/资金搬运 | 标记 transfer，默认不勾选 |
| `mock_duplicate.csv` | 重复交易 | 第二次导入全部判为 duplicate |
| `mock_cross_platform.csv` | 跨平台同额同商户 | **不判为重复**，仅标 advisory |

所有数据**必须虚构**：商户用 `示例咖啡`/`示例超市`，单号用 `TEST-WX-0001`，账号用 `示例账号`。
