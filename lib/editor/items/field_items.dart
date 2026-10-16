/// The press-and-hold menu's pages for a to-do's fields. Ports `src/app/editor/FieldItems.tsx` and
/// `FieldItems.module.css`.
///
/// - **A day** (the due day, or a start or scheduled day tapped): Today, Tomorrow, Next week, Pick a date and
///   Remove when it has one. The day it has is lit.
/// - **Priority**: the five, the most urgent first, in the marks the chips draw, and None. The one it has is lit.
/// - **A person** tapped: Remove.
/// - **Assign**: the people the note already names, lit where they are on the line, each pressed on and off, and
///   Someone new, which writes the at sign where a person goes and leaves the caret after it for the name.
///
/// Every press writes through `lib/core/task_fields.dart` and closes the menu, but a person pressed on Assign,
/// which stays so a second can be added. The editor gets its focus back only where it had it: a chip tapped on a
/// note being read must not raise the keyboard.
///
/// What differs: on the web these are rows of the note's own press-and-hold band (`ContextMenu.tsx`,
/// `MenuBand.tsx`). [fieldItems] is the page as data - each choice's icon, word, name, whether it is lit, its
/// priority's tone and its press - for the band to draw as its rows (lib/editor/band). [FieldMenuHost] is what
/// hears a chip's tap (`useFieldTaps`): in a note it hands the tap to the band ([FieldMenuHost.onTap]), which
/// opens at the chip on that field's page, as the page's does; a view given no band draws the page in the kit's
/// menu, hung from the chip, lit said with the kit's own selected row and a priority's mark in its chip's colour.
library;

import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/task_fields.dart';
import '../../core/text.dart' show capitalise;
import '../../reminders/remind_choices.dart' show remindChoices;
import '../../reminders/reminder_settings.dart' show reminderSettings;
import '../../reminders/reminder_syntax.dart' show reminderOn;
import '../editor.dart';
import 'field_chips.dart';
import 'field_menu.dart';
import 'task_fields.dart' show fieldsToday;

const Map<String, LucideIcon> _dayIcon = <String, LucideIcon>{'today': Lucide.sun, 'tomorrow': Lucide.sunrise, 'next-week': Lucide.calendarDays};

/// Each of Remind me's times (lib/reminders/remind_choices.dart).
const Map<String, LucideIcon> _remindIcon = <String, LucideIcon>{'hour': Lucide.hourglass, 'evening': Lucide.clock, 'tomorrow': Lucide.sunrise};

/// How many of the note's people Assign offers before Someone new: a band's width on a phone, about.
const int _mostPeople = 6;

/// A field's choice: its icon over its word, lit where the line has it.
class FieldItem {
  const FieldItem({required this.icon, required this.label, this.name, this.lit, this.tone, required this.onPress, this.closes = true});

  final LucideIcon icon;
  final String label;

  /// What a screen reader hears, where it is more than the label.
  final String? name;

  /// Null for a row that is not one of a set (`menuitem`); else whether it is the one the line has
  /// (`menuitemradio`).
  final bool? lit;

  /// A priority's name, whose mark wears its chip's colour.
  final String? tone;

  /// The press, with where the row is on the screen.
  final void Function(Rect box) onPress;

  /// Whether the menu closes on the press: all but a person pressed on Assign.
  final bool closes;
}

