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

    /** The `ghost/voicefx` channel: modes (what this build can do) and configure (the mode and the gain). */
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "ghost/voicefx").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "modes" -> {
                        val bits = nativeModes(handle)
                        result.success(listOfNotNull(if (bits and (1 shl 1) != 0) "rnnoise" else null, if (bits and (1 shl 2) != 0) "deepfilter" else null, "live", "effects"))
                    }
                    // Live voice changing (lib/voice/live_changer.dart): what was said, taken; the changed voice, fed.
                    // A voice effect made here as it is said (lib/voice/live_changer.dart, native/voicefx voicefx_effect).
                    "effect" -> {
                        nativeEffect(handle, call.argument<String>("name") ?: "none")
                        result.success(attach())
                    }
                    "live" -> {
                        nativeLive(handle, call.argument<Boolean>("on") == true)
                        result.success(attach())
                    }
                    "take" -> result.success(nativeTake(handle, call.argument<Int>("most") ?: 32000))
                    "feed" -> {
                        nativeFeed(handle, call.argument<ByteArray>("pcm") ?: ByteArray(0), call.argument<Int>("rate") ?: 24000)
                        result.success(nativeQueued(handle))
                    }
                    "queued" -> result.success(nativeQueued(handle))
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
        // The voice as it is sent, for a recording of the call being made here (CallRecorder.kt).
        CallRecorder.mic(buffer, numFrames, numFrames * 100)
        // And for the call's captions, where they are on (LiveCaptions.kt).
        LiveCaptions.feed(buffer, numFrames, numFrames * 100)
    }

    private external fun nativeCreate(): Long
    private external fun nativeModes(fx: Long): Int
    private external fun nativeConfigure(fx: Long, mode: Int, gain: Float)
    private external fun nativeProcess(fx: Long, buffer: ByteBuffer, frames: Int, rate: Int)
    private external fun nativeEffect(fx: Long, name: String)
    private external fun nativeLive(fx: Long, on: Boolean)
    private external fun nativeTake(fx: Long, most: Int): ByteArray
    private external fun nativeFeed(fx: Long, pcm: ByteArray, rate: Int)
    private external fun nativeQueued(fx: Long): Int
}
