import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture made ready for a note, as android/…/ghost_md/Pictures.kt makes it on the phone: shrunk so its long
/// side is at most 1600 px, turned as its EXIF says, laid on white paper (a transparent screenshot must not turn
/// black as a JPEG) and written as a JPEG at 85 to `<cache>/picked/<uuid>.jpg`, where the core adopts it from
/// (`sync_put_file_path`, lib/core/phone_pictures.dart).
///
/// SHARED (apple/): compiled into ios/Runner, for the picture chooser and the clipboard there. The Mac app has
/// these lines as `GhostChannels.keep` in macos/Runner/GhostChannels.swift, which they were taken from; ImageIO is
/// the same on both, so when that file is next at rest its copy goes and its target takes this one.
enum PictureKeep {
  /// The long side a picture is kept at: Pictures.kt's `MAX_PX`.
  static let longSide = 1600

  /// Writes [source]'s first picture under [cache] and answers the file's path; nil where it cannot be read.
  static func keep(_ source: CGImageSource, cache: URL) -> String? {
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: longSide]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let width = image.width, height = image.height
    guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    let all = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(all)
    context.draw(image, in: all)
    guard let flat = context.makeImage() else { return nil }
    let folder = cache.appendingPathComponent("picked", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let out = folder.appendingPathComponent("\(UUID().uuidString.lowercased()).jpg")
    guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, flat, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? out.path : nil
  }

  /// The same for a picture's bytes.
  static func keep(_ data: Data, cache: URL) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return keep(source, cache: cache)
  }

  /// And for a picture in a file.
  static func keep(_ url: URL, cache: URL) -> String? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return keep(source, cache: cache)
  }
}