/// The rows of `page` for line `line` (from 1) of `view`, or null where there is no such line. `onClose` closes
/// the menu, `onBack` (absent for a page a chip opened) goes back to the line's actions, `refocus` is whether the
/// editor had its focus when the menu opened, and so gets it back, and `redraw` asks for the rows again.
List<FieldItem>? fieldItems(EditorViewLike view, int line, FieldPage page, {VoidCallback? onBack, required VoidCallback onClose, bool refocus = false, VoidCallback? redraw, String? today}) {
  final fields = lineFields(view, line);
  if (fields == null) return null;
  final day = today ?? todayIs();

  // A press that writes and closes: the menu first, then the edit, then the focus where it was.
  void Function(Rect) write(void Function() run) => (_) {
    haptic(HapticKind.selection);
    onClose();
    run();
    if (refocus) view.focus();
  };

  final items = <FieldItem>[if (onBack != null) FieldItem(icon: Lucide.chevronLeft, label: 'Back', name: "Back to the note's actions", onPress: (_) => onBack(), closes: false)];

  switch (page) {
    case DatePage(:final key):
      final current = fields.date(key);
      for (final choice in dayChoices(day)) {
        items.add(
          FieldItem(icon: _dayIcon[choice.id]!, label: choice.label, name: '${capitalise(key)} ${choice.label.toLowerCase()}', lit: current == choice.day, onPress: write(() => setLineField(view, line, key, choice.day))),
        );
      }
      if (view.state.facet(dayPicker) != null) {
        items.add(
          FieldItem(
            icon: Lucide.calendarSearch,
            label: 'Pick a date',
            onPress: (box) {
              // Opened from the press itself, before the menu goes.
              pickDay(view, box.topLeft, current, (picked) {
                setLineField(view, line, key, picked);
                if (refocus) view.focus();
              });
              haptic(HapticKind.selection);
              onClose();
            },
          ),
        );
      }
      if (current != null) items.add(FieldItem(icon: Lucide.calendarX, label: 'Remove', name: 'Remove the $key date', onPress: write(() => setLineField(view, line, key, null))));
    case PriorityPage():
      for (final priority in priorities) {
        items.add(
          FieldItem(
            icon: priorityIcon[priority.name]!,
            label: priority.label,
            name: '${priority.label} priority',
            tone: priority.name,
            lit: fields.priority == priority.name,
            onPress: write(() => setLineField(view, line, 'priority', priority.name)),
          ),
        );
      }
      items.add(FieldItem(icon: Lucide.ban, label: 'None', name: 'No priority', lit: fields.priority == null, onPress: write(() => setLineField(view, line, 'priority', null))));
    case PersonPage(:final name):
      final shown = personShown(name);
      items.add(FieldItem(icon: Lucide.userMinus, label: 'Remove', name: 'Take $shown off', onPress: write(() => setLinePerson(view, line, name, false))));
    case RemindPage():
      // Remind me: the times on offer, the one the line has lit, then the phone's own calendar and clock.
      final current = reminderOn(view.state.doc.line(line).text);
      for (final choice in remindChoices(view.state.facet(fieldsNow)?.call() ?? DateTime.now(), reminderSettings.value)) {
        items.add(FieldItem(icon: _remindIcon[choice.id]!, label: choice.label, name: choice.name, lit: current == choice.at, onPress: write(() => setLineReminder(view, line, choice.at))));
      }
      final pick = view.state.facet(reminderPicker);
      if (pick != null) {
        items.add(
          FieldItem(
            icon: Lucide.calendarSearch,
            label: 'Pick a time',
            onPress: (box) {
              // Opened from the press itself, before the menu goes.
              unawaited(pick(box.topLeft, current).then((picked) {
                if (picked == null) return;
                setLineReminder(view, line, picked);
                if (refocus) view.focus();
              }));
              haptic(HapticKind.selection);
              onClose();
            },
          ),
        );
      }
      if (current != null) items.add(FieldItem(icon: Lucide.calendarX, label: 'Remove', name: 'Remove the reminder', onPress: write(() => setLineReminder(view, line, null))));
    case AssignPage():
      // Assign: who the note names, then someone new.
      for (final person in peopleIn(view.state.doc.toString()).take(_mostPeople)) {
        final on = fields.assignees.any((name) => samePerson(name, person));
        final shown = personShown(person);
        items.add(
          FieldItem(
            icon: Lucide.userRound,
            label: shown,
            name: on ? 'Take $shown off' : 'Assign $shown',
            lit: on,
            closes: false,
            onPress: (_) {
              haptic(HapticKind.selection);
              setLinePerson(view, line, person, !on);
              redraw?.call();
            },
          ),
        );
      }
      items.add(
        FieldItem(
          icon: Lucide.userPlus,
          label: 'Someone new',
          onPress: (_) {
            haptic(HapticKind.selection);
            onClose();
            startPerson(view, line);
          },
        ),
      );
  }
  return items;
}

