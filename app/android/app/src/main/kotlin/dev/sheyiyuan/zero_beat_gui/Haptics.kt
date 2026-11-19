package dev.sheyiyuan.zero_beat_gui

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * A direct vibrator fallback for button ticks.
 *
 * Flutter's HapticFeedback uses View.performHapticFeedback with the TOUCH
 * usage, which some ROMs (notably MIUI) ignore when their system touch haptic
 * feedback setting is off. A short direct one-shot with NOTIFICATION usage is
 * still allowed while the system touch category is muted, and the system
 * master vibration switch still applies.
 */
internal object Haptics {
    private const val channelName = "zero_beat/haptics"

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "selectionClick" -> {
                    try {
                        result.success(selectionClick(context))
                    } catch (error: Exception) {
                        result.error("haptics", error.message ?: "振动不可用", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun selectionClick(context: Context): Boolean {
        val vibrator = vibrator(context)
        if (vibrator == null || !vibrator.hasVibrator()) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // No explicit usage: some MIUI builds filter NOTIFICATION/
            // HARDWARE_FEEDBACK usage when the touch haptic switch is off.
            // A plain one-shot still follows the system master vibration switch.
            vibrator.vibrate(VibrationEffect.createOneShot(12L, 80))
        } else {
            vibrator.vibrate(12L)
        }
        return true
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            context.getSystemService(Vibrator::class.java)
        }
}
