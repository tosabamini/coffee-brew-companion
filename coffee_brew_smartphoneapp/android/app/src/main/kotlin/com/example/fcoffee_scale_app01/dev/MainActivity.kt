package com.example.fcoffee_scale_app01.dev

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * ほかのアプリを使っている間のミニ表示（ピクチャーインピクチャー）。Dart 側は lib/features/scale/services/pip_service.dart。
 * スケールとつながっている間（autoEnter = true）だけ、ホームに戻ったりアプリを切り替えたときに小窓になる。
 */
class MainActivity : FlutterActivity() {
    private var autoEnter = false
    private var pipChannel: MethodChannel? = null

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= 26 &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    /** 小窓の設定（横長 16:9）。Android 12 以降は自動で小窓にする設定もここで渡す */
    private fun applyPipParams() {
        if (!pipSupported() || Build.VERSION.SDK_INT < 26) return
        val b = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= 31) {
            b.setAutoEnterEnabled(autoEnter)
            b.setSeamlessResizeEnabled(false)
        }
        try {
            setPictureInPictureParams(b.build())
        } catch (e: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brew/pip")
        pipChannel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(pipSupported())
                "setAutoEnter" -> {
                    autoEnter = call.argument<Boolean>("enabled") == true
                    applyPipParams()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Android 11 以前：ホームボタンなどでアプリを離れるときに自分で小窓にする（12 以降は上の自動設定に任せる）
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoEnter && pipSupported() && Build.VERSION.SDK_INT >= 26 && Build.VERSION.SDK_INT <= 30) {
            try {
                enterPictureInPictureMode(
                    PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
                )
            } catch (e: Exception) {
            }
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
