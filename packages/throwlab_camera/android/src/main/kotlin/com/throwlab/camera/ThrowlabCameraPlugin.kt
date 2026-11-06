package com.throwlab.camera

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraConstrainedHighSpeedCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Range
import android.util.Size
import android.view.OrientationEventListener
import android.view.Surface
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import java.io.File
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
 */
class ThrowlabCameraPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var textures: TextureRegistry
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: ((Boolean) -> Unit)? = null
    private var camera: Recorder? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textures = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "throwlab_camera")
        channel.setMethodCallHandler(this)
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
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("camera", e.message ?: e.toString(), null)
        }
    }

    // --- Permission ---------------------------------------------------------

    private fun withPermission(result: MethodChannel.Result, then: () -> Unit) {
        if (context.checkSelfPermission(Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            then()
            return
        }
        val host = activity ?: return result.error("permission", "No activity to ask from.", null)
        pendingPermission = { granted ->
            if (granted) then() else result.error("permission", "Camera permission denied.", null)
        }
        host.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST)
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
            val minFrame = map.getOutputMinFrameDuration(MediaRecorder::class.java, size)
            val fastest = if (minFrame > 0) 1_000_000_000L / minFrame else 30L
            for (fps in listOf(30, 60)) {
                if (fps in fixed && fps <= fastest + 1) modes.add(mode(size, fps, false))
            }
        }
        return mapOf(
            "modes" to modes,
            "sensorOrientation" to (traits.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90),
        )
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
        private val size: Size,
        private val fps: Int,
        private val highSpeed: Boolean,
    ) {
        private val thread = HandlerThread("throwlab-camera").apply { start() }
        private val handler = Handler(thread.looper)
        private var producer: TextureRegistry.SurfaceProducer? = null
        private var device: CameraDevice? = null
        private var session: CameraCaptureSession? = null
        private var encoderSurface: Surface? = null
        private var recorder: MediaRecorder? = null
        private var path: String? = null
        private var deviceDegrees = 0
        /**
         * Past 1080p at 120 the pixels come faster than a phone's H.264
         * encoder takes them — 4K at 120 is four times that — and the phone's
         * own camera records them in HEVC, so this does too. Below it, H.264,
         * which every player and every editor opens.
         */
        private val hevc = size.width.toLong() * size.height * fps > 1920L * 1080 * 120

        private val sensorOrientation =
            manager.getCameraCharacteristics(id).get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

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

        private fun previewSurface(): Surface = producer!!.surface

        @SuppressLint("MissingPermission")
        fun open(result: MethodChannel.Result) {
            val entry = textures.createSurfaceProducer()
            producer = entry
            entry.setSize(size.width, size.height)
            entry.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceCleanup() {
                    // Flutter is taking the surface back (the app went to the
                    // background). The screen closes the camera on its way
                    // out; this keeps the session off a dead surface until it
                    // does.
                    try {
                        session?.stopRepeating()
                    } catch (_: Exception) {
                    }
                }
            })
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
                        device = camera
                        configure { error ->
                            answer {
                                if (error != null) {
                                    result.error("camera", error, null)
                                } else {
                                    result.success(
                                        mapOf(
                                            "textureId" to entry.id(),
                                            "width" to size.width,
                                            "height" to size.height,
                                            "fps" to fps,
                                            "highSpeed" to highSpeed,
                                            "sensorOrientation" to sensorOrientation,
                                        ),
                                    )
                                }
                            }
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

        @Suppress("DEPRECATION")
        private fun configure(done: (String?) -> Unit) {
            val camera = device ?: return done("The camera closed.")
            val outputs = listOf(previewSurface(), encoderSurface!!)
            val callback = object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(configured: CameraCaptureSession) {
                    session = configured
                    try {
                        repeat(recording = false)
                        done(null)
                    } catch (e: Exception) {
                        done(e.message ?: e.toString())
                    }
                }

                override fun onConfigureFailed(failed: CameraCaptureSession) {
                    done("This camera can't film at ${size.width}x${size.height}, $fps fps.")
                }
            }
            if (highSpeed) {
                camera.createConstrainedHighSpeedCaptureSession(outputs, callback, handler)
            } else {
                camera.createCaptureSession(outputs, callback, handler)
            }
        }

        /**
         * The request the session repeats: the preview alone, or the preview
         * and the encoder. A high-speed session takes it as a burst, and
         * previews at a range starting lower where the camera offers one,
         * which is how the platform's own samples keep the viewfinder cool.
         */
        private fun repeat(recording: Boolean) {
            val camera = device ?: return
            val active = session ?: return
            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(previewSurface())
                if (recording) addTarget(encoderSurface!!)
                set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                set(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO,
                )
                set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, rangeFor(recording))
            }.build()
            if (active is CameraConstrainedHighSpeedCaptureSession) {
                active.setRepeatingBurst(active.createHighSpeedRequestList(request), null, handler)
            } else {
                active.setRepeatingRequest(request, null, handler)
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
                try {
                    // The back camera is turned by the sensor's own mounting
                    // plus however far the phone is turned.
                    val hint = (sensorOrientation + deviceDegrees) % 360
                    val made = newRecorder(output, encoderSurface!!, hint)
                    recorder = made
                    path = output
                    repeat(recording = true)
                    made.start()
                    main.post { result.success(null) }
                } catch (e: Exception) {
                    recorder?.release()
                    recorder = null
                    File(output).delete()
                    main.post { result.error("record", e.message ?: e.toString(), null) }
                }
            }
        }

        fun stop(result: MethodChannel.Result) {
            val made = recorder ?: return result.error("idle", "Not recording.", null)
            handler.post {
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
                try {
                    repeat(recording = false)
                } catch (_: Exception) {
                }
                val written = path
                path = null
                main.post {
                    if (error != null) result.error("record", error, null) else result.success(written)
                }
            }
        }

        /**
         * Lets the camera go, and waits — briefly — until it has: a mode
         * switch reopens it at once, and a camera still held by the session
         * being closed refuses the one being opened.
         */
        fun close() {
            orientation.disable()
            val released = CountDownLatch(1)
            handler.post {
                try {
                    recorder?.stop()
                } catch (_: RuntimeException) {
                }
                recorder?.release()
                recorder = null
                try {
                    session?.close()
                } catch (_: Exception) {
                }
                session = null
                device?.close()
                device = null
                encoderSurface?.release()
                encoderSurface = null
                released.countDown()
                thread.quitSafely()
            }
            released.await(1500, TimeUnit.MILLISECONDS)
            producer?.release()
            producer = null
        }
    }

    companion object {
        private const val PERMISSION_REQUEST = 4721
    }
}
