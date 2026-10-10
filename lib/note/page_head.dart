import 'package:flutter/widgets.dart';

/// The room the note's page keeps at its top, under the header's glass and the AI's strip (`.page {
/// padding-block-start: calc(var(--wisp-under) + … + var(--ai-strip-room, 0px)) }`, editor/NoteScreen.module.css):
/// said to what the page holds in place of its words (a notebook's index, a journal's), so that what sticks to the
/// page's top there (a notebook read straight through, book/BookView.module.css `.readBar`) stops under the header
/// as the page's does, a scroll container's padding being where a sticky box comes to rest.
class PageHead extends InheritedWidget {
  const PageHead({super.key, required this.height, required super.child});

  final double height;

  /// The room at the top of the page this is built in; 0 where nothing says (a test of the view alone, a page with
  /// no header over it).
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PageHead>()?.height ?? 0;

  @override
  bool updateShouldNotify(PageHead oldWidget) => oldWidget.height != height;
}
