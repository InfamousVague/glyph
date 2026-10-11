/// What a desktop's keyboard and menu bar ask of the app, and who answers.
///
/// The web app bound these on its page: Command-N and Command-R in App.tsx (the Mac app only: docs/DESIGN.md §144
/// and §210 of tauri/), Command-K in the kit's palette, Command-F in Settings' field, and Tauri's default menu
/// beside them. Here they are named once, so the Mac's menu bar (macos/Runner/AppDelegate.swift, through
/// lib/shell/desktop/mac_window.dart) and the keyboard reach the same handler:
///
/// | key | command | answered by |
/// | --- | ------- | ----------- |
/// | Command-N | [DesktopCommand.newNote] | the root: a new blank note, only on a place and with nothing open over it |
/// | Command-R | [DesktopCommand.sync] | the root: the pull's refresh, and a toast when it is done |
/// | Command-K | [DesktopCommand.palette] | the root: the command palette (the kit binds the key itself) |
/// | Command-F | [DesktopCommand.find] | the open note: its find bar (Settings takes the key itself while it is open) |
/// | Command-, | [DesktopCommand.settings] | the root: Settings |
///
/// A handler answers whether it did anything; the newest handler is asked first, so a note opened over another
/// finds in itself. A key nobody answers is left for whatever else wants it.
///
/// What differs from the web: the page's Command-N and Command-R were the Mac app's alone, since in a browser they
/// are the browser's. Here they are every desktop's ([DesktopKeys.attach] is given the platform), Control standing
/// for Command off the Mac, as the kit's palette key does.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DesktopCommand { newNote, sync, palette, find, settings }

/// The command a menu's choice names (`ghost_md/window` `menu`), or null.
DesktopCommand? desktopCommandNamed(String name) => switch (name) {
      'newNote' => DesktopCommand.newNote,
      'sync' => DesktopCommand.sync,
      'palette' => DesktopCommand.palette,
      'find' => DesktopCommand.find,
      'settings' => DesktopCommand.settings,
      _ => null,
    };

typedef DesktopHandler = bool Function();

class DesktopCommands {
  final Map<DesktopCommand, List<DesktopHandler>> _handlers = {};

  /// Whether something modal is over the page (Settings, the palette, a sheet): the root says. A note under it
  /// does not answer Find then, since what is over it has the keyboard.
  bool Function()? covered;

  /// Answers [command] with [handler] until the function given back is called.
  VoidCallback on(DesktopCommand command, DesktopHandler handler) {
    (_handlers[command] ??= []).add(handler);
    return () => _handlers[command]?.remove(handler);
  }

  /// Asks the handlers of [command], newest first, until one says it did something.
  bool run(DesktopCommand command) {
    if (command == DesktopCommand.find && (covered?.call() ?? false)) return false;
    for (final handler in [...?_handlers[command]].reversed) {
      if (handler()) return true;
    }
    return false;
  }
}

/// The app's one set: the root and the open note answer on it.
final DesktopCommands desktopCommands = DesktopCommands();

/// The key a command is asked by, with Command (the Mac) or Control (elsewhere) alone held.
DesktopCommand? desktopCommandFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.keyN) return DesktopCommand.newNote;
  if (key == LogicalKeyboardKey.keyR) return DesktopCommand.sync;
  if (key == LogicalKeyboardKey.keyF) return DesktopCommand.find;
  if (key == LogicalKeyboardKey.comma) return DesktopCommand.settings;
  // Command-K is the kit's own (packages/glacier command_palette.dart), bound where the palette is.
  return null;
}

/// The keyboard's half: one handler on the hardware keyboard for the life of the app, on a desktop.
class DesktopKeys {
  DesktopKeys({required this.commands, required this.mac});

  final DesktopCommands commands;

  /// Whether Command is the key (a Mac), or Control.
  final bool mac;

  bool _attached = false;

  /// Begins to listen, on a desktop; nothing on a phone, where these chords are the keyboard's own.
  static DesktopKeys? attach({TargetPlatform? platform, DesktopCommands? commands}) {
    final device = platform ?? defaultTargetPlatform;
    final desktop = device == TargetPlatform.macOS || device == TargetPlatform.windows || device == TargetPlatform.linux;
    if (!desktop) return null;
    final keys = DesktopKeys(commands: commands ?? desktopCommands, mac: device == TargetPlatform.macOS);
    HardwareKeyboard.instance.addHandler(keys.handle);
    keys._attached = true;
    return keys;
  }

  void dispose() {
    if (_attached) HardwareKeyboard.instance.removeHandler(handle);
    _attached = false;
  }

  /// One key event: a command's chord, pressed once and not held (`event.repeat`), with no other modifier.
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final chord = mac ? keyboard.isMetaPressed && !keyboard.isControlPressed : keyboard.isControlPressed && !keyboard.isMetaPressed;
    if (!chord || keyboard.isAltPressed || keyboard.isShiftPressed) return false;
    final command = desktopCommandFor(event.logicalKey);
    return command != null && commands.run(command);
  }
}
