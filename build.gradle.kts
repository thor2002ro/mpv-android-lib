buildscript {
    val kotlinVersion by extra("2.4.10")
    repositories {
        mavenCentral()
        gradlePluginPortal()
        google()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.4.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

plugins {
    id("com.vanniktech.maven.publish") version "0.37.0"
}

allprojects {
    repositories {
        providers.gradleProperty("libassProviderRepository").orNull?.let { providerRepository ->
            exclusiveContent {
                forRepository {
                    maven {
                        name = "libassProvider"
                        url = uri(providerRepository)
                    }
                }
                filter {
                    includeModule("io.github.peerless2012", "libass-android-provider")
                }
            }
        }
        mavenCentral()
        gradlePluginPortal()
        google()
    }
}

