// Smooth, eased scrolling for the marketing video's recordings (tool/marketing): pixel-precise scroll-wheel events
// at 120 a second, an ease-in-out over the whole distance, so a page glides the way a trackpad's does. The events go
// to the app's process itself, at a point in its window, so it scrolls while another window is in front.
//
//   swiftc -O tool/marketing/glide.swift -o build/marketing/glide
//   build/marketing/glide <pid> <pixels, positive scrolls down> <seconds> <x> <y>
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 6, let pid = pid_t(args[1]), let total = Double(args[2]), let seconds = Double(args[3]), let x = Double(args[4]), let y = Double(args[5]) else {
  print("usage: glide <pid> <pixels> <seconds> <x> <y>")
  exit(2)
}
let at = CGPoint(x: x, y: y)
// pid 0: the system's own stream, to the window under the pointer, which is moved there first.
if pid == 0 {
  CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
  usleep(120_000)
}
let rate = 120.0
let steps = max(1, Int(seconds * rate))
func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
var sent = 0.0
var carry = 0.0
for i in 1...steps {
  let target = total * ease(Double(i) / Double(steps))
  let delta = target - sent + carry
  let whole = delta.rounded(.towardZero)
  carry = delta - whole
  sent += whole
  if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-whole), wheel2: 0, wheel3: 0) {
    event.location = at
    // A trackpad's gesture: continuous, its phase begun, changing, then ended.
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: i == 1 ? 1 : (i == steps ? 4 : 2))
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(-whole))
    if pid == 0 { event.post(tap: .cghidEventTap) } else { event.postToPid(pid) }
  }
  usleep(useconds_t(1_000_000 / rate))
}
