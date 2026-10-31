/// The label picker (Matt, 2026-10-31: "A label picker with type-to-create"): the labels the library already uses,
/// the chosen ones ticked, a field that finds one or makes a new one as it is typed, and a page of colours where the
/// ticket's notebook can keep one (`label-colours:`, lib/tickets/labels.dart). Opened from a ticket's panel, the
/// triage list's L, and the bulk bar's Labels.
///
/// For many tickets at once a label some of them have is shown as some ([LabelPicker.some]); a press gives it to all
/// of them, a second takes it off all.
///
/// The ticket picker is here too ([TicketPickSheet]): Triage's D, a ticket found by its key or title.
library;

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

import '../../book/tickets.dart' show TicketChoice;
import '../../editor/fields/field_picker.dart' show StatusIcon;
import '../../editor/fields/field_picks.dart' show statusLook;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../labels.dart';
import 'label_chips.dart';

class LabelPicker extends StatefulWidget {
  const LabelPicker({
    super.key,
    required this.chosen,
    required this.known,
    required this.onToggle,
    required this.onClose,
    this.some = const [],
    this.colours = const {},
    this.onColour,
    this.record = '',
  });

  /// The labels every ticket picked for has.
  final List<String> chosen;

  /// The labels some of them have, and some not: many tickets at once.
  final List<String> some;

  /// Every label the library uses, the most used first (labels.dart `labelsIn`).
  final List<String> known;

  /// A label pressed: [on] to give it, false to take it off.
  final void Function(String label, bool on) onToggle;
  final VoidCallback onClose;

  /// The notebook's colours, by label.
  final Map<String, String> colours;

  /// A label's colour kept in the notebook, or taken off for null; absent where there is no notebook to keep it in,
  /// and the page of colours is not offered.
  final void Function(String label, String? hue)? onColour;

  /// The ticket it is for, said under the title: "WAIT-4 · Spam sign-ups", "3 tickets".
  final String record;

