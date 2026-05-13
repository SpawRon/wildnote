import java.util.Properties
import java.io.FileInputStream

// 1. Загружаем настройки ключа безопасно
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeyProperties = keystorePropertiesFile.exists()

if (hasKeyProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Извлекаем значения с безопасным приведением типов
val myKeyAlias = (keystoreProperties["keyAlias"] as? String) ?: ""
val myKeyPassword = (keystoreProperties["keyPassword"] as? String) ?: ""
val myStoreFile = (keystoreProperties["storeFile"] as? String) ?: ""
val myStorePassword = (keystoreProperties["storePassword"] as? String) ?: ""

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "mauniver.ivt.ponarin.wildnote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "mauniver.ivt.ponarin.wildnote"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Если файл ключей есть — используем его, иначе временно подставляем пустые строки
            keyAlias = myKeyAlias
            keyPassword = myKeyPassword
            storeFile = if (myStoreFile.isNotEmpty()) file(myStoreFile) else null
            storePassword = myStorePassword
        }
    }

    buildTypes {
        getByName("release") {
            // Если ключей нет, используем стандартную debug-подпись, чтобы сборка не ломалась
            signingConfig = if (hasKeyProperties) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
