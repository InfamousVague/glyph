/// The room a menu has on the screen, and where the press-and-hold band sits in it: a port of
/// `src/app/editor/menuRoom.ts`, with the placing `ContextMenu.tsx` does in its layout effect.
///
/// Matt: "Allow the header to be overlapped by the popup menus". The room runs from under the phone's status bar
/// (`--app-inset-top`, app.css) down to what the keyboard leaves, [menuEdge] in from each side. The header and the
/// tabs are inside it: a menu may cover them, and never the status bar or the keyboard.
///
/// What differs:
/// - `menuRoom()` read the window, the visual viewport and the root's style itself; [menuRoom] is told them, and
///   [menuRoomOf] reads them where a widget stands: the window from `MediaQuery`, the keyboard from its
///   `viewInsets`, the status bar from the tokens;
/// - [statusBar] takes the custom property's text, as the page's `getComputedStyle` handed it over;
/// - the placing was inline in `ContextMenu.tsx`; it is [placeBand] here, so it can be asked without a widget. It
///   takes the band's size as the page's `offsetWidth` and `offsetHeight` gave it, rounded to a whole pixel
///   ([offsetSize]), which is what the page's arithmetic was done with.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

/// How near a menu comes to the room's edges (`MENU_EDGE`).
const double menuEdge = 8;

/// How far over the caret's top the band's foot stops, and how far under the caret's top it starts when it cannot
/// go above (`open.y - height - 12`, `open.y + 40`, ContextMenu.tsx).
const double bandLift = 12, bandDrop = 40;

/// Where the menu is asked for: the caret's place when the view has one for it, else the finger's; and the
/// selection (`Held`, editor/pressAndHold.ts). In the window's coordinates.
@immutable
class Held {
  const Held({required this.x, required this.y, required this.from, required this.to});

  final double x;
  final double y;
  final int from;
  final int to;

  @override
  bool operator ==(Object other) => other is Held && other.x == x && other.y == y && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(x, y, from, to);

  @override
  String toString() => 'Held($x, $y, $from-$to)';
}

/// The room, in the window's coordinates.
@immutable
class MenuRoom {
  const MenuRoom({required this.top, required this.bottom, required this.left, required this.right});

  final double top;
  final double bottom;
  final double left;
  final double right;

  @override
  bool operator ==(Object other) => other is MenuRoom && other.top == top && other.bottom == bottom && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(top, bottom, left, right);

  @override
  String toString() => 'MenuRoom(top: $top, bottom: $bottom, left: $left, right: $right)';
}

final RegExp _leadingNumber = RegExp(r'^\s*[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

/// The status bar's height in px, from what `--app-inset-top` says: "32px" is 32, and an inset that cannot be read
/// (nothing, or the raw `env(...)` text) is none (`statusBar`, as `parseFloat(...) || 0`).
double statusBar(String? inset) {
  final found = inset == null ? null : _leadingNumber.firstMatch(inset);
  if (found == null) return 0;
  final value = double.tryParse(found.group(0)!.trim()) ?? 0;
  return value.isNaN ? 0 : value;
}

/// The room: under the status bar, over the keyboard, [menuEdge] in from each side (`menuRoom`). [viewTop] and
/// [viewHeight] are the visual viewport's, what the keyboard leaves; without them the window is all of it.
MenuRoom menuRoom({required Size window, double statusBar = 0, double? viewTop, double? viewHeight}) {
  final top = viewHeight == null ? 0.0 : (viewTop ?? 0);
  final bottom = viewHeight == null ? window.height : (viewTop ?? 0) + viewHeight;
  return MenuRoom(top: math.max(top, statusBar) + menuEdge, bottom: bottom - menuEdge, left: menuEdge, right: window.width - menuEdge);
}

/// The room where `context` stands: the window `MediaQuery` describes, less the keyboard, under the status bar the
/// tokens give (`--app-inset-top`).
MenuRoom menuRoomOf(BuildContext context) {
  final media = MediaQuery.of(context);
  double inset;
  try {
    inset = context.tokens.len('app-inset-top');
  } on Object {
    inset = media.padding.top;
  }
  return menuRoom(window: media.size, statusBar: inset, viewTop: 0, viewHeight: media.size.height - media.viewInsets.bottom);
}

/// A box's size as the page's `offsetWidth` and `offsetHeight` say it: whole pixels.
Size offsetSize(Size size) => Size(size.width.roundToDouble(), size.height.roundToDouble());

/// Where the band's corner goes for a press at [held], the band being [size] (its `offsetWidth` by `offsetHeight`):
/// centred on the caret and kept in the room; above the selection, over the header if it must be, under it when
/// above would reach the status bar; never past the keyboard's top, and on a window too short for either the status
/// bar wins.
Offset placeBand(Held held, Size size, MenuRoom room) {
  var left = held.x - size.width / 2;
  left = math.max(room.left, math.min(left, room.right - size.width));
  var top = held.y - size.height - bandLift;
  if (top < room.top) top = held.y + bandDrop;
  top = math.max(room.top, math.min(top, room.bottom - size.height));
  return Offset(left, top);
}
