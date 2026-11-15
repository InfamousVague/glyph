// swift-tools-version: 5.9
// voicefx as a Swift package, for the Mac app (macos/Runner/VoiceFx.swift): RNNoise and the microphone's gain, in C.
import PackageDescription

let package = Package(
    name: "VoiceFx",
    platforms: [.macOS("10.15")],
    products: [.library(name: "VoiceFxC", targets: ["VoiceFxC"])],
    targets: [
        .target(
            name: "VoiceFxC",
            path: ".",
            exclude: ["test", "README.md", "rnnoise/COPYING"],
            sources: ["voicefx.c", "rnnoise/src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("rnnoise/include"),
                .headerSearchPath("rnnoise/src"),
                .unsafeFlags(["-O2"]),
            ]
        )
    ]
)
