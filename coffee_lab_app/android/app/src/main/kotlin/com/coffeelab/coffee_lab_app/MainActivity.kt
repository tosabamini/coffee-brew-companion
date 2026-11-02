package com.coffeelab.coffee_lab_app

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ble: BleLink? = null

    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= 31) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coffee_lab/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 画面の明るさ（0〜1）。負の値で端末の設定に戻す
                    "setBrightness" -> {
                        val v = (call.argument<Double>("value") ?: -1.0).toFloat()
                        val lp = window.attributes
                        lp.screenBrightness =
                            if (v < 0f) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            else v.coerceIn(0.01f, 1f)
                        window.attributes = lp
                        result.success(null)
                    }
                    // 画面を消さない
                    "keepOn" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    // 画面の物理的な細かさ（方眼を実寸で描くため）
                    "displayInfo" -> {
                        val m = resources.displayMetrics
                        result.success(
                            mapOf(
                                "xdpi" to m.xdpi.toDouble(),
                                "ydpi" to m.ydpi.toDouble(),
                                "density" to m.density.toDouble(),
                                "widthPixels" to m.widthPixels,
                                "heightPixels" to m.heightPixels,
                                "model" to (android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL)
                            )
                        )
                    }
                    // 振動。timings = [待ち, 振動, 待ち, 振動, …]（ミリ秒）、amplitude = 1〜255
                    "vibrate" -> {
                        val v = vibrator()
                        if (v == null || !v.hasVibrator()) {
                            result.success(false)
                        } else {
                            val timings = (call.argument<List<Int>>("timings") ?: listOf(0, 300))
                                .map { it.toLong().coerceIn(0L, 60000L) }.toLongArray()
                            val amp = (call.argument<Int>("amplitude") ?: 255).coerceIn(1, 255)
                            v.cancel()
                            if (Build.VERSION.SDK_INT >= 26) {
                                val amps = IntArray(timings.size) { i ->
                                    if (i % 2 == 0) 0 else if (v.hasAmplitudeControl()) amp else VibrationEffect.DEFAULT_AMPLITUDE
                                }
                                v.vibrate(VibrationEffect.createWaveform(timings, amps, -1))
                            } else {
                                @Suppress("DEPRECATION")
                                v.vibrate(timings, -1)
                            }
                            result.success(true)
                        }
                    }
                    "vibrateCancel" -> {
                        vibrator()?.cancel()
                        result.success(null)
                    }
                    // 設定ファイルの置き場所
                    "filesDir" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }

        // ライトとカメラの Bluetooth 連携（BleLink.kt / lib/ble_link.dart）
        val bleChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coffee_lab/ble")
        val b = BleLink(this, bleChannel)
        ble = b
        bleChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ensure" -> b.ensure(call.argument<String>("role") ?: "central", result)
                "serverStart" -> b.startServer(result)
                "serverStop" -> { b.stopServer(); result.success(null) }
                "connect" -> b.connect(call.argument<Int>("timeoutMs") ?: 6000, result)
                "request" -> b.request(call.argument<String>("data") ?: "{}", result)
                "disconnect" -> { b.disconnect(); result.success(null) }
                "isConnected" -> result.success(b.isReady())
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        ble?.onPermissionResult(requestCode)
    }

    override fun onDestroy() {
        ble?.stopServer()
        ble?.disconnect()
        super.onDestroy()
    }
}
