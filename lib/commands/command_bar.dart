import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/ghost.dart';
import '../core/back.dart';
import 'palette.dart';

/// The command palette on screen: a port of the web app's `src/app/commands/CommandBar.tsx`, the kit's
/// [GlacierCommandPalette] over the app's own list of doings (palette.dart).
///
/// The kit binds ⌘K / Ctrl+K itself and does the searching, the grouping and the cursor. Three things are the app's:
///
/// - **A phone has no ⌘.** The ways in there are the home page's dock and the sidebar's search tool, which call the
///   opener [onReady] hands over (or [CommandBarState.show] through a key), so this holds the open state.
/// - **The back gesture closes it.** It stands on the app's back stack (lib/core/back.dart) while open, over
///   whatever was up before it, so back closes the palette and leaves the note behind it where it was.
/// - **What is typed is held here**, so the notes offered by name come from the whole library ([notesByName]) and
///   every opening starts empty.
///
/// The words are the web's: the field says "What would you like to do?", nothing found is the ghost looking with
/// "Nothing by that name.", and the footer is the kit's own key hints. The one thing the app's stylesheets lay over
/// the kit's palette is `kbd { font-feature-settings: var(--app-mono-features); letter-spacing: 0 }`
/// (typefaces.css), which is passed as the key caps' style.
///
/// What differs from the web:
/// - **The ghost is held to the room the panel has.** On the page it is 40% of the window's height tall whatever
///   the panel's own limit (`min(28rem, 70vh)`), so at 390 x 844 and at 1280 x 800 the empty state is taller than
///   the panel: the words "Nothing by that name." and the key hints are drawn below the panel's edge, over the
///   scrim. Here the ghost takes what is left of the panel once the field, the words and the hints have theirs,
///   and no more than the page's 40%.
/// - **The list is built only while the palette is open.** The page keeps it built; nothing reads it shut.
/// - **[CommandBar.over]** is not on the page: the world and the doings asked for when the palette opens, for a
///   root that does not rebuild with the shell.
/// - [onReady] is handed the opener once, after the first frame, as the page's effect did; a key and
///   [CommandBarState] reach the same thing without waiting for it.
/// - Mount it once, in the app's root beside the shell and outside any hued or inverse scope: the kit's palette
///   reads its tokens where it is mounted and draws on the root overlay (see [GlacierCommandPalette]).
class CommandBar extends StatefulWidget {
  /// The web's own shape: the world and the doings as they stand at this build. Whoever builds this must build
  /// again when either changes (the screen, the tabs, the trail), as App.tsx renders again on any of them.
  const CommandBar({super.key, required PaletteWorld this.world, required PaletteDoing this.doing, this.onReady, this.shortcut = true})
      : worldNow = null,
        doingNow = null;

  /// The same palette, asking for the world and the doings when it opens and at each letter typed, rather than
  /// being handed them at every build. For lib/root, which is not rebuilt when the shell changes its screen: what
  /// the palette offers is then read from the shell at the moment it is opened, and nothing is worked out while it
  /// is shut.
  const CommandBar.over({super.key, required ValueGetter<PaletteWorld> world, required ValueGetter<PaletteDoing> doing, this.onReady, this.shortcut = true})
      : world = null,
        doing = null,
        worldNow = world,
        doingNow = doing;

  final PaletteWorld? world;
  final PaletteDoing? doing;
  final ValueGetter<PaletteWorld>? worldNow;
  final ValueGetter<PaletteDoing>? doingNow;

  /// Handed back a function that opens the palette, for whatever chrome wants to offer it.
  final ValueChanged<VoidCallback>? onReady;

  /// Whether ⌘K / Ctrl+K opens it. The web always binds it; off is for a host that owns the chord.
  final bool shortcut;

  /// The field's words, empty (`placeholder`).
  static const String placeholder = 'What would you like to do?';

  /// The words under the ghost when nothing matches.
  static const String nothing = 'Nothing by that name.';

  @override
  State<CommandBar> createState() => CommandBarState();
}

class CommandBarState extends State<CommandBar> {
  bool _open = false;

  /// What is typed, held here so the notes offered by name can come from the whole library.
  String _query = '';

  bool get isOpen => _open;
  String get query => _query;

  @override
  void initState() {
    super.initState();
    // The opener is handed over ONCE, on mount: a caller passing a new callback on every build is never called
    // again, so it cannot loop however it holds what it is given.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call(show);
    });
  }

  /// Opens the palette, empty.
  void show() => _set(true);

  /// Closes it.
  void close() => _set(false);

  void _set(bool next) {
    if (!mounted) return;
    setState(() {
      if (next) _query = '';
      _open = next;
    });
  }

  /// `'calt', 'liga'` as the font's features.
  static List<FontFeature> _features(String? value) => [for (final tag in RegExp(r'''["']([A-Za-z0-9]{4})["']''').allMatches(value ?? '')) FontFeature(tag.group(1)!)];

  @override
  Widget build(BuildContext context) {
    final t = GlacierTheme.of(context);
    // The list is rebuilt as the app changes under it: a note opened, a tab closed, a workspace chosen.
    final commands = _open ? paletteCommands(widget.world ?? widget.worldNow!(), widget.doing ?? widget.doingNow!(), _query) : const <PaletteCommand>[];
    return OnBack(
      // Over everything else, so it closes first and the note behind it stays open.
      active: _open,
      onBack: close,
      child: GlacierCommandPalette(
        open: _open,
        onOpenChange: _set,
        query: _query,
        onQueryChange: (next) {
          if (next != _query) setState(() => _query = next);
        },
        commands: [for (final command in commands) command.descriptor],
        onRun: (id) {
          for (final command in commands) {
            if (command.descriptor.id == id) return command.run();
          }
        },
        placeholder: CommandBar.placeholder,
        emptyLabel: const _Nothing(),
        shortcut: widget.shortcut,
        kbdStyle: TextStyle(fontFeatures: _features(t.raw('app-mono-features')), letterSpacing: 0),
      ),
    );
  }
}

/// `emptyLabel`: the ghost looking through its glass over "Nothing by that name.", a grid centred with a step
/// between and a step of padding above and below.
class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) {
    final t = GlacierTheme.of(context);
    final media = MediaQuery.of(context);
    final window = media.size.height - media.viewInsets.bottom;
    final hairline = t.len('glacier-hairline');
    final words = t.fontSize('sm') * t.len('glacier-leading-sm');
    final hint = t.fontSize('xs') * t.len('glacier-leading-xs');
    // What the kit's panel is made of around this, top to bottom (CommandPalette.module.css): its border and
    // padding, the field, a gap, .empty's padding, this grid's padding, the ghost, a gap, the words, .empty's
    // padding, a gap, the footer's rule, padding and line, and the panel's padding and border again.
    final panel = math.min(t.lenOf('28rem'), window * 0.7);
    final around = 2 * (hairline + t.space(2)) + t.len('glacier-control-height-md') + t.space(2) + 2 * t.space(6) + 2 * t.space(4) + t.space(3) + words.ceilToDouble() + t.space(2) + hairline + t.space(2) + hint.ceilToDouble() + t.space(1);
    // The page's `40dvh`, or what the panel has left where that is less.
    final tall = math.max(0.0, math.min(window * 0.4, panel - around));
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space(4)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tall >= t.lenOf('3rem')) ...[
            Ghost(scene: GhostScene.searchNothing, align: GhostAlign.center, heightShare: tall / media.size.height),
            SizedBox(height: t.space(3)),
          ],
          const Text(CommandBar.nothing),
        ],
      ),
    );
  }
}
