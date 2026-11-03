// Types like a person, for the marketing video's writing scene (tool/marketing): each character as its own key event
// to the app's process, with a human, slightly uneven pace, a longer breath after a sentence or a line.
//
//   swiftc -O tool/marketing/typer.swift -o build/marketing/typer
//   build/marketing/typer <pid> <text file> [characters a second, 14 by default]
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]), let text = try? String(contentsOfFile: args[2], encoding: .utf8) else {
  print("usage: typer <pid> <text file> [cps]")
  exit(2)
}
let cps = args.count >= 4 ? Double(args[3]) ?? 14 : 14
var rng = SystemRandomNumberGenerator()
func key(_ code: CGKeyCode) {
  for down in [true, false] {
    if let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) { if pid == 0 { e.post(tap: .cghidEventTap) } else { e.postToPid(pid) } }
    usleep(4_000)
  }
}
for ch in text {
  if ch == "\n" {
    key(36)  // Return
    usleep(useconds_t(260_000))
    continue
  }
  let units = Array(String(ch).utf16)
  for down in [true, false] {
    if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) {
      event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
      if pid == 0 { event.post(tap: .cghidEventTap) } else { event.postToPid(pid) }
    }
    usleep(4_000)
  }
  var pause = 1.0 / cps * Double.random(in: 0.6...1.5, using: &rng)
  if ".,!?:".contains(ch) { pause += 0.18 }
  usleep(useconds_t(pause * 1_000_000))
}
