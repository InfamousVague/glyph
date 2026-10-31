/// A notebook's rules for its tickets: when something happens to one, do something (Matt, 2026-10-31, of the ticket
/// features: "Rules / automations", simple when/then rules kept in plain Markdown). Pure: what a rule says, read and
/// written, and which rules a change to a ticket sets off. Running them is rule_runs.dart.
///
/// The rules are a ```rules fence in the notebook's index note, a sentence a line:
///
///     ```rules
///     When status becomes Done, post to Slack #eng "{id} {title} shipped"
///     When a ticket is created, set assignee to Sam
///     When a ticket is assigned, notify the assignee
///     When due passes and priority is High, notify me "{id} is overdue"
///     When blocked for 3 days, post to Discord #triage "{id} has been stuck for three days"
///     When label bug is added, set priority to High, then run the Claude rule "Triage a bug"
///     When status becomes In review, make a note from "Review checklist" in Kiln called "Review {id}"
///     ```
///
/// Why a fence of sentences, and not an `automations:` block in the front matter: the front matter here is a key and
/// a value a line (lib/core/properties.dart), so a rule there would be a YAML map in flow syntax, `{when: …, then:
/// …}`, which reads as code in every other app; a fence of sentences reads as what it does in any of them (a grey
/// block of plain English), the sentence builder writes exactly what a person would type, and the notebook's index
/// keeps its rules in sight where its pages are listed. A line that is not understood is kept as it is and said as
/// not understood ([RuleSet.problems]); `#` starts a comment.
///
/// - **When**: `status becomes <status>` (or `status changes` for any), `a ticket is created`, `a ticket is assigned`
///   (or `assigned to <person>`), `due passes`, `blocked for <n> days` (waiting on a ticket that is not done, or a
///   status called Blocked), `label <label> is added` (or `a label is added`).
/// - **And**: `<field> is <value>`, `<field> is not <value>` (`=` and `!=` too), each read from the ticket's front
///   matter after the change, any case.
/// - **Do** (the buttons' actions, lib/core/note_buttons.dart, and the bell): `set <field> to <value>` (`to nothing`
///   takes it off), `post to Slack|Discord [#channel] ["text"]` (the note itself where no text is given),
///   `run the Claude rule "<rule>"` or `ask Claude "<prompt>"`, `notify <person>|the assignee|me ["text"]`,
///   `make a note from "<template>" [in <notebook or folder>] [called "<title>"]`. Several are joined by `, then`.
/// - Words in braces are the ticket's: `{id}`, `{title}`, `{status}`, `{assignee}`, `{due}`, or any front matter key.
///
/// A value with a comma, a quote or the word `and` in it is written in quotes. A rule's id ([TicketRule.id]) is a
/// hash of how it is written, the same on every device, so its runs are known everywhere (rule_runs.dart).
library;

import 'package:flutter/foundation.dart';

import '../core/days.dart' show daysBetween;
import '../core/front_matter.dart' show frontMatterValue;
import '../core/item_syntax.dart' show jsTrim;
import '../core/properties.dart' show StatusCategory, Ticket, propertiesOf, propertyList;

// ---- what a rule says -------------------------------------------------------------------------------------------

/// What sets a rule off.
enum RuleTrigger {
  /// `status becomes Done`; with no status, `status changes`.
  status,

  /// `a ticket is created`.
  created,

  /// `a ticket is assigned`, or `assigned to Sam`.
  assigned,

  /// `due passes`: the due day is behind it and the ticket is not done.
  duePasses,

  /// `blocked for 3 days`.
  blocked,

  /// `label bug is added`, or `a label is added`.
  labelAdded;

  /// Whether the clock sets it off, not a change: one device looks for these (rule_runs.dart).
  bool get timed => this == duePasses || this == blocked;
}

/// The when of a rule: its trigger, and what it names (a status, a person, a label), or the days a block lasts.
@immutable
class RuleWhen {
  const RuleWhen(this.trigger, {this.value, this.days});

