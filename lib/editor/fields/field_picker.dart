/// A field picked in a sheet: what a tap on a status, a priority, a person or a day in a query, a board or a
/// notebook's index opens (docs/DESIGN.md §169). A port of `src/app/editor/FieldPicker.tsx` and the marks of
/// `FieldPicker.module.css`. Matt: "make parts of query boards and stuff intractable, I'd like to be able to click
/// things like done labels in order to change the status … use modals with iconography and color".
///
/// Every choice wears its mark in its colour, the same marks the cells draw: a status its category's (a dashed ring
/// for a backlog, a ring not started, a dot under way, an eye in review, a tick done, in the faint ink, blue, purple
/// and green), a priority Jira's chevrons, a person their initial in a round, a day the sun, the sunrise or the
/// calendar. The one it has is lit with the sheet's tick. A choice writes and closes; the writing is the caller's
/// (`onPick`, a value or null to take it off), so the same sheet serves a record in this note and one in another.
///
/// The sheet is lib/sheet/sheet.dart and its rows lib/sheet/kit.dart: build a [FieldPicker] while it is open and
/// stop building it in `onClose`, as every sheet of the app is opened and closed.
///
/// What differs:
/// - **Pick a date.** The page opens its own date input (`editor/fieldMenu.ts` `pickDay`) in the middle of the
///   window. The port's `pickDay` (lib/editor/items/field_menu.dart) asks an editor's `dayPicker` facet, and a query
///   or an index has no editor to ask: the calendar is handed in as [FieldPicker.dayPicker], the same [DayPicker]
///   the facet holds, and is opened in the middle of the window with the day the field has. Without one the row is
///   left out, as the band leaves it out where the facet is empty.
/// - A mark's `1em` is the size of the icon theme it is drawn in (a sheet row's slot sets 18, which is the page's
///   `.icon { font-size: 18px }`), else the text's; [StatusIcon.size] and [Avatar.em] say another.
/// - A mark's `data-status`, `data-priority` and `data-hue`, which the page's tests read, are the widget's own
///   fields here ([StatusIcon.look], [Avatar.hue]) and the colour its icon is drawn in.
/// - The name's field: `autoComplete="off"` has no like here and is left to the keyboard; Enter on a name is the
///   field's `onSubmitted`, where the page caught the key.
/// - An avatar's initial is the name's first letter whole, where the page took its first UTF-16 unit.
library;

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/days.dart' show isIsoDay;
import '../../core/task_fields.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../items/field_chips.dart' show dayLabel, priorityIcon;
import '../items/field_menu.dart' show DayPicker, dayChoices;
import 'field_picks.dart';

// ---- the marks ----------------------------------------------------------------------------------------------------

/// `1em` where a mark is drawn: the size an icon theme set round it gives its icons, else the text's.
double _em(BuildContext context) => context.dependOnInheritedWidgetOfExactType<IconTheme>()?.data.size ?? DefaultTextStyle.of(context).style.fontSize ?? 14;

const Map<StatusLook, LucideIcon> _statusIcon = <StatusLook, LucideIcon>{
  StatusLook.backlog: Lucide.circleDashed,
  StatusLook.todo: Lucide.circle,
  StatusLook.doing: Lucide.circleDot,
  StatusLook.review: Lucide.eye,
  StatusLook.done: Lucide.circleCheck,
};

/// A status's mark in its colour, for a sheet's row, a cell or an index ([look] from [statusLook]).
class StatusIcon extends StatelessWidget {
  const StatusIcon({super.key, required this.look, this.size});

  final StatusLook look;

  /// Its width and height; the page's `1em` where none is given.
  final double? size;

  /// The kit's icon a look is drawn with.
  static LucideIcon iconOf(StatusLook look) => _statusIcon[look]!;

  /// `.mark[data-status]`: the faint ink not started, blue under way, purple in review, green done.
  static Color colorOf(Tokens t, StatusLook look) => switch (look) {
        StatusLook.backlog || StatusLook.todo => t.color('app-ink-3'),
        StatusLook.doing => t.color('glacier-blue-11'),
        StatusLook.review => t.color('glacier-purple-11'),
        StatusLook.done => t.color('glacier-green-11'),
      };

  @override
  Widget build(BuildContext context) => AppIcon(iconOf(look), size: size ?? _em(context), strokeWidth: 2.4, color: colorOf(context.tokens, look));
}

