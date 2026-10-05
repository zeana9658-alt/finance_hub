# ENVIRONMENT.md — 工具链搭建与构建指南

> 本文件记录**在 Windows 上从零搭建 Flutter + Android 工具链**的完整过程、踩过的坑，
> 以及可复现的构建命令。目的是让下一个人（或下一次会话）不用重复摸索。
>
> 📌 **路径约定**：文中的 `C:\tools\` 是"工具链根目录"的**占位符**，
> 请替换成你自己的实际路径（如 `D:\dev\sdk`、`C:\Users\<你>\sdk`）。
> 凡是需要你替换的地方都会显式标注。

---

## 1. 已安装的工具链

| 组件 | 版本 | 位置（示例） |
|---|---|---|
| Flutter SDK | 3.47.6 stable | `C:\tools\flutter` |
| Dart | 3.13.5 | 随 Flutter SDK |
| JDK | Temurin **21.0.12.1+1** | `C:\tools\jdk-21.0.12.1+1` |
| Gradle | **9.3.1** | `C:\tools\gradle-9.3.1` |
| Android SDK | platforms **35 + 36**、build-tools **36.0.0 / 37.0.0**、platform-tools | `C:\tools\android-sdk` |
| Android NDK | **28.2.13676358**（= r28c） | `...\android-sdk\ndk\28.2.13676358` |
| CMake | **3.22.1** | `...\android-sdk\cmake\3.22.1` |
| Git | 2.55.0 | 系统 |

Flutter 已通过 `flutter config` 记住 SDK 与 JDK 路径，无需每次重设。

---

## 2. 六个必踩的坑（务必先看）

### 坑 1：`http_proxy` 会让 `flutter pub get` 假死

本机默认设置了 `http_proxy=http://127.0.0.1:64886`。
带代理时 pub 会长时间停在 `Resolving dependencies...`。

**跑 pub / flutter 构建前先 unset 代理：**

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
```

> ⚠️ 反直觉之处：**curl 恰恰相反** —— 用 curl 探测站点时必须**保留**代理，
> unset 掉就完全没网（全部返回 000）。Flutter/Dart 自己能走系统代理。

### 坑 1.5：unset 代理还不够，必须再把 `localhost` 加进 `no_proxy`

**症状**：`flutter test` 随机失败或**永久挂起**，报

```
Unable to connect to flutter_tester process:
WebSocketException: Invalid WebSocket upgrade request
```

或者干脆什么都不报，测试停在 `did not complete`，日志长时间不增长。

**原因**：`flutter test` 会起一个 `flutter_tester` 子进程，Dart 通过
**本机 WebSocket**（127.0.0.1 随机端口）与它通信。系统级代理设置会把这条
本地回环连接也劫持走，代理不认识 WebSocket 升级请求，于是握手失败。
表现是"随机"的，因为端口是随机的 —— 极容易被误判成"测试本身有 bug"。

**解决**：显式把回环地址排除：

```bash
export no_proxy="localhost,127.0.0.1,::1,0.0.0.0"
export NO_PROXY="$no_proxy"
```

> 排查心得：`flutter test` 出现**没有断言失败、只是不结束**的情况时，
> 先怀疑通信链路，不要先怀疑被测代码。用 `--reporter expanded` 能看到
> 卡在哪个用例，用 `timeout` 包一层避免无限等待。

### 坑 1.6：两个 flutter 命令**不能并行** —— 会死在启动锁上

Flutter 用 `bin/cache/lockfile` 做启动锁。前一个命令（哪怕是被中断、
被 kill 掉的）没退干净时，后一个会停在：

```
Waiting for another flutter command to release the startup lock...
```

**而且没有任何超时**，看起来就像"构建卡住了"。表现极具误导性：
`build/` 下不再有新文件、进程列表里看不到 java/dart，但也不报错 ——
很容易被误判成"Gradle 在慢速下载"或"网络问题"。

**判断与对策**：

- 怀疑卡锁时先跑 `flutter --version`：如果它也被挡住，就是锁。
- **一次只跑一个 flutter 命令。** 不要为了"省时间"并行开构建。
- 后台任务被中断后，先确认进程真的退出了，再发起下一次构建。
- 锁是 OS 级文件锁，进程退出即释放，**不需要手工删 `lockfile`**。

### 坑 2：pub 的包数在完成前**不会增长**——不要中途杀进程

pub 把包解压到 `%LOCALAPPDATA%\Pub\Cache\_temp\dirXXXX`，
**全部下载完才一次性改名**到 `hosted/pub.dev/<pkg>-<ver>/`。
判断是否真卡住，要看 `_temp` 里的 `dir*` 数量是否增长。

### 坑 3：`flutter test` / `flutter build` 需要 `%PROGRAMFILES(X86)%`

Git Bash 里没有这个 Windows 变量，Flutter 工具会直接报错退出：

```
%PROGRAMFILES(X86)% environment variable not found.
```

**解决：用 `env` 显式注入。**

```bash
env 'PROGRAMFILES(X86)=C:\Program Files (x86)' 'PROGRAMFILES=C:\Program Files' flutter build apk
```

### 坑 4：`flutter build apk` **绝不能**加 `--no-pub`

本项目最阴的一个坑：跑测试加 `--no-pub` 是好习惯，**构建 APK 加它会直接编译失败**。

```
错误: 程序包dev.flutter.plugins.integration_test不存在
      GeneratedPluginRegistrant.java:24
