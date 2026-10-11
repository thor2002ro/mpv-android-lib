import java.nio.file.Files
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.security.MessageDigest
import java.util.Properties
import java.util.Locale

@Suppress("UNCHECKED_CAST")
val splitAarRoots = extra["splitAarRoots"] as List<File>
fun aarSha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(1024 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(Locale.ROOT, it) }
}

splitAarRoots.asSequence().flatMap { it.walkTopDown() }
    .filter { it.isFile && it.name.endsWith(".aar.parts") }
    .forEach { manifest ->
        val metadata = Properties().apply { manifest.inputStream().use(::load) }
        val aar = File(manifest.parentFile, manifest.name.removeSuffix(".parts"))
        val count = metadata.getProperty("parts")?.toIntOrNull()
        val size = metadata.getProperty("size")?.toLongOrNull()
        val checksum = metadata.getProperty("sha256")
        require(count != null && size != null && count > 0 && size >= count &&
            checksum != null && checksum.matches(Regex("[0-9a-f]{64}"))) {
            "Invalid split AAR manifest: $manifest"
        }
        if (!aar.isFile || aar.length() != size || aarSha256(aar) != checksum) {
            val parts = (1..count).asSequence().map { File(manifest.parentFile, "${aar.name}.part%03d".format(Locale.ROOT, it)) }
            require(parts.all(File::isFile)) { "Missing split AAR part for $aar" }
            require(parts.all { it.length() in 1L..(90L * 1024 * 1024) } && parts.sumOf(File::length) == size) {
                "Split AAR size mismatch: $aar"
            }
            val temporary = Files.createTempFile(aar.parentFile.toPath(), aar.name, ".tmp").toFile()
            try {
                temporary.outputStream().use { output ->
                    parts.forEach { part -> part.inputStream().use { it.copyTo(output) } }
                }
                require(temporary.length() == size && aarSha256(temporary) == checksum) {
                    "Split AAR checksum mismatch: $aar"
                }
                Files.move(temporary.toPath(), aar.toPath(), REPLACE_EXISTING)
                println("Restored split AAR: ${aar.name}")
            } finally {
                temporary.delete()
            }
        }
    }
