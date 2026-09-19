import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La firma de release sale de android/key.properties, que no va al repositorio
// (ver «Firma de release» en el README). Sin ese fichero la release se firma con
// la clave de depuración, para que `flutter run --release` funcione en cualquier
// clon; build_apk.sh se niega a producir un APK así.
val ficheroDeFirma = rootProject.file("key.properties")
val hayFirmaDeRelease = ficheroDeFirma.exists()
val propiedadesDeFirma = Properties().apply {
    if (hayFirmaDeRelease) ficheroDeFirma.inputStream().use { load(it) }
}

fun propiedadDeFirma(nombre: String): String =
    propiedadesDeFirma.getProperty(nombre)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("android/key.properties: falta «$nombre»")

android {
    namespace = "com.diegoandresvega.dividi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications necesita desugaring de java.time
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.diegoandresvega.dividi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayFirmaDeRelease) {
            create("release") {
                storeFile = file(propiedadDeFirma("storeFile"))
                storePassword = propiedadDeFirma("storePassword")
                keyAlias = propiedadDeFirma("keyAlias")
                keyPassword = propiedadDeFirma("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // R8 (minify y shrinkResources) lo activa el plugin de Flutter en release.
            signingConfig = signingConfigs.getByName(if (hayFirmaDeRelease) "release" else "debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
