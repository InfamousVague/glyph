/// A ticket says so where it is listed (docs/DESIGN.md §157): its key and its status, small and quiet, the status in
/// its category's colour. The web's `src/app/notes/TicketMark.tsx`.
///
/// The mark itself was ported with the home page, beside the page that draws it: [TicketMark] in
/// lib/home/marks.dart, which the All notes cards draw through lib/home/note_card.dart. This file hands it on under
/// the web's own place, `notes/`, so nothing that lists a ticket has to know where it lives.
///
/// And the status as a button, where its list can change it (a notebook's index; docs/DESIGN.md §169):
/// [TicketStatusButton], with `TicketMark.module.css`'s `.statusButton` and `.statusWords`, drawn with the editor's
/// [StatusIcon] and [statusLook] (lib/editor/fields/). It only says it was pressed; the sheet of the workflow
/// (lib/editor/fields/field_picker.dart `FieldPicker`) is opened by whoever lists the ticket.
///
/// What differs:
/// - `@media (max-width: 520px)`, which leaves the pill its mark alone, is asked of the window's width where the
///   button is built ([MediaQuery]).
/// - `onPointerDown`'s `stopPropagation`, which keeps a press on the button from the row it lies on, is the
///   pressable's own here: it takes its presses whole, and what is under it is not pressed.
/// - `:hover { filter: brightness(1.12) }` is there at once, without its 120 ms; `title="Change the status"`, a
///   pointer's tooltip, is not carried, the label says as much.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/properties.dart';
import '../editor/fields/field_picker.dart';
import '../editor/fields/field_picks.dart';
import '../sheet/css.dart' show pageText;

export '../home/marks.dart' show TicketMark;

/// A ticket's status as a button, where its list can change it (`TicketStatusButton`): a pill in its category's
/// colour with its mark, as a query's cell draws it, that opens the sheet of its workflow. "Set status" on a ticket
/// that has none. Nothing for a note that is not a ticket.
///
/// [notebook] is the body of the notebook it is a page of, whose workflow its status is placed in.
class TicketStatusButton extends StatelessWidget {
  const TicketStatusButton({super.key, required this.body, this.notebook, required this.onPress});

  final String body;
  final String? notebook;
  final VoidCallback onPress;

  /// Whether a button is drawn for [body] at all.
  static bool has(String body) => isTicket(body);

  /// `filter: brightness(1.12)`: each colour's parts 1.12 times as bright.
  static const ColorFilter _brighter = ColorFilter.matrix(<double>[1.12, 0, 0, 0, 0, 0, 1.12, 0, 0, 0, 0, 0, 1.12, 0, 0, 0, 0, 0, 1, 0]);

  @override
  Widget build(BuildContext context) {
    final notebook = this.notebook;
    final workflow = notebook == null || notebook.isEmpty ? null : statusesOf(notebook);
    final ticket = ticketOf(body, workflow);
    if (ticket == null) return const SizedBox.shrink();
    final status = ticket.status;
    final look = status == null ? StatusLook.todo : statusLook(status, workflow);
    final t = context.tokens;
    // `font: inherit; font-size: var(--glacier-font-size-xs)`: every em below is of this.
    final em = t.fontSize('xs');
    // The rules in the stylesheet's order, a later one over an earlier: `[data-category='doing']`,
    // `[data-look='review']`, `[data-category='done']`, `[data-empty]`.
    final (Color ink, Color ground) = status == null
        ? (t.color('glacier-text-muted'), const Color(0x00000000))
        : ticket.category == StatusCategory.done
            ? (t.color('glacier-green-11'), t.colorOf('color-mix(in srgb, var(--glacier-green-9) 14%, transparent)'))
            : look == StatusLook.review
                ? (t.color('glacier-purple-11'), t.colorOf('color-mix(in srgb, var(--glacier-purple-9) 14%, transparent)'))
                : ticket.category == StatusCategory.doing
                    ? (t.color('glacier-blue-11'), t.colorOf('color-mix(in srgb, var(--glacier-blue-9) 14%, transparent)'))
                    : (t.color('app-ink-2'), t.colorOf('color-mix(in srgb, var(--app-ink-4) 18%, transparent)'));
    // On a phone the pill is its mark alone, in its colour: beside the three tools its words left a page's title a
    // few letters wide. The status is still said to a screen reader by the button's label.
    final narrow = MediaQuery.sizeOf(context).width <= 520;
    final radius = BorderRadius.circular(t.radius('full'));

    return GlacierPressable(
      onPressed: onPress,
      // `aria-label`
      semanticLabel: status == null ? 'Set a status' : 'Status: $status. Change it',
      builder: (context, state) {
        Widget pill = ConstrainedBox(
          // `max-inline-size: 11em; min-block-size: 1.9em`
          constraints: BoxConstraints(maxWidth: 11 * em, minHeight: 1.9 * em),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ground,
              borderRadius: radius,
              // `[data-empty] { box-shadow: inset 0 0 0 1px var(--glacier-border-subtle) }`
              border: status == null ? Border.all(color: t.color('glacier-border-subtle')) : null,
            ),
            child: Padding(
              // `padding: 0.15em 0.6em 0.15em 0.45em`, and on a phone `padding-inline: 0.45em`.
              padding: EdgeInsetsDirectional.fromSTEB(0.45 * em, 0.15 * em, (narrow ? 0.45 : 0.6) * em, 0.15 * em),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusIcon(look: look, size: em),
                  if (!narrow) ...[
                    // `gap: 0.35em`
                    SizedBox(width: 0.35 * em),
                    // `.statusWords { overflow: hidden; text-overflow: ellipsis }` on `white-space: nowrap`.
                    Flexible(child: Text(status ?? 'Status', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, em, color: ink))),
                  ],
                ],
              ),
            ),
          ),
        );
        // `.statusButton:hover { filter: brightness(1.12) }`
        if (state.hovered) pill = ColorFiltered(colorFilter: _brighter, child: pill);
        // `:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: 1px }`
        // Its words are in the label already; they are not read twice.
        return GlacierFocusRing(visible: state.focused, offset: 1, radius: t.radius('full'), child: ExcludeSemantics(child: pill));
      },
    );
  }
}
