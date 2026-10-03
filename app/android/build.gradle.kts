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
    project.evaluationDependsOn(":app")
}
subprojects {
    val configureSdk = {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            try {
                val setCompileSdk = androidExt.javaClass.getMethod("setCompileSdk", java.lang.Integer::class.java)
                setCompileSdk.invoke(androidExt, 36)
            } catch (_: Exception) {
                try {
                    val compileSdkVersion = androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    compileSdkVersion.invoke(androidExt, 36)
                } catch (_: Exception) {}
            }
        }
    }
    if (project.state.executed) {
        configureSdk()
    } else {
        project.afterEvaluate { configureSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