```

**机理**（读 flutter_tools 源码确认，见 `runner/flutter_command.dart` 与 `commands/packages.dart`）：

1. Android 的插件注册表 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
   由 Dart 侧生成，入口 `regeneratePlatformSpecificToolingIfApplicable()` 第一句是
   ```dart
   if (!shouldRunPub) {
     return;
   }
   ```
   —— **`--no-pub` 会完全跳过注册表的重新生成**，直接用磁盘上那份旧的。
2. `flutter pub get` 也会生成它，但传的是
   ```dart
   releaseMode: ignoreReleaseModeSinceItsNotABuildAndHopeItWorks
   ```
   （变量名是官方原话）。`releaseMode: false` 时**不过滤 dev 依赖**，
   于是 `dev_dependencies` 里的 `integration_test` 被写进注册表。
3. `integration_test` 是 SDK 提供的 dev 插件，release 构建里没有这个包 →
   javac 报"程序包不存在"。

于是形成一条很坏的因果链：**任何一次 `flutter pub get`（包括 `flutter test`
隐式触发的）都会把注册表写脏，而带 `--no-pub` 的 release 构建会原样用这份脏文件。**

**对策**：

- 构建 APK **不要**加 `--no-pub`。`flutter build apk --release` 会以
  `releaseMode: true` 重新生成注册表，自动过滤掉 dev 依赖插件。
- 自查（期望输出 `0`）：
  ```bash
  grep -c integration_test \
    android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
  ```

> 顺带说明：**`flutter test --no-pub` 是安全的**（测试不碰 Android 注册表），
> 所以"测试用 `--no-pub`、构建不用"这个组合是对的 —— 不要因为踩了这个坑
> 就把测试的 `--no-pub` 也去掉。

---

## 3. 标准命令（复制即用）

```bash
export PATH="/c/tools/flutter/bin:$PATH"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
export no_proxy="localhost,127.0.0.1,::1,0.0.0.0"
export NO_PROXY="$no_proxy"
export JAVA_HOME="C:\\tools\\jdk-21.0.12.1+1"
export ANDROID_HOME="C:\\tools\\android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export GRADLE_USER_HOME="%TEMP%\\gradle-home"
cd /path/to/finance_hub

flutter pub get
dart analyze                                  # 当前：No issues found
env 'PROGRAMFILES(X86)=C:\Program Files (x86)' 'PROGRAMFILES=C:\Program Files' flutter test --no-pub
                                              # 当前：247 个用例全部通过

# 出 APK（约 12 分钟，首次会久一些）
env 'PROGRAMFILES(X86)=C:\Program Files (x86)' 'PROGRAMFILES=C:\Program Files' \
  flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

---

## 4. 构建 APK 的完整依赖（缺一不可）

这一步花了最久，把每个卡点都记下来：

| 卡点报错 | 原因 | 解决 |
|---|---|---|
| `ClassNotFoundException: GradleWrapperMain` | 在 Git Bash 里直接跑 `./gradlew`，路径含空格导致 classpath 失效 | 改用 `flutter build apk`，不要手搓 gradlew |
| 停在 `Running Gradle task 'assembleRelease'...` 十几分钟无输出 | AGP 在跑 `sdkmanager --install ndk;28.2.13676358`（`jni` 插件声明了 `ndkVersion`）。sdkmanager 走系统代理能通，但 2 GB 下载极慢 | 手动装 NDK 到 `android-sdk/ndk/28.2.13676358/` |
| `Failed to find target with hash string 'android-35'` | `jni` / `jni_flutter` 硬编码 `compileSdk 35`，项目其他模块用 36 | 补装 `platforms/android-35` |
| `[CXX1300] CMake '3.22.1' was not found` | `jni` 会用 CMake 编译 `libdartjni.so`，**确实需要原生工具链** | 装 CMake 3.22.1，并把 `bin/`、`share/`、`source.properties` 一起放到 `android-sdk/cmake/3.22.1/` |

