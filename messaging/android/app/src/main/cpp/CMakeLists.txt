# voicefx for Android (native/voicefx): RNNoise and the gain, run in flutter_webrtc's capture hook (VoiceFx.kt).
cmake_minimum_required(VERSION 3.18)
project(voicefx C)
set(VFX ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native/voicefx)
file(GLOB RNNOISE ${VFX}/rnnoise/src/*.c)
add_library(voicefx SHARED ${VFX}/voicefx.c ${RNNOISE} voicefx_jni.c)
target_include_directories(voicefx PRIVATE ${VFX}/include ${VFX}/rnnoise/include ${VFX}/rnnoise/src)
target_compile_options(voicefx PRIVATE -O2 -std=c11 -fvisibility=hidden)
target_link_libraries(voicefx m log)
