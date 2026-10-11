// The Rust core is a static library on an iPhone (tool/build-native.sh ios, ios/Core/GhostCore.xcframework), and
// nothing compiled here calls it: Dart finds its five functions by name in the app's own image
// (lib/core/native/ghost_worker.dart, `DynamicLibrary.process`). A linker takes from a static library only what
// something names, and then drops what nothing reaches, so they are named here, in a table it is told to keep:
// that pulls the core into the app and holds the five through the release build's dead stripping. They stay
// findable by name because the Runner strips only what is not global (STRIP_STYLE, Runner.xcodeproj).
//
// The signatures are native/src/ffi.rs's; only the addresses are taken.
#include <stddef.h>
#include <stdint.h>

extern uint8_t *ghost_alloc(size_t len);
extern void ghost_free(uint8_t *ptr, size_t len);
extern uint8_t *ghost_invoke(const uint8_t *cmd, size_t cmd_len, const uint8_t *args, size_t args_len, size_t *out_len);
extern void ghost_set_listener(void (*listener)(uint8_t *json, size_t len));
extern void ghost_forget_listener(void (*listener)(uint8_t *json, size_t len));

__attribute__((used, visibility("default"))) const void *const ghost_core_kept[] = {
  (const void *)&ghost_alloc,
  (const void *)&ghost_free,
  (const void *)&ghost_invoke,
  (const void *)&ghost_set_listener,
  (const void *)&ghost_forget_listener,
};
