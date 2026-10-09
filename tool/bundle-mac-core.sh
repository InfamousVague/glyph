#!/bin/sh
# Xcode's "Bundle the core" phase (macos/Runner.xcodeproj): puts the Rust core where the Mac app loads it from,
# <app>/Contents/Frameworks/libghost_core.dylib (lib/core/native/ghost_worker.dart `defaultLibraryName`), and
# signs it with the identity the app itself is being signed with, before Xcode signs the app around it.
#
# The library is tool/build-native.sh mac's (macos/Core/, not in git, as the phone's jniLibs is not). A build with
# none there stops here and says so, rather than making an app that opens on no library.
#
# A debug build is signed ad hoc ("-") and so is the copy. A release signed with a Developer ID gets the hardened
# runtime and a secure timestamp on the library too: notarisation refuses an app with a nested library that has
# neither. Nothing here notarises or publishes anything.
set -eu

core="$PROJECT_DIR/Core/libghost_core.dylib"
if [ ! -f "$core" ]; then
  echo "error: no macos/Core/libghost_core.dylib: run tool/build-native.sh mac first." >&2
  exit 1
fi

# Every architecture the app is being built for must be in it: a universal app with an Apple silicon core alone
# opens on an Intel Mac and finds no library.
have="$(lipo -archs "$core")"
for arch in $ARCHS; do
  case " $have " in
    *" $arch "*) ;;
    *) echo "error: macos/Core/libghost_core.dylib is built for $have, not $arch: run tool/build-native.sh mac." >&2; exit 1 ;;
  esac
done

into="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$into"
cp -f "$core" "$into/libghost_core.dylib"

identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[ -n "$identity" ] || identity="-"
if [ "$identity" = "-" ]; then
  codesign --force --sign - "$into/libghost_core.dylib"
else
  codesign --force --sign "$identity" --options runtime --timestamp "$into/libghost_core.dylib"
fi
