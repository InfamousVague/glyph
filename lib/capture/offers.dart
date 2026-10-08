/// "Shall I?": what a command read at Done will do, before it does anything. A port of
/// `src/app/capture/offers.ts`.
///
/// The reader at Done (final_instruction.dart) carries out two commands, and each asks first: words for a note by
/// name, and a new list by name. A plan becomes an offer here - the note it names and the lines as they would land,
/// or the list and its items - which is what the confirm card draws and what the take carries out on a tap.
///
/// Pure, so every plan's offer is a test.
///
/// What differs: the shapes. `Offer` is a sealed class ([OfferPlace], [OfferNew]), generic in any note (see
/// take_types.dart). A place offer's `placement` is the plan's `Placement` alone, where the web hands over the whole
/// plan because a plan has a placement's fields; and `into` is list_append.dart's `PlacedInto`. [placingOf] is new:
/// the `Placement` a command read, as the `Placing` that `placeWords` (list_append.dart) takes, which on the web is
/// the same object under two type names.
library;

import 'command.dart' show FinalPlan, Placement, PlanCreateList, PlanPlace;
import 'list_append.dart' show PlacedInto, Placing, PlacingHow, placeWords;
import 'take_types.dart' show TakeCandidate;

bool _sameList<T>(List<T>? a, List<T>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A command understood and waiting for a tap: what it will do, shown on the card (`Offer`).
sealed class Offer<N extends Object> {
  const Offer();

  /// The web's `kind`: `place` or `new`.
  String get kind;

  String get title;
}

/// Words for a note: the note, and the lines as they would land.
final class OfferPlace<N extends Object> extends Offer<N> {
  const OfferPlace({required this.note, required this.title, required this.text, required this.placement, required this.added, required this.into});

  final N note;
  @override
  final String title;
  final String text;
  final Placement placement;
  final List<String> added;
  final PlacedInto into;

  @override
  String get kind => 'place';

  @override
  bool operator ==(Object other) =>
      other is OfferPlace &&
      other.note == note &&
      other.title == title &&
      other.text == text &&
      other.placement == placement &&
      _sameList(other.added, added) &&
      other.into == into;

  @override
  int get hashCode => Object.hash(kind, note, title, text, placement, Object.hashAll(added), into);

  @override
  String toString() => '{kind: place, note: $note, title: $title, text: $text, placement: $placement, added: $added, into: ${into.name}}';
}

/// A new list by name, with the items said for it.
final class OfferNew<N extends Object> extends Offer<N> {
  const OfferNew({required this.title, this.lines});

  @override
  final String title;
  final List<String>? lines;

  @override
  String get kind => 'new';

  @override
  bool operator ==(Object other) => other is OfferNew && other.title == title && _sameList(other.lines, lines);

  @override
  int get hashCode => Object.hash(kind, title, lines == null ? null : Object.hashAll(lines!));

  @override
  String toString() => '{kind: new, title: $title${lines == null ? '' : ', lines: $lines'}}';
}

/// A command's placement as `placeWords` (list_append.dart) takes it.
Placing placingOf(Placement placement) => Placing(
  how: PlacingHow.values.byName(placement.how.name),
  task: placement.task,
  many: placement.many,
  near: placement.near,
  items: placement.items,
);

/// The offer [plan] makes, or null when there is nothing to offer: words that would add nothing to the note they
/// name.
Offer<N>? offerFor<N extends Object>(FinalPlan<TakeCandidate<N>> plan) {
  switch (plan) {
    case PlanCreateList(:final title, :final items):
      return OfferNew<N>(title: title, lines: items != null && items.isNotEmpty ? items : null);
    case PlanPlace():
      final note = plan.note.note;
      final preview = placeWords(plan.note.noteBody ?? '', plan.text, placingOf(plan.placement));
      if (preview.added.isEmpty) return null;
      return OfferPlace<N>(note: note, title: plan.note.title, text: plan.text, placement: plan.placement, added: preview.added, into: preview.into);
  }
}
