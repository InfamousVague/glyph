package com.infamousvague.ghostmessaging

import android.content.Context

/**
 * The direct network's core (native/p2p, libghost_p2p.so; docs/OPEN_NETWORK.md, section 2), as far as Kotlin has
 * anything to do with it: Dart opens the library and drives it (lib/net/p2p/node_ffi.dart), but only Android's own
 * code can tell it which DNS servers the phone uses, and that takes the app's context. So the library is loaded here
 * once, before Dart can start a node, and handed the context through its one JNI function.
 *
 * Without it a link helper's name could not be looked up at all: the core asks the phone's own DNS servers and no
 * public one in their place. A build that does not carry the library (the direct route is simply not there) is
 * left as it is.
 */
object P2pCore {
    @Volatile private var installed = false

    /** Loads the core where the build has it and gives it the app's context. Called again, it does nothing. */
    @Synchronized
    fun install(context: Context) {
        if (installed) return
        try {
            System.loadLibrary("ghost_p2p")
            installed = nativeInstall(context.applicationContext)
        } catch (_: UnsatisfiedLinkError) {
            // Not in this build.
        } catch (e: Throwable) {
            DevLog.add(context, "p2p", "the direct network's core was not given the app's context: ${e.message ?: e.javaClass.simpleName}")
        }
    }

    /** `Java_com_infamousvague_ghostmessaging_P2pCore_nativeInstall` in native/p2p/src/ffi.rs; true once the context is in place. */
    private external fun nativeInstall(context: Context): Boolean
}
