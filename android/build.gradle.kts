allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.buildDir = "../build"

subprojects {
    project.buildDir = "${rootProject.buildDir}/${project.name}"
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Force compileSdk 36 for every Android library/plugin module
subprojects { sub ->
    sub.afterEvaluate {
        if (sub.plugins.hasPlugin("com.android.library") ||
            sub.plugins.hasPlugin("com.android.application")) {
            sub.android {
                compileSdk = 36
            }
        }
    }
}

tasks.register("clean", Delete) {
    delete rootProject.buildDir
}