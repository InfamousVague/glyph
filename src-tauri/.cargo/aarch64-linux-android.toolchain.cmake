# whisper.cpp for aarch64-linux-android: the three things the NDK's own
# toolchain file has to be told, and the one place they CAN be told.
#
# Only the Android build ever reads this file. `.cargo/config.toml` names it
# as CMAKE_TOOLCHAIN_FILE_aarch64_linux_android, and the `cmake` crate reads
# that target-suffixed name and no other, so a macOS or iOS build never sees
# a line of it.
#
# Why a wrapper at all, rather than pointing that variable straight at
# <ndk>/build/cmake/android.toolchain.cmake: the NDK file takes its ABI and API
# level as CMake VARIABLES (-DANDROID_ABI=...), and reads no environment. The
# only door into this cmake invocation is whisper-rs-sys's build script, which
# forwards environment variables whose names start CMAKE_, GGML_ or WHISPER_ -
# and ANDROID_ABI starts with none of them. Pointed at the NDK file directly,
# the build does not fail: the NDK quietly defaults ANDROID_ABI to
# armeabi-v7a, compiles ggml as 32-bit ARM, and the link of libglyph_lib.so
# fails an hour later with a wall of "incompatible target" errors that say
# nothing about why. So this file sets them and then hands over.

# The NDK is the one that compiles every other C file in this crate. cargo-
# mobile2 (inside `tauri android build`) and config.toml both name its clang as
# CC_aarch64_linux_android, and walking up from that binary reaches the NDK
# root - so ggml cannot be built by a different NDK than SQLite and ring were,
# which is the mismatch that shows up as a libc++ symbol missing at load time
# on the phone rather than as anything at build time.
#   <ndk>/toolchains/llvm/prebuilt/<host>/bin/aarch64-linux-android24-clang
set(_glyph_cc "$ENV{CC_aarch64_linux_android}")
if(_glyph_cc)
  get_filename_component(_glyph_ndk "${_glyph_cc}/../../../../../.." ABSOLUTE)
elseif(DEFINED ENV{NDK_HOME})
  set(_glyph_ndk "$ENV{NDK_HOME}")
else()
  message(FATAL_ERROR
    "No NDK: neither CC_aarch64_linux_android nor NDK_HOME is set. "
    "src-tauri/.cargo/config.toml sets the first for a plain cargo build and "
    "`tauri android build` sets both.")
endif()
if(NOT EXISTS "${_glyph_ndk}/build/cmake/android.toolchain.cmake")
  message(FATAL_ERROR "${_glyph_ndk} is not an NDK (no build/cmake/android.toolchain.cmake).")
endif()

# 64-bit ARM, which is the only ABI the Fold (or any phone Glyph targets)
# runs. Without it: armeabi-v7a, as above.
set(ANDROID_ABI arm64-v8a)

# The API level the rest of the crate is compiled against, read off the same
# clang's name (aarch64-linux-android24-clang) so that minSdk has one owner -
# build.gradle.kts, which cargo-mobile2 turns into that name. Without it the
# NDK falls back to its own minimum (21 for r26), and ggml would link against a
# bionic older than the one the Rust half assumes.
if(_glyph_cc MATCHES "android([0-9]+)-clang")
  set(ANDROID_PLATFORM "android-${CMAKE_MATCH_1}")
else()
  set(ANDROID_PLATFORM android-24)
endif()

# The C++ runtime is linked statically into libglyph_lib.so: whisper-rs-sys
# (vendored build.rs) and llama-cpp-sys-2 (`android-static-stdcxx`) both link
# c++_static, so ggml is compiled against the same STL - mixing them is two
# copies of the C++ runtime in one process. Static rather than the shared
# runtime because NDK r26's libc++_shared.so is 4 KB page-aligned, which Google
# Play refuses (16 KB page sizes); named here although it is the NDK's default
# for a toolchain-file build, so the choice is written down in one place.
set(ANDROID_STL c++_static)

# The CPU features ggml may assume. A cross-compile turns GGML_NATIVE off by
# itself (ggml/CMakeLists.txt: CMAKE_CROSSCOMPILING), and without a named arch
# ggml builds for bare armv8-a - NEON, but no dot-product kernels and no fp16
# vector arithmetic, which are the two that the q5_1 matmuls and whisper's F16
# tensors actually spend their time in.
#
# armv8.2-a+dotprod+fp16 rather than the Fold's full feature set: every arm64
# phone core since the Cortex-A55/A75 (2018) has both, so this is fast on the
# target without being a SIGILL on the next phone. i8mm (armv8.6) is the next
# candidate and is untested - it speeds up the q4 repack kernels, not q5_1.
#
# A CACHE entry, not a plain set(): ggml declares this with
# set(... CACHE STRING ""), and under the policies its cmake_minimum_required
# selects, that declaration deletes a plain variable of the same name. An
# existing cache entry it leaves alone.
set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "ggml: CPU architecture for ARM")

# An EMPTY libggml-blas.a, because whisper-rs-sys 0.15.0 asks for one it never
# builds.
#
# Its build.rs says `if cfg!(target_os = "macos") || cfg!(feature = "openblas")
# { rustc-link-lib=static=ggml-blas }`. A `cfg!` in a build script describes the
# machine RUNNING the script, not the target, so a Mac building for Android
# asks for the Accelerate BLAS backend that only a macOS target compiles - and
# rustc stops at the whisper-rs-sys rlib with "could not find native static
# library `ggml-blas`", after every line of C++ has already compiled cleanly.
# Still present on whisper-rs master as of 2026-09-12 (sys/build.rs line 317);
# the fix upstream is `CARGO_CFG_TARGET_OS`. A vendored, patched copy of the
# crate was the alternative, and is 13 MB of whisper.cpp kept in step by hand
# for the sake of one word.
#
# The stub goes in the build directory's root, which that same build script
# adds to rustc's search path (add_link_search_path over out/build). rustc
# bundles an empty archive into the rlib as nothing at all, and nothing in ggml
# references a BLAS symbol, because GGML_BLAS is off for this target. Delete
# this block the day the build succeeds without it. The one way it can bite is
# somebody enabling a real BLAS for Android: the stub sits earlier on the
# search path than ggml/src/ggml-blas/ and would shadow it.
#
# Skipped inside try_compile, which re-reads this file with a scratch
# directory as its binary dir that CMake deletes again straight afterwards.
get_property(_glyph_in_try_compile GLOBAL PROPERTY IN_TRY_COMPILE)
if(NOT _glyph_in_try_compile AND NOT EXISTS "${CMAKE_BINARY_DIR}/libggml-blas.a")
  file(WRITE "${CMAKE_BINARY_DIR}/libggml-blas.a" "!<arch>\n")
endif()

include("${_glyph_ndk}/build/cmake/android.toolchain.cmake")
