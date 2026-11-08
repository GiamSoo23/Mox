import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Supabase credentials come from local.properties, which git ignores, so they
// never end up in source control. Missing values build an app that says it
// isn't configured (CI builds this way).
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun localProperty(name: String): String = localProperties.getProperty(name, "").trim()

android {
    namespace = "com.mox.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.mox.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        buildConfigField("String", "SUPABASE_URL", "\"${localProperty("mox.supabaseUrl")}\"")
        buildConfigField("String", "SUPABASE_KEY", "\"${localProperty("mox.supabaseKey")}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // JVM unit tests. org.json is added explicitly because android.jar only
    // ships stubs of it for local tests.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260814")
}

// ---------------------------------------------------------------------------
// ktlint: Kotlin style check. Uses the official CLI directly (no third-party
// Gradle plugin). Rules and code style come from the repo's .editorconfig.
//   ./gradlew ktlintCheck    report problems (also runs with `check`)
//   ./gradlew ktlintFormat   fix what can be fixed automatically
// ---------------------------------------------------------------------------
val ktlint: Configuration by configurations.creating

dependencies {
    ktlint("com.pinterest.ktlint:ktlint-cli:1.8.0") {
        attributes {
            attribute(Bundling.BUNDLING_ATTRIBUTE, objects.named(Bundling.EXTERNAL))
        }
    }
}

val ktlintSources = listOf("**/src/**/*.kt", "**/*.kts", "!**/build/**")

val ktlintCheck by tasks.registering(JavaExec::class) {
    group = LifecycleBasePlugin.VERIFICATION_GROUP
    description = "Checks Kotlin code style with ktlint."
    classpath = ktlint
    mainClass.set("com.pinterest.ktlint.Main")
    workingDir = rootDir
    args(ktlintSources)
}

tasks.register<JavaExec>("ktlintFormat") {
    group = LifecycleBasePlugin.VERIFICATION_GROUP
    description = "Formats Kotlin code with ktlint."
    classpath = ktlint
    mainClass.set("com.pinterest.ktlint.Main")
    jvmArgs("--add-opens=java.base/java.lang=ALL-UNNAMED")
    workingDir = rootDir
    args(listOf("--format") + ktlintSources)
}

tasks.named("check") { dependsOn(ktlintCheck) }
