# ENVIRONMENT.md — 工具链搭建与已知限制

> 本文件记录**本机从零搭建 Flutter 环境**的完整过程、踩过的坑，以及当前仍存在的限制。
> 目的是让下一个人（或下一次会话）不用重复摸索。

---

## 1. 已完成的搭建

| 组件 | 版本 | 位置 |
|---|---|---|
| Flutter SDK | 3.47.6 stable | `C:\Users\kol56\.workbuddy-ai\tools\flutter` |
| Dart | 3.13.5 | 随 Flutter SDK |
| Git | 2.55.0 | 系统 |

安装来源：`https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.6-stable.zip`（1.93 GB，解压约 12 分钟）。

> 安装路径刻意选**无空格**的目录，避免 Gradle / CMake 处理空格路径时出问题。

### 1.1 环境变量

每次开新终端都需要：

```bash
export PATH="/c/Users/kol56/.workbuddy-ai/tools/flutter/bin:$PATH"
```

---

## 2. 三个必踩的坑（务必先看）

### 坑 1：`http_proxy` 会让 `flutter pub get` 假死

本机默认设置了 `http_proxy=http://127.0.0.1:64886`。
带代理时 pub 会长时间停在 `Resolving dependencies...`，看起来像卡死。

**解决：跑 pub 前先 unset 代理。**

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
flutter pub get
```

### 坑 2：pub 的包数在完成前**不会增长**——不要中途杀进程

pub 把包解压到 `%LOCALAPPDATA%\Pub\Cache\_temp\dirXXXX`，
**全部下载完才一次性改名**到 `hosted/pub.dev/<pkg>-<ver>/`。

所以中途查看缓存目录，包数是不变的。看起来像卡住，其实在正常工作。
本次因为反复误判"卡死"并杀进程，白白多花了一个多小时。

**判断是否真卡住的方法**：看 `_temp` 目录里的 `dir*` 数量是否在增长，而不是看包数。

### 坑 3：`flutter test` / `flutter build` 需要 `%PROGRAMFILES(X86)%`

Git Bash 环境里没有这个 Windows 变量，Flutter 工具会直接报错退出：

```
%PROGRAMFILES(X86)% environment variable not found.
```

**解决：用 `env` 显式注入。**

```bash
env 'PROGRAMFILES(X86)=C:\Program Files (x86)' \
    'PROGRAMFILES=C:\Program Files' \
    flutter test
```

---

## 3. 标准命令（复制即用）

```bash
export PATH="/c/Users/kol56/.workbuddy-ai/tools/flutter/bin:$PATH"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
cd "C:\Users\kol56\WorkBuddy AI\2026-10-05-16-44-05\finance_hub"

# 依赖
flutter pub get

# 静态分析（当前结果：No issues found）
dart analyze

# 测试（当前结果：110 个用例全部通过）
env 'PROGRAMFILES(X86)=C:\Program Files (x86)' 'PROGRAMFILES=C:\Program Files' flutter test

# 只跑解析相关测试
env 'PROGRAMFILES(X86)=C:\Program Files (x86)' 'PROGRAMFILES=C:\Program Files' \
  flutter test test/import/
```

---

## 4. 当前未打通的两条构建路径

### 4.1 `flutter build apk` —— 缺 JDK 与 Android SDK

实测缺失：`java` 不在 PATH、`ANDROID_HOME` 未设置、默认 Android SDK 目录不存在。

**解除方法**（需要用户手动执行，约 3–5 GB 下载）：

1. 安装 JDK 17（Temurin 或 Oracle）
2. 安装 Android SDK Command-line Tools，并装：
   ```bash
   sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
   ```
3. 设置 `ANDROID_HOME` 与 `ANDROID_SDK_ROOT`
4. Gradle 依赖需要走镜像（`repo1.maven.org` 在本机**不可达**，
   `maven.aliyun.com` 可达）。在 `android/build.gradle.kts` 里加：
   ```kotlin
   maven { url = uri("https://maven.aliyun.com/repository/public") }
   maven { url = uri("https://maven.aliyun.com/repository/google") }
   ```
5. 然后 `flutter build apk --release`

### 4.2 `flutter build windows` —— Visual Studio 缺 C++ 工作负载

`C:\Program Files\Microsoft Visual Studio` **存在**，但 Flutter 报：

```
Unable to find suitable Visual Studio toolchain.
```

说明装的是 VS 但**没有勾选「使用 C++ 的桌面开发」工作负载**。

**解除方法**：打开 Visual Studio Installer → 修改 → 勾选
「使用 C++ 的桌面开发」（含 MSVC v143 生成工具 + Windows 10/11 SDK）。

> 另有一个已知的 Flutter 侧问题：`windows/flutter/ephemeral/.plugin_symlinks/`
> 里的符号链接若已存在，Flutter 会报 `errno 183 文件已存在` 而不是跳过。
> 遇到时把 `windows/flutter/ephemeral` 整个目录移走再构建即可。

---

## 5. 本环境的验证强度说明

| 验证项 | 状态 |
|---|---|
| `dart analyze` | ✅ **No issues found**（零 error / 零 warning / 零 info） |
| `flutter test` | ✅ **110 个用例全部通过** |
| 单元测试覆盖 | 金额精度、GBK 一致性、表头定位、微信/支付宝解析、来源识别、去重（含跨平台）、分类优先级、迁移与仓储、金额完整性 |
| Widget 测试覆盖 | 空态、小屏 360×640、1.5× 大字体、暗色模式、五页导航、未实现功能显式声明 |
| `flutter build apk` | ❌ 缺 JDK + Android SDK（见 §4.1） |
| `flutter build windows` | ❌ VS 缺 C++ 工作负载（见 §4.2） |

**结论**：代码逻辑已被静态分析与 110 个测试充分验证；
两条打包路径受限于本机工具链，不是代码问题。按 §4 补齐后即可直接构建。
