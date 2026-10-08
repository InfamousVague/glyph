/// Glides a page back to its top when what it shows changes. A port of `src/app/core/glideToTop.ts` (Matt: "when I
/// click different workspaces the page should scroll back up smoothly, not just jump to the top").
///
/// The jump was the layout's, not ours: the new list is usually shorter, so the page cannot stay as far down as it
/// was and snaps up in the same frame. So where the page was is remembered as it moves, and when the key changes the
/// page is given room at its foot to stay where it was, and then scrolled to the top smoothly. The room goes once
/// the page is at the top, where it is out of sight, or after three seconds whatever happened. With reduced motion
/// it goes to the top at once.
///
/// What differs:
/// - The web hook measured how short the new list was and borrowed exactly that much (`padding-block-end`), after
///   the new list was laid out and before it was painted. Here the room has to be asked for while the new list is
///   being built, before its height is known, so it is always enough: how far down the page was, and a window's
///   height. The page is at the same place either way, and the room is below everything on it.
/// - The glide is 420ms on an ease-out, the home page's own (lib/home/home_screen.dart), where the page asked the
///   browser for `behavior: 'smooth'` and took whatever it gave.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// `useGlideToTop(scroller, key)` for a [ScrollController]: call [keyed] from the page's build with the key and pad
/// the scroller's foot by what it answers. The differences from the hook are in the library doc.
class GlideToTop {
  GlideToTop(this.controller, {required this.onRoom}) {
    controller.addListener(_remember);
  }

  final ScrollController controller;

  /// The room at the foot has changed: draw again ([State.setState]).
  final VoidCallback onRoom;

  /// How long the glide takes, and how long the borrowed room may outlive it.
  static const Duration glide = Duration(milliseconds: 420);
  static const Duration most = Duration(milliseconds: 3000);

  String? _key;
  bool _keyed = false;
  double _lastTop = 0;
  double _room = 0;
  Timer? _cap;
  int _run = 0;
  bool _gone = false;

  /// The room the page's foot is borrowing now, in logical pixels: 0 at rest.
  double get room => _room;

  void _remember() {
    if (controller.hasClients && _room == 0) _lastTop = controller.position.pixels;
  }

  /// The key the page is drawn for. Answers the room to pad the foot by in this build: more than 0 from the build
  /// the key changes in, while the page was scrolled, until the glide ends. A null key never glides.
  double keyed(String? key, {required bool still}) {
    if (!_keyed) {
      _keyed = true;
      _key = key;
      return _room;
    }
    if (key == _key) return _room;
    _key = key;
    final from = _lastTop;
    if (key == null || from <= 0 || !controller.hasClients) return _room;
    if (still) {
      // Reduced motion: to the top at once, with no room borrowed.
      _end();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_gone && controller.hasClients) controller.jumpTo(0);
      });
      return _room;
    }
    _room = from + controller.position.viewportDimension;
    final run = _run += 1;
    _cap?.cancel();
    _cap = Timer(most, () {
      if (run == _run) _end(tell: true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gone || run != _run || !controller.hasClients) return;
      // Only the end of the glide itself takes the room away, and only once the page is at the top: a glide cut
      // short by a finger keeps the room until the cap, as the hook's `scrollend` check does.
      controller.animateTo(0, duration: glide, curve: Curves.easeOutCubic).whenComplete(() {
        if (run == _run && controller.hasClients && controller.position.pixels <= 1) _end(tell: true);
      });
    });
    return _room;
  }

  void _end({bool tell = false}) {
    _cap?.cancel();
    _cap = null;
    _run += 1;
    if (_room == 0) return;
    _room = 0;
    _lastTop = controller.hasClients ? controller.position.pixels : 0;
    if (tell && !_gone) onRoom();
  }

  /// Leaving the page mid-glide: the borrowed room goes with it.
  void dispose() {
    _gone = true;
    _cap?.cancel();
    controller.removeListener(_remember);
  }
}
