/// A workspace's colour, chosen from a swatch: six hues and the app's own ink, as dots in a row. A port of
/// `src/app/notes/WorkspaceSwatch.tsx`, with the dots' look from `settings/swatch.module.css`, which it composes.
///
/// The app is grey everywhere else on purpose, so this is the one place a colour carries meaning, and each hue is
/// drawn at the lightness its paper needs (ink.css `[data-hue]`). The dots are a radio group: one is chosen, the
/// arrow keys move between them, and the chosen one wears a tick rather than only a ring, so it is not colour alone
/// that says which.
///
/// What differs: nothing in what it draws. The sheet it sits in (`notes/WorkspaceSheet.tsx`) is not ported yet; the
/// home page hands its "New workspace" and "Edit" to a callback.
library;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/workspaces.dart';
import '../home/home_icons.dart';

/// What each hue is called, for the finger that cannot see the colour (`NAMES`).
const Map<String, String> workspaceHueNames = {'ink': 'Ink', 'ember': 'Ember', 'amber': 'Amber', 'moss': 'Moss', 'sea': 'Sea', 'violet': 'Violet', 'rose': 'Rose'};

/// The seven hues as a radio group of dots (`src/app/notes/WorkspaceSwatch.tsx`, `settings/swatch.module.css`).
/// Nothing differs in what it draws; a press also takes the keyboard to its dot, as a click on a button does.
class WorkspaceSwatch extends StatefulWidget {
  const WorkspaceSwatch({super.key, required this.hue, required this.onHue});

  /// The hue chosen: one of [workspaceHues].
  final String hue;
  final ValueChanged<String> onHue;

  @override
  State<WorkspaceSwatch> createState() => _WorkspaceSwatchState();
}

class _WorkspaceSwatchState extends State<WorkspaceSwatch> {
  late final Map<String, FocusNode> _nodes = {for (final hue in workspaceHues) hue: FocusNode(debugLabel: 'Hue $hue')};

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final step = key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown ? 1 : (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp ? -1 : 0);
    if (step == 0) return KeyEventResult.ignored;
    final at = workspaceHues.indexOf(widget.hue);
    final next = workspaceHues[(at + step + workspaceHues.length) % workspaceHues.length];
    widget.onHue(next);
    _nodes[next]!.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: 'Colour',
      role: SemanticsRole.radioGroup,
      explicitChildNodes: true,
      child: Padding(
        // `.swatch`: one row, however narrow the sheet; the dots share what room there is.
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(4)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final hue in workspaceHues)
              GlacierScope(
                attrs: {'hue': hue},
                child: Builder(
                  builder: (context) {
                    final here = context.tokens;
                    final on = hue == widget.hue;
                    final fill = here.colorOf('var(--app-space, var(--app-ink))');
                    final paper = here.color('app-paper');
                    return Semantics(
                      inMutuallyExclusiveGroup: true,
                      checked: on,
                      label: workspaceHueNames[hue],
                      onTap: () => widget.onHue(hue),
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        includeSemantics: false,
                        onKeyEvent: (node, event) => _onKey(event),
                        child: GlacierPressable(
                          focusNode: _nodes[hue],
                          // A press takes the keyboard to the dot, as a click on a button does on the page.
                          onPressed: () {
                            _nodes[hue]!.requestFocus();
                            widget.onHue(hue);
                          },
                          haptic: HapticKind.selection,
                          excludeSemantics: true,
                          builder: (context, state) => GlacierFocusRing(
                            visible: state.focused,
                            offset: 3,
                            child: AnimatedScale(
                              // Chosen: `transform: scale(1.06)`, over 160ms; still under reduced motion.
                              scale: on && !here.reducedMotion ? 1.06 : 1,
                              duration: here.reducedMotion ? Duration.zero : const Duration(milliseconds: 160),
                              curve: here.curve('glacier-ease-out'),
                              child: AnimatedContainer(
                                duration: here.reducedMotion ? Duration.zero : const Duration(milliseconds: 160),
                                curve: here.curve('glacier-ease-out'),
                                width: here.lenOf('2rem'),
                                height: here.lenOf('2rem'),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: fill,
                                  // A ring of the page around it, then the dot's own colour again (the first of a CSS shadow list is on top).
                                  boxShadow: on ? [BoxShadow(color: fill, spreadRadius: 4), BoxShadow(color: paper, spreadRadius: 2)] : const [],
                                ),
                                child: on ? HomeIcon(HomeGlyph.check, size: 14, color: paper) : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
