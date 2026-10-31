/// A notebook's rules and GitHub, set from its More sheet (Matt, 2026-10-31, of the ticket features: "a small rule
/// editor (a sentence builder: "When [status] becomes [Done], [post to Slack #eng] …"), plus the raw text").
///
/// - **The rules**, each its sentence (rules.dart), a press opening the builder; a line the app cannot read is listed
///   with why, to be put right in the text. Add a rule, and Edit as text, which is the fence's own lines.
/// - **The builder** is the rule as a sentence of words and slots, `When [status becomes] [Done], [post to Slack]
///   [#eng] [“{id} shipped”]`: a press on a slot opens its choices under the sentence (the triggers, the workflow's
///   statuses, the actions) or its field, and the sentence is written as it reads. One test (`and priority is High`)
///   and any number of actions (`then …`); a rule of more tests is the text's.
/// - **GitHub**: the repos its tickets' pull requests are in (`github:`), and what a merge does (`on-merge:`).
///
/// Every change is written into the notebook as it is made, through the note screen's own writer, so one Undo of the
/// note takes it back. In simple mode the row that opens this is behind the More sheet's More (note_settings.dart).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/front_matter.dart' show frontMatterValue;
import '../core/properties.dart' show StatusCategory, statusCategory, statusesOf, withProperty;
import '../editor/tickets/ticket_work.dart' show showWorkSheet;
import '../plugins/github/repos.dart' show githubToken;
import '../settings/kit/settings_type.dart' show pageText;
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import 'rules.dart';

/// What the More sheet's row says of a notebook's rules and GitHub: "2 rules · ghost/app", or how to start.
String rulesSummary(String notebook) {
  final rules = rulesIn(notebook).rules.length;
  final repos = githubReposOf(notebook);
  final parts = [if (rules > 0) '$rules ${rules == 1 ? 'rule' : 'rules'}', ...repos];
  return parts.isEmpty ? 'When a ticket changes, post, set, notify or ask Claude; link pull requests.' : parts.join(' · ');
}

/// Opens the notebook's rules and GitHub over the app. [body] is the notebook's words now; [write] changes them.
Future<void> openTicketRules(BuildContext context, {required String Function() body, required void Function(String Function(String was) change) write, List<String> people = const [], bool? hasToken}) =>
    showWorkSheet<void>(context, (done) => RulesSheet(body: body, write: write, people: people, hasToken: hasToken ?? githubToken().trim().isNotEmpty, onClose: () => done(null)));

enum _Page { list, rule, text }

/// The slots of the builder's sentence.
enum _Slot { trigger, value, condition, verb, actionValues }

class RulesSheet extends StatefulWidget {
  const RulesSheet({super.key, required this.body, required this.write, required this.onClose, this.people = const [], this.hasToken = true});

  final String Function() body;
  final void Function(String Function(String was) change) write;
  final VoidCallback onClose;
  final List<String> people;

  /// Whether a GitHub token is on this device: without one no pull request is read.
  final bool hasToken;

  @override
  State<RulesSheet> createState() => _RulesSheetState();
}

class _RulesSheetState extends State<RulesSheet> {
  _Page _page = _Page.list;

  /// The rule in the builder, and where it was in the list (null for a new one).
  TicketRule? _rule;
  int? _editing;
  _Slot? _slot;
  int _action = 0;
  late final TextEditingController _text = TextEditingController();
  late String _repos = githubReposOf(widget.body()).join(', ');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  RuleSet get _read => rulesIn(widget.body());
  List<String> get _statuses => statusesOf(widget.body());

  void _write(String Function(String was) change) {
    widget.write(change);
    setState(() {});
  }

  void _openRule(int? at) {
    final rules = _read.rules;
    setState(() {
      _editing = at;
      _rule = at == null ? const TicketRule(when: RuleWhen(RuleTrigger.status, value: 'Done'), actions: [RuleAction(RuleVerb.notify, {'person': 'assignee'})]) : rules[at];
      _slot = null;
      _action = 0;
      _page = _Page.rule;
    });
  }

