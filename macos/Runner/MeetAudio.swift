import AVFoundation
import Foundation

/// `ghost_md/meet_audio` on the Mac: a meeting Ghost was in, its sound made the WAV a meeting recorded here keeps
/// (lib/meet/tape.dart, docs/MEET.md "On the device"). Dart reads the bot's WebM and hands over its Opus packets in a
/// file (`GOP1`, lib/meet/webm.dart `packedForDecoder`); this decodes them with the Mac's own Opus decoder
/// (`AVAudioConverter` from `kAudioFormatOpus`), mixes the channels to one, drops the stream's pre-skip, converts
/// 48 kHz to 16 kHz with the converter's best quality, and writes 16-bit PCM, a chunk at a time, so an hour's meeting
/// is never held whole.
///
/// - `opusToWav {packets, wav}` -> `{ms}`: an error with the reason where the packets will not decode.
///
/// No Flutter in [MeetAudio] itself, so it is compiled and run against a real WebM outside the app
/// (docs/MEET.md, "On the device", says how); the channel is GhostChannels.swift's.
enum MeetAudio {
  struct Failure: Error, CustomStringConvertible {
    let description: String
  }

  /// The packets file, read.
  struct Packets {
    var channels: Int
    var preSkip: Int
    var data: Data
    var offsets: [Int] = []
    var sizes: [Int] = []
    var frames: [Int] = []
  }

  static func read(_ url: URL) throws -> Packets {
    let data = try Data(contentsOf: url, options: .alwaysMapped)
    func u32(_ at: Int) -> Int {
      guard at + 4 <= data.count else { return -1 }
      return data[data.startIndex + at ..< data.startIndex + at + 4].reduce(0) { ($0 << 8) | Int($1) }
    }
    guard data.count >= 8, data.prefix(4) == Data("GOP1".utf8) else { throw Failure(description: "Those are not a meeting's packets.") }
    let length = u32(4)
    guard length > 0, 8 + length <= data.count,
          let head = try JSONSerialization.jsonObject(with: data[data.startIndex + 8 ..< data.startIndex + 8 + length]) as? [String: Any]
    else { throw Failure(description: "Those packets have no head.") }
    let channels = (head["channels"] as? Int) ?? 1
    var packets = Packets(channels: max(1, min(2, channels)), preSkip: (head["preSkip"] as? Int) ?? 0, data: data)
    var at = 8 + length + ((head["headBytes"] as? Int) ?? 0)
    while at + 8 <= data.count {
      let size = u32(at), frames = u32(at + 4)
      guard size >= 0, at + 8 + size <= data.count else { break }
      if size > 0 {
        packets.offsets.append(at + 8)
        packets.sizes.append(size)
        packets.frames.append(frames)
      }
      at += 8 + size
    }
    return packets
  }

  /// A 16 kHz mono 16-bit WAV, its header written last.
  final class Wav {
    let handle: FileHandle
    var samples = 0

    init(_ url: URL) throws {
      FileManager.default.createFile(atPath: url.path, contents: nil)
      handle = try FileHandle(forWritingTo: url)
      try handle.write(contentsOf: Data(count: 44))
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
      guard buffer.frameLength > 0, let channel = buffer.int16ChannelData?[0] else { return }
      try handle.write(contentsOf: Data(bytes: channel, count: Int(buffer.frameLength) * 2))
      samples += Int(buffer.frameLength)
    }

    func close() throws {
      var header = Data()
      func put(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
      func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
      let bytes = UInt32(samples * 2)
      header.append(contentsOf: Array("RIFF".utf8)); put(36 + bytes)
      header.append(contentsOf: Array("WAVEfmt ".utf8)); put(16); put16(1); put16(1); put(16000); put(32000); put16(2); put16(16)
      header.append(contentsOf: Array("data".utf8)); put(bytes)
      try handle.seek(toOffset: 0)
      try handle.write(contentsOf: header)
      try handle.close()
    }
  }

