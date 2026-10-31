/// A task's panel on a Gantt chart (gantt_chart.dart): what a click on a bar opens, in a small popover over it on a
/// wide window and in a sheet from the foot on a phone ([GanttSheet]).
///
/// Its name, its days (or its day, for a milestone), its person, how far along it is and what it waits on, each
/// written as it is left or Enter is pressed in it, one change each, so each is a step of the note's undo; a
/// milestone's switch; and a sentence saying what moving it does to what waits on it, which `follow:` decides. Under
/// More, open from the start unless the app is simple (Preferences.simple): the chart's follow and working days, and
/// the bar's colour. A ticket's name is the ticket's, and Open goes to it.
///
/// Enter in the name writes it and closes the panel with the chart chosen again, so Enter there adds the next task:
/// a list of tasks is typed a name and an Enter at a time.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/days.dart' show isIsoDay;
import '../../core/gantt/gantt.dart';
import '../../sheet/kit.dart' show SheetTitle;
import '../../sheet/sheet.dart';
import 'gantt_chart.dart';

/// The words a panel says about what waits on [item], as `follow:` has it.
String followWords(GanttModel model, GanttItem item) {
  final waiting = model.waiting[item.key]?.length ?? 0;
  if (waiting == 0) return 'Nothing waits on it.';
  final them = waiting == 1 ? 'the task that waits on it' : 'the $waiting tasks that wait on it';
  return model.follow ? 'Moving it pushes $them along (follow: true).' : 'Moving it leaves $them where they are (follow: false).';
}

class GanttPanel extends StatefulWidget {
  const GanttPanel({super.key, required this.item, required this.model, required this.actions, required this.simple, required this.onClose, required this.onDone});

  final GanttItem item;
  final GanttModel model;
  final GanttActions actions;
  final bool simple;

  /// Closes the panel; [onDone] closes it with [GanttItem.key] chosen.
  final VoidCallback onClose;
  final void Function(String key) onDone;

  @override
  State<GanttPanel> createState() => GanttPanelState();
}

class GanttPanelState extends State<GanttPanel> {
  late final TextEditingController _name = TextEditingController(text: widget.item.name);
  late final TextEditingController _start = TextEditingController(text: widget.item.start);
  late final TextEditingController _end = TextEditingController(text: widget.item.end);
  late final TextEditingController _person = TextEditingController(text: widget.item.person == null ? '' : '@${widget.item.person}');
  late final TextEditingController _progress = TextEditingController(text: widget.item.progress?.toString() ?? '');
  late final TextEditingController _waits = TextEditingController(text: _waitWords());
  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  late bool _more = !widget.simple;
  String? _wrong;

  FocusNode _node(String name) => _nodes[name] ??= FocusNode(debugLabel: 'gantt $name')..addListener(() => _left(name));

  String _waitWords() => [for (final on in widget.item.after) widget.model.byKey[on]?.name ?? on].join(', ');

  bool get _fresh => widget.item.name == 'New task';