  void _saveRule() {
    final rule = _rule;
    if (rule == null) return;
    _write((was) {
      final read = rulesIn(was);
      final rules = [...read.rules];
      final at = _editing;
      if (at != null && at < rules.length) {
        rules[at] = TicketRule(when: rule.when, conditions: rule.conditions, actions: rule.actions, line: read.rules[at].line);
      } else {
        rules.add(TicketRule(when: rule.when, conditions: rule.conditions, actions: rule.actions));
      }
      return withRules(was, rules, read: read);
    });
    setState(() => _page = _Page.list);
  }

  void _deleteRule() {
    final at = _editing;
    if (at != null) {
      _write((was) {
        final read = rulesIn(was);
        return withRules(was, [...read.rules]..removeAt(at), read: read);
      });
    }
    setState(() => _page = _Page.list);
  }

  void _back() {
    if (_page == _Page.list) return widget.onClose();
    if (_page == _Page.text) _write((was) => withRulesText(was, _text.text));
    setState(() => _page = _Page.list);
  }

  Widget _icon(LucideIcon icon) => AppIcon(icon, size: 18, strokeWidth: 2);

  // ---- the list -------------------------------------------------------------------------------------------------

  List<Widget> _list() {
    final body = widget.body();
    final read = _read;
    final onMerge = onMergeOf(body);
    final said = (frontMatterValue(body, 'on-merge') ?? '').trim();
    final done = _statuses.where((each) => statusCategory(each, _statuses) == StatusCategory.done).firstOrNull ?? 'Done';
    return [
      SheetTitle.text('Rules and GitHub'),
      const SheetNote('When something happens to one of this notebook’s tickets, do something. Kept in the notebook as plain sentences, in a rules block at the foot of its index.'),
      const SheetHeading('Rules'),
      SheetGroup(
        children: [
          for (final (i, rule) in read.rules.indexed) SheetRow(key: ValueKey('rule-$i'), icon: _icon(Lucide.workflow), label: rule.text, onPress: () => _openRule(i)),
          for (final problem in read.problems) SheetRow(icon: _icon(Lucide.x), label: problem.text, hint: problem.why, onPress: _openText),
          SheetRow(key: const ValueKey('rule-add'), icon: _icon(Lucide.plus), label: 'Add a rule', onPress: () => _openRule(null)),
          SheetRow(key: const ValueKey('rule-text'), icon: _icon(Lucide.pencil), label: 'Edit as text', hint: 'The sentences as they are written, one a line.', onPress: _openText),
        ],
      ),
      const SheetHeading('GitHub'),
      SheetGroup(
        children: [
          SheetField(
            key: const ValueKey('rules-github'),
            label: 'Repos',
            value: _repos,
            placeholder: 'owner/repo',
            autoCapitalize: TextCapitalization.none,
            autoCorrect: false,
            onChange: (typed) {
              setState(() => _repos = typed);
              final repos = [for (final part in typed.split(RegExp(r'[,\s]+'))) if (RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(part)) part];
              widget.write((was) => withProperty(was, 'github', repos.isEmpty ? null : (repos.length == 1 ? repos.single : repos)));
            },
          ),
        ],
      ),
      SheetNote(widget.hasToken
          ? 'A pull request whose title, branch, body or commits name a ticket’s key, like ${frontMatterValue(body, 'key') ?? 'HT'}-12, shows on the ticket with its state and checks. Read with your GitHub token, on this device.'
          : 'Add a GitHub token in Settings › GitHub, and pull requests that name a ticket’s key show on it.'),
      const SheetHeading('When a pull request merges'),
      SheetGroup(
        children: [
          SheetRow(key: const ValueKey('merge-done'), label: 'Move the ticket to $done', chosen: onMerge != null && onMerge.toLowerCase() == 'done', onPress: () => _write((was) => withProperty(was, 'on-merge', null))),
          for (final status in _statuses)
            if (statusCategory(status, _statuses) != StatusCategory.done)
              SheetRow(key: ValueKey('merge-$status'), label: 'Move it to $status', chosen: said.toLowerCase() == status.toLowerCase(), onPress: () => _write((was) => withProperty(was, 'on-merge', status))),
          SheetRow(key: const ValueKey('merge-off'), label: 'Leave it as it is', chosen: onMerge == null, onPress: () => _write((was) => withProperty(was, 'on-merge', 'off'))),
        ],
      ),
    ];
  }