/// A priority's chevrons in its chip's colour (`.mark[data-priority]`).
class _PriorityIcon extends StatelessWidget {
  const _PriorityIcon(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = switch (name) {
      'highest' || 'high' => t.color('glacier-red-11'),
      'medium' => t.color('glacier-amber-11'),
      'low' => t.color('glacier-blue-11'),
      _ => t.color('app-ink-3'),
    };
    return AppIcon(priorityIcon[name]!, size: _em(context), strokeWidth: 2.6, color: color);
  }
}

/// A person's initial in a round, coloured by their name, so one person wears one colour wherever they are listed.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.em});

  final String name;

  /// The size of the text it stands in, which its own is 0.85 of; the page's `1em` where none is given.
  final double? em;

  /// The hue it wears ([hueOf]): `data-hue`.
  String get hue => hueOf(name);

  /// What is written in it: the name's first letter in capitals, at signs aside, or a question mark for no name.
  String get initial {
    final said = name.replaceFirst(RegExp('^@+'), '');
    return said.isEmpty ? '?' : String.fromCharCode(said.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `font-size: 0.85em; inline-size: 1.35em; block-size: 1.35em` (of its own size).
    final size = 0.85 * (em ?? _em(context));
    final ink = t.color('glacier-$hue-11');
    // `font-weight: 650; line-height: 1`: between the kit's semibold and its bold, on the face's weight axis.
    final face = t.textAt(size, weight: 'semibold', color: ink, height: 1);
    final style = face.copyWith(fontVariations: [for (final each in face.fontVariations ?? const <FontVariation>[]) each.axis == 'wght' ? const FontVariation('wght', 650) : each]);
    return ExcludeSemantics(
      child: Container(
        width: 1.35 * size,
        height: 1.35 * size,
        alignment: Alignment.center,
        // `border-radius: 50%; background: var(--glacier-<hue>-3)`
        decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('glacier-$hue-3')),
        child: Text(initial, maxLines: 1, softWrap: false, style: style),
      ),
    );
  }
}

/// The tones of a plain icon (`.mark[data-tone]`).
enum _Tone { quiet, day, danger }

/// A plain icon in a tone, for the rows that are not a value: None, No one, Remove, and the days (`toned`).
class _Toned extends StatelessWidget {
  const _Toned(this.icon, this.tone);
  final LucideIcon icon;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = switch (tone) {
      _Tone.quiet => t.color('app-ink-3'),
      _Tone.day => t.color('glacier-accent-11'),
      _Tone.danger => t.color('glacier-red-11'),
    };
    return AppIcon(icon, size: _em(context), strokeWidth: 2.2, color: color);
  }
}

const Map<String, Widget> _dayIcon = <String, Widget>{'today': _Toned(Lucide.sun, _Tone.day), 'tomorrow': _Toned(Lucide.sunrise, _Tone.day), 'next-week': _Toned(Lucide.calendarDays, _Tone.day)};
const Widget _pickIcon = _Toned(Lucide.calendarSearch, _Tone.day);
const Widget _removeDay = _Toned(Lucide.calendarX, _Tone.danger);
const Widget _noPriority = _Toned(Lucide.ban, _Tone.quiet);
const Widget _noOne = _Toned(Lucide.userMinus, _Tone.quiet);

// ---- the sheet ----------------------------------------------------------------------------------------------------

/// The sheet of one field's choices (`FieldPicker`). Built while it is open.
class FieldPicker extends StatefulWidget {
  const FieldPicker({super.key, required this.pick, required this.label, required this.record, required this.onPick, required this.onClose, this.dayPicker});

  final FieldPick pick;

  /// What the field is called, the sheet's title: "Status", "Due".
  final String label;

  /// The record it is set on, said under the title.
  final String record;

  /// A choice: the value written, or null to take the field off. A to-do's box is written as "done" or "todo".
  final void Function(String? value) onPick;
  final VoidCallback onClose;

  /// The app's calendar, for Pick a date; without one the row is left out.
  final DayPicker? dayPicker;

  @override
  State<FieldPicker> createState() => _FieldPickerState();
}

class _FieldPickerState extends State<FieldPicker> {
  String _typed = '';

  VoidCallback _choose(String? value) => () {
        // The callbacks as they are now: closing may take this sheet down before the choice is written.
        final onPick = widget.onPick;
        widget.onClose();
        onPick(value);
      };

