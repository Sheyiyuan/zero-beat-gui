package dev.sheyiyuan.zero_beat_gui

import android.webkit.CookieManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Reads cookies the official login page stored in the system WebView.
 * Only the hosts used by the in-app login are readable. Values are not logged.
 */
object WebLoginCookies {
    private const val channelName = "zero_beat/web_login"
    private val hosts = setOf(
        "music.163.com",
        "y.music.163.com",
        "interface.music.163.com",
        "interface3.music.163.com",
        "163.com",
        "bilibili.com",
        "www.bilibili.com",
        "m.bilibili.com",
        "passport.bilibili.com",
    )

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    val urls = call.argument<List<String>>("urls").orEmpty()
                    result.success(read(urls))
                }
                "clear" -> CookieManager.getInstance().removeAllCookies {
                    CookieManager.getInstance().flush()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun read(urls: List<String>): Map<String, String> {
        val manager = CookieManager.getInstance()
        manager.flush()
        val merged = linkedMapOf<String, String>()
        for (url in urls) {
            if (!allowed(url)) continue
            val header = manager.getCookie(url).orEmpty()
            for (part in header.split(';')) {
                val item = part.trim()
                val eq = item.indexOf('=')
                if (eq <= 0) continue
                val name = item.substring(0, eq).trim()
                val value = item.substring(eq + 1).trim()
                if (name.isNotEmpty() && value.isNotEmpty()) merged[name] = value
            }
        }
        return merged
    }

    private fun allowed(url: String): Boolean {
        if (!url.startsWith("https://")) return false
        val host = url.removePrefix("https://").substringBefore('/').substringBefore(':').lowercase()
        if (host in hosts) return true
        return hosts.any { host == it || host.endsWith(".$it") }
    }
}
