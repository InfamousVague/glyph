import 'dart:ui' show SemanticsRole;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/preferences.dart';
import 'kit/settings_icons.dart';
import 'settings_screen.dart' show SettingsNoSwipe;
import 'words.dart';

/// Port of `AccentSwatch` (src/app/settings/AccentSwatch.tsx, AccentSwatch.module.css, swatch.module.css): the app's
/// one colour, chosen from a swatch. Ink first, which is Ghost.md's own answer and no accent at all, then the colours
/// the kit carries. Each dot wears the accent itself, so what it shows is the very ramp that choosing it would put
/// on the app (tokens.css `[data-accent]`), drawn by the kit rather than by a list of colours kept here.
///
/// A radio group: one stop for the Tab key, the arrow keys step round it and choose as they go, and the chosen dot
/// is ticked as well as ringed, so it is never colour alone that says which is picked.
///
/// What differs from the web original: the left and right arrows follow the text direction.
class AccentSwatch extends StatefulWidget {
  const AccentSwatch({super.key, required this.accent, required this.onAccent});

  final String accent;
  final ValueChanged<String> onAccent;

  @override
  State<AccentSwatch> createState() => _AccentSwatchState();
}

class _AccentSwatchState extends State<AccentSwatch> {
  late final List<FocusNode> _nodes = [
    for (final one in accents) FocusNode(debugLabel: 'accent $one', onKeyEvent: (node, event) => _onKey(event)),
  ];

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AccentSwatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// `tabIndex={one === accent ? 0 : -1}`
  void _sync() {
    for (var i = 0; i < accents.length; i++) {
      _nodes[i].skipTraversal = accents[i] != widget.accent;
    }
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final int step;
    if (key == LogicalKeyboardKey.arrowDown || key == (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)) {
      step = 1;
    } else if (key == LogicalKeyboardKey.arrowUp || key == (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft)) {
      step = -1;
    } else {
      // Any other key is the page's.
      return KeyEventResult.ignored;
    }
    final at = accents.indexOf(widget.accent);
    final next = (at + step + accents.length) % accents.length;
    widget.onAccent(accents[next]);
    _nodes[next].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.lenOf('2rem');
    final paper = t.color('app-paper');
    final ease = t.curve('glacier-ease-out');
    final duration = t.reducedMotion ? Duration.zero : const Duration(milliseconds: 160);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.radioGroup,
      label: 'Accent',
      // A group of radios that are buttons on the page: a swipe across it is still Settings' swipe.
      child: SettingsNoSwipe(
        swipes: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(4)),
          // One row, however narrow the sheet: the dots share what room there is rather than wrapping.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < accents.length; i++)
                Builder(builder: (context) {
                  final one = accents[i];
                  final chosen = one == widget.accent;
                  // Ink: the page's own, which is what choosing it does. Any other is its ramp's solid step.
                  final ramp = one == 'ink' ? null : t.child(attrs: {'accent': one});
                  final fill = ramp == null ? t.color('app-ink') : ramp.color('glacier-accent-9');
                  final ink = ramp == null ? paper : ramp.color('glacier-accent-contrast');
                  return Semantics(
                    container: true,
                    inMutuallyExclusiveGroup: true,
                    checked: chosen,
                    label: accentWords[one],
                    child: GlacierPressable(
                      onPressed: () => widget.onAccent(one),
                      focusNode: _nodes[i],
                      excludeSemantics: true,
                      builder: (context, state) => GlacierFocusRing(
                        visible: state.focused,
                        offset: 3,
                        child: AnimatedScale(
                          // Chosen: a ring of the page around it, then the dot's own colour again.
                          scale: chosen && !t.reducedMotion ? 1.06 : 1,
                          duration: duration,
                          curve: ease,
                          child: AnimatedContainer(
                            key: ValueKey('accent-dot-$one'),
                            duration: duration,
                            curve: ease,
                            width: side,
                            height: side,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: fill,
                              boxShadow: [
                                BoxShadow(color: chosen ? fill : fill.withValues(alpha: 0), spreadRadius: chosen ? 4 : 0),
                                BoxShadow(color: chosen ? paper : paper.withValues(alpha: 0), spreadRadius: chosen ? 2 : 0),
                              ],
                            ),
                            child: chosen ? SettingsIcon(SettingsGlyph.check, size: 14, color: ink) : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
