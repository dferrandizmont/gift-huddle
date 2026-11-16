import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Última actualización privada del paquete antiguo para obtener la recuperación.
val legacyAppId = project.findProperty("legacyAppId") == "true"

// Firma de release: android/key.properties (fuera de git) apunta a la clave de subida
// fuera del repositorio. Sin ella, la release solo se firma con la clave de depuración
// si se pasa -PallowDebugSigning=true (nunca para tiendas).
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !keyProperties.getProperty(it).isNullOrBlank() }
val allowDebugSigning =
    (project.findProperty("allowDebugSigning") as String?)?.toBoolean() == true

android {
    namespace = "com.dferrandizmont.regalos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identificador definitivo elegido para el producto (2026-11-14).
        applicationId = if (legacyAppId) "app.gifthuddle" else "es.gifthuddle.app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // La puente solo se abre desde el lanzador; los enlaces y documentos son
    // de la app nueva. Recursos, Kotlin y firma siguen siendo los mismos.
    sourceSets.getByName("main") {
        manifest.srcFile(if (legacyAppId) "src/legacy/AndroidManifest.xml" else "src/main/AndroidManifest.xml")
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                allowDebugSigning -> signingConfigs.getByName("debug")
                // Sin clave la release sale sin firmar y no se puede instalar ni subir.
                else -> null
            }
        }
    }
}

// Revisión de la fase 2b, hallazgo 12: una versión de tienda
// (--dart-define=STORE_BUILD=true) no sale con App Links verificados
// (android:autoVerify) mientras web/public/.well-known lleve marcadores
// REEMPLAZAR_. Las prereleases (sin STORE_BUILD) no se comprueban.
val isStoreBuild = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.mapNotNull { entry ->
        runCatching { String(Base64.getDecoder().decode(entry)) }.getOrNull()
    }
    ?.any { it.trim() == "STORE_BUILD=true" } == true

val checkStoreAppLinks = tasks.register("checkStoreAppLinks") {
    description = "Falla si el manifiesto verifica App Links y quedan marcadores REEMPLAZAR_."
    val manifest = file("src/main/AndroidManifest.xml")
    // Cada plataforma comprueba solo su fichero: Android verifica sus App Links
    // con assetlinks.json; el Team ID de apple-app-site-association es cosa del
    // build de iOS (decisión de publicación del 2026-11-14). El README de
    // la carpeta también nombra los marcadores y no cuenta.
    val wellKnown = rootProject.file(
        project.findProperty("appLinksDir") as String? ?: "../../web/public/.well-known",
    )
    val published = listOf("assetlinks.json")
    doLast {
        // Lo comentado no cuenta: el manifiesto guarda un filtro desactivado.
        val active = manifest.readText().replace(Regex("<!--[\\s\\S]*?-->"), "")
        if (!Regex("android:autoVerify\\s*=\\s*\"true\"").containsMatchIn(active)) return@doLast
        val missing = published.filter { !wellKnown.resolve(it).isFile }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "Versión de tienda con android:autoVerify y sin ${missing.joinToString()} en " +
                    "$wellKnown (revisión de la fase 2b, hallazgo 12).",
            )
        }
        val left = published.filter { wellKnown.resolve(it).readText().contains("REEMPLAZAR_") }
        if (left.isNotEmpty()) {
            throw GradleException(
                "Versión de tienda con android:autoVerify y marcadores REEMPLAZAR_ en " +
                    "web/public/.well-known (${left.joinToString()}): pon las huellas reales " +
                    "antes de publicar (revisión de la fase 2b, hallazgo 12).",
            )
        }
    }
}

if (isStoreBuild) {
    tasks.named("preBuild") { dependsOn(checkStoreAppLinks) }
}
// Un AAB es para la tienda aunque se haya olvidado STORE_BUILD; las
// prereleases son APK y no pasan por aquí.
tasks.matching { it.name == "bundleRelease" }.configureEach { dependsOn(checkStoreAppLinks) }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
