package com.infamousvague.ghostmessaging

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

/**
 * What is done to the microphone before Opus, on the phone (lib/voice/voice_fx.dart; Matt, 2026-11-15: "build in like
 * krisp noise supression or other fancy noise suppression tools, add a volume slider for input ... with
 * overboosting"): RNNoise and the gain from native/voicefx, run in flutter_webrtc's capture post-processing hook,
 * on WebRTC's audio thread. DeepFilterNet is the computers'; the phone answers RNNoise alone.
 *
 * The hook exists once flutter_webrtc has made its PeerConnectionFactory, so [attach] is tried at every configure
 * (the Dart side configures again once the microphone is open).
 */
object VoiceFx : AudioProcessingAdapter.ExternalAudioFrameProcessing {
    private val handle: Long by lazy {
        System.loadLibrary("voicefx")
        nativeCreate()
    }
    @Volatile private var rate = 48000
    private var attached: AudioProcessingAdapter? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "ghost/voicefx").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "modes" -> {
                        val bits = nativeModes(handle)
                        result.success(listOfNotNull(if (bits and (1 shl 1) != 0) "rnnoise" else null, if (bits and (1 shl 2) != 0) "deepfilter" else null))
                    }
                    "configure" -> {
                        val mode = when (call.argument<String>("mode")) { "rnnoise" -> 1; "deepfilter" -> 2; else -> 0 }
                        val gain = (call.argument<Double>("gain") ?: 1.0).toFloat()
                        nativeConfigure(handle, mode, gain)
                        result.success(attach())
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("voicefx", e.message, null)
            }
        }
    }

    /** Into flutter_webrtc's capture hook, once; true once it is in. */
    @Synchronized
    private fun attach(): Boolean {
        if (attached != null) return true
        val hook = runCatching { FlutterWebRTCPlugin.sharedSingleton?.audioProcessingController?.capturePostProcessing }.getOrNull() ?: return false
        hook.addProcessor(this)
        attached = hook
        return true
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {
        rate = sampleRateHz
    }

    override fun reset(newRate: Int) {
        rate = newRate
    }

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        // One block of 10 ms: its rate is its length (webrtc-sdk's ExternalAudioProcessor says the same).
        nativeProcess(handle, buffer, numFrames, numFrames * 100)
    }

    private external fun nativeCreate(): Long
    private external fun nativeModes(fx: Long): Int
    private external fun nativeConfigure(fx: Long, mode: Int, gain: Float)
    private external fun nativeProcess(fx: Long, buffer: ByteBuffer, frames: Int, rate: Int)
}
