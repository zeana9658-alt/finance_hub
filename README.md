# 聚账 · FinanceHub

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

### 已规划（按阶段交付）

- [ ] **导入**：微信（CSV/XLSX/粘贴表格）、支付宝（CSV/XLSX/粘贴表格），自动识别来源，GBK 编码自动处理
- [ ] **导入预览**：可导入 / 重复 / 异常 分类统计 + 逐条明细 + 筛选 + 手动改分类
- [ ] **去重**：交易单号优先 + 指纹哈希 + 部分唯一索引兜底
- [ ] **分类**：17 个一级分类 + 二级分类 + 商户记忆规则，规则可重跑
- [ ] **Dashboard**：本月收支、环比、月度趋势（周/月/季/年）、分类占比下钻
- [ ] **统计**：消费日历、时段热力图、大额支出 TOP5、商户分析
- [ ] **账单明细**：搜索 / 多维筛选 / 排序 / 按商户汇总
- [ ] **预算**：按分类设预算，进度条 + 温和预警
- [ ] **备份**：JSON / CSV / Excel 导出与恢复（恢复前预览 + 确认）
- [ ] **AI 分析**（可选）：只发送聚合数字，不含商户与订单信息

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

```bash
export PATH="/c/Users/kol56/.workbuddy-ai/tools/flutter/bin:$PATH"
# ⚠️ 本机 http_proxy 会让 pub 假死，务必先 unset
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
cd finance_hub

# 依赖
flutter pub get

# 静态分析（当前：No issues found）
dart analyze

# 测试（当前：110 个用例全部通过）
# ⚠️ Git Bash 缺 %PROGRAMFILES(X86)%，需要显式注入
env 'PROGRAMFILES(X86)=C:\Program Files (x86)' 'PROGRAMFILES=C:\Program Files' flutter test

# 构建
flutter build apk --release        # Android（需先装 JDK + Android SDK）
flutter build windows --release    # Windows（需 VS 的 C++ 桌面开发工作负载）
```

> **当前验证状态**
> - ✅ `dart analyze`：零 error / 零 warning / 零 info
> - ✅ `flutter test`：110 个用例全部通过（含金额精度、GBK、去重、分类、迁移、Widget）
> - ❌ 两条打包路径受限于本机工具链（缺 JDK+Android SDK / VS 缺 C++ 工作负载），
>   **不是代码问题**。补齐方法见 [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) §4。

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
├── import/      解析测试
├── domain/      去重与分类测试
├── consistency/ 方向/期间/金额一致性校验
└── performance/ 10000 条规模测试
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
| [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) | **工具链搭建全过程、三个必踩的坑、当前构建限制与解除方法** |

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

MIT