  @override
  void initState() {
    super.initState();
    // A task just added has its name chosen, to be written over.
    if (_fresh && widget.actions.rename != null) {
      _name.selection = TextSelection(baseOffset: 0, extentOffset: _name.text.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node('name').requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(GanttPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // What the chart says now, in every field not being typed in.
    void put(String name, TextEditingController controller, String value) {
      if (!(_nodes[name]?.hasFocus ?? false) && controller.text != value) controller.text = value;
    }

    final item = widget.item;
    put('name', _name, item.name);
    put('start', _start, item.start);
    put('end', _end, item.end);
    put('person', _person, item.person == null ? '' : '@${item.person}');
    put('progress', _progress, item.progress?.toString() ?? '');
    put('waits', _waits, _waitWords());
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    for (final controller in <TextEditingController>[_name, _start, _end, _person, _progress, _waits]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// A field left: what it says written, where it changed.
  void _left(String name) {
    if (!mounted || (_nodes[name]?.hasFocus ?? true)) return;
    write(name);
  }

  void _said(String? words) {
    if (mounted) setState(() => _wrong = words);
  }

  /// Writes field [name] where what it says is not what the task has.
  void write(String name) {
    final item = widget.item;
    final actions = widget.actions;
    switch (name) {
      case 'name':
        final words = _name.text.trim();
        if (words.isNotEmpty && words != item.name) _said(actions.rename?.call(item.key, words));
      case 'start' || 'end':
        final start = _start.text.trim();
        final end = item.milestone ? start : _end.text.trim();
        if (start == item.start && end == item.end) return;
        if (!isIsoDay(start) || !isIsoDay(end)) return _said('A day is written 2026-11-02.');
        _said(actions.move?.call(item.key, start, end.compareTo(start) < 0 ? start : end, name == 'end' ? GanttGrip.end : GanttGrip.move));
      case 'person':
        final people = _person.text.split(RegExp(r'[,\s]+')).where((each) => each.replaceAll('@', '').isNotEmpty).toList();
        final had = item.person == null ? <String>[] : <String>[item.person!];
        if (people.map((each) => each.replaceAll('@', '')).join(',') == had.join(',')) return;
        _said(actions.setPeople?.call(item.key, people));
      case 'progress':
        final words = _progress.text.replaceAll('%', '').trim();
        final value = words.isEmpty ? null : int.tryParse(words);
        if (words.isNotEmpty && value == null) return _said('How far along is a number, 0 to 100.');
        if (value == item.progress) return;
        _said(actions.setProgress?.call(item.key, value?.clamp(0, 100)));
      case 'waits':
        final names = _waits.text.split(',').map((each) => each.trim()).where((each) => each.isNotEmpty).toList();
        if (names.join(', ') == _waitWords()) return;
        _said(actions.setWaits?.call(item.key, names));
    }
  }

  /// Every field written, and the panel closed with the task chosen.
  void done() {
    for (final name in <String>['name', 'start', 'end', 'person', 'progress', 'waits']) {
      write(name);
    }
    if (_wrong == null) widget.onDone(widget.item.key);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final item = widget.item;
    final actions = widget.actions;
    final small = t.textAt(t.fontSize('xs'), color: t.color('app-ink-3'));
    final words = t.textAt(t.fontSize('sm'), color: t.color('app-ink'));
    final ticket = item.ticket != null || item.label != null;

    Widget label(String text) => Padding(padding: EdgeInsets.only(bottom: t.space(1)), child: Text(text, style: small));

    Widget field(String name, TextEditingController controller, {String? placeholder, bool enabled = true, TextInputType? input, bool closes = false}) => GlacierInput(
      key: ValueKey<String>('gantt-field:$name'),
      size: GlacierFieldSize.sm,
      controller: controller,
      focusNode: _node(name),
      placeholder: placeholder,
      readOnly: !enabled,
      inputMode: input,
      ariaLabel: name,
      onSubmitted: (_) {
        write(name);
        if (closes && _wrong == null) widget.onDone(item.key);
      },
      onKeyDown: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[Expanded(child: a), SizedBox(width: t.space(2)), Expanded(child: b)],
    );

    Widget block(String title, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[label(title), child]);

    Widget button(String text, VoidCallback onTap, {bool danger = false, bool strong = false, Key? key}) => GlacierPressable(
      key: key,
      onPressed: onTap,
      semanticLabel: text,
      builder: (context, _) => Container(
        padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1) + 2),
        decoration: ShapeDecoration(color: strong ? t.color('app-ink') : t.colorOf('color-mix(in srgb, var(--app-ink) 8%, transparent)'), shape: const StadiumBorder()),
        child: Text(text, style: t.textAt(t.fontSize('xs'), weight: 'semibold', color: danger ? t.color('glacier-red-11') : (strong ? t.color('app-paper') : t.color('app-ink')))),
      ),
    );

    final swatches = Wrap(
      spacing: t.space(1),
      runSpacing: t.space(1),
      children: <Widget>[
        for (final colour in <String?>[null, ...ganttColours])
          GestureDetector(
            key: ValueKey<String>('gantt-colour:${colour ?? 'none'}'),
            onTap: actions.setColour == null ? null : () => _said(actions.setColour!(item.key, colour)),
            child: Semantics(
              button: true,
              selected: item.colour == colour,
              label: colour ?? 'Its section’s',
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colour == null ? null : (colour == 'gray' ? t.color('glacier-gray-9') : t.color('glacier-$colour-9')),
                  border: Border.all(color: item.colour == colour ? t.color('app-ink') : t.color('app-rule'), width: item.colour == colour ? 2 : 1),
                ),
                child: colour == null ? Center(child: Text('–', style: small)) : null,
              ),
            ),
          ),
      ],
    );

    final more = <Widget>[
      if (actions.setFront != null) ...<Widget>[
        GlacierSwitch(
          key: const ValueKey<String>('gantt-follow'),
          checked: widget.model.follow,
          label: const Text('Push what waits on a task along'),
          onCheckedChange: (on) => _said(actions.setFront!('follow', on ? null : 'false')),
        ),
        SizedBox(height: t.space(2)),
        GlacierSwitch(
          key: const ValueKey<String>('gantt-workdays'),
          checked: widget.model.workdays,
          label: const Text('Count working days, Monday to Friday'),
          onCheckedChange: (on) => _said(actions.setFront!('workdays', on ? 'true' : null)),
        ),
        SizedBox(height: t.space(3)),
      ],
      if (actions.setColour != null && item.line != null) block('Colour', swatches),
    ];

    return DefaultTextStyle(
      style: words,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (ticket)
            Row(
              children: <Widget>[
                if (item.label != null) Padding(padding: EdgeInsets.only(right: t.space(1)), child: Text(item.label!, style: t.textAt(t.fontSize('xs'), mono: true, color: t.color('app-ink-3')))),
                Expanded(child: Text(item.name, style: t.textAt(t.fontSize('sm'), weight: 'semibold'), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            )
          else
            block('Name', field('name', _name, enabled: actions.rename != null, closes: true)),
          SizedBox(height: t.space(2)),
          if (item.milestone)
            block('On', field('start', _start, placeholder: '2026-11-02', enabled: actions.move != null, input: TextInputType.datetime))
          else
            pair(
              block('Starts', field('start', _start, placeholder: '2026-11-02', enabled: actions.move != null, input: TextInputType.datetime)),
              block('Ends', field('end', _end, placeholder: '2026-11-06', enabled: actions.move != null, input: TextInputType.datetime)),
            ),
          SizedBox(height: t.space(2)),
          pair(
            block('Who', field('person', _person, placeholder: '@name', enabled: actions.setPeople != null)),
            block('Done', field('progress', _progress, placeholder: '0–100%', enabled: actions.setProgress != null && item.line != null, input: TextInputType.number)),
          ),
          if (actions.setWaits != null && item.line != null) ...<Widget>[
            SizedBox(height: t.space(2)),
            block('Waits on', field('waits', _waits, placeholder: 'Names, with commas between')),
          ],
          SizedBox(height: t.space(2)),
          Text(followWords(widget.model, item), key: const ValueKey<String>('gantt-follow-words'), style: small),
          if (actions.setMilestone != null && item.line != null) ...<Widget>[
            SizedBox(height: t.space(2)),
            GlacierSwitch(key: const ValueKey<String>('gantt-milestone'), checked: item.milestone, label: const Text('A milestone'), onCheckedChange: (on) => _said(actions.setMilestone!(item.key, on))),
          ],
          if (more.isNotEmpty) ...<Widget>[
            SizedBox(height: t.space(2)),
            if (!_more)
              Align(alignment: Alignment.centerLeft, child: button('More', () => setState(() => _more = true), key: const ValueKey<String>('gantt-more')))
            else ...<Widget>[
              Container(height: 1, color: t.color('app-rule')),
              SizedBox(height: t.space(2)),
              ...more,
            ],
          ],
          if (_wrong != null) ...<Widget>[
            SizedBox(height: t.space(2)),
            Text(_wrong!, key: const ValueKey<String>('gantt-wrong'), style: t.textAt(t.fontSize('xs'), color: t.color('glacier-red-11'))),
          ],
          SizedBox(height: t.space(3)),
          Row(
            children: <Widget>[
              if (actions.delete != null && item.line != null)
                button('Delete', () {
                  _said(actions.delete!(item.key));
                  widget.onClose();
                }, danger: true, key: const ValueKey<String>('gantt-delete')),
              if (actions.open != null && item.ticket != null) ...<Widget>[
                SizedBox(width: t.space(1)),
                button('Open', () => actions.open!(item), key: const ValueKey<String>('gantt-open')),
              ],
              const Spacer(),
              button('Done', done, strong: true, key: const ValueKey<String>('gantt-done')),
            ],
          ),
        ],
      ),
    );
  }
}

/// A task's panel as a sheet from the foot, on a phone.
class GanttSheet extends StatelessWidget {
  const GanttSheet({super.key, required this.item, required this.model, required this.actions, required this.simple, required this.onClose, required this.onDone});

  final GanttItem item;
  final GanttModel model;
  final GanttActions actions;
  final bool simple;
  final VoidCallback onClose;
  final void Function(String key) onDone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Sheet(
      label: item.name,
      onClose: onClose,
      centred: false,
      children: <Widget>[
        SheetTitle(child: Text(item.milestone ? 'Milestone' : 'Task')),
        Padding(
          padding: EdgeInsets.fromLTRB(t.space(4), 0, t.space(4), t.space(4)),
          child: GanttPanel(key: ValueKey<String>('gantt-panel:${item.key}'), item: item, model: model, actions: actions, simple: simple, onClose: onClose, onDone: onDone),
        ),
      ],
    );
  }
}
