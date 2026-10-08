/// A few words shown under what was tapped, over the note: a footnote's text and the note on a mark. Ports
/// `src/app/editor/textPanel.ts`.
///
/// One at a time for each kind, closed by a tap elsewhere, a change to the note, or a scroll. The panel opens under
/// the tapped words and is held inside the editor's width.
///
/// What differs: the web appends a `<div>` to the editor's element and styles it with a base theme. Here the
/// panels a view shows are a list on the view ([textPanels]), and [EditorTextPanels], which the note screen stacks
/// over the editor, draws them, placed from `coordsAtPos` each time it builds. `textPanel(className)` on the web
/// also closed the panel when the note scrolled; the screen that owns the scroll view calls [closeTextPanel] for
/// that, the view having no scroll events of its own.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../looks/look.dart';
import 'editor_view.dart';

/// One panel: what it says, where it hangs, and which kind it is.
class TextPanel {
  const TextPanel({required this.at, required this.text, required this.className, required this.label});

  final int at;
  final String text;

  /// The kind: each keeps its own class, so closing one never closes the other.
  final String className;

  /// What a screen reader calls it.
  final String label;
}

final Expando<ValueNotifier<List<TextPanel>>> _panels = Expando<ValueNotifier<List<TextPanel>>>('textPanels');

/// The panels `view` is showing.
ValueNotifier<List<TextPanel>> textPanels(EditorView view) => _panels[view] ??= ValueNotifier<List<TextPanel>>(const <TextPanel>[]);

/// Shows `text` in a panel of class `className` under the position `at`, in place of any it already shows.
void showTextPanel(EditorView view, int at, String text, {required String className, required String label}) {
  final shown = textPanels(view);
  shown.value = <TextPanel>[...shown.value.where((panel) => panel.className != className), TextPanel(at: at, text: text, className: className, label: label)];
}

/// Takes away the panel of class `className`, if one is showing.
void closeTextPanel(EditorView view, String className) {
  final shown = textPanels(view);
  if (shown.value.any((panel) => panel.className == className)) shown.value = shown.value.where((panel) => panel.className != className).toList();
}

/// Draws a view's text panels over it. Put in a `Stack` with the editor, covering it.
class EditorTextPanels extends StatelessWidget {
  const EditorTextPanels({super.key, required this.view});

  final EditorView view;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<List<TextPanel>>(
      valueListenable: textPanels(view),
      builder: (context, panels, _) {
        if (panels.isEmpty) return const SizedBox.shrink();
        final window = MediaQuery.sizeOf(context);
        final look = view.look;
        // `font: inherit; font-size: 0.86em; line-height: 1.4`: the note's own face, a touch smaller.
        final em = (look?.env.body ?? t.len('app-body')) * 0.86;
        final face = (look?.line(LookElement(null)).base.style ?? t.textAt(em)).copyWith(fontSize: em, height: 1.4, leadingDistribution: TextLeadingDistribution.even);
        // `max-inline-size: min(20rem, 76vw)`
        final rem = t.lenOf('20rem'), most = rem < window.width * 0.76 ? rem : window.width * 0.76;
        return Stack(
          children: <Widget>[
            for (final panel in panels)
              if (view.coordsAtPos(panel.at) case final coords?)
                Positioned.fill(
                  child: CustomSingleChildLayout(
                    delegate: _Under(coords, context),
                    child: Semantics(
                      label: panel.label,
                      container: true,
                      // padding: 0.5em 0.7em; border-radius: var(--glacier-radius-lg); background: var(--app-paper-2);
                      // border: 1px solid var(--app-rule); box-shadow: 0 6px 20px rgb(0 0 0 / 0.18)
                      child: Container(
                        constraints: BoxConstraints(maxWidth: most),
                        padding: EdgeInsets.symmetric(vertical: 0.5 * em, horizontal: 0.7 * em),
                        decoration: BoxDecoration(
                          color: t.color('app-paper-2'),
                          border: Border.all(color: t.color('app-rule')),
                          borderRadius: BorderRadius.circular(t.radius('lg')),
                          boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x2E000000), offset: Offset(0, 6), blurRadius: 20)],
                        ),
                        child: Text(panel.text, style: face, textScaler: TextScaler.noScaling),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// `top: coords.bottom - box.top + 6`, `left: max(8, min(coords.left - box.left, box.width - width - 8))`.
class _Under extends SingleChildLayoutDelegate {
  _Under(this.coords, this.context);

  /// Where the tapped words are, on the screen.
  final Rect coords;
  final BuildContext context;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(maxWidth: constraints.maxWidth - 16 < 0 ? 0 : constraints.maxWidth - 16);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.attached ? box.localToGlobal(Offset.zero) : Offset.zero;
    final left = coords.left - origin.dx, most = size.width - childSize.width - 8;
    return Offset(left < most ? (left < 8 ? 8 : left) : (most < 8 ? 8 : most), coords.bottom - origin.dy + 6);
  }

  @override
  bool shouldRelayout(_Under oldDelegate) => oldDelegate.coords != coords;
}
