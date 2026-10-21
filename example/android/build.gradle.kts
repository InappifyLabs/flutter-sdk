allprojects {
    repositories {
        // Use an already built native SDK without sharing incompatible Gradle toolchains.
        providers.gradleProperty("inappifyKotlinSdkRepository").orNull?.let { repositoryPath ->
            exclusiveContent {
                forRepository {
                    maven {
                        name = "LocalInappifyKotlinSdk"
                        url = uri(repositoryPath)
                    }
                }
                filter { includeModule("com.github.InappifyLabs", "kotlin-sdk") }
            }
        }
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
