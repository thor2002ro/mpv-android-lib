buildscript {
    val kotlinVersion by extra("2.4.10")
    repositories {
        mavenCentral()
        gradlePluginPortal()
        google()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.3.2")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

plugins {
    id("com.vanniktech.maven.publish") version "0.37.0"
}

allprojects {
    repositories {
        mavenCentral()
        gradlePluginPortal()
        google()
    }
}

