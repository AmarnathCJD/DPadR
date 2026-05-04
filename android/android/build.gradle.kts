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

    // Workaround for old Flutter plugins (e.g. flutter_bluetooth_serial 0.4.0) that
    // predate AGP 8's mandatory `namespace` requirement. If a library plugin doesn't
    // set a namespace, derive one from its declared package attribute in the manifest.
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val pkg = Regex("""package\s*=\s*"([^"]+)"""")
                        .find(manifestFile.readText())
                        ?.groupValues
                        ?.get(1)
                    if (pkg != null) {
                        namespace = pkg
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