  final RuleTrigger trigger;

  /// The status, the person or the label it names; null for any.
  final String? value;

  /// For [RuleTrigger.blocked]: how many days.
  final int? days;

  /// As a rule writes it, after `When `.
  String get words => switch (trigger) {
        RuleTrigger.status => value == null ? 'status changes' : 'status becomes ${_quoted(value!)}',
        RuleTrigger.created => 'a ticket is created',
        RuleTrigger.assigned => value == null ? 'a ticket is assigned' : 'a ticket is assigned to ${_quoted(value!)}',
        RuleTrigger.duePasses => 'due passes',
        RuleTrigger.blocked => 'blocked for ${days ?? 1} ${days == 1 ? 'day' : 'days'}',
        RuleTrigger.labelAdded => value == null ? 'a label is added' : 'label ${_quoted(value!)} is added',
      };

  @override
  bool operator ==(Object other) => other is RuleWhen && other.trigger == trigger && other.value == value && other.days == days;

  @override
  int get hashCode => Object.hash(trigger, value, days);
}

/// A test on the ticket's front matter: `priority is High`, `assignee is not Sam`.
@immutable
class RuleCondition {
  const RuleCondition(this.field, this.value, {this.not = false});
  final String field;
  final String value;
  final bool not;

  String get words => '$field is ${not ? 'not ' : ''}${_quoted(value)}';

  /// Whether [body]'s front matter passes it: the field's value, any case, with an at sign or a hash before it taken
  /// off; a list (labels) passes where any of its items does. Nothing for `nothing` / `empty`.
  bool holds(String body) {
    final raw = frontMatterValue(body, field) ?? '';
    final items = [for (final item in propertyList(raw)) _bare(item).toLowerCase()];
    final want = _bare(value).toLowerCase();
    final empty = want == 'nothing' || want == 'empty' || want.isEmpty;
    final has = empty ? items.isEmpty : items.contains(want);
    return not ? !has : has;
  }

  @override
  bool operator ==(Object other) => other is RuleCondition && other.field == field && other.value == value && other.not == not;

  @override
  int get hashCode => Object.hash(field, value, not);
}

/// What a rule does.
enum RuleVerb { set, post, claude, notify, make }

/// One thing a rule does, and with what: a set's `field` and `value`; a post's `to` (`slack` or `discord`),
/// `channel` and `text`; Claude's `rule` or `prompt`; a notice's `person` and `text`; a make's `template`, `in` and
/// `title`.
@immutable
class RuleAction {
  const RuleAction(this.verb, [this.values = const {}]);
  final RuleVerb verb;
  final Map<String, String> values;

  String? operator [](String key) => values[key];

  /// The plugin whose work it is (docs/ACTIVITY.md, Plugin marks): Slack's or Discord's for a post, Claude's for Claude.
  String? get plugin => switch (verb) {
        RuleVerb.post => this['to'] == 'discord' ? 'discord' : 'slack',
        RuleVerb.claude => 'claude',
        _ => null,
      };

  /// As a rule writes it.
  String get words {
    String text(String key) => (values[key] ?? '').isEmpty ? '' : ' "${_escaped(values[key]!)}"';
    switch (verb) {
      case RuleVerb.set:
        final value = values['value'] ?? '';
        return 'set ${values['field']} to ${value.isEmpty ? 'nothing' : _quoted(value)}';
      case RuleVerb.post:
        final channel = values['channel'] ?? '';
        return 'post to ${values['to'] == 'discord' ? 'Discord' : 'Slack'}${channel.isEmpty ? '' : ' #${channel.replaceFirst(RegExp('^#'), '')}'}${text('text')}';
      case RuleVerb.claude:
        return (values['rule'] ?? '').isNotEmpty ? 'run the Claude rule${text('rule')}' : 'ask Claude${text('prompt')}';
      case RuleVerb.notify:
        final person = values['person'] ?? 'assignee';
        final who = switch (person.toLowerCase()) { 'assignee' => 'the assignee', 'me' => 'me', _ => _quoted(person) };
        return 'notify $who${text('text')}';
      case RuleVerb.make:
        final place = values['in'] ?? '';
        return 'make a note from${text('template')}${place.isEmpty ? '' : ' in ${_quoted(place)}'}${text('title').isEmpty ? '' : ' called${text('title')}'}';
    }
  }