  void _openText() {
    _text.text = rulesFenceOf(widget.body())?.text ?? '';
    setState(() => _page = _Page.text);
  }

  // ---- the text -------------------------------------------------------------------------------------------------

  List<Widget> _textPage() {
    final read = rulesOf(_text.text);
    return [
      SheetTitle.text('Rules as text'),
      const SheetNote('One rule a line: “When status becomes Done, post to Slack #eng”. A line starting with # is a note to yourself.'),
      _RulesField(key: const ValueKey('rules-text'), controller: _text, onChange: () => setState(() {})),
      for (final problem in read.problems) SheetNote('Line ${problem.line + 1}: ${problem.why}'),
      SheetGroup(
        children: [
          SheetRow(key: const ValueKey('rules-text-save'), label: 'Save', onPress: _back),
        ],
      ),
    ];
  }

  // ---- the builder ----------------------------------------------------------------------------------------------

  void _set(TicketRule rule) => setState(() => _rule = rule);

  RuleAction get _act => _rule!.actions[_action.clamp(0, _rule!.actions.length - 1)];

  void _setAction(RuleAction action) {
    final actions = [..._rule!.actions];
    actions[_action.clamp(0, actions.length - 1)] = action;
    _set(_rule!.copyWith(actions: actions));
  }

  Widget _press({Key? key, required String label, bool selected = false, required VoidCallback onPress, required Widget child}) => Semantics(
        key: key,
        container: true,
        button: true,
        selected: selected,
        label: label,
        onTap: onPress,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            fireMotor(HapticKind.selection);
            onPress();
          },
          child: child,
        ),
      );

  Widget _word(String text) => Text(text, style: pageText(context.tokens, context.tokens.fontSize('md'), color: context.tokens.color('app-ink-2')));

  Widget _slotChip(String text, _Slot slot, {int action = 0, Key? key}) {
    final t = context.tokens;
    final on = _slot == slot && (slot != _Slot.verb && slot != _Slot.actionValues || _action == action);
    return _press(
      key: key,
      label: text,
      selected: on,
      onPress: () => setState(() {
        _slot = on ? null : slot;
        _action = action;
      }),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
        decoration: BoxDecoration(
          color: on ? t.color('glacier-accent-solid').withValues(alpha: 0.16) : t.color('app-paper'),
          border: Border.all(color: on ? t.color('glacier-accent-solid') : t.color('app-rule')),
          borderRadius: BorderRadius.circular(t.radius('md')),
        ),
        child: Text(text, style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink'))),
      ),
    );
  }

  String _triggerWords(RuleWhen when) => switch (when.trigger) {
        RuleTrigger.status => when.value == null ? 'status changes' : 'status becomes',
        RuleTrigger.created => 'a ticket is created',
        RuleTrigger.assigned => when.value == null ? 'a ticket is assigned' : 'a ticket is assigned to',
        RuleTrigger.duePasses => 'due passes',
        RuleTrigger.blocked => 'blocked for',
        RuleTrigger.labelAdded => when.value == null ? 'a label is added' : 'label',
      };

  String _verbWords(RuleAction action) => switch (action.verb) {
        RuleVerb.set => 'set ${action['field'] ?? 'a field'}',
        RuleVerb.post => 'post to ${action['to'] == 'discord' ? 'Discord' : 'Slack'}',
        RuleVerb.claude => (action['rule'] ?? '').isNotEmpty ? 'run the Claude rule' : 'ask Claude',
        RuleVerb.notify => 'notify',
        RuleVerb.make => 'make a note from',
      };

  String _actionValueWords(RuleAction action) => switch (action.verb) {
        RuleVerb.set => 'to ${(action['value'] ?? '').isEmpty ? 'nothing' : action['value']}',
        RuleVerb.post => [if ((action['channel'] ?? '').isNotEmpty) '#${action['channel']}', if ((action['text'] ?? '').isNotEmpty) '“${action['text']}”'].join(' ').ifEmpty('the ticket'),
        RuleVerb.claude => '“${action['rule'] ?? action['prompt'] ?? ''}”',
        RuleVerb.notify => [switch ((action['person'] ?? 'assignee').toLowerCase()) { 'assignee' => 'the assignee', 'me' => 'me', _ => action['person']! }, if ((action['text'] ?? '').isNotEmpty) '“${action['text']}”'].join(' '),
        RuleVerb.make => '“${action['template'] ?? ''}”${(action['in'] ?? '').isEmpty ? '' : ' in ${action['in']}'}',
      };

  /// The sentence: words and slots, wrapped as words are.
  Widget _sentence() {
    final rule = _rule!;
    final when = rule.when;
    final valueWords = switch (when.trigger) {
      RuleTrigger.status || RuleTrigger.assigned || RuleTrigger.labelAdded => when.value,
      RuleTrigger.blocked => '${when.days ?? 1} ${when.days == 1 ? 'day' : 'days'}',
      _ => null,
    };
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
      child: Wrap(
        key: const ValueKey('rule-sentence'),
        spacing: t.space(1),
        runSpacing: t.space(2),
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _word('When'),
          _slotChip(_triggerWords(when), _Slot.trigger, key: const ValueKey('slot-trigger')),
          if (valueWords != null) _slotChip(when.trigger == RuleTrigger.labelAdded ? '$valueWords is added' : valueWords, _Slot.value, key: const ValueKey('slot-value')),
          if (rule.conditions.isNotEmpty) ...[_word('and'), _slotChip(rule.conditions.first.words, _Slot.condition, key: const ValueKey('slot-condition'))] else _slotChip('+ and…', _Slot.condition, key: const ValueKey('slot-condition')),
          _word(','),
          for (final (i, action) in rule.actions.indexed) ...[
            if (i > 0) _word('then'),
            _slotChip(_verbWords(action), _Slot.verb, action: i, key: ValueKey('slot-verb-$i')),
            _slotChip(_actionValueWords(action), _Slot.actionValues, action: i, key: ValueKey('slot-values-$i')),
          ],
          _press(
            key: const ValueKey('slot-then'),
            label: 'Then do something else',
            onPress: () => setState(() {
              _set(rule.copyWith(actions: [...rule.actions, const RuleAction(RuleVerb.notify, {'person': 'me'})]));
              _action = rule.actions.length;
              _slot = _Slot.verb;
            }),
            child: Padding(padding: EdgeInsets.all(t.space(1)), child: Text('+ then…', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))),
          ),
        ],
      ),
    );
  }

  List<Widget> _choices() {
    final rule = _rule!;
    final when = rule.when;
    switch (_slot) {
      case null:
        return const [];
      case _Slot.trigger:
        RuleWhen pick(RuleTrigger trigger) => switch (trigger) {
              RuleTrigger.status => RuleWhen(trigger, value: when.trigger == trigger ? when.value : 'Done'),
              RuleTrigger.blocked => RuleWhen(trigger, days: when.days ?? 3),
              RuleTrigger.labelAdded => RuleWhen(trigger, value: when.trigger == trigger ? when.value : 'bug'),
              _ => RuleWhen(trigger),
            };
        const names = {
          RuleTrigger.status: 'Its status becomes…',
          RuleTrigger.created: 'A ticket is created',
          RuleTrigger.assigned: 'A ticket is assigned',
          RuleTrigger.duePasses: 'Its due day passes',
          RuleTrigger.blocked: 'It is blocked for some days',
          RuleTrigger.labelAdded: 'A label is added',
        };
        return [
          SheetGroup(children: [
            for (final MapEntry(key: trigger, value: name) in names.entries)
              SheetRow(key: ValueKey('trigger-${trigger.name}'), label: name, chosen: when.trigger == trigger, onPress: () => setState(() {
                _set(rule.copyWith(when: pick(trigger)));
                _slot = trigger == RuleTrigger.status || trigger == RuleTrigger.blocked || trigger == RuleTrigger.labelAdded || trigger == RuleTrigger.assigned ? _Slot.value : null;
              })),
          ]),
        ];
      case _Slot.value:
        switch (when.trigger) {
          case RuleTrigger.status:
            return [
              SheetGroup(children: [
                for (final status in _statuses) SheetRow(key: ValueKey('status-$status'), label: status, chosen: when.value?.toLowerCase() == status.toLowerCase(), onPress: () => setState(() => _set(rule.copyWith(when: RuleWhen(RuleTrigger.status, value: status))))),
                SheetRow(key: const ValueKey('status-any'), label: 'Any status', chosen: when.value == null, onPress: () => setState(() => _set(rule.copyWith(when: const RuleWhen(RuleTrigger.status))))),
              ]),
            ];
          case RuleTrigger.assigned:
            return [
              SheetGroup(children: [
                SheetRow(label: 'Anyone', chosen: when.value == null, onPress: () => setState(() => _set(rule.copyWith(when: const RuleWhen(RuleTrigger.assigned))))),
                for (final person in widget.people.take(8)) SheetRow(label: person, chosen: when.value == person, onPress: () => setState(() => _set(rule.copyWith(when: RuleWhen(RuleTrigger.assigned, value: person))))),
                SheetField(label: 'Someone else', value: widget.people.contains(when.value) ? '' : (when.value ?? ''), placeholder: 'Sam', autoCorrect: false, onChange: (typed) => _set(rule.copyWith(when: RuleWhen(RuleTrigger.assigned, value: typed.trim().isEmpty ? null : typed.trim())))),
              ]),
            ];
          case RuleTrigger.blocked:
            return [
              SheetGroup(children: [
                SheetField(key: const ValueKey('value-days'), label: 'Days', value: '${when.days ?? 1}', inputMode: TextInputType.number, autoCorrect: false, onChange: (typed) {
                  final days = int.tryParse(typed.trim());
                  if (days != null && days > 0) _set(rule.copyWith(when: RuleWhen(RuleTrigger.blocked, days: days)));
                }),
              ]),
            ];
          case RuleTrigger.labelAdded:
            return [
              SheetGroup(children: [
                SheetField(key: const ValueKey('value-label'), label: 'Label', value: when.value ?? '', placeholder: 'Any label', autoCorrect: false, autoCapitalize: TextCapitalization.none, onChange: (typed) => _set(rule.copyWith(when: RuleWhen(RuleTrigger.labelAdded, value: typed.trim().isEmpty ? null : typed.trim().replaceFirst('#', ''))))),
              ]),
            ];
          default:
            return const [];
        }
      case _Slot.condition:
        final condition = rule.conditions.firstOrNull;
        return [
          SheetGroup(children: [
            SheetField(
              key: const ValueKey('value-condition'),
              label: 'And',
              value: condition?.words ?? '',
              placeholder: 'priority is High',
              autoCorrect: false,
              onChange: (typed) {
                final read = ruleConditionOf(typed);
                _set(rule.copyWith(conditions: typed.trim().isEmpty ? const [] : (read == null ? rule.conditions : [read, ...rule.conditions.skip(1)])));
              },
            ),
          ]),
          const SheetNote('A field of the ticket and what it holds: “priority is High”, “assignee is not Sam”.'),
        ];
      case _Slot.verb:
        final act = _act;
        const verbs = [
          (RuleVerb.post, 'slack', 'Post to Slack'),
          (RuleVerb.post, 'discord', 'Post to Discord'),
          (RuleVerb.set, null, 'Set a field'),
          (RuleVerb.notify, null, 'Notify someone'),
          (RuleVerb.claude, null, 'Run a Claude rule'),
          (RuleVerb.make, null, 'Make a note from a template'),
        ];
        return [
          SheetGroup(children: [
            for (final (verb, to, name) in verbs)
              SheetRow(
                key: ValueKey('verb-${verb.name}${to ?? ''}'),
                label: name,
                chosen: act.verb == verb && (to == null || act['to'] == to),
                onPress: () => setState(() {
                  _setAction(switch (verb) {
                    RuleVerb.post => RuleAction(RuleVerb.post, {'to': to!, if ((act['channel'] ?? '').isNotEmpty) 'channel': act['channel']!}),
                    RuleVerb.set => const RuleAction(RuleVerb.set, {'field': 'status', 'value': 'Done'}),
                    RuleVerb.notify => const RuleAction(RuleVerb.notify, {'person': 'assignee'}),
                    RuleVerb.claude => const RuleAction(RuleVerb.claude, {'rule': ''}),
                    RuleVerb.make => const RuleAction(RuleVerb.make, {'template': ''}),
                  });
                  _slot = _Slot.actionValues;
                }),
              ),
            if (rule.actions.length > 1)
              SheetRow(label: 'Take this one out', danger: true, onPress: () => setState(() {
                _set(rule.copyWith(actions: [...rule.actions]..removeAt(_action.clamp(0, rule.actions.length - 1))));
                _action = 0;
                _slot = null;
              })),
          ]),
        ];
      case _Slot.actionValues:
        final act = _act;
        SheetField field(String key, String label, String placeholder, {bool words = false}) => SheetField(
              key: ValueKey('value-$key'),
              label: label,
              value: act[key] ?? '',
              placeholder: placeholder,
              autoCorrect: words,
              autoCapitalize: words ? TextCapitalization.sentences : TextCapitalization.none,
              onChange: (typed) {
                final values = {...act.values};
                final clean = key == 'channel' ? typed.trim().replaceFirst('#', '') : typed;
                if (clean.trim().isEmpty && key != 'value') {
                  values.remove(key);
                } else {
                  values[key] = clean.trim();
                }
                _setAction(RuleAction(act.verb, values));
              },
            );
        final fields = switch (act.verb) {
          RuleVerb.set => [field('field', 'Field', 'status'), field('value', 'To', 'Done', words: true)],
          RuleVerb.post => [field('channel', 'Channel', 'eng'), field('text', 'Words', '{id} {title} shipped', words: true)],
          RuleVerb.claude => [field('rule', 'Claude rule', 'Triage a bug', words: true)],
          RuleVerb.notify => [field('person', 'Who', 'assignee, me, or a name'), field('text', 'Words', '{id} is yours', words: true)],
          RuleVerb.make => [field('template', 'Template', 'Bug triage', words: true), field('in', 'In', 'A notebook or folder', words: true), field('title', 'Called', 'Triage {id}', words: true)],
        };
        return [
          SheetGroup(children: fields),
          const SheetNote('Words in braces are the ticket’s: {id}, {title}, {status}, {assignee}, {due}.'),
        ];
    }
  }

  List<Widget> _rulePage() {
    final rule = _rule!;
    final readsBack = ruleOf(rule.text).rule?.text == rule.text;
    return [
      SheetTitle.text(_editing == null ? 'New rule' : 'Rule'),
      _sentence(),
      ..._choices(),
      if (!readsBack) const SheetNote('Something in this rule would not read back the same. Check its words.'),
      SheetGroup(
        children: [
          SheetRow(key: const ValueKey('rule-save'), label: _editing == null ? 'Add the rule' : 'Save', disabled: !readsBack, onPress: readsBack ? _saveRule : null),
          if (_editing != null) SheetRow(key: const ValueKey('rule-delete'), label: 'Delete the rule', danger: true, onPress: _deleteRule),
          SheetRow(label: 'Cancel', onPress: () => setState(() => _page = _Page.list)),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final children = switch (_page) {
      _Page.list => _list(),
      _Page.rule => _rulePage(),
      _Page.text => _textPage(),
    };
    return Sheet(key: ValueKey('rules-sheet-${_page.name}'), label: 'Rules and GitHub', onClose: () {
      if (_page == _Page.text) _write((was) => withRulesText(was, _text.text));
      widget.onClose();
    }, onBack: _back, children: children);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// The rules as text: a field of several lines that grows with them, Enter a new line, nothing corrected.
class _RulesField extends StatefulWidget {
  const _RulesField({super.key, required this.controller, required this.onChange});
  final TextEditingController controller;
  final VoidCallback onChange;

  @override
  State<_RulesField> createState() => _RulesFieldState();
}

class _RulesFieldState extends State<_RulesField> {
  final FocusNode _focus = FocusNode(debugLabel: 'rules text');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink');
    final style = pageText(t, t.fontSize('sm'), color: ink, mono: true);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focus.requestFocus,
        child: DecoratedBox(
          decoration: BoxDecoration(color: ink.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(t.radius('md'))),
          child: Padding(
            padding: EdgeInsets.all(t.space(3)),
            child: Semantics(
              label: 'The rules, one a line',
              textField: true,
              child: EditableText(
                controller: widget.controller,
                focusNode: _focus,
                style: style,
                cursorColor: ink,
                cursorWidth: 1,
                backgroundCursorColor: t.color('app-ink-3'),
                selectionColor: t.color('glacier-selection'),
                minLines: 5,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
                onChanged: (_) => widget.onChange(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
