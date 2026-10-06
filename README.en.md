[简体中文](README.md) | **English**

# 聚账 (JuZhang) · FinanceHub

[![CI](https://github.com/zeana9658-alt/finance_hub/actions/workflows/ci.yml/badge.svg)](https://github.com/zeana9658-alt/finance_hub/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.47%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows-3DDC84?logo=android&logoColor=white)](#tech-stack)
[![Tests](https://img.shields.io/badge/tests-249%20passed-brightgreen)](#quick-start)

> **A personal finance data hub** — throw your Alipay and WeChat Pay bills at it, and the app tells the story of your spending.

This is not a traditional "type in every expense" app. The point is to **pull bills from different platforms into one place, deduplicate them, categorise them, and visualise them**, so you can finally see where your money actually goes.

> Note: this app is built for the Chinese payment ecosystem (Alipay / WeChat Pay bill exports). The interface is in Chinese; the code and docs are bilingual.

---

## Why this is not just another expense tracker

| Typical expense app | 聚账 (FinanceHub) |
|---|---|
| You enter every transaction by hand | Import WeChat / Alipay bill files, parsed automatically |
| Each platform stays separate | One unified data model — WeChat and Alipay in the same statistics |
| Just a flat list of transactions | Monthly trends / category drill-down / spending calendar / hour-of-day heatmap / merchant analysis |
| Your data lives in the cloud | **LOCAL FIRST** — bills never leave your device |
| Categories are your problem | Three-level categories + merchant memory + re-runnable rules |

---

## Core principles

- **LOCAL FIRST** — no sign-in, works fully offline, bills are never uploaded.
- **Zero rounding error** — amounts are stored as integer "cents" end to end, never floats.
- **Always preview an import** — nothing is written to the database until you have seen the summary and the per-row detail and confirmed it.
- **Deduplicate without false positives** — transaction ID first, fingerprint hash when there is none; the same amount at the same merchant on two different platforms is **not** treated as a duplicate.
- **Errors stay visible** — a parse failure never crashes and is never silently dropped; every bad row reports *line number / raw text / reason*.
- **Categories are re-runnable** — after editing rules you can recategorise everything, and **your manual overrides are never overwritten**.

---

## Features

### Done

- [x] **Import**: WeChat (CSV / XLSX / pasted table) and Alipay (CSV / XLSX / pasted table); source auto-detected, GBK encoding handled automatically.
- [x] **Import preview**: importable / duplicate / invalid buckets, per-row detail, filtering, and **manual category editing**.
- [x] **Deduplication**: transaction ID first + fingerprint hash + partial unique index as a safety net; no cross-platform false positives.
- [x] **Categories**: 17 top-level and 40+ second-level categories, with a three-tier priority engine (merchant memory → platform category → keyword rule).
- [x] **Category rule management**: create / edit / delete rules, priorities and match modes in the UI; built-in rules can be disabled but not deleted.
- [x] **One-tap recategorisation of history**: recompute after rule changes, **never overwriting manual categories**, writing only the rows that actually changed.
- [x] **Merchant memory management**: view / delete / clear the merchant→category associations the app learns.
- [x] **Dashboard**: this month's income and spending, month-over-month change, 12-month trend chart, category breakdown.
- [x] **Category drill-down**: category → subcategory → merchant → merchant detail (four levels).
- [x] **Statistics**: spending calendar heatmap, hour-of-day distribution, merchant ranking.
- [x] **Transaction list**: search / source / type / date range / sorting — all pushed down to SQL.
- [x] **Budgets**: per-category budgets with a progress bar and low-saturation amber warnings (deliberately not alarming red).
- [x] **Backup**: full JSON backup + CSV export + restore (preview → merge or overwrite → confirm).
- [x] **Quick entry**: income / expense, amount, category, merchant, date, payment method, note; the merchant field suggests a category in real time using **the same engine as imports**, one tap to apply.

### Not implemented yet (clearly labelled in the UI, never faked with placeholder data)

- [ ] **AI spending analysis / natural-language queries** (the privacy boundary `FinancialSummary` is already designed in `docs/PRIVACY.md`).

### Explicitly out of scope

- ❌ Enterprise ERP / full accounting systems
- ❌ Double-entry bookkeeping (debit/credit accounts)
- ❌ Securities trading / banking app features
- ❌ Cloud sync / accounts
- ❌ Accessibility-service scraping, notification listening, or SMS reading (see below)

> **On "automatic scraping"**: on Android, all three routes (accessibility service, notification listener, SMS) require highly sensitive permissions and break whenever WeChat or Alipay ships an update. Importing bill files is the only route that is *low effort + highly reliable + root-free + zero sensitive permissions*, which is why this project takes it. The full research is in `docs/GITHUB_RESEARCH.md` §4.3.

---

## Tech stack

| Layer | Choice |
|---|---|
| Framework | Flutter / Dart |
| Target platforms | Android (primary), Windows (secondary), iOS / macOS (planned) |
| State management | Riverpod |
| Local database | SQLite (`sqflite` + `sqflite_common_ffi`) |
| Bill parsing | Hand-written (`csv` + `excel` + `charset`) |
| Charts | `fl_chart` + hand-drawn calendar / heatmap |
| File picking | `file_picker` |

---

## Quick start

Requires **Flutter 3.47+ / Dart 3.13+**. The full toolchain setup (including the Windows pitfalls) is documented in [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) (Chinese).

```bash
# 1) Dependencies
flutter pub get

# 2) Static analysis (currently: No issues found)
dart analyze

# 3) Tests (currently: all 249 cases pass)
flutter test

# 4) Build the Android APK
flutter build apk --release
#    output: build/app/outputs/flutter-apk/app-release.apk
```

### Windows + Git Bash users (everyone else can skip this)

```bash
# Git Bash does not define %PROGRAMFILES(X86)%, and the Flutter tool exits with an
# error without it — inject it explicitly:
env 'PROGRAMFILES(X86)=C:\Program Files (x86)' 'PROGRAMFILES=C:\Program Files' flutter test

# If you run a system proxy, unset it and explicitly exclude loopback addresses —
# otherwise flutter_tester's local WebSocket gets intercepted and tests fail or
# hang randomly ("Invalid WebSocket upgrade request").
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
export no_proxy="localhost,127.0.0.1,::1,0.0.0.0"; export NO_PROXY="$no_proxy"
```

> ⚠️ **Never pass `--no-pub` when building the APK.** It skips regeneration of the Android plugin registrant, so the dev dependency `integration_test` ends up compiled into the release build and javac fails with `package dev.flutter.plugins.integration_test does not exist`. Using `--no-pub` for tests is safe. See [`docs/ENVIRONMENT.md` pitfall 4](docs/ENVIRONMENT.md).

### Producing a properly signed build (optional)

If `android/key.properties` is missing, release builds fall back to the debug signature so that a bare clone still builds. For a properly signed build, copy the example file and fill in your own keystore:

```bash
cp android/key.properties.example android/key.properties   # then edit it
```

```bash
keytool -genkeypair -v -keystore android/app/your-release.jks \
  -alias youralias -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=YourName, OU=Personal, O=YourName, L=Unknown, ST=Unknown, C=CN"
```

> Both files are in `.gitignore` and **are never committed**.

> **Current verification status**
> - ✅ `dart analyze`: zero errors / warnings / infos
> - ✅ `flutter test`: **all 249 cases pass** (money precision, GBK, deduplication, categories, recategorisation, migrations, backup, intent parsing, query engine, widgets)
> - ✅ `flutter build apk --release`: builds successfully, release-signed, **zero dangerous permissions**, covering arm64-v8a / armeabi-v7a / x86_64
> - ⚠️ `flutter build windows`: requires Visual Studio's "Desktop development with C++" workload
> - ⚠️ **Never run `PRAGMA journal_mode = WAL` on Android** — it makes `openDatabase` throw, which shows up as "database failed to open". See [`docs/DATABASE.md` §7.1](docs/DATABASE.md)

---

## Project layout

```
lib/
├── app/         theme, routing, app wiring
├── core/        money value object, Result, utilities, constants
├── domain/      entities, enums, services (dedup / categorisation / aggregation / import orchestration) — pure Dart
├── import/      bill parsing subsystem (decoding / spreadsheets / source detection / parsers)
├── data/        SQLite, migrations, repository implementations
├── features/    feature pages
└── shared/      shared widgets
test/
├── fixtures/    entirely fictional test data
├── core/        money precision
├── import/      parsing tests
├── domain/      dedup, categorisation, intent parsing, insights
├── data/        migrations, analytics DAO, backup, query engine, platform PRAGMA regression
└── widget/      UI and startup gate
docs/            design and specification documents
```

---

## Documentation

| File | Contents |
|---|---|
| [`docs/GITHUB_RESEARCH.md`](docs/GITHUB_RESEARCH.md) | Research on 6 reference projects and the adopt / reject decisions |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Layered architecture, data flow, technology choices, UI system, performance design |
| [`docs/DATABASE.md`](docs/DATABASE.md) | Full DDL for the 10 tables, dedup fingerprint algorithm, migration mechanism |
| [`docs/IMPORT_FORMATS.md`](docs/IMPORT_FORMATS.md) | Real WeChat / Alipay bill formats and parsing rules |
| [`docs/PRIVACY.md`](docs/PRIVACY.md) | Privacy commitments, AI privacy boundary, repository rules |
| [`docs/TESTING.md`](docs/TESTING.md) | Test strategy, must-test checklist, self-check checklist |
| [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) | **Full toolchain setup, the six pitfalls, current build limits and how to lift them** |

All documents are written in Chinese.

---

## Privacy

- No account or sign-up required
- Fully usable in aeroplane mode
- Bills are never uploaded to any server
- AI analysis (optional, off by default) sends only aggregate numbers, never merchants or order details

See [`docs/PRIVACY.md`](docs/PRIVACY.md) for details.

---

## Prior art

The following open-source projects were studied during the design phase (**study the design → understand the principles → reimplement**; no large chunks of code were copied):

- [MageGojo/lizhang](https://github.com/MageGojo/lizhang) — local-first bookkeeping in Flutter
- [zalexrose/FamilyFinanceManager](https://github.com/zalexrose/FamilyFinanceManager) — Python bill adapters
- [changdaye/bill-aggregator](https://github.com/changdaye/bill-aggregator) — SQLite schema and GBK handling
- [lemon970/jizhang-app](https://github.com/lemon970/jizhang-app) — module decomposition
- [dtsola/xiaoyaoprivatebill](https://github.com/dtsola/xiaoyaoprivatebill) — taxonomy of analysis dimensions
- [cxy0714/beancount-auto-bookkeeping](https://github.com/cxy0714/beancount-auto-bookkeeping) — declarative rules

---

## Licence

[MIT](LICENSE) © 2026 FinanceHub contributors

---

## Disclaimer

This project is a **personal finance tool**. It does not provide investment, tax or accounting advice and does not constitute professional opinion. Always check the parsed results yourself; the author accepts no liability for any loss arising from use of this software.

You are responsible for the bill files you import. The project follows **LOCAL FIRST**: no network access, no uploads — but **please still back up your data**, because the database lives only on your device and uninstalling the app removes it.