  /// What it does, in a sentence, for the activity record's line.
  String get doing => switch (verb) {
        RuleVerb.set => 'Setting ${values['field']}',
        RuleVerb.post => 'Posting to ${values['to'] == 'discord' ? 'Discord' : 'Slack'}',
        RuleVerb.claude => 'Claude is on it',
        RuleVerb.notify => 'Telling ${switch ((values['person'] ?? 'assignee').toLowerCase()) { 'assignee' => 'the assignee', 'me' => 'you', _ => values['person'] }}',
        RuleVerb.make => 'Making a note from “${values['template']}”',
      };

  @override
  bool operator ==(Object other) => other is RuleAction && other.verb == verb && mapEquals(other.values, values);

  @override
  int get hashCode => Object.hash(verb, Object.hashAll(values.entries.map((e) => '${e.key}=${e.value}')));

  @override
  String toString() => 'RuleAction($words)';
}

/// One rule: when, and what else must hold, and what it does.
@immutable
class TicketRule {
  const TicketRule({required this.when, this.conditions = const [], required this.actions, this.line = -1});

  final RuleWhen when;
  final List<RuleCondition> conditions;
  final List<RuleAction> actions;

  /// The line of the fence it was read from, from 0; -1 for one made.
  final int line;

  /// The rule as it is written: `When status becomes Done, post to Slack #eng`.
  String get text => 'When ${[when.words, for (final c in conditions) c.words].join(' and ')}, ${[for (final a in actions) a.words].join(', then ')}';

  /// The same on every device for the same words ([text]): what its runs are known by.
  String get id => ruleHash(text);

  /// Whether every condition holds on [body].
  bool holds(String body) => conditions.every((condition) => condition.holds(body));

  TicketRule copyWith({RuleWhen? when, List<RuleCondition>? conditions, List<RuleAction>? actions}) => TicketRule(when: when ?? this.when, conditions: conditions ?? this.conditions, actions: actions ?? this.actions, line: line);

  @override
  bool operator ==(Object other) => other is TicketRule && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'TicketRule($text)';
}

/// A short hash of [text], as hex: FNV-1a, so every device makes the same.
String ruleHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

// ---- writing ------------------------------------------------------------------------------------------------------

final RegExp _needsQuotes = RegExp(r'[,"]|\band\b|\bthen\b|^\s|\s$|^$', caseSensitive: false);

/// A value as a rule writes it: bare where it reads back the same, else in quotes.
String _quoted(String value) => _needsQuotes.hasMatch(value) ? '"${_escaped(value)}"' : value;

String _escaped(String value) => value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String _bare(String value) => jsTrim(value).replaceFirst(RegExp('^[@#]+'), '');

// ---- reading ------------------------------------------------------------------------------------------------------

/// A notebook's rules, read: each rule, and each line that was not understood, with its line in the fence.
@immutable
class RuleSet {
  const RuleSet({this.rules = const [], this.problems = const []});

  static const RuleSet none = RuleSet();

  final List<TicketRule> rules;

  /// The lines that are no rule, by their line in the fence, with why.
  final List<({int line, String text, String why})> problems;

  bool get isEmpty => rules.isEmpty && problems.isEmpty;
}

/// Splits [text] at each [separator] outside quotes.
List<String> _split(String text, RegExp separator) {
  final parts = <String>[];
  var quoted = false;
  var from = 0;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == r'\' && quoted) {
      i += 2;
      continue;
    }
    if (c == '"') quoted = !quoted;
    if (!quoted) {
      final found = separator.matchAsPrefix(text, i);
      if (found != null && found.end > i) {
        parts.add(text.substring(from, i));
        from = i = found.end;
        continue;
      }
    }
    i += 1;
  }
  parts.add(text.substring(from));
  return parts;
}

