# 聚账 · FinanceHub

[![CI](https://github.com/zeana9658-alt/finance_hub/actions/workflows/ci.yml/badge.svg)](https://github.com/zeana9658-alt/finance_hub/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.47%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows-3DDC84?logo=android&logoColor=white)](#技术栈)
[![Tests](https://img.shields.io/badge/tests-249%20passed-brightgreen)](#快速开始)

> **个人财务数据中枢** —— 把支付宝和微信账单扔进去，App 帮你把消费生活讲清楚。

不是传统的"手动记账 App"。核心价值是**把散落在不同平台的账单统一进来、去重、分类、可视化**，让你真正看懂"我的钱都花到哪里去了"。

---

## 为什么不是又一个记账 App

| 传统记账 App | 聚账 |
|---|---|
| 要你手动一笔笔记 | 导入微信/支付宝账单文件，自动解析 |
| 平台各记各的 | 统一数据模型，微信支付宝混在一起统计 |
| 只有流水列表 | 月度趋势 / 分类下钻 / 消费日历 / 时段热力图 / 商户分析 |
| 数据在云上 | **LOCAL FIRST**，账单永不离开设备 |
| 分类靠你自己想 | 三级分类 + 商户记忆 + 可重跑规则 |

---

## 核心原则

- **LOCAL FIRST** —— 默认不登录、不联网也能用、不上传账单
- **金额零误差** —— 全链路以"分"为整数存储，绝不用浮点
- **导入必预览** —— 选完文件不直接写库，先看统计与逐条明细，确认后才落盘
- **去重不误杀** —— 交易单号优先，无单号走指纹；跨平台同额同商户**不判重复**
- **错误看得见** —— 任何解析失败都不崩、不静默丢弃，逐行给出"第几行 / 原文 / 原因"
- **分类可重跑** —— 改规则后可全量重分类，且**不覆盖你手动改过的分类**

---

## 功能

### 已完成

- [x] **导入**：微信（CSV/XLSX/粘贴表格）、支付宝（CSV/XLSX/粘贴表格），自动识别来源，GBK 编码自动处理
- [x] **导入预览**：可导入 / 重复 / 异常 分类统计 + 逐条明细 + 筛选 + **手动改分类**
- [x] **去重**：交易单号优先 + 指纹哈希 + 部分唯一索引兜底；跨平台不误判
- [x] **分类**：17 个一级 + 40+ 二级分类，三级优先级引擎（商户记忆 → 平台分类 → 关键词规则）
- [x] **分类规则管理**：可视化增删改规则、优先级与匹配模式；内置规则可禁用不可删
- [x] **一键重跑历史账单**：改完规则一键重算，**绝不覆盖手动分类**，且只写变化的行
- [x] **商户记忆管理**：查看 / 删除 / 清空自动记住的商户分类
- [x] **Dashboard**：本月收支、环比、近 12 个月趋势图、分类占比
- [x] **分类下钻**：分类 → 二级分类 → 商户 → 商户详情（四层）
- [x] **统计**：消费日历热力图、消费时段分布、商户排行
- [x] **账单明细**：搜索 / 来源 / 类型 / 时间范围 / 排序（全部 SQL 下推）
- [x] **预算**：按分类设预算，进度条 + 低饱和琥珀预警（不用刺眼红色）
- [x] **备份**：JSON 完整备份 + CSV 明细导出 + 恢复（预览 → 选合并/覆盖 → 确认）
- [x] **快速记账**：收入 / 支出、金额、分类、商户、日期、支付方式、备注；
      输入商户时会用**和导入同一套分类引擎**实时给出分类建议，点一下即应用

### 暂未实现（界面上已明确标注，未用假数据伪装）

- [ ] **AI 消费分析 / 自然语言查询**（隐私边界 `FinancialSummary` 已在 docs/PRIVACY.md 设计好）

### 明确不做

- ❌ 企业 ERP / 复杂会计系统
- ❌ 复式记账（借贷科目）
- ❌ 证券交易 / 银行 App
- ❌ 云同步 / 需要账号
- ❌ 无障碍服务抓取 / 通知监听 / 读短信（见下方说明）

> **关于"自动抓取"**：安卓上无障碍/通知/短信三条路线都需要高敏感权限，且微信支付宝一改版就失效，可靠性有限。
> 账单文件导入是唯一"低难度 + 高可靠 + 免 root + 零敏感权限"的路线，因此本项目采用它。
> 详细调研见 `docs/GITHUB_RESEARCH.md` §4.3。

---

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter / Dart |
| 目标平台 | Android（首选）、Windows（次选）、iOS/macOS（预留） |
| 状态管理 | Riverpod |
| 本地库 | SQLite（`sqflite` + `sqflite_common_ffi`） |
| 账单解析 | 自研（`csv` + `excel` + `charset`） |
| 图表 | `fl_chart` + 自绘日历/热力图 |
| 文件选择 | `file_picker` |

---

## 快速开始

需要 **Flutter 3.47+ / Dart 3.13+**。完整工具链搭建（含 Windows 上的坑）见
[`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md)。

```bash
# 1) 依赖
flutter pub get

# 2) 静态分析（当前：No issues found）
dart analyze

# 3) 测试（当前：249 个用例全部通过）
flutter test

# 4) 出 Android APK
flutter build apk --release
#    产物：build/app/outputs/flutter-apk/app-release.apk
```

### Windows + Git Bash 用户请注意（其余平台可跳过）

```bash
# Git Bash 里没有 %PROGRAMFILES(X86)%，Flutter 工具会直接报错退出，
# 需要用 env 显式注入：
env 'PROGRAMFILES(X86)=C:\Program Files (x86)' 'PROGRAMFILES=C:\Program Files' flutter test

# 如果你本机开了系统代理，务必 unset，并显式把回环地址排除掉 ——
# 否则 flutter_tester 的本机 WebSocket 会被代理拦截，
# 测试会随机失败或静默挂起（报 "Invalid WebSocket upgrade request"）。
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
export no_proxy="localhost,127.0.0.1,::1,0.0.0.0"; export NO_PROXY="$no_proxy"
```

> ⚠️ **构建 APK 时不要加 `--no-pub`。** 它会让 Android 插件注册表不重新生成，
> 从而把 dev 依赖插件（`integration_test`）编进 release，导致 javac 报
> 「程序包 `dev.flutter.plugins.integration_test` 不存在」。
> 跑测试加 `--no-pub` 是安全的。机理见 [`docs/ENVIRONMENT.md` 坑 4](docs/ENVIRONMENT.md)。

### 出正式签名包（可选）

`android/key.properties` 缺失时 release 会自动退回 debug 签名，保证裸克隆也能构建。
要出正式签名包，复制示例文件并填入自己的 keystore：

```bash
cp android/key.properties.example android/key.properties   # 再编辑填入
```

```bash
keytool -genkeypair -v -keystore android/app/your-release.jks \
  -alias youralias -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=YourName, OU=Personal, O=YourName, L=Unknown, ST=Unknown, C=CN"
```

> 这两份文件都已在 `.gitignore` 中，**不会被提交**。

> **当前验证状态**
> - ✅ `dart analyze`：零 error / 零 warning / 零 info
> - ✅ `flutter test`：**249 个用例全部通过**（金额精度、GBK、去重、分类、重跑、迁移、备份、意图解析、查询引擎、Widget）
> - ✅ `flutter build apk --release`：构建成功，release 签名，**零危险权限**，覆盖 arm64-v8a / armeabi-v7a / x86_64
> - ⚠️ `flutter build windows`：需要 Visual Studio 的「使用 C++ 的桌面开发」工作负载
> - ⚠️ **Android 上不要执行 `PRAGMA journal_mode = WAL`** —— 会让 `openDatabase` 直接抛异常，
>   表现为「数据库打开失败」。机理见 [`docs/DATABASE.md` §7.1](docs/DATABASE.md)

完整的工具链搭建过程、六个必踩的坑、以及 Android SDK 手动组装方法见
[`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md)。

---

## 项目结构

```
lib/
├── app/         主题、路由、App 装配
├── core/        金额值对象、Result、工具、常量
├── domain/      实体、枚举、服务（去重/分类/聚合/导入编排）—— 纯 Dart
├── import/      账单解析子系统（解码/表格/识别/解析器）
├── data/        SQLite、迁移、仓储实现
├── features/    各业务页面
└── shared/      通用 Widget
test/
├── fixtures/    全虚构测试数据
├── core/        金额精度
├── import/      解析测试
├── domain/      去重、分类、意图解析、洞察
├── data/        迁移、统计 DAO、备份、查询引擎、平台 PRAGMA 回归
└── widget/      界面与启动闸门
docs/            设计与规范文档
```

---

## 文档

| 文件 | 内容 |
|---|---|
| [`docs/GITHUB_RESEARCH.md`](docs/GITHUB_RESEARCH.md) | 6 个参考项目的调研结论与采纳/拒绝决策 |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 分层架构、数据流、技术选型、UI 系统、性能设计 |
| [`docs/DATABASE.md`](docs/DATABASE.md) | 10 张表完整 DDL、去重指纹算法、迁移机制 |
| [`docs/IMPORT_FORMATS.md`](docs/IMPORT_FORMATS.md) | 微信/支付宝账单真实格式与解析规范 |
| [`docs/PRIVACY.md`](docs/PRIVACY.md) | 隐私承诺、AI 隐私边界、仓库规范 |
| [`docs/TESTING.md`](docs/TESTING.md) | 测试策略、必测清单、自检清单 |
| [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) | **工具链搭建全过程、六个必踩的坑、当前构建限制与解除方法** |

---

## 隐私

- 不需要注册账号
- 飞行模式也能完整使用
- 账单不会上传到任何服务器
- AI 分析（可选、默认关闭）只发送汇总数字，不含商户与订单信息

详见 [`docs/PRIVACY.md`](docs/PRIVACY.md)。

---

## 参考项目

本项目在设计阶段调研了以下开源项目（**研究设计 → 理解原理 → 重新实现**，未复制大段代码）：

- [MageGojo/lizhang](https://github.com/MageGojo/lizhang) —— Flutter 本地优先记账
- [zalexrose/FamilyFinanceManager](https://github.com/zalexrose/FamilyFinanceManager) —— Python 账单 Adapter
- [changdaye/bill-aggregator](https://github.com/changdaye/bill-aggregator) —— SQLite schema 与 GBK 处理
- [lemon970/jizhang-app](https://github.com/lemon970/jizhang-app) —— 模块切分范式
- [dtsola/xiaoyaoprivatebill](https://github.com/dtsola/xiaoyaoprivatebill) —— 分析维度分类学
- [cxy0714/beancount-auto-bookkeeping](https://github.com/cxy0714/beancount-auto-bookkeeping) —— 声明式规则

---

## 许可证

[MIT](LICENSE) © 2026 FinanceHub contributors

---

## 免责声明

本项目是**个人财务管理工具**，不提供任何投资、税务或会计建议，也不构成专业意见。
所有账单解析结果请自行核对；因使用本软件造成的任何损失，作者不承担责任。

导入的账单文件由你自己保管。项目遵循 **LOCAL FIRST**：不联网、不上传，
但**请仍然自行备份** —— 数据库只存在本机，卸载应用会一并清除。
