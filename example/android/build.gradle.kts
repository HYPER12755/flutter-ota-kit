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
subprojects {
    // The device only has Android SDK Platform 36 installed (and the SDK dir is
    // read-only, so missing platforms can't be fetched). Some plugins (e.g.
    // restart_app) pin an older compileSdk (34) that isn't present, which fails
    // the build. Force every Android subproject to compile against the installed
    // platform. Registered before evaluationDependsOn so it runs pre-evaluation.
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            try {
                (ext as com.android.build.gradle.BaseExtension).compileSdkVersion(36)
            } catch (_: Throwable) {
                // Not an Android project or incompatible extension; ignore.
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