/// The first quoted words in [text], and what is left around them; null where there are none.
({String inside, String before, String after})? _firstQuoted(String text) {
  final start = text.indexOf('"');
  if (start < 0) return null;
  final out = StringBuffer();
  var i = start + 1;
  while (i < text.length) {
    final c = text[i];
    if (c == r'\' && i + 1 < text.length) {
      out.write(text[i + 1]);
      i += 2;
      continue;
    }
    if (c == '"') return (inside: out.toString(), before: text.substring(0, start), after: text.substring(i + 1));
    out.write(c);
    i += 1;
  }
  return null;
}

/// A value as written: its quotes taken off where it is quoted, else trimmed.
String _value(String text) {
  final trimmed = jsTrim(text);
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) return _firstQuoted(trimmed)?.inside ?? trimmed;
  return trimmed;
}

final RegExp _comma = RegExp(r'\s*,\s*');
final RegExp _thens = RegExp(r'\s*(?:,\s*then\s+|;\s*|\s+then\s+)', caseSensitive: false);
final RegExp _ands = RegExp(r'\s+and\s+', caseSensitive: false);
final RegExp _when = RegExp(r'^\s*(?:[-*+]\s+)?when\s+', caseSensitive: false);

final RegExp _statusBecomes = RegExp(r'^(?:the\s+)?status\s+(?:becomes|changes\s+to|moves\s+to|is\s+set\s+to|turns)\s+(.+)$', caseSensitive: false);
final RegExp _statusChanges = RegExp(r'^(?:the\s+)?status\s+(?:changes|is\s+changed|moves)$', caseSensitive: false);
final RegExp _created = RegExp(r'^(?:(?:a|the)\s+(?:new\s+)?(?:ticket|issue)|it)\s+is\s+(?:created|made|added)$|^(?:created|a\s+new\s+ticket)$', caseSensitive: false);
final RegExp _assigned = RegExp(r'^(?:(?:(?:a|the)\s+(?:ticket|issue)|it)\s+is\s+)?assigned(?:\s+to\s+(.+))?$|^(?:the\s+)?assignee\s+changes$', caseSensitive: false);
final RegExp _due = RegExp(r'^(?:the\s+)?due(?:\s+(?:date|day))?\s+(?:passes|is\s+passed|has\s+passed)$|^(?:(?:a|the)\s+ticket\s+|it\s+)?is\s+overdue$|^overdue$', caseSensitive: false);
final RegExp _blocked = RegExp(r'^(?:(?:(?:a|the)\s+ticket|it)\s+is\s+)?blocked\s+for\s+(?:more\s+than\s+|over\s+)?(\d+)\s+days?$', caseSensitive: false);
final RegExp _labelAdded = RegExp(r'^(?:the\s+)?label\s+(.+?)\s+is\s+added$|^(?:a\s+)?label\s+(?:is\s+)?added(?:\s+(.+))?$', caseSensitive: false);

final RegExp _condition = RegExp(r'^([\w.-]+)\s*(?:(is\s+not|isn.t|!=)|(is|==?))\s*(.+)$', caseSensitive: false);

final RegExp _set = RegExp(r'^set\s+([\w.-]+)\s+to\s+(.+)$', caseSensitive: false);
final RegExp _clear = RegExp(r'^(?:clear|remove)\s+(?:the\s+)?([\w.-]+)$', caseSensitive: false);
final RegExp _post = RegExp(r'^post\s+(?:it\s+)?to\s+(slack|discord)\b\s*(.*)$', caseSensitive: false);
final RegExp _claudeRule = RegExp(r'^(?:run|follow|use)\s+(?:the\s+)?claude\s+rule\b\s*(.*)$', caseSensitive: false);
final RegExp _askClaude = RegExp(r'^ask\s+claude\b\s*(?:to\s+)?(.*)$', caseSensitive: false);
final RegExp _notify = RegExp(r'^(?:notify|tell|ping)\s+(.+)$', caseSensitive: false);
final RegExp _make = RegExp(r'^(?:make|create|new)\s+(?:a\s+)?(?:new\s+)?note\s+from\s+(?:the\s+)?(?:template\s+)?(.+)$', caseSensitive: false);

