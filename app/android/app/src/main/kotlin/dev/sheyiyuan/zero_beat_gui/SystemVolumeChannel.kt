package dev.sheyiyuan.zero_beat_gui

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Android media stream (`STREAM_MUSIC`) to Flutter.
 *
 * The system mixer is the final volume stage, so the mobile slider controls the
 * real phone volume instead of the core/mpv volume. Hardware volume keys and
 * other apps change the same stream; a ContentObserver plus the framework's
 * volume-changed broadcast report those changes back to Dart.
 *
 * Observers are only registered while Dart has an active EventChannel listener,
 * so leaving the full player stops the platform-side work.
 */
class SystemVolumeChannel(private val activity: Activity) {
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var watching = false
    private var lastVolume = -1
    private var lastMax = -1

    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean, uri: android.net.Uri?) {
            if (uri == null || uri == Settings.System.getUriFor(MUSIC_VOLUME_KEY)) emit()
        }
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val stream = intent?.getIntExtra(EXTRA_VOLUME_STREAM_TYPE, -1) ?: -1
            if (stream == -1 || stream == AudioManager.STREAM_MUSIC) emit()
        }
    }

    fun register(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> result.success(audio.getStreamVolume(AudioManager.STREAM_MUSIC))
                    "max" -> result.success(audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC))
                    "set" -> {
                        val requested = when (val args = call.arguments) {
                            is Number -> args.toInt()
                            is Map<*, *> -> (args["volume"] as? Number)?.toInt()
                            else -> null
                        }
                        if (requested == null) {
                            result.error("bad_args", "缺少系统音量值", null)
                        } else {
                            val value = requested.coerceIn(0, maxVolume())
                            if (value > 0 && audio.isStreamMute(AudioManager.STREAM_MUSIC)) {
                                // setStreamVolume changes the index but does not
                                // clear some ROMs' stream mute flag. Raising the
                                // slider must actually restore audible output.
                                audio.adjustStreamVolume(
                                    AudioManager.STREAM_MUSIC,
                                    AudioManager.ADJUST_UNMUTE,
                                    0,
                                )
                            }
                            audio.setStreamVolume(AudioManager.STREAM_MUSIC, value, 0)
                            emit()
                            result.success(value)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    startWatching()
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                    stopWatching()
                }
            })
        }
    }

    fun dispose() {
        stopWatching()
        sink = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
    }

    private fun maxVolume(): Int {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        return if (max > 0) max else 1
    }

    private fun startWatching() {
        if (watching) return
        watching = true
        try {
            // Observe the whole settings namespace with descendants: some
            // devices notify the parent URI rather than volume_music directly.
            activity.contentResolver.registerContentObserver(
                Settings.System.CONTENT_URI,
                true,
                observer,
            )
        } catch (_: Exception) {
        }
        val filter = IntentFilter().apply {
            addAction(VOLUME_CHANGED_ACTION)
            addAction(STREAM_MUTE_CHANGED_ACTION)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                activity.registerReceiver(receiver, filter)
            }
        } catch (_: Exception) {
        }
        lastVolume = -1
        lastMax = -1
        emit()
    }

    private fun stopWatching() {
        if (!watching) return
        watching = false
        try {
            activity.contentResolver.unregisterContentObserver(observer)
        } catch (_: Exception) {
        }
        try {
            activity.unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
        lastVolume = -1
        lastMax = -1
    }

    private fun emit() {
        val events = sink ?: return
        if (!watching) return
        val volume = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        val max = maxVolume()
        if (volume == lastVolume && max == lastMax) return
        lastVolume = volume
        lastMax = max
        events.success(mapOf("volume" to volume, "max" to max))
    }

    companion object {
        const val METHOD_CHANNEL = "zero_beat/volume"
        const val EVENT_CHANNEL = "zero_beat/volume_events"

        // Internal Settings.System key used by AudioService for STREAM_MUSIC.
        private const val MUSIC_VOLUME_KEY = "volume_music"

        // Hidden framework constants; spelling the strings avoids depending on
        // non-public SDK fields.
        private const val VOLUME_CHANGED_ACTION = "android.media.VOLUME_CHANGED_ACTION"
        private const val STREAM_MUTE_CHANGED_ACTION = "android.media.STREAM_MUTE_CHANGED_ACTION"
        private const val EXTRA_VOLUME_STREAM_TYPE = "android.media.EXTRA_VOLUME_STREAM_TYPE"
    }
}
