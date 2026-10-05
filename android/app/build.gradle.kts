import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─────────────────────────────────────────────────────────────
// 签名配置：从 android/key.properties 读取（该文件不入库，见 .gitignore）
// 文件不存在时退回 debug 签名，保证「裸克隆也能构建」。
// ─────────────────────────────────────────────────────────────
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.financehub.finance_hub"
    compileSdk = flutter.compileSdkVersion

    // 说明：本项目的依赖链里**确实有原生代码** —— `jni`（file_picker 的传递依赖）
    // 会用 CMake 编译 libdartjni.so，因此需要 NDK 与 CMake。
    // 由于 android.builder.sdkDownload=false（避免 sdkmanager 在受限网络下挂起），
    // AGP 不会自动下载它们，必须预先放好：
    //   $ANDROID_HOME/ndk/<version>/    ← 版本由 jni 插件声明（当前 28.2.13676358 = r28c）
    //   $ANDROID_HOME/cmake/3.22.1/     ← 或在 local.properties 里配 cmake.dir

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.financehub.finance_hub"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                storeFile = file(
                    keystoreProperties.getProperty("storeFile")
                        ?: "finance_hub-release.jks",
                )
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 体积已经很小（58 MB，主要来自三个 ABI 的 Flutter 引擎），
            // 先不开混淆，避免引入难以排查的反射问题。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