/// The when of a rule, read; null where it is not one.
RuleWhen? _whenOf(String text) {
  final words = jsTrim(text);
  if (_statusChanges.hasMatch(words)) return const RuleWhen(RuleTrigger.status);
  if (_statusBecomes.firstMatch(words) case final found?) return RuleWhen(RuleTrigger.status, value: _value(found.group(1)!));
  if (_created.hasMatch(words)) return const RuleWhen(RuleTrigger.created);
  if (_assigned.firstMatch(words) case final found?) {
    final who = found.group(1);
    return RuleWhen(RuleTrigger.assigned, value: who == null ? null : _bare(_value(who)));
  }
  if (_due.hasMatch(words)) return const RuleWhen(RuleTrigger.duePasses);
  if (_blocked.firstMatch(words) case final found?) return RuleWhen(RuleTrigger.blocked, days: int.parse(found.group(1)!));
  if (_labelAdded.firstMatch(words) case final found?) {
    final label = found.group(1) ?? found.group(2);
    return RuleWhen(RuleTrigger.labelAdded, value: label == null ? null : _bare(_value(label)));
  }
  return null;
}

/// A test as typed, `priority is High`, or null where it is none: the builder's And.
RuleCondition? ruleConditionOf(String text) => _conditionOf(text);

RuleCondition? _conditionOf(String text) {
  final found = _condition.firstMatch(jsTrim(text));
  if (found == null) return null;
  return RuleCondition(found.group(1)!, _value(found.group(4)!), not: found.group(2) != null);
}

/// A post's or a notice's tail: a `#channel` or a name, then its quoted words.
({String name, String text}) _nameAndText(String rest) {
  final quoted = _firstQuoted(rest);
  final name = jsTrim(quoted == null ? rest : quoted.before);
  return (name: name, text: quoted?.inside ?? '');
}

RuleAction? _actionOf(String text) {
  final words = jsTrim(text);
  if (_set.firstMatch(words) case final found?) {
    final value = _value(found.group(2)!);
    final none = value.toLowerCase() == 'nothing' || value.toLowerCase() == 'empty';
    return RuleAction(RuleVerb.set, {'field': found.group(1)!, 'value': none ? '' : value});
  }
  if (_clear.firstMatch(words) case final found?) return RuleAction(RuleVerb.set, {'field': found.group(1)!, 'value': ''});
  if (_post.firstMatch(words) case final found?) {
    final tail = _nameAndText(found.group(2)!);
    final channel = tail.name.replaceFirst(RegExp(r'^(?:the\s+)?(?:channel\s+)?#?', caseSensitive: false), '');
    return RuleAction(RuleVerb.post, {'to': found.group(1)!.toLowerCase(), if (channel.isNotEmpty) 'channel': channel, if (tail.text.isNotEmpty) 'text': tail.text});
  }
  if (_claudeRule.firstMatch(words) case final found?) {
    final rule = _value(found.group(1)!);
    return rule.isEmpty ? null : RuleAction(RuleVerb.claude, {'rule': rule});
  }
  if (_askClaude.firstMatch(words) case final found?) {
    final prompt = _value(found.group(1)!);
    return prompt.isEmpty ? null : RuleAction(RuleVerb.claude, {'prompt': prompt});
  }
  if (_notify.firstMatch(words) case final found?) {
    final tail = _nameAndText(found.group(1)!);
    final who = tail.name.toLowerCase();
    final person = switch (who) {
      'the assignee' || 'assignee' || 'its assignee' => 'assignee',
      'me' || 'myself' => 'me',
      '' => 'assignee',
      _ => _bare(_value(tail.name)),
    };
    return RuleAction(RuleVerb.notify, {'person': person, if (tail.text.isNotEmpty) 'text': tail.text});
  }
  if (_make.firstMatch(words) case final found?) {
    final rest = found.group(1)!;
    final template = _firstQuoted(rest);
    final String name;
    var after = '';
    if (template != null && jsTrim(template.before).isEmpty) {
      name = template.inside;
      after = template.after;
    } else {
      final cut = RegExp(r'\s+(?:in|called)\s+', caseSensitive: false).firstMatch(rest);
      name = jsTrim(cut == null ? rest : rest.substring(0, cut.start));
      after = cut == null ? '' : rest.substring(cut.start);
    }
    if (name.isEmpty) return null;
    String? place, title;
    final called = RegExp(r'\s*called\s+', caseSensitive: false).firstMatch(after);
    final inPart = called == null ? after : after.substring(0, called.start);
    final inFound = RegExp(r'^\s*in\s+(.+)$', caseSensitive: false).firstMatch(inPart);
    if (inFound != null) place = _value(inFound.group(1)!);
    if (called != null) title = _value(after.substring(called.end));
    return RuleAction(RuleVerb.make, {'template': name, if (place != null && place.isNotEmpty) 'in': place, if (title != null && title.isNotEmpty) 'title': title});
  }
  return null;
}

