/// A card's own menu: what it offers, and the kit's menu hung from its **more** button over the page. Ports
/// `src/app/editor/boards/cardMenu.ts` and `boards/CardMenu.tsx`.
///
/// It opens from a button rather than a press and hold, because a press and hold is already how a card is picked up
/// to drag. It is the kit's menu (Matt: "Allow the header to be overlapped by the popup menus use the glacierUI
/// context menus"), drawn over the page, whole, over the header where it must be.
///
/// One is open at a time, and a second press on the same button closes it. It closes on a row, on a press anywhere
/// else and on the back gesture (shell/pop_menu.dart), and on any change to the note or a redraw that takes its
/// button away: its rows are the card as it was when it opened.
///
/// What a plugin offers a card is given the item's line and its words (Matt: "Add context menu to board items for
/// moving lanes and adding to notion etc."). The line comes first and the words second on purpose: a card names an
/// exact line, and two items that read the same way are told apart by nothing else. `suggest` is the per-line offer
/// the note already shows quietly under a line; `action` is the one a swipe on a list item runs, by text, and is
/// only reached for when there is no offer for that line. Neither goes near a plugin: both are the registry's.
///
/// What differs:
/// - The page kept one open menu for the whole module, mounted in a React root of its own at the body. Here the
///   board's own widget holds its open menu ([OpenCardMenu]) and builds [CardMenu] while it is open; "only ever
///   one" across boards is kept by a notifier on the view ([openCardMenuOf]) every board listens to.
/// - The kit's module was loaded on the first press, for jsdom's sake; there is nothing to defer here.
/// - The focus going back to the more button on Escape is the page's keyboard focus; nothing on a board takes the
///   keyboard's focus here, so there is none to give back.
/// - A row runs a microtask after the menu closes, as on the page, so Go to the line takes the note's focus after
///   the menu has let go of its own.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/boards.dart';
import '../../shell/pop_menu.dart';
import '../editor.dart';
import 'icons.dart';
import 'navigate.dart';

/// What this editor's plugins offer a card (`CardActions`).
class CardActions {
  const CardActions({required this.suggest, required this.action});

  final List<({int line, String label, Future<void> Function() run})> Function(String body) suggest;
  final ({String label, Future<void> Function(String text) run})? Function() action;
}

/// What this editor's plugins offer a card, or nothing where the note is not one a plugin acts on (`cardActions`).
final Facet<CardActions, CardActions?> cardActions = Facet.define<CardActions, CardActions?>(combine: (values) => values.isEmpty ? null : values.first);

/// What the menu's rows do to the card: the board's own edits (card_edits.dart), bound to this card (`CardMoves`).
class CardMoves {
  const CardMoves({required this.columns, required this.land, required this.tick, required this.takeOff});

  /// The board's lanes, in its own order.
  final List<BoardColumn> columns;

  /// Into lane `column`, at its foot.
  final void Function(int column) land;
  final VoidCallback tick;
  final VoidCallback takeOff;
}

/// A row of a card's menu: what it says, the board's icon beside it, and what it does to the card (`CardRow`).
class CardRow {
  const CardRow({required this.label, required this.icon, required this.run});

  final String label;
  final String icon;
  final VoidCallback run;
}

/// What a card's menu offers (`cardRows`): each other lane to move to, the item's tick, the line in the note,
/// whatever a plugin offers this item (its own line's offer first, then the one a swipe would run), and the card
/// off the board. Nothing that cannot be done is offered, so a card whose item is gone offers only to take itself
/// off. The rows are the card as it is when the menu opens.
List<CardRow> cardRows(EditorViewLike view, Card card, CardMoves does) {
  final rows = <CardRow>[];
  final item = card.item;
  // Every other lane, in the board's own order.
  for (final (index, column) in does.columns.indexed) {
    if (index == card.column) continue;
    rows.add(CardRow(label: 'Move to ${column.name}', icon: index < card.column ? 'left' : 'right', run: () => does.land(index)));
  }
  if (item != null && item.done != null) {
    rows.add(CardRow(label: item.done! ? 'Untick' : 'Tick', icon: 'check', run: does.tick));
  }
  if (item != null) {
    rows.add(CardRow(label: 'Go to the line', icon: 'words', run: () => goToLine(view, item.line)));
    final offer = _pluginOffer(view, item);
    if (offer != null) rows.add(CardRow(label: offer.label, icon: 'link', run: () => unawaited(offer.run())));
  }
  rows.add(CardRow(label: 'Take off the board', icon: 'off', run: does.takeOff));
  return rows;
}