/// A priority's mark in its chip's colour (`FieldItems.module.css`); null for the row's own ink.
Color? fieldToneColor(Tokens t, String? tone) => switch (tone) {
  'highest' || 'high' => t.color('glacier-red-11'),
  'medium' => t.color('glacier-amber-11'),
  'low' => t.color('glacier-blue-11'),
  'lowest' => t.color('app-ink-3'),
  _ => null,
};

/// Hears a chip's tap in `view` (`useFieldTaps`). With [onTap], the tap is handed over (to the note's band, which
/// opens at the chip on the field's page) and nothing is drawn here. Without, the chip's page is drawn in the
/// kit's menu, hung from the chip, over `child` (the editor); the rows are [fieldItems] either way.
class FieldMenuHost extends StatefulWidget {
  const FieldMenuHost({super.key, required this.view, required this.child, this.onTap});

  /// The editor; null while there is none yet, when [child] is drawn alone.
  final EditorViewLike? view;
  final Widget child;

  /// What takes a tapped chip in place of this host's own menu: the band.
  final void Function(EditorViewLike view, FieldTap tap)? onTap;

  @override
  State<FieldMenuHost> createState() => _FieldMenuHostState();
}

class _FieldMenuHostState extends State<FieldMenuHost> {
  bool _refocus = false;

  ValueNotifier<FieldTap?>? _tapOf(EditorViewLike? view) => view == null ? null : fieldTapOf(view);
  ValueNotifier<FieldTap?>? get _tap => _tapOf(widget.view);

  void _changed() {
    if (!mounted) return;
    final view = widget.view, tap = _tap?.value, hand = widget.onTap;
    if (hand != null) {
      // The band's: handed over, and forgotten here so the same chip tapped again is a tap again.
      if (view == null || tap == null) return;
      _tap?.value = null;
      hand(view, tap);
      return;
    }
    if (tap != null) _refocus = view?.hasFocus ?? false;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tap?.addListener(_changed);
  }

  @override
  void didUpdateWidget(FieldMenuHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view)) {
      _tapOf(oldWidget.view)?.removeListener(_changed);
      _tap?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _tap?.removeListener(_changed);
    super.dispose();
  }

  void _close() => _tap?.value = null;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final tap = _tap?.value;
    final items = tap == null || view == null ? null : fieldItems(view, tap.line, tap.page, onClose: _close, refocus: _refocus, redraw: () => setState(() {}), today: view.state.facet(fieldsToday)?.call());
    final t = context.tokens;
    // The child keeps its place in the tree whether a menu is up or not: a page that scrolls is not made to move
    // house (and take a new scroll position) by a chip's tap.
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        if (tap != null && items != null)
        GlacierMenu(
          anchor: GlacierAnchor.rect(Rect.fromLTWH(tap.x, tap.y, 0, t.len('app-body') * 1.35)),
          open: true,
          onOpenChange: (open) {
            if (!open) _close();
          },
          ariaLabel: 'Field',
          children: <Widget>[
            for (final item in items)
              Builder(
                builder: (context) => GlacierMenuItem(
                  icon: AppIcon(item.icon, size: 16, color: item.lit == true ? null : fieldToneColor(t, item.tone), wash: false),
                  ariaLabel: item.name,
                  shortcut: item.lit == true ? const AppIcon(Lucide.check, size: 14, wash: false) : null,
                  onSelect: () {
                    final box = context.findRenderObject();
                    item.onPress(box is RenderBox && box.attached ? box.localToGlobal(Offset.zero) & box.size : Rect.zero);
                  },
                  child: Text(item.label),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
