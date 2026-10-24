import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The list's own column (300px, app.css `.app-split`) and a note beside it no narrower than a small phone
/// (`SIDEBAR_WIDE`, core/useWideScreen.ts).
const double sidebarWide = 660;

/// A window that is not a strip (`SIDEBAR_TALL`): a phone held in landscape is as wide as a small desktop window and
/// a few hundred pixels tall, with no room to put a list beside anything.
const double sidebarTall = 600;

/// Whether the window is wide enough for more in a header (`useWideScreen`): a tablet, or a folding phone opened out.
bool wideScreen(Size window) => window.width >= 600;

/// Whether the notes may sit in a pane beside the open note (`splitFits` behind `useSidebar`, core/useWideScreen.ts).
/// A question about the window's shape, not about the device: wide enough, and tall enough unless the pointer is a
/// [mouse], where a short window is one the person chose and not the shape of the hardware.
///
/// Differs from the web: the page held its answer while something was being typed into, because the keyboard coming
/// up took the window under the height. Flutter's window keeps its size under the keyboard (the keyboard is an inset
/// of it), so there is nothing to hold.
bool splitFits(Size window, {required bool mouse}) => window.width >= sidebarWide && (window.height >= sidebarTall || mouse);

/// Whether the screen's own pointer is a mouse rather than a finger, as `(pointer: fine)` and `(hover: hover)` ask
/// it: here, whether the app is on a desktop.
///
/// A mouse joined to a phone or a tablet does not change the answer, and it does not change the page's either. A
/// page's two questions are about the PRIMARY pointer, and Chromium on Android answers them by the touch screen
/// while there is one, whatever else is plugged in (ui/base/pointer: the primary pointer is coarse if any pointer
/// is, and the primary hover is none if any is). Asked of the Tauri app's own page on an emulator whose touch
/// screens are styluses too, 2026-10-09 (WebView 133): `(any-pointer: fine)` true, `(pointer: fine)` false,
/// `(pointer: coarse)` true, `(hover: hover)` false. So every rule the page guards with these (the header's blur
/// strip in place of smoke, `wispHead`, which here is the blur on every platform since 2026-10-24; the tab row's plain fade; a row's cross or a folder's More that waits to be
/// pointed at; the + in the gutter's and the + list's hover grounds; the fly-out submenu; a canvas's eight handles
/// in place of a finger's four) is the finger's on a phone with a mouse, there and here. What a mouse does get on
/// a phone, there and here, is what asks the EVENT and not the screen: an unguarded `:hover`, a right-click's menu
/// (`byMouse`), a card dragged without being picked first.
bool get mousePointer => switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
      _ => false,
    };

/// `(hover: hover)`: the screen's own pointer can be held over a thing. The same answer as [mousePointer], for the
/// same reason.
bool get hoverPointer => mousePointer;

/// A phone or a tablet, whatever its window's width (`isMobile`, core/platform.ts).
bool get mobileDevice => !mousePointer;

/// Whether the docked sidebar shows before it has ever been toggled (`readSidebarShown`): where there is a mouse, and
/// hidden under a finger, so a folding phone opened out starts on the note with its sidebar a tap away.
bool sidebarShownByDefault({required bool mouse}) => mouse;

/// The split window's columns (app.css `.app-split`): the sidebar `clamp(300px, 30vw, 380px)`, the aside
/// `clamp(240px, 22vw, 320px)`, the note the rest.
double sidebarColumn(double window) => (window * 0.30).clamp(300.0, 380.0);

/// Simple mode's list column beside the note (GHST-105): about 360px, a little narrower on a window where the note
/// would otherwise be a strip (the Fold opened out is 704 wide).
double simpleListColumn(double window) => (window * 0.42).clamp(300.0, 360.0);
double asideColumn(double window) => (window * 0.22).clamp(240.0, 320.0);