/// One line read as a rule, or why it is none.
({TicketRule? rule, String? why}) ruleOf(String line, {int at = 0}) {
  final start = _when.firstMatch(line);
  if (start == null) return (rule: null, why: 'A rule starts with “When”.');
  final rest = line.substring(start.end);
  // The when and its tests, then what it does: split at the first comma outside quotes.
  final parts = _split(rest, _comma);
  if (parts.length < 2) return (rule: null, why: 'Say what to do after a comma: “When status becomes Done, post to Slack”.');
  final head = _split(parts.first, _ands);
  final when = _whenOf(head.first);
  if (when == null) return (rule: null, why: 'Not a “when” this app knows: “${jsTrim(head.first)}”.');
  final conditions = <RuleCondition>[];
  for (final each in head.skip(1)) {
    final condition = _conditionOf(each);
    if (condition == null) return (rule: null, why: 'Not a test this app knows: “${jsTrim(each)}”. Try “priority is High”.');
    conditions.add(condition);
  }
  final actions = <RuleAction>[];
  for (final each in _split(parts.skip(1).join(', '), _thens)) {
    if (jsTrim(each).isEmpty) continue;
    final action = _actionOf(each);
    if (action == null) return (rule: null, why: 'Not something a rule can do: “${jsTrim(each)}”.');
    actions.add(action);
  }
  if (actions.isEmpty) return (rule: null, why: 'Say what to do after the comma.');
  return (rule: TicketRule(when: when, conditions: conditions, actions: actions, line: at), why: null);
}

/// Where the ```rules fence is in [body]: its opening and closing lines, and its words; null where it has none.
({int open, int close, String text})? rulesFenceOf(String body) {
  if (!body.contains('rules')) return null;
  final lines = body.split('\n');
  for (var i = 0; i < lines.length; i += 1) {
    final found = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*rules\s*$', caseSensitive: false).firstMatch(lines[i]);
    if (found == null) continue;
    final mark = found.group(1)!;
    for (var j = i + 1; j < lines.length; j += 1) {
      final trimmed = lines[j].trim();
      if (trimmed.startsWith(mark[0] * 3) && trimmed.replaceAll(mark[0], '').isEmpty && trimmed.length >= mark.length) {
        return (open: i, close: j, text: lines.sublist(i + 1, j).join('\n'));
      }
    }
    return null;
  }
  return null;
}

/// Every rule in [text], the fence's own lines: blank lines and `#` comments are passed over.
RuleSet rulesOf(String text) {
  final rules = <TicketRule>[];
  final problems = <({int line, String text, String why})>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('//')) continue;
    final read = ruleOf(line, at: i);
    if (read.rule != null) {
      rules.add(read.rule!);
    } else {
      problems.add((line: i, text: trimmed, why: read.why!));
    }
  }
  return RuleSet(rules: rules, problems: problems);
}