> **教训**：Gradle「卡住」时第一件事是 `flutter build apk -v` 看最后一行输出，
> 不要凭感觉猜是网络慢还是被拦。

---

## 5. Android SDK 的手动组装方法（sdkmanager 走不通时）

sdkmanager 的仓库地址**硬编码 `dl.google.com`**，无法改镜像。
在受限网络下按下面的办法手动组装：

1. 取仓库索引：
   - `https://mirrors.cloud.tencent.com/AndroidSDK/repository2-3.xml`
   - 或 Google 自家 CDN 旁路：`https://redirector.gvt1.com/edgedl/android/repository/repository2-3.xml`
2. 从 XML 里 grep 出包的确切文件名（如 `platform-36_r02.zip`、`build-tools_r36_windows.zip`）
3. 从 `https://mirrors.cloud.tencent.com/AndroidSDK/<文件名>` 下载
4. **注意压缩包内部顶层目录名 ≠ 目标目录名**，必须重命名：

   | 压缩包 | 内部顶层 | 目标路径 |
   |---|---|---|
   | `platform-36_r02.zip` | `android-36/` | `platforms/android-36` |
   | `build-tools_r36_windows.zip` | `android-16/` | `build-tools/36.0.0` |
   | `build-tools_r37_windows.zip` | `android-37.0/` | `build-tools/37.0.0` |
   | `platform-tools_*.zip` | `platform-tools/` | `platform-tools` |
   | `commandlinetools-*.zip` | `cmdline-tools/` | `cmdline-tools/latest` |
   | `android-ndk-r28c-windows.zip` | `android-ndk-r28c/` | `ndk/28.2.13676358` |
   | `cmake-3.22.1-windows.zip` | `bin/` + `share/` | `cmake/3.22.1/{bin,share,source.properties}` |

5. **必须手写许可证文件**，否则 AGP 报未接受许可：
   - `licenses/android-sdk-license`（三行哈希）
   - `licenses/android-sdk-preview-license`

---

## 6. 构建产物与安装

```
finance_hub/dist/finance_hub-v0.1.1-release.apk
finance_hub/dist/finance_hub-v0.1.1-release.apk.sha256
finance_hub/dist/archive/          # 历史构建，仅留档，不要安装
```

> `dist/archive/` 里的 `finance_hub-v0.1.0-release.apk` 是**修复前**的构建
> （手机端会「数据库打开失败」），只作为对照保留，**不要安装到手机**。

| 项 | 值 |
|---|---|
| 包名 | `com.financehub.finance_hub` |
| 应用名 | 聚账 |
| versionName / versionCode | 0.1.1 / 2 |
| minSdk / targetSdk / compileSdk | 24 / 36 / 36 |
| 覆盖 ABI | arm64-v8a、armeabi-v7a、x86_64 |
| 签名 | `CN=FinanceHub, OU=Personal Finance, O=FinanceHub, L=Beijing, ST=Beijing, C=CN` |
| 签名方案 | APK Signature Scheme v2 ✅ |
| 权限 | **零危险权限**（仅 AndroidX 自动生成的 DYNAMIC_RECEIVER） |

**安装**：把 APK 传到手机，允许「安装未知来源应用」后点击安装即可。

> 签名用的是本项目专属的 release 密钥库（`android/app/finance_hub-release.jks`，
> 口令在 `android/key.properties`，两者都已 `.gitignore`）。
> **请务必备份这个 .jks** —— 丢了就无法覆盖升级已安装的 App，只能卸载重装。

---

## 7. 未打通的路径

### `flutter build windows`

Visual Studio 已安装，但缺「使用 C++ 的桌面开发」工作负载，
Flutter 报 `Unable to find suitable Visual Studio toolchain`。

**解除方法**：打开 Visual Studio Installer → 修改 → 勾选
「使用 C++ 的桌面开发」（含 MSVC v143 生成工具 + Windows 10/11 SDK）。

> 另有一个 Flutter 侧已知问题：`windows/flutter/ephemeral/.plugin_symlinks/`
> 里的符号链接若已存在，Flutter 会报 `errno 183 文件已存在` 而不是跳过。
> 遇到时把 `windows/flutter/ephemeral` 整个目录移走再构建。

---

## 8. 本环境的验证强度

| 验证项 | 状态 |
|---|---|
| `dart analyze` | ✅ No issues found |
| `flutter test` | ✅ 247 个用例全部通过 |
| `flutter build apk --release` | ✅ **成功**，产物已验签 |
| `flutter build windows` | ❌ VS 缺 C++ 工作负载（见 §7） |
