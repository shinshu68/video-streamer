package com.shinshu68.video_streamer

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.PictureInPictureUiState
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var videoAspectRatio: Rational? = null
    private var isFlutterViewSizeFixed = false
    private var isEnteringPictureInPicture = false

    private val contentView: View
        get() = findViewById(android.R.id.content)

    private val flutterView: View
        get() = findViewById(FLUTTER_VIEW_ID)

    private val isPictureInPictureSupported: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            channel?.invokeMethod("onAction", intent.getStringExtra(EXTRA_ACTION_NAME))
        }
    }

    private val actionIntent: String
        get() = "$packageName.PICTURE_IN_PICTURE_ACTION"

    // 小窓の間は FlutterView を拡大縮小する (fitFlutterViewToWindow)。
    // 既定の SurfaceView はビューの拡大縮小に追従しない。
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        contentView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            fitFlutterViewToWindow()
        }
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
            "isSupported" -> result.success(isPictureInPictureSupported)
            "enter", "update" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isPictureInPictureSupported) {
                    val params = pictureInPictureParams(call)
                    if (call.method == "enter") {
                        enterPictureInPictureMode(params)
                    } else {
                        setPictureInPictureParams(params)
                    }
                }
                result.success(null)
            }
            "disableAutoEnter" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && isPictureInPictureSupported) {
                    setPictureInPictureParams(
                        PictureInPictureParams.Builder().setAutoEnterEnabled(false).build(),
                    )
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
            val ratio = aspectRatio(width, height)
            videoAspectRatio = ratio
            builder.setAspectRatio(ratio)
            sourceRectHint(ratio)?.let(builder::setSourceRectHint)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(isPlaying)
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

    // 再生画面の今の動画の位置は使わない。小窓に入り始めると動画だけの表示に変わるため、
    // AppBar の分だけずれる。画面の大きさから求めれば、小窓の中でも全画面の位置が分かる。
    private fun sourceRectHint(ratio: Rational): Rect? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return null
        }
        val screen = windowManager.maximumWindowMetrics.bounds
        return centeredVideoRect(ratio, screen.width(), screen.height())
    }

    private fun centeredVideoRect(ratio: Rational, areaWidth: Int, areaHeight: Int): Rect {
        val width = min(areaWidth, (areaHeight * ratio.toDouble()).roundToInt())
        val height = min(areaHeight, (areaWidth / ratio.toDouble()).roundToInt())
        val left = (areaWidth - width) / 2
        val top = (areaHeight - height) / 2
        return Rect(left, top, left + width, top + height)
    }

    // Flutter はサイズが変わると、新しいサイズの描画面に古いサイズのフレームを1度描くため、
    // 小窓の出入りで動画が潰れたり黒くなったりする。Flutter の設定では防げないので、
    // 小窓の間は FlutterView のサイズを全画面のまま固定し、サイズの変更自体を起こさない。
    private fun fixFlutterViewSize() {
        if (!isFlutterViewSizeFixed) {
            isFlutterViewSizeFixed = true
            val view = flutterView
            view.layoutParams = FrameLayout.LayoutParams(view.width, view.height)
        }
    }

    private fun fitFlutterViewToWindow() {
        if (!isFlutterViewSizeFixed) {
            return
        }
        val view = flutterView
        val isWindowSmall = contentView.width < view.width && contentView.height < view.height
        if (isWindowSmall) {
            val ratio = videoAspectRatio
            if (isEnteringPictureInPicture && ratio != null) {
                // ホーム画面は縦向きなので、横向きで入ると小窓の間に画面の向きが変わる。
                // 画面ではなく、固定した FlutterView の大きさを基準にする。
                val video = centeredVideoRect(ratio, view.width, view.height)
                val scale = contentView.width.toFloat() / video.width()
                view.pivotX = 0f
                view.pivotY = 0f
                view.scaleX = scale
                view.scaleY = scale
                view.translationX = -video.left * scale
                view.translationY = -video.top * scale
            }
            return
        }
        view.scaleX = 1f
        view.scaleY = 1f
        view.translationX = 0f
        view.translationY = 0f
        if (!isEnteringPictureInPicture) {
            isFlutterViewSizeFixed = false
            // レイアウトの途中では LayoutParams を変えられない。
            view.post {
                view.layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                )
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        val hint = videoAspectRatio?.let(::sourceRectHint)
        if (hint != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            setPictureInPictureParams(
                PictureInPictureParams.Builder().setSourceRectHint(hint).build(),
            )
        }
    }

    override fun onPictureInPictureUiStateChanged(pipState: PictureInPictureUiState) {
        super.onPictureInPictureUiStateChanged(pipState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            return
        }
        // 小窓に入りきってから操作を隠すと、アニメーションの最後にレイアウトが変わって点滅する。
        val transitioning = pipState.isTransitioningToPip
        if (transitioning || !isInPictureInPictureMode) {
            isEnteringPictureInPicture = transitioning
            if (transitioning) {
                fixFlutterViewSize()
            } else {
                fitFlutterViewToWindow()
            }
            channel?.invokeMethod("onModeChanged", transitioning)
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
        isEnteringPictureInPicture = isInPictureInPictureMode
        fitFlutterViewToWindow()
        channel?.invokeMethod("onModeChanged", isInPictureInPictureMode)
    }

    private companion object {
        const val CHANNEL = "com.shinshu68.video_streamer/picture_in_picture"
        const val EXTRA_ACTION_NAME = "name"
        val MIN_ASPECT_RATIO = Rational(100, 239)
        val MAX_ASPECT_RATIO = Rational(239, 100)
    }
}