  @override
  State<LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<LabelPicker> {
  String _typed = '';
  late List<String> _chosen = [...widget.chosen];
  late List<String> _some = [...widget.some];
  late Map<String, String> _colours = {...widget.colours};

  /// The label whose colour is being picked; null for the list.
  String? _colouring;
  bool _colourPage = false;

  bool _has(List<String> list, String label) => list.any((each) => sameLabel(each, label));

  void _toggle(String label) {
    final on = !_has(_chosen, label);
    setState(() {
      _chosen = on ? [..._chosen, label] : [for (final each in _chosen) if (!sameLabel(each, label)) each];
      _some = [for (final each in _some) if (!sameLabel(each, label)) each];
    });
    widget.onToggle(label, on);
  }

  void _make() {
    final label = cleanLabel(_typed);
    if (label.isEmpty) return;
    setState(() => _typed = '');
    if (!_has(_chosen, label)) _toggle(label);
  }

  @override
  Widget build(BuildContext context) {
    final onColour = widget.onColour;
    final colouring = _colouring;
    if (colouring != null && onColour != null) {
      final now = _colours[labelKey(colouring)];
      return Sheet(
        label: 'Colour of $colouring',
        onBack: () => setState(() => _colouring = null),
        onClose: widget.onClose,
        children: [
          SheetTitle.text(colouring),
          const SheetNote('Kept in the notebook, so the label wears it on every ticket there.'),
          SheetGroup(
            children: [
              for (final hue in labelHues)
                SheetRow(
                  key: ValueKey('label-hue:$hue'),
                  icon: LabelDot(hue: hue, size: 14),
                  label: '${hue[0].toUpperCase()}${hue.substring(1)}',
                  chosen: now == hue,
                  onPress: () {
                    setState(() {
                      _colours = {..._colours, labelKey(colouring): hue};
                      _colouring = null;
                    });
                    onColour(colouring, hue);
                  },
                ),
              SheetRow(
                key: const ValueKey('label-hue:default'),
                icon: LabelDot(hue: labelHue(colouring), size: 14),
                label: 'Its own',
                hint: 'The colour it wears where the notebook says none.',
                chosen: now == null,
                onPress: () {
                  setState(() {
                    _colours = {..._colours}..remove(labelKey(colouring));
                    _colouring = null;
                  });
                  onColour(colouring, null);
                },
              ),
            ],
          ),
        ],
      );
    }

    final needle = labelKey(_typed);
    final everyone = <String>[..._chosen, for (final each in _some) if (!_has(_chosen, each)) each, for (final each in widget.known) if (!_has(_chosen, each) && !_has(_some, each)) each];
    final shown = [for (final label in everyone) if (needle.isEmpty || labelKey(label).contains(needle)) label];
    final fresh = cleanLabel(_typed);
    final makes = fresh.isNotEmpty && !everyone.any((each) => sameLabel(each, fresh));

    if (_colourPage && onColour != null) {
      return Sheet(
        label: 'Label colours',
        onBack: () => setState(() => _colourPage = false),
        onClose: widget.onClose,
        children: [
          const SheetTitle(child: Text('Label colours')),
          SheetGroup(
            children: [
              for (final label in everyone.take(40))
                SheetRow(
                  key: ValueKey('label-colour:$label'),
                  icon: LabelDot(hue: labelHue(label, _colours), size: 14),
                  label: label,
                  hint: _colours.containsKey(labelKey(label)) ? null : 'Its own colour',
                  onPress: () => setState(() => _colouring = label),
                ),
            ],
          ),
        ],
      );
    }

    return Sheet(
      label: 'Labels',
      onClose: widget.onClose,
      children: [
        const SheetTitle(child: Text('Labels')),
        if (widget.record.isNotEmpty) SheetNote(widget.record),
        SheetField(
          label: 'Find or make a label',
          value: _typed,
          placeholder: 'bug, ui, waitlist…',
          autoFocus: true,
          autoCorrect: false,
          enterKeyHint: TextInputAction.done,
          onChange: (text) => setState(() => _typed = text),
          onSubmitted: (_) {
            if (makes) {
              _make();
            } else if (shown.isNotEmpty) {
              _toggle(shown.first);
              setState(() => _typed = '');
            }
          },
        ),
        SheetGroup(
          children: [
            if (makes) SheetRow(key: const ValueKey('label-make'), icon: LabelDot(hue: labelHue(fresh, _colours)), label: 'Make “$fresh”', onPress: _make),
            if (shown.isEmpty && !makes) const SheetRow(label: 'No labels yet. Type one to make it.'),
            for (final label in shown.take(40))
              SheetRow(
                key: ValueKey('label:$label'),
                icon: LabelDot(hue: labelHue(label, _colours)),
                label: label,
                hint: _has(_some, label) ? 'On some of them' : null,
                chosen: _has(_chosen, label),
                onPress: () => _toggle(label),
              ),
          ],
        ),
        if (onColour != null && everyone.isNotEmpty)
          SheetGroup(children: [SheetRow(key: const ValueKey('label-colours'), label: 'Colours…', hint: 'Give a label its colour in this notebook.', onPress: () => setState(() => _colourPage = true))]),
      ],
    );
  }
}

/// A ticket found by its key or its title, for Triage's D: what this one is a duplicate of.
class TicketPickSheet extends StatefulWidget {
  const TicketPickSheet({super.key, required this.title, required this.choices, required this.onPick, required this.onClose, this.note, this.workflow});

  final String title;
  final String? note;
  final List<TicketChoice> choices;
  final ValueChanged<TicketChoice> onPick;
  final VoidCallback onClose;
  final List<String>? workflow;

  @override
  State<TicketPickSheet> createState() => _TicketPickSheetState();
}

class _TicketPickSheetState extends State<TicketPickSheet> {
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final needle = _typed.trim().toLowerCase();
    final choices = [
      for (final choice in widget.choices)
        if (needle.isEmpty || '${choice.key ?? ''} ${choice.title}'.toLowerCase().contains(needle)) choice,
    ];
    void pick(TicketChoice choice) {
      final onPick = widget.onPick;
      widget.onClose();
      onPick(choice);
    }

    return Sheet(
      label: widget.title,
      onClose: widget.onClose,
      children: [
        SheetTitle.text(widget.title),
        if (widget.note != null) SheetNote(widget.note!),
        SheetField(
          label: 'Find a ticket',
          value: _typed,
          placeholder: 'Its key or its title',
          autoFocus: true,
          autoCorrect: false,
          onChange: (text) => setState(() => _typed = text),
          onSubmitted: (_) {
            if (choices.isNotEmpty) pick(choices.first);
          },
        ),
        SheetGroup(
          children: [
            if (choices.isEmpty) SheetRow(label: needle.isNotEmpty ? 'No ticket by that key or title.' : 'No other tickets yet.'),
            for (final choice in choices.take(40))
              SheetRow(
                key: ValueKey('pick-ticket:${choice.key ?? choice.title}'),
                icon: StatusIcon(look: statusLook(choice.status ?? '', widget.workflow)),
                label: choice.key != null ? '${choice.key}  ${choice.title}' : choice.title,
                hint: choice.status,
                onPress: () => pick(choice),
              ),
          ],
        ),
      ],
    );
  }
}
