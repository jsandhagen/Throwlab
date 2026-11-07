package com.throwlab.camera

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraConstrainedHighSpeedCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.provider.MediaStore
import android.net.Uri
import android.util.Range
import android.util.Size
import android.view.OrientationEventListener
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * ThrowLab's camera, for the one thing no other Flutter camera does: record
 * at the frame rate the phone's own camera app records at.
 *
 * A phone that films 120 or 240 fps does it through Camera2's constrained
 * high-speed session, which takes exactly two outputs — a preview and an
 * encoder — at one of the sizes the camera lists for it. The stock Flutter
 * camera asks an ordinary session for the rate instead, and an ordinary
 * session on a Samsung tops out at 60, so it hands back 30 or 60 without a
 * word. This one opens the high-speed session when a high-speed mode is
 * asked for and an ordinary one otherwise.
 *
 * The encoder's surface is a persistent one, made once and kept in the
 * session from the start, so recording is a change of request rather than a
 * new session: starting costs nothing, and the first frames of a throw are
 * not spent setting a camera up.
 *
 * The preview is a [SurfaceView] handed to Flutter as a platform view, not a
 * Flutter texture. A texture is fed through an image queue Flutter drains on
 * the app's main thread, a couple of frames at a time; when it falls behind,
 * the camera waits for a free buffer, and a camera waiting on its preview
 * is a camera not delivering frames to the encoder either — a choppy
 * preview and a recording with frames missing out of it, which is what the
 * texture did. A SurfaceView is composited by the system, the way the
 * phone's own camera app draws its viewfinder, and never makes the camera
 * wait.
 */
class ThrowlabCameraPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: ((Boolean) -> Unit)? = null
    private var camera: Recorder? = null
    private val main = Handler(Looper.getMainLooper())

    /** The preview's surface while Flutter has the view up, and its size. */
    private var previewHolder: SurfaceHolder? = null
    private var previewSize: Size? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "throwlab_camera")
        channel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(PREVIEW_VIEW, PreviewFactory())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        camera?.close()
        camera = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "modes" -> withPermission(result) { result.success(listModes()) }
                "open" -> withPermission(result) { open(call, result) }
                "start" -> {
                    val cam = camera ?: return result.error("closed", "No camera is open.", null)
                    cam.start(call.argument<String>("path")!!, result)
                }
                "stop" -> {
                    val cam = camera ?: return result.error("closed", "No camera is open.", null)
                    cam.stop(result)
                }
                "close" -> {
                    camera?.close()
                    camera = null
                    keepScreenOn(false)
                    result.success(null)
                }
                "beep" -> {
                    beep(call.argument<String>("kind") ?: "tick")
                    result.success(null)
                }
                "displayRotation" -> result.success(displayDegrees())
                "phoneCamera" -> result.success(phoneCamera())
                "openPhoneCamera" -> result.success(openPhoneCamera())
                "videosSince" -> withPermission(result, mediaPermission) {
                    io.execute {
                        val found = try {
                            videosSince(call.argument<Number>("since")!!.toLong())
                        } catch (e: Exception) {
                            null
                        }
                        main.post {
                            if (found == null) {
                                result.error("media", "The phone's videos couldn't be read.", null)
                            } else {
                                result.success(found)
                            }
                        }
                    }
                }
                "copyVideo" -> {
                    val uri = Uri.parse(call.argument<String>("uri")!!)
                    val dest = call.argument<String>("path")!!
                    io.execute {
                        val ok = try {
                            context.contentResolver.openInputStream(uri)!!.use { input ->
                                File(dest).outputStream().use { input.copyTo(it, 1 shl 20) }
                            }
                            true
                        } catch (e: Exception) {
                            File(dest).delete()
                            false
                        }
                        main.post {
                            if (ok) result.success(dest) else result.error("media", "The clip couldn't be copied.", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("camera", e.message ?: e.toString(), null)
        }
    }

    // --- Permission ---------------------------------------------------------

    private fun withPermission(
        result: MethodChannel.Result,
        permission: String = Manifest.permission.CAMERA,
        then: () -> Unit,
    ) {
        if (context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            then()
            return
        }
        val host = activity ?: return result.error("permission", "No activity to ask from.", null)
        pendingPermission = { granted ->
            if (granted) then() else result.error("permission", "$permission denied.", null)
        }
        host.requestPermissions(arrayOf(permission), PERMISSION_REQUEST)
    }

    /** Reading the phone's own videos: one permission from Android 13, another before. */
    private val mediaPermission: String
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_VIDEO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    // --- The phone's own camera ---------------------------------------------

    /** Copies and queries run off the main thread: a 4K clip is gigabytes. */
    private val io = Executors.newSingleThreadExecutor()

    /**
     * Which camera app the phone has for what ThrowLab's own can't film:
     * 'samsung' where Samsung's is there — it films 4K at 120 in Pro Video,
     * which it keeps to itself — 'other' for any camera app, or null.
     */
    private fun phoneCamera(): String? {
        val pm = context.packageManager
        if (pm.getLaunchIntentForPackage(SAMSUNG_CAMERA) != null) return "samsung"
        val video = Intent(MediaStore.INTENT_ACTION_VIDEO_CAMERA)
        return if (video.resolveActivity(pm) != null) "other" else null
    }

    /**
     * Opens the phone's camera app the way its own icon does, not as a
     * capture for ThrowLab: launched from its icon, Samsung's comes back in
     * the mode it was last left in, so Pro Video set to 4K at 120 once is
     * where it opens every time. A capture request would open it in plain
     * video, which is what made 4K at 120 so hard to get to.
     */
    private fun openPhoneCamera(): Boolean {
        val host = activity ?: return false
        val pm = context.packageManager
        val intent = pm.getLaunchIntentForPackage(SAMSUNG_CAMERA)
            ?: Intent(MediaStore.INTENT_ACTION_VIDEO_CAMERA)
        return try {
            host.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Videos the phone has added since [sinceMillis], newest first — what
     * was just filmed in its camera app, to bring straight in.
     */
    private fun videosSince(sinceMillis: Long): List<Map<String, Any>> {
        val found = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DATE_ADDED,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.DISPLAY_NAME,
        )
        context.contentResolver.query(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Video.Media.DATE_ADDED} >= ?",
            arrayOf((sinceMillis / 1000).toString()),
            "${MediaStore.Video.Media.DATE_ADDED} DESC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                found.add(
                    mapOf(
                        "uri" to ContentUris.withAppendedId(
                            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            id,
                        ).toString(),
                        "addedMillis" to cursor.getLong(1) * 1000,
                        "durationMillis" to cursor.getLong(2),
                        "width" to cursor.getInt(3),
                        "height" to cursor.getInt(4),
                        "name" to (cursor.getString(5) ?: ""),
                    ),
                )
            }
        }
        return found
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val callback = pendingPermission ?: return true
        pendingPermission = null
        callback(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
        return true
    }

    // --- Modes --------------------------------------------------------------

    private val manager: CameraManager
        get() = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    /**
     * The back camera that can film fastest: a phone lists several, and the
     * main one is the one with a high-speed session.
     */
    private fun backCamera(): String? {
        var fallback: String? = null
        for (id in manager.cameraIdList) {
            val traits = manager.getCameraCharacteristics(id)
            if (traits.get(CameraCharacteristics.LENS_FACING) !=
                CameraCharacteristics.LENS_FACING_BACK
            ) continue
            if (highSpeedCapable(traits)) return id
            if (fallback == null) fallback = id
        }
        return fallback
    }

    private fun highSpeedCapable(traits: CameraCharacteristics): Boolean =
        traits.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)?.contains(
            CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_CONSTRAINED_HIGH_SPEED_VIDEO,
        ) == true

    /**
     * Every rate this camera will really record at, and at what size: the
     * high-speed session's own fixed rates at every size it lists (4K
     * included, on a phone that gives it to apps), and the ordinary
     * session's 30 and 60 at 4K, 1080p and 720p where the camera can keep
     * up.
     */
    private fun listModes(): Map<String, Any> {
        val id = backCamera() ?: return mapOf("modes" to emptyList<Any>())
        val traits = manager.getCameraCharacteristics(id)
        val map = traits.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
        val modes = mutableListOf<Map<String, Any>>()
        if (highSpeedCapable(traits)) {
            for (size in map.highSpeedVideoSizes) {
                val rates = map.getHighSpeedVideoFpsRangesFor(size)
                    .filter { it.lower == it.upper && it.upper >= 90 }
                    .map { it.upper }
                    .distinct()
                for (fps in rates) modes.add(mode(size, fps, true))
            }
        }
        val fixed = (traits.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
            ?: emptyArray())
            .filter { it.lower == it.upper }
            .map { it.upper }
            .toSet()
        val recordable = map.getOutputSizes(MediaRecorder::class.java)?.toList() ?: emptyList()
        for (size in listOf(Size(3840, 2160), Size(1920, 1080), Size(1280, 720))) {
            if (size !in recordable) continue
            val fastest = fastestAt(map, size)
            // Every steady rate the ordinary session offers, not just 30 and
            // 60: a phone that lets apps have 4K at 120 at all does it here,
            // since its high-speed sizes stop at 1080p.
            for (fps in fixed.filter { it >= 24 }.sorted()) {
                if (fps <= fastest + 1) modes.add(mode(size, fps, false))
            }
        }
        return mapOf(
            "modes" to modes,
            "sensorOrientation" to (traits.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90),
            "details" to details(),
        )
    }

    private fun fastestAt(map: android.hardware.camera2.params.StreamConfigurationMap, size: Size): Long {
        val minFrame = map.getOutputMinFrameDuration(MediaRecorder::class.java, size)
        return if (minFrame > 0) 1_000_000_000L / minFrame else 30L
    }

    /**
     * What every back camera tells apps it can film, in lines a coach can
     * screenshot: the question of whether a phone gives apps 4K at 120 is
     * settled by what it says here and nowhere else, since the phone's own
     * camera app is allowed more than it lists.
     */
    private fun details(): List<String> {
        val lines = mutableListOf<String>()
        for (id in manager.cameraIdList) {
            val traits = manager.getCameraCharacteristics(id)
            if (traits.get(CameraCharacteristics.LENS_FACING) !=
                CameraCharacteristics.LENS_FACING_BACK
            ) continue
            val map = traits.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: continue
            val focal = traits.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?.firstOrNull()?.let { " · %.1f mm".format(it) } ?: ""
            lines.add("Back camera $id$focal")
            val highSpeed = if (highSpeedCapable(traits)) {
                map.highSpeedVideoSizes.joinToString(", ") { size ->
                    val rates = map.getHighSpeedVideoFpsRangesFor(size)
                        .filter { it.lower == it.upper }.map { it.upper }.distinct().sorted()
                    "${size.width}x${size.height} at ${rates.joinToString("/")}"
                }
            } else {
                "none"
            }
            lines.add("  High speed: $highSpeed")
            val steady = (traits.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                ?: emptyArray()).filter { it.lower == it.upper }.map { it.upper }.distinct().sorted()
            lines.add("  Steady rates: ${steady.joinToString("/")}")
            val recordable = map.getOutputSizes(MediaRecorder::class.java)?.toList() ?: emptyList()
            for (size in listOf(Size(3840, 2160), Size(1920, 1080))) {
                if (size !in recordable) continue
                lines.add("  ${size.width}x${size.height}: up to ${fastestAt(map, size)} fps")
            }
        }
        return lines
    }

    private fun mode(size: Size, fps: Int, highSpeed: Boolean) = mapOf(
        "width" to size.width,
        "height" to size.height,
        "fps" to fps,
        "highSpeed" to highSpeed,
    )

    // --- Opening ------------------------------------------------------------

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        camera?.close()
        camera = null
        val id = backCamera() ?: return result.error("camera", "This phone has no back camera.", null)
        val size = Size(call.argument<Int>("width")!!, call.argument<Int>("height")!!)
        val fps = call.argument<Int>("fps")!!
        val highSpeed = call.argument<Boolean>("highSpeed") ?: false
        val recorder = Recorder(id, size, fps, highSpeed)
        camera = recorder
        keepScreenOn(true)
        recorder.open(result)
        // A preview already up is resized to the new mode, which hands the
        // camera its surface again once it has taken the size.
        previewHolder?.setFixedSize(size.width, size.height)
    }

    // --- Preview ------------------------------------------------------------

    private inner class PreviewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
            PreviewView(context)
    }

    /**
     * The viewfinder. Its buffers are set to the mode's size, which a
     * high-speed session insists on for both of its outputs; the system
     * turns them upright for the screen and scales them into the view, so
     * Flutter only has to give the view the right shape.
     */
    private inner class PreviewView(context: Context) : PlatformView, SurfaceHolder.Callback {
        private val surfaceView = SurfaceView(context).also { it.holder.addCallback(this) }

        override fun getView(): View = surfaceView

        override fun dispose() {
            surfaceView.holder.removeCallback(this)
            if (previewHolder === surfaceView.holder) forgetPreview()
        }

        override fun surfaceCreated(holder: SurfaceHolder) {
            previewHolder = holder
            previewSize = null
            camera?.let { holder.setFixedSize(it.size.width, it.size.height) }
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            previewHolder = holder
            previewSize = Size(width, height)
            camera?.previewChanged()
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            if (previewHolder === holder) forgetPreview()
        }
    }

    private fun forgetPreview() {
        previewHolder = null
        previewSize = null
        camera?.previewGone()
    }

    /** The preview's surface, if it is up and at [size]. */
    private fun previewAt(size: Size): Surface? {
        val holder = previewHolder ?: return null
        if (previewSize != size) return null
        return holder.surface?.takeIf { it.isValid }
    }

    /**
     * The screen stays on while the camera is: an athlete filming themselves
     * is twenty meters away for longer than a phone's screen timeout, and a
     * screen that goes off takes the camera — and the recording — with it.
     */
    private fun keepScreenOn(on: Boolean) {
        val window = activity?.window ?: return
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    @Suppress("DEPRECATION")
    private fun displayDegrees(): Int {
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity?.display?.rotation
        } else {
            activity?.windowManager?.defaultDisplay?.rotation
        } ?: Surface.ROTATION_0
        return when (rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
    }

    // --- Signals ------------------------------------------------------------

    /**
     * A beep loud enough to hear from the ring: on the alarm stream, which a
     * phone keeps up when its media volume is down.
     */
    private fun beep(kind: String) {
        val (tone, millis) = when (kind) {
            "go" -> ToneGenerator.TONE_PROP_BEEP2 to 500
            "stop" -> ToneGenerator.TONE_PROP_ACK to 400
            else -> ToneGenerator.TONE_PROP_BEEP to 150
        }
        try {
            val generator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
            generator.startTone(tone, millis)
            main.postDelayed({ generator.release() }, millis + 200L)
        } catch (_: RuntimeException) {
            // No tone to be had; the countdown on the screen still runs.
        }
    }

    /** One open camera, its session, and the recording going through it. */
    private inner class Recorder(
        private val id: String,
        val size: Size,
        private val fps: Int,
        private val highSpeed: Boolean,
    ) {
        private val thread = HandlerThread("throwlab-camera").apply { start() }
        private val handler = Handler(thread.looper)
        private var device: CameraDevice? = null
        private var session: CameraCaptureSession? = null
        private var sessionPreview: Surface? = null
        private var encoderSurface: Surface? = null
        private var recorder: MediaRecorder? = null
        private var path: String? = null
        private var deviceDegrees = 0
        @Volatile private var closed = false

        /**
         * Past 1080p at 120 the pixels come faster than a phone's H.264
         * encoder takes them — 4K at 120 is four times that — and the phone's
         * own camera records them in HEVC, so this does too. Below it, H.264,
         * which every player and every editor opens.
         */
        private val hevc = size.width.toLong() * size.height * fps > 1920L * 1080 * 120

        private val sensorOrientation =
            manager.getCameraCharacteristics(id).get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

        // What the camera actually delivered to the encoder during a take,
        // counted off its own results: the number that says whether 120 was
        // 120, which nothing downstream can tell apart from a camera that
        // dropped half of them and had the gaps filled in.
        private var frames = 0
        private var failed = 0
        private var firstStamp = 0L
        private var lastStamp = 0L

        private val counting = object : CameraCaptureSession.CaptureCallback() {
            override fun onCaptureCompleted(
                session: CameraCaptureSession,
                request: CaptureRequest,
                result: TotalCaptureResult,
            ) {
                val stamp = result.get(CaptureResult.SENSOR_TIMESTAMP) ?: return
                if (frames == 0) firstStamp = stamp
                lastStamp = stamp
                frames++
            }

            override fun onCaptureFailed(
                session: CameraCaptureSession,
                request: CaptureRequest,
                failure: CaptureFailure,
            ) {
                failed++
            }
        }

        /**
         * Which way up the phone is held, off the accelerometer rather than
         * the screen: a phone on a tripod with rotation locked still films
         * the way it is standing.
         */
        private val orientation = object : OrientationEventListener(context) {
            override fun onOrientationChanged(degrees: Int) {
                if (degrees == ORIENTATION_UNKNOWN) return
                deviceDegrees = ((degrees + 45) / 90 * 90) % 360
            }
        }

        @SuppressLint("MissingPermission")
        fun open(result: MethodChannel.Result) {
            if (orientation.canDetectOrientation()) orientation.enable()
            encoderSurface = MediaCodec.createPersistentInputSurface().also { surface ->
                // A persistent surface has no buffers until an encoder has
                // been configured on it once: a recorder is prepared and
                // thrown away so the session can take it from the start.
                val primer = newRecorder(File(context.cacheDir, "throwlab_primer.mp4").path, surface, 0)
                primer.release()
            }
            var answered = false
            fun answer(block: () -> Unit) {
                if (answered) return
                answered = true
                main.post(block)
            }
            try {
                manager.openCamera(id, object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        if (closed) {
                            camera.close()
                            return
                        }
                        device = camera
                        answer {
                            result.success(
                                mapOf(
                                    "width" to size.width,
                                    "height" to size.height,
                                    "fps" to fps,
                                    "highSpeed" to highSpeed,
                                    "sensorOrientation" to sensorOrientation,
                                ),
                            )
                            previewChanged()
                        }
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        camera.close()
                        device = null
                        answer { result.error("camera", "The camera was taken by another app.", null) }
                    }

                    override fun onError(camera: CameraDevice, error: Int) {
                        camera.close()
                        device = null
                        answer { result.error("camera", "The camera failed to open ($error).", null) }
                    }
                }, handler)
            } catch (e: CameraAccessException) {
                answer { result.error("camera", e.message ?: "The camera is unavailable.", null) }
            }
        }

        /**
         * The preview came up, or took a new size: the session is built on
         * it once it is at this mode's size — a high-speed session refuses
         * outputs of two sizes — and rebuilt if it is a new surface.
         */
        fun previewChanged() {
            val surface = previewAt(size)
            if (surface == null) {
                previewHolder?.let { holder ->
                    if (previewSize != size) holder.setFixedSize(size.width, size.height)
                }
                return
            }
            handler.post {
                if (closed || device == null) return@post
                if (session != null && sessionPreview === surface) return@post
                closeSession()
                configure(surface)
            }
        }

        /** The preview went (the app left the screen): no session without it. */
        fun previewGone() {
            handler.post { closeSession() }
        }

        private fun closeSession() {
            try {
                session?.close()
            } catch (_: Exception) {
            }
            session = null
            sessionPreview = null
        }

        @Suppress("DEPRECATION")
        private fun configure(preview: Surface) {
            val camera = device ?: return
            val outputs = listOf(preview, encoderSurface!!)
            val callback = object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(configured: CameraCaptureSession) {
                    if (closed) {
                        configured.close()
                        return
                    }
                    session = configured
                    sessionPreview = preview
                    try {
                        repeat(recording = recorder != null)
                        main.post { channel.invokeMethod("ready", null) }
                    } catch (e: Exception) {
                        main.post { channel.invokeMethod("failed", e.message ?: e.toString()) }
                    }
                }

                override fun onConfigureFailed(failed: CameraCaptureSession) {
                    main.post {
                        channel.invokeMethod(
                            "failed",
                            "This camera can't film at ${size.width}x${size.height}, $fps fps.",
                        )
                    }
                }
            }
            try {
                if (highSpeed) {
                    camera.createConstrainedHighSpeedCaptureSession(outputs, callback, handler)
                } else {
                    camera.createCaptureSession(outputs, callback, handler)
                }
            } catch (e: Exception) {
                main.post { channel.invokeMethod("failed", e.message ?: e.toString()) }
            }
        }

        /**
         * The request the session repeats: the preview alone, or the preview
         * and the encoder, counted. A high-speed session takes it as a burst,
         * and previews at a range starting lower where the camera offers one,
         * which is how the platform's own samples keep the viewfinder cool.
         */
        private fun repeat(recording: Boolean) {
            val camera = device ?: return
            val active = session ?: return
            val preview = sessionPreview ?: return
            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(preview)
                if (recording) addTarget(encoderSurface!!)
                set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                set(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO,
                )
                set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, rangeFor(recording))
            }.build()
            val callback = if (recording) counting else null
            if (active is CameraConstrainedHighSpeedCaptureSession) {
                active.setRepeatingBurst(active.createHighSpeedRequestList(request), callback, handler)
            } else {
                active.setRepeatingRequest(request, callback, handler)
            }
        }

        private fun rangeFor(recording: Boolean): Range<Int> {
            if (!highSpeed || recording) return Range(fps, fps)
            val map = manager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
            return map.getHighSpeedVideoFpsRangesFor(size)
                .filter { it.upper == fps && it.lower < fps }
                .minByOrNull { it.lower } ?: Range(fps, fps)
        }

        @Suppress("DEPRECATION")
        private fun newRecorder(output: String, surface: Surface, hint: Int): MediaRecorder {
            val made = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                MediaRecorder()
            }
            return made.apply {
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setOutputFile(output)
                // About what a phone's own camera spends at these rates: the
                // fast frames are the point, and starving them of bits blurs
                // exactly the arm and the implement they were taken for.
                setVideoEncodingBitRate(
                    (size.width.toLong() * size.height * fps / (if (hevc) 8 else 5))
                        .coerceIn(8_000_000L, 200_000_000L).toInt(),
                )
                setVideoFrameRate(fps)
                setVideoSize(size.width, size.height)
                setVideoEncoder(
                    if (hevc) MediaRecorder.VideoEncoder.HEVC else MediaRecorder.VideoEncoder.H264,
                )
                setInputSurface(surface)
                setOrientationHint(hint)
                prepare()
            }
        }

        fun start(output: String, result: MethodChannel.Result) {
            if (recorder != null) return result.error("busy", "Already recording.", null)
            handler.post {
                if (session == null) {
                    main.post { result.error("record", "The camera isn't ready yet.", null) }
                    return@post
                }
                try {
                    // The back camera is turned by the sensor's own mounting
                    // plus however far the phone is turned.
                    val hint = (sensorOrientation + deviceDegrees) % 360
                    val made = newRecorder(output, encoderSurface!!, hint)
                    recorder = made
                    path = output
                    frames = 0
                    failed = 0
                    firstStamp = 0L
                    lastStamp = 0L
                    repeat(recording = true)
                    made.start()
                    main.post { result.success(null) }
                } catch (e: Exception) {
                    recorder?.release()
                    recorder = null
                    File(output).delete()
                    try {
                        repeat(recording = false)
                    } catch (_: Exception) {
                    }
                    main.post { result.error("record", e.message ?: e.toString(), null) }
                }
            }
        }

        fun stop(result: MethodChannel.Result) {
            val made = recorder ?: return result.error("idle", "Not recording.", null)
            handler.post {
                // The preview goes back to its own request first, so no
                // frame is sent to an encoder that has been told to stop.
                try {
                    repeat(recording = false)
                } catch (_: Exception) {
                }
                var error: String? = null
                try {
                    made.stop()
                } catch (e: RuntimeException) {
                    // Stopped before a single frame was written.
                    error = "Nothing was recorded."
                    path?.let { File(it).delete() }
                }
                made.release()
                recorder = null
                val written = path
                path = null
                val take = mapOf(
                    "path" to written,
                    "frames" to frames,
                    "failed" to failed,
                    "seconds" to (lastStamp - firstStamp) / 1e9,
                )
                main.post {
                    if (error != null) result.error("record", error, null) else result.success(take)
                }
            }
        }

        /**
         * Lets the camera go, and waits — briefly — until it has: a mode
         * switch reopens it at once, and a camera still held by the session
         * being closed refuses the one being opened.
         */
        fun close() {
            closed = true
            orientation.disable()
            val released = CountDownLatch(1)
            handler.post {
                try {
                    recorder?.stop()
                } catch (_: RuntimeException) {
                }
                recorder?.release()
                recorder = null
                closeSession()
                device?.close()
                device = null
                encoderSurface?.release()
                encoderSurface = null
                released.countDown()
                thread.quitSafely()
            }
            released.await(1500, TimeUnit.MILLISECONDS)
        }
    }

    companion object {
        private const val PERMISSION_REQUEST = 4721
        private const val PREVIEW_VIEW = "throwlab_camera/preview"
        private const val SAMSUNG_CAMERA = "com.sec.android.app.camera"
    }
}