  @override
  Widget build(BuildContext context) {
    final pick = widget.pick;
    final head = <Widget>[SheetTitle.text(widget.label), if (widget.record.isNotEmpty) SheetNote(widget.record)];
    Widget sheet(List<Widget> blocks) => Sheet(label: widget.label, onClose: widget.onClose, children: [...head, ...blocks]);

    switch (pick) {
      case StatusPick():
        final current = pick.value?.toLowerCase();
        // The workflow, and the status it has where the workflow does not name it, so the choice it has is never hidden.
        final offered = current != null && current.isNotEmpty && !pick.workflow.any((status) => status.toLowerCase() == current) ? [...pick.workflow, pick.value!] : pick.workflow;
        return sheet([
          SheetGroup(
            children: [
              for (final status in offered) SheetRow(key: ValueKey('status:$status'), icon: StatusIcon(look: statusLook(status, pick.workflow)), label: status, chosen: current == status.toLowerCase(), onPress: _choose(status)),
              SheetRow(icon: _noPriority, label: 'No status', chosen: current == null, onPress: _choose(null)),
            ],
          ),
        ]);

      case BoxPick():
        return sheet([
          SheetGroup(
            children: [
              SheetRow(icon: const StatusIcon(look: StatusLook.todo), label: 'To do', chosen: !pick.done, onPress: _choose('todo')),
              SheetRow(icon: const StatusIcon(look: StatusLook.done), label: 'Done', chosen: pick.done, onPress: _choose('done')),
            ],
          ),
        ]);

      case PriorityPick():
        return sheet([
          SheetGroup(
            children: [
              for (final priority in priorities) SheetRow(key: ValueKey('priority:${priority.name}'), icon: _PriorityIcon(priority.name), label: priority.label, chosen: pick.value == priority.name, onPress: _choose(priority.name)),
              SheetRow(icon: _noPriority, label: 'None', chosen: pick.value == null, onPress: _choose(null)),
            ],
          ),
        ]);

      case PersonPick():
        final name = _typed.trim().replaceFirst(RegExp('^@+'), '');
        final people = [for (final person in pick.people) if (name.isEmpty || person.toLowerCase().contains(name.toLowerCase())) person];
        final known = people.any((person) => samePerson(person, name));
        final value = pick.value;
        return sheet([
          // Not in a card: the page has the field straight on the sheet, over the people.
          SheetField(
            label: 'Name',
            value: _typed,
            placeholder: 'Type a name',
            enterKeyHint: TextInputAction.done,
            onChange: (text) => setState(() => _typed = text),
            onSubmitted: (_) {
              if (name.isNotEmpty) _choose(name)();
            },
          ),
          SheetGroup(
            children: [
              if (name.isNotEmpty && !known) SheetRow(key: const ValueKey('person-new'), icon: Avatar(name: name), label: 'Assign to $name', onPress: _choose(name)),
              for (final person in people.take(30)) SheetRow(key: ValueKey('person:$person'), icon: Avatar(name: person), label: person, chosen: value != null && value.isNotEmpty && samePerson(value, person), onPress: _choose(person)),
              SheetRow(icon: _noOne, label: 'No one', chosen: value == null || value.isEmpty, onPress: _choose(null)),
            ],
          ),
        ]);

      case DayPick():
        // A day: today, tomorrow and next week, the phone's own calendar, and Remove where it has one.
        final choices = dayChoices(pick.today);
        final value = pick.value;
        final has = value != null && value.isNotEmpty;
        final other = has && !choices.any((choice) => choice.day == value) ? value : null;
        final picker = widget.dayPicker;
        // The calendar in the middle of the screen where the sheet was: the phone's is a sheet of its own.
        final middle = MediaQuery.sizeOf(context).center(Offset.zero);
        Future<void> pickOther() async {
          final onPick = widget.onPick;
          widget.onClose();
          final day = await picker!(middle, has && isIsoDay(value) ? value : null);
          if (day != null && isIsoDay(day)) onPick(day);
        }
        return sheet([
          SheetGroup(
            children: [
              for (final choice in choices)
                SheetRow(
                  key: ValueKey('day:${choice.id}'),
                  icon: _dayIcon[choice.id],
                  label: choice.label,
                  hint: dayLabel(choice.day, pick.today) == choice.label ? null : dayLabel(choice.day, pick.today),
                  chosen: value == choice.day,
                  onPress: _choose(choice.day),
                ),
              if (picker != null) SheetRow(key: const ValueKey('day-pick'), icon: _pickIcon, label: 'Pick a date', hint: other == null ? null : dayLabel(other, pick.today), chosen: other != null, onPress: pickOther),
              if (has) SheetRow(key: const ValueKey('day-remove'), icon: _removeDay, label: 'Remove', danger: true, onPress: _choose(null)),
            ],
          ),
        ]);
    }
  }
}