/// The notebook's rules, from its index note's ```rules fence.
RuleSet rulesIn(String notebook) => switch (rulesFenceOf(notebook)) { final fence? => rulesOf(fence.text), null => RuleSet.none };

/// [notebook] with its ```rules fence holding [text]: the fence made at the foot of the index where there is none,
/// and taken out for nothing.
String withRulesText(String notebook, String text) {
  final words = text.trimRight();
  final fence = rulesFenceOf(notebook);
  final lines = notebook.split('\n');
  if (fence == null) {
    if (words.trim().isEmpty) return notebook;
    return '${notebook.trimRight()}\n\n```rules\n$words\n```\n';
  }
  if (words.trim().isEmpty) {
    final before = lines.sublist(0, fence.open);
    final after = lines.sublist(fence.close + 1);
    while (before.isNotEmpty && before.last.trim().isEmpty && (after.isEmpty || after.first.trim().isEmpty)) {
      before.removeLast();
    }
    return [...before, ...after].join('\n');
  }
  return [...lines.sublist(0, fence.open + 1), words, ...lines.sublist(fence.close)].join('\n');
}

/// [notebook] with [rules] written in its fence, one a line: what the sentence builder saves. Each rule read from the
/// fence ([TicketRule.line]) is written over the line it was read from, one left out takes its line with it, and a
/// rule made in the builder (its line -1) goes at the foot; comments and lines not understood stay where they are.
String withRules(String notebook, List<TicketRule> rules, {RuleSet? read}) {
  final fence = rulesFenceOf(notebook);
  final had = read ?? (fence == null ? RuleSet.none : rulesOf(fence.text));
  final lines = fence == null ? <String>[] : fence.text.split('\n');
  final from = {for (final rule in had.rules) rule.line};
  final over = {for (final rule in rules) if (from.contains(rule.line)) rule.line: rule};
  final out = <String>[
    for (var i = 0; i < lines.length; i += 1)
      if (!from.contains(i)) lines[i] else if (over[i] case final rule?) rule.text,
    for (final rule in rules)
      if (!from.contains(rule.line)) rule.text,
  ];
  return withRulesText(notebook, out.join('\n'));
}

// ---- which rules a change sets off ------------------------------------------------------------------------------

/// A rule set off, and why: what its run is known by on every device, after the rule and the ticket
/// (rule_runs.dart `runId`): `status:done`, `assigned:sam`, `label:bug`, `due:2026-10-30`, `blocked:<since>`.
@immutable
class Fired {
  const Fired(this.rule, this.cause);
  final TicketRule rule;
  final String cause;

  @override
  bool operator ==(Object other) => other is Fired && other.rule == rule && other.cause == cause;

  @override
  int get hashCode => Object.hash(rule, cause);

  @override
  String toString() => 'Fired(${rule.text} · $cause)';
}

String _key(String value) => _bare(value).toLowerCase();

List<String> _labelsOf(String? body) => body == null ? const [] : [for (final label in propertyList(frontMatterValue(body, 'labels'))) _bare(label)];

