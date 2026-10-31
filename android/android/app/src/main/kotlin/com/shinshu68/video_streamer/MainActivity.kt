package com.shinshu68.video_streamer

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.annotation.RequiresApi
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            channel?.invokeMethod("onAction", intent.getStringExtra(EXTRA_ACTION_NAME))
        }
    }

    private val actionIntent: String
        get() = "$packageName.PICTURE_IN_PICTURE_ACTION"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(actionIntent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(actionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(actionReceiver, filter)
        }
    }

    override fun onDestroy() {
        unregisterReceiver(actionReceiver)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler(::onMethodCall)
        }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE),
            )
            "enter", "update" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val params = pictureInPictureParams(call)
                    if (call.method == "enter") {
                        enterPictureInPictureMode(params)
                    } else {
                        setPictureInPictureParams(params)
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun pictureInPictureParams(call: MethodCall): PictureInPictureParams {
        val isPlaying = call.argument<Boolean>("isPlaying")!!
        val builder = PictureInPictureParams.Builder().setActions(
            listOf(
                remoteAction(
                    "previous",
                    android.R.drawable.ic_media_previous,
                    "前の動画",
                    0,
                    call.argument<Boolean>("hasPrevious")!!,
                ),
                remoteAction(
                    "playPause",
                    if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                    if (isPlaying) "一時停止" else "再生",
                    1,
                    true,
                ),
                remoteAction(
                    "next",
                    android.R.drawable.ic_media_next,
                    "次の動画",
                    2,
                    call.argument<Boolean>("hasNext")!!,
                ),
            ),
        )
        val width = call.argument<Int>("width")!!
        val height = call.argument<Int>("height")!!
        if (width > 0 && height > 0) {
            builder.setAspectRatio(aspectRatio(width, height))
        }
        return builder.build()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun remoteAction(
        name: String,
        icon: Int,
        title: String,
        requestCode: Int,
        enabled: Boolean,
    ): RemoteAction {
        val intent = Intent(actionIntent).setPackage(packageName).putExtra(EXTRA_ACTION_NAME, name)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return RemoteAction(Icon.createWithResource(this, icon), title, title, pendingIntent).apply {
            isEnabled = enabled
        }
    }

    // Android が受け付ける縦横比は 100:239 から 239:100 までで、外れると例外になる。
    private fun aspectRatio(width: Int, height: Int): Rational {
        val ratio = Rational(width, height)
        return when {
            ratio > MAX_ASPECT_RATIO -> MAX_ASPECT_RATIO
            ratio < MIN_ASPECT_RATIO -> MIN_ASPECT_RATIO
            else -> ratio
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // 閉じるボタンでは Activity が止まってから小窓が解除される。
        // タスクを残すと、次に開いたときに video_player が再生を再開してしまう。
        if (!isInPictureInPictureMode && lifecycle.currentState == Lifecycle.State.CREATED) {
            finishAndRemoveTask()
            return
        }
        channel?.invokeMethod("onModeChanged", isInPictureInPictureMode)
    }

    private companion object {
        const val CHANNEL = "com.shinshu68.video_streamer/picture_in_picture"
        const val EXTRA_ACTION_NAME = "name"
        val MIN_ASPECT_RATIO = Rational(100, 239)
        val MAX_ASPECT_RATIO = Rational(239, 100)
    }
}
