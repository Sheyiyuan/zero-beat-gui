package dev.sheyiyuan.zero_beat_gui

import java.io.File
import java.io.InputStream

/** One instance per process; activity recreation must not delete playing files. */
internal class ResourceCache(private val directory: File) {
    init {
        check(directory.isDirectory || directory.mkdirs()) { "无法创建本地音频缓存" }
        // No handles from a previous process remain open.
        directory.listFiles()?.filter { it.name.startsWith("resource-") }?.forEach { it.delete() }
    }

    fun stage(input: InputStream): File = input.use { stream ->
        val file = File.createTempFile("resource-", ".media", directory)
        try {
            file.outputStream().use { stream.copyTo(it) }
            file
        } catch (e: Exception) {
            file.delete()
            throw e
        }
    }
}