/// The rules [after] sets off as it now stands against [before] (null for a ticket just made): a status it moved to,
/// an assignee given, a label added, a ticket made. A clock's triggers are [firedByClock]'s. Each rule's tests are
/// asked of [after].
List<Fired> firedByChange(List<TicketRule> rules, {required String? before, required String after, required Ticket? was, required Ticket now}) {
  final fired = <Fired>[];
  final made = before == null || was == null;
  for (final rule in rules) {
    final when = rule.when;
    String? cause;
    switch (when.trigger) {
      case RuleTrigger.created:
        if (made) cause = 'created';
      case RuleTrigger.status:
        final status = now.status ?? '';
        final moved = made ? status.isNotEmpty : _key(was.status ?? '') != _key(status);
        if (moved && (when.value == null || _key(when.value!) == _key(status))) cause = 'status:${_key(status)}';
      case RuleTrigger.assigned:
        final who = now.assignee ?? '';
        final given = who.isNotEmpty && (made || _key(was.assignee ?? '') != _key(who));
        if (given && (when.value == null || _key(when.value!) == _key(who))) cause = 'assigned:${_key(who)}';
      case RuleTrigger.labelAdded:
        final had = {for (final label in _labelsOf(made ? null : before)) label.toLowerCase()};
        for (final label in _labelsOf(after)) {
          if (had.contains(label.toLowerCase())) continue;
          if (when.value == null || _key(when.value!) == label.toLowerCase()) {
            cause = 'label:${label.toLowerCase()}';
            break;
          }
        }
      case RuleTrigger.duePasses || RuleTrigger.blocked:
        break;
    }
    if (cause != null && rule.holds(after)) fired.add(Fired(rule, cause));
  }
  return fired;
}

/// Whether a ticket is blocked: waiting on a ticket that is not done ([waiting], by the screen's lookup), or in a
/// status called Blocked, and not done itself.
bool isBlockedTicket(Ticket ticket, {required bool waiting}) => ticket.category != StatusCategory.done && (waiting || _key(ticket.status ?? '') == 'blocked');

/// The rules the clock sets off for a ticket on [today]: its due day passed while it is not done (`due:<day>`, once
/// for each due day it is given), or blocked since [blockedSince] (ms) for the rule's days (`blocked:<since>`, once
/// for each time it is blocked). [now] is the time in ms.
List<Fired> firedByClock(List<TicketRule> rules, {required String body, required Ticket ticket, required String today, int? blockedSince, required int now}) {
  final fired = <Fired>[];
  for (final rule in rules) {
    String? cause;
    switch (rule.when.trigger) {
      case RuleTrigger.duePasses:
        final due = ticket.due;
        if (due != null && ticket.category != StatusCategory.done) {
          final between = daysBetween(today, due);
          if (between != null && between < 0) cause = 'due:$due';
        }
      case RuleTrigger.blocked:
        final days = rule.when.days ?? 1;
        if (blockedSince != null && now - blockedSince >= days * 86400000) cause = 'blocked:$blockedSince';
      default:
        break;
    }
    if (cause != null && rule.holds(body)) fired.add(Fired(rule, cause));
  }
  return fired;
}

/// [text] with the ticket's words put in its braces: `{id}`, `{title}`, `{status}`, `{assignee}`, `{due}`, and any
/// key of its front matter; one it has nothing for is left empty.
String filledIn(String text, {required String body, required String title}) {
  if (!text.contains('{')) return text;
  final keys = {for (final property in propertiesOf(body)) property.key.toLowerCase(): jsTrim(property.value)};
  return text.replaceAllMapped(RegExp(r'\{([\w.-]+)\}'), (m) {
    final key = m.group(1)!.toLowerCase();
    if (key == 'title') return title;
    if (key == 'key') return _value(keys['id'] ?? '');
    return _value(keys[key] ?? '');
  });
}

// ---- the notebook's GitHub settings -----------------------------------------------------------------------------

/// The repos a notebook's tickets are linked with (`github: owner/repo`, or a list of them), as `owner/repo`.
List<String> githubReposOf(String notebook) => [
      for (final repo in propertyList(frontMatterValue(notebook, 'github')))
        if (RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(jsTrim(repo))) jsTrim(repo),
    ];

/// What a merged pull request does to its ticket, by the notebook's `on-merge:` key: `off` nothing, `done` the
/// workflow's first done status (what it does where the key is not written), or the status named.
String? onMergeOf(String notebook) {
  final said = jsTrim(frontMatterValue(notebook, 'on-merge') ?? '');
  if (said.toLowerCase() == 'off' || said.toLowerCase() == 'nothing') return null;
  return said.isEmpty ? 'done' : _value(said);
}
