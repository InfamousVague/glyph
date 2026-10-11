/// The board's icons, drawn in the same strokes as the rest of the app's (lucide's paths, 24-unit box, round caps),
/// so the controls are icons rather than the characters `‹ › +` set in whatever face the phone falls back to; and
/// the picture an empty column shows, by what the column is for. Ports `src/app/editor/boards/icons.ts`.
///
/// What differs: `icon(name, size)` made an `<svg>`; [BoardIcon] is a widget that paints the same paths. The soft
/// fill every closed-silhouette icon in the app wears reaches these by name on the page (app.css
/// `svg.app-drawnIcon[data-icon='doing']`), and only the hourglass is named: so here too.
library;

import 'package:flutter/widgets.dart';

import '../../art/app_icon.dart';
import '../../core/item_syntax.dart' show isDoneName;

/// Each icon's paths; the card's menu draws its rows' icons from these too (`ICONS`).
const Map<String, List<String>> boardIcons = <String, List<String>>{
  'plus': <String>['M5 12h14', 'M12 5v14'],
  // A page with an N on it, as the Notion plugin draws its own mark (plugins/notion/marks.tsx).
  'notion': <String>['M5 4h10l4 4v12H5z', 'M9 16V9l6 7V9'],
  // Any other plugin's link: two rings of a chain.
  'link': <String>['M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71', 'M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71'],
  'left': <String>['m15 18-6-6 6-6'],
  'right': <String>['m9 18 6-6-6-6'],
  'check': <String>['M20 6 9 17l-5-5'],
  // The card's own menu: three dots (lucide ellipsis).
  'more': <String>['M5 12h.01', 'M12 12h.01', 'M19 12h.01'],
  // What the menu offers: go to the line, take the card off the board.
  'words': <String>['M4 6h16', 'M4 12h10', 'M4 18h13'],
  'off': <String>['M18 6 6 18', 'M6 6l12 12'],
  // An empty column's picture, by what the column is for (lucide list-checks, hourglass, check-check, inbox).
  'todo': <String>['M13 5h8', 'M13 12h8', 'M13 19h8', 'm3 17 2 2 4-4', 'm3 7 2 2 4-4'],
  'doing': <String>[
    'M5 22h14',
    'M5 2h14',
    'M17 22v-4.172a2 2 0 0 0-.586-1.414L12 12l-4.414 4.414A2 2 0 0 0 7 17.828V22',
    'M7 2v4.172a2 2 0 0 0 .586 1.414L12 12l4.414-4.414A2 2 0 0 0 17 6.172V2',
  ],
  'done': <String>['M18 6 7 17l-5-5', 'm22 10-7.5 7.5L13 16'],
  'inbox': <String>['M22 12h-6l-2 3h-4l-2-3H2', 'M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z'],
};

final RegExp _finished = RegExp(r'^finished|^complete');
final RegExp _doing = RegExp(r'doing|in progress|progress|working|active|started|underway');
final RegExp _todo = RegExp(r'to ?do|backlog|up next|^next|later|this week|today|planned|waiting');

/// What an empty column shows, by what its name says it is for (Matt: "add an icon when there are no items in a
/// board like no todo items or no doing tasks"). Column names are free, so this reads the common ones and gives any
/// other column the plain empty tray (`emptyLook`).
({String icon, String words}) emptyLook(String name) {
  final called = name.trim().toLowerCase();
  // The lane a ticked card goes to (core/item_syntax.dart `isDoneName`), and the other words for having finished.
  if (isDoneName(called) || _finished.hasMatch(called)) return (icon: 'done', words: 'Nothing done yet');
  if (_doing.hasMatch(called)) return (icon: 'doing', words: 'Nothing in progress');
  if (_todo.hasMatch(called)) return (icon: 'todo', words: 'Nothing to do');
  return (icon: 'inbox', words: 'No cards');
}

/// One of the board's icons, `size` across, in `color` (`icon`): stroke 2.4 on the 24 grid, round caps and joins.
class BoardIcon extends StatelessWidget {
  const BoardIcon(this.name, {super.key, required this.size, required this.color});

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final paths = boardIcons[name] ?? const <String>[];
    return CustomPaint(
      size: Size.square(size),
      // The hourglass over an empty "in progress" column was the one outline among filled icons (Matt: "even the
      // hour glass icon doesn't have fill"): its whole drawing wears the wash.
      painter: DrawnIconPainter(strokes: paths, washed: name == 'doing' ? paths : const <String>[], color: color, strokeWidth: 2.4),
    );
  }
}
