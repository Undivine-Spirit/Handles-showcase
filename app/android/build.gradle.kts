allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// flutter_displaymode's own android/build.gradle hardcodes
// `compileSdkVersion 33` directly (verified in the pub cache - not derived
// from Flutter's default at all, just an outdated literal the plugin
// author never bumped). Setting compileSdk in app/build.gradle.kts alone
// only affects the :app module, not plugin subprojects - and a plain
// `plugins.withType { }` callback here fires as soon as the plugin applies
// itself, which is *before* that hardcoded line later in the same script
// runs, so it would just get overwritten right back to 33. `afterEvaluate`
// defers this until the whole subproject script (hardcoded line included)
// has already run, so this override actually wins. Registered before
// evaluationDependsOn(":app") below - that call forces early evaluation of
// some subprojects, and Gradle refuses to register a new afterEvaluate
// once a project's evaluation has already finished.
subprojects {
    afterEvaluate {
        plugins.withType<com.android.build.gradle.BasePlugin> {
            extensions.configure<com.android.build.gradle.BaseExtension> {
                compileSdkVersion(36)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
