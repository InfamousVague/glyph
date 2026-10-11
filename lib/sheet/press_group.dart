import 'package:flutter/widgets.dart';

/// The surfaces a press in any of which is a press inside all of them: a floating card, the icon that opened it, and
/// whatever the card opens over the page in its turn.
///
/// On the page a sheet opened from the sidebar's card is the card's own descendant, so the card's "was that press
/// outside me?" (`card.contains(event.target)`, notes/FloatingCard.tsx) answers no for a press in the sheet. Here a
/// sheet is drawn in the app's overlay, outside the card's box, so the card says which group it is ([PressGroup]) and
/// a surface opened under it joins the group ([PressGroup.join]) through a [TapRegion] of the same id.
class PressGroup extends InheritedWidget {
  const PressGroup({super.key, required this.id, required super.child});

  /// The [TapRegion.groupId] of the surface this stands under.
  final Object id;

  /// The group in force at [context], or null under no card.
  static Object? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PressGroup>()?.id;

  /// [child] as part of the group in force at [context]: a press in it is not a press outside the surface that
  /// opened it. Under no group, [child] alone.
  static Widget join(BuildContext context, {required Widget child}) {
    final id = of(context);
    return id == null ? child : TapRegion(groupId: id, child: child);
  }

  @override
  bool updateShouldNotify(PressGroup old) => old.id != id;
}
