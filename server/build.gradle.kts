import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    kotlin("jvm") version "1.9.24"
    kotlin("plugin.serialization") version "1.9.24"
    application
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

group = "com.debridmusic.server"
version = "0.1.0"

repositories {
    mavenCentral()
}

val ktorVersion = "2.3.12"

dependencies {
    // Ktor server (Netty engine) + content negotiation + partial content (Range) + CORS.
    implementation("io.ktor:ktor-server-core-jvm:$ktorVersion")
    implementation("io.ktor:ktor-server-netty-jvm:$ktorVersion")
    implementation("io.ktor:ktor-server-content-negotiation-jvm:$ktorVersion")
    implementation("io.ktor:ktor-serialization-kotlinx-json-jvm:$ktorVersion")
    implementation("io.ktor:ktor-server-partial-content-jvm:$ktorVersion")
    implementation("io.ktor:ktor-server-auto-head-response-jvm:$ktorVersion")
    implementation("io.ktor:ktor-server-cors-jvm:$ktorVersion")
    implementation("io.ktor:ktor-server-status-pages-jvm:$ktorVersion")
    implementation("io.ktor:ktor-server-call-logging-jvm:$ktorVersion")

    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")

    // HTML scraping for the RuTracker source (pure JVM).
    implementation("org.jsoup:jsoup:1.17.2")

    // SQLite index (raw JDBC, no ORM).
    implementation("org.xerial:sqlite-jdbc:3.46.0.0")

    // Audio tag reading.
    implementation("net.jthink:jaudiotagger:3.0.1")

    // Logging.
    implementation("ch.qos.logback:logback-classic:1.5.6")

    testImplementation("io.ktor:ktor-server-test-host-jvm:$ktorVersion")
    testImplementation(kotlin("test"))
}

application {
    mainClass.set("com.debridmusic.server.MainKt")
}

tasks.withType<KotlinCompile> {
    kotlinOptions { jvmTarget = "17" }
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}

tasks.shadowJar {
    archiveBaseName.set("musicserver")
    archiveClassifier.set("")
    archiveVersion.set("")
    mergeServiceFiles()
}