/// What a plugin offers this item: its own line's offer, else the one a swipe on the line would run. Null for none.
({String label, Future<void> Function() run})? _pluginOffer(EditorViewLike view, Item item) {
  final actions = view.state.facet(cardActions);
  if (actions == null) return null;
  // The line first: a card names an exact line, and two items that read the same way are told apart by nothing else.
  for (final offer in actions.suggest(view.state.doc.toString())) {
    if (offer.line == item.line) return (label: offer.label, run: offer.run);
  }
  final action = actions.action();
  if (action == null) return null;
  return (label: action.label, run: () => action.run(itemWords(view.state.doc.line(item.line).text) ?? item.text));
}

/// A card's menu that is open: whose it is, the button it hangs from, and its rows.
class OpenCardMenu {
  OpenCardMenu({required this.card, required this.more, required this.rows});

  /// The card's anchor.
  final String card;

  /// The card's more button on the page.
  final GlobalKey more;
  final List<CardRow> rows;
}

final Expando<ValueNotifier<OpenCardMenu?>> _open = Expando<ValueNotifier<OpenCardMenu?>>('cardMenu');

/// The card menu `view` has open, or null: one for the whole editor, whichever board's card it is.
ValueNotifier<OpenCardMenu?> openCardMenuOf(EditorViewLike view) => _open[view] ??= ValueNotifier<OpenCardMenu?>(null);

/// Opens `card`'s menu from its more button, in place of any other; a second press on the same button closes it
/// (`openCardMenu`).
void openCardMenu(EditorViewLike view, Card card, GlobalKey more, CardMoves does) {
  final open = openCardMenuOf(view);
  final again = identical(open.value?.more, more);
  open.value = null;
  if (again) return;
  open.value = OpenCardMenu(card: card.id, more: more, rows: cardRows(view, card, does));
}

/// Closes the card menu `view` has open; safe whether or not one is (`closeCardMenu`).
void closeCardMenu(EditorViewLike view) => openCardMenuOf(view).value = null;

/// Whether `view` has a card's menu open (`cardMenuIn`).
bool cardMenuIn(EditorViewLike view) => openCardMenuOf(view).value != null;

/// A card's menu goes with the note it describes (boards.ts `cardMenuGoes`): its rows are the card as it was when
/// it opened, so any change to the note closes it, and so does the view going.
final Extension cardMenuGoes = ViewPlugin.define<_CardMenuGoes>((view) => _CardMenuGoes(view));

class _CardMenuGoes extends PluginValue {
  _CardMenuGoes(this.view);

  final EditorViewLike view;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged && cardMenuIn(view)) closeCardMenu(view);
  }

  @override
  void destroy() => closeCardMenu(view);
}

/// A board card's menu as the kit draws it (`CardMenu`): hung from the card's more button, under it and by its end,
/// turned above where there is no room below.
class CardMenu extends StatelessWidget {
  const CardMenu({super.key, required this.open, required this.onDismiss, this.coarse});

  final OpenCardMenu open;
  final VoidCallback onDismiss;
  final bool? coarse;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final coarse = this.coarse ?? coarsePointer;
    final size = PopMenu.styleOf(t, PopReach.either, coarse: coarse).item?.iconSize ?? 16;
    return PopMenu(
      anchor: GlacierAnchor.key(open.more),
      placement: Placement.bottomEnd,
      reach: PopReach.either,
      ariaLabel: 'Card',
      coarse: this.coarse,
      onDismiss: onDismiss,
      children: <Widget>[
        for (final (index, row) in open.rows.indexed)
          GlacierMenuItem(
            key: ValueKey<String>('$index:${row.label}'),
            icon: Builder(builder: (context) => BoardIcon(row.icon, size: size, color: IconTheme.of(context).color ?? t.color('glacier-text'))),
            // Closed first, then done, as the lane's menu was: Go to the line must take the focus into the note
            // after the menu has let go, not before.
            onSelect: () => scheduleMicrotask(row.run),
            child: Text(row.label),
          ),
      ],
    );
  }
}