  /// Decodes [packets] into the WAV at [wav]; answers its length in ms.
  static func opusToWav(packets url: URL, wav out: URL) throws -> Int {
    let packets = try read(url)
    guard !packets.sizes.isEmpty else { throw Failure(description: "That meeting has no sound in it.") }
    let channels = AVAudioChannelCount(packets.channels)
    // The frames most packets hold: 960, twenty milliseconds, from Chrome. A packet that differs says its own.
    var counts: [Int: Int] = [:]
    for frames in packets.frames { counts[frames, default: 0] += 1 }
    let common = counts.max { $0.value < $1.value }?.key ?? 960
    var described = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: UInt32(max(common, 1)), mBytesPerFrame: 0, mChannelsPerFrame: channels, mBitsPerChannel: 0, mReserved: 0)
    guard let opus = AVAudioFormat(streamDescription: &described),
          let decoded = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: channels, interleaved: false),
          let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false),
          let wanted = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
          let decoder = AVAudioConverter(from: opus, to: decoded),
          let resampler = AVAudioConverter(from: mono, to: wanted)
    else { throw Failure(description: "This Mac cannot decode the meeting's sound.") }
    resampler.sampleRateConverterQuality = AVAudioQuality.max.rawValue

    let wav = try Wav(out)
    var finished = false
    defer { if !finished { try? wav.handle.close(); try? FileManager.default.removeItem(at: out) } }

    var next = 0
    let chunk = 50
    func input(_ wanted: AVAudioPacketCount, _ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
      guard next < packets.sizes.count else {
        status.pointee = .endOfStream
        return nil
      }
      let count = min(chunk, packets.sizes.count - next)
      let largest = packets.sizes[next ..< next + count].max() ?? 1
      let buffer = AVAudioCompressedBuffer(format: opus, packetCapacity: AVAudioPacketCount(count), maximumPacketSize: largest)
      var offset = 0
      packets.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        for i in 0 ..< count {
          let index = next + i, size = packets.sizes[index]
          (buffer.data + offset).copyMemory(from: raw.baseAddress! + packets.offsets[index], byteCount: size)
          let frames = packets.frames[index]
          buffer.packetDescriptions![i] = AudioStreamPacketDescription(mStartOffset: Int64(offset), mVariableFramesInPacket: frames == common ? 0 : UInt32(max(frames, 0)), mDataByteSize: UInt32(size))
          offset += size
        }
      }
      buffer.packetCount = AVAudioPacketCount(count)
      buffer.byteLength = UInt32(offset)
      next += count
      status.pointee = .haveData
      return buffer
    }

    /// [buffer] (48 kHz mono) through the resampler into the file; with [last], what it holds back too.
    func resample(_ buffer: AVAudioPCMBuffer?, last: Bool) throws {
      var given = buffer == nil
      while true {
        guard let into = AVAudioPCMBuffer(pcmFormat: wanted, frameCapacity: 16384) else { throw Failure(description: "Out of memory.") }
        var error: NSError?
        let status = resampler.convert(to: into, error: &error) { _, status in
          if !given, let buffer {
            given = true
            status.pointee = .haveData
            return buffer
          }
          status.pointee = last ? .endOfStream : .noDataNow
          return nil
        }
        if status == .error { throw error ?? Failure(description: "The sound could not be converted.") }
        try wav.write(into)
        if status != .haveData { return }
      }
    }

    var skip = packets.preSkip
    while true {
      guard let into = AVAudioPCMBuffer(pcmFormat: decoded, frameCapacity: 48000) else { throw Failure(description: "Out of memory.") }
      var error: NSError?
      let status = decoder.convert(to: into, error: &error) { wanted, status in input(wanted, status) }
      if status == .error { throw error ?? Failure(description: "The meeting's sound would not decode.") }
      let frames = Int(into.frameLength)
      if frames > skip, let source = into.floatChannelData, let mixed = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(frames - skip)) {
        let count = frames - skip
        let target = mixed.floatChannelData![0]
        let share = 1 / Float(channels)
        for i in 0 ..< count {
          var sum: Float = 0
          for c in 0 ..< Int(channels) { sum += source[c][skip + i] }
          target[i] = sum * share
        }
        mixed.frameLength = AVAudioFrameCount(count)
        skip = 0
        try resample(mixed, last: false)
      } else {
        skip -= min(skip, frames)
      }
      if status == .endOfStream || (status == .inputRanDry && next >= packets.sizes.count) { break }
    }
    try resample(nil, last: true)
    try wav.close()
    finished = true
    return wav.samples / 16
  }
}
