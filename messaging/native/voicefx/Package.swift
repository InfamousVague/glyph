// swift-tools-version: 5.9
// voicefx as a Swift package, for the Mac app (macos/Runner/VoiceFx.swift): RNNoise and the microphone's gain, in C,
// and DeepFilterNet where deepfilter/build.sh has built it (tool/release-mac.mjs does): without it, RNNoise alone.
import Foundation
import PackageDescription

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let deepFilter = FileManager.default.fileExists(atPath: here + "/deepfilter/build/VoiceFxDeepFilter.xcframework")

var targets: [Target] = [
    .target(
        name: "VoiceFxC",
        dependencies: deepFilter ? ["VoiceFxDeepFilter"] : [],
        path: ".",
        exclude: ["test", "README.md", "rnnoise/COPYING", "deepfilter"],
        sources: ["voicefx.c", "rnnoise/src"],
        publicHeadersPath: "include",
        cSettings: [
            .headerSearchPath("rnnoise/include"),
            .headerSearchPath("rnnoise/src"),
            .unsafeFlags(["-O2"]),
        ] + (deepFilter ? [.define("VOICEFX_WITH_DEEPFILTER")] : []),
        linkerSettings: deepFilter ? [.linkedFramework("Security"), .linkedFramework("CoreFoundation")] : []
    )
]
if deepFilter {
    targets.append(.binaryTarget(name: "VoiceFxDeepFilter", path: "deepfilter/build/VoiceFxDeepFilter.xcframework"))
}

let package = Package(
    name: "VoiceFx",
    platforms: [.macOS("10.15")],
    products: [.library(name: "VoiceFxC", targets: ["VoiceFxC"])],
    targets: targets
)
