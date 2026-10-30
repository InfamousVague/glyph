/// Buttons in a note (Matt, 2026-10-30, of a list of plain-Markdown features: "add all 12"): a mark that runs an
/// action, written as a link whose address is the app's own, so the file still reads in any other Markdown app.
///
///     [Move to done](ghost:set?status=Done)
///     [Assign to Sam](ghost:set?assignee=Sam)
///     [Tell the team](ghost:post?to=slack&channel=launch&text=Shipped%20it)
///     [Tidy with Claude](ghost:claude?rule=Tidy%20my%20notes)
///     [Open the roadmap](ghost:open?note=Roadmap)
///     [Log a bug](ghost:new?template=Bug%20report&in=Kiln)
///
/// Why a link and not a fenced ```button block: a link is one line in the words it sits among, and every other app
/// draws it as what it is, its label underlined, a click that does nothing harmful (Obsidian and GitHub leave an
/// unknown scheme alone); a fence would be a grey box of `label:` and `action:` lines in every one of them, and could
/// never sit in a sentence or a to-do. The address is a URI as any reader parses one: the verb, then its values as a
/// query, a space written `%20` (a `+` is read as one too), so nothing new has to be learnt to read or write it.
///
/// Five verbs:
/// - `set`: each value a front matter field to write, `status`, `assignee` or any other (`?status=Done&assignee=Sam`);
///   an empty value takes the field off.
/// - `post`: to Slack or Discord through their plugins, `to=slack|discord`, a `channel` by name (the one there is where
///   it is left out), and `text`, or the whole note where there is none. It posts, so it asks first.
/// - `claude`: the app's Claude on this note, with one of the Claude rules by name (`rule=`) or a prompt of its own
///   (`prompt=`). It spends, so it asks first.
/// - `open`: a note by title (`note=`) or a link (`url=`).
/// - `new`: a note from one of your templates (`template=`), in a notebook or a folder (`in=`), with a title
///   (`title=`).
///
/// Anything else after `ghost:` is not a button and is left as the link it is. Pure.
library;

import 'package:flutter/foundation.dart';

/// The scheme a button's address has.
const String buttonScheme = 'ghost';

/// What a button does.
enum ButtonVerb {
  set('set'),
  post('post'),
  claude('claude'),
  open('open'),
  make('new');

  const ButtonVerb(this.word);

  /// As the address writes it.
  final String word;

  static ButtonVerb? of(String word) {
    for (final verb in values) {
      if (verb.word == word.toLowerCase()) return verb;
    }
    return null;
  }
}

/// A button: its label, what it does and with what, and where its mark lies in the note.
@immutable
class NoteButton {
  const NoteButton({required this.label, required this.verb, this.values = const {}, this.from = 0, this.to = 0});

  /// The words on it.
  final String label;
  final ButtonVerb verb;

  /// Its values, in the order written: a `set`'s fields, a `post`'s `to`, `channel` and `text`, and so on.
  final Map<String, String> values;

  /// Where its `[label](ghost:…)` starts and ends in the note's words; 0 for one made, not read.
  final int from;
  final int to;

  String? operator [](String key) => values[key];

  /// Whether it reaches past the note: a post, or Claude, which spends. These ask before they run.
  bool get asksFirst => verb == ButtonVerb.post || verb == ButtonVerb.claude;

  /// Whether a view that cannot be edited runs it: only an open, which changes nothing.
  bool get runsReadOnly => verb == ButtonVerb.open;

  /// Its address: `ghost:set?status=Done`.
  String get address {
    if (values.isEmpty) return '$buttonScheme:${verb.word}';
    final query = [for (final MapEntry(:key, :value) in values.entries) '${_encode(key)}=${_encode(value)}'].join('&');
    return '$buttonScheme:${verb.word}?$query';
  }

  /// The button as it is written: `[Move to done](ghost:set?status=Done)`.
  String get markdown => '[${_label(label)}]($address)';

  /// What it does, in a sentence: what a confirmation and the builder's preview say.
  String get does => switch (verb) {
        ButtonVerb.set => values.isEmpty
            ? 'Changes nothing.'
            : 'Sets ${[for (final MapEntry(:key, :value) in values.entries) value.isEmpty ? '$key to nothing' : '$key to $value'].join(' and ')}.',
        ButtonVerb.post => 'Posts ${values['text'] != null && values['text']!.isNotEmpty ? '“${values['text']}”' : 'this note'} to ${_service(values['to'])}${values['channel'] != null && values['channel']!.isNotEmpty ? ', ${values['channel']}' : ''}.',
        ButtonVerb.claude => values['rule'] != null && values['rule']!.isNotEmpty ? 'Asks Claude to follow the rule “${values['rule']}” on this note.' : 'Asks Claude: “${values['prompt'] ?? ''}”, on this note.',
        ButtonVerb.open => values['url'] != null && values['url']!.isNotEmpty ? 'Opens ${values['url']}.' : 'Opens “${values['note'] ?? ''}”.',
        ButtonVerb.make => 'Makes a note from “${values['template'] ?? ''}”${values['in'] != null && values['in']!.isNotEmpty ? ' in ${values['in']}' : ''}.',
      };

  NoteButton copyWith({String? label, ButtonVerb? verb, Map<String, String>? values}) => NoteButton(label: label ?? this.label, verb: verb ?? this.verb, values: values ?? this.values, from: from, to: to);

  @override
  bool operator ==(Object other) => other is NoteButton && other.label == label && other.verb == verb && mapEquals(other.values, values) && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(label, verb, Object.hashAll(values.entries.map((e) => '${e.key}=${e.value}')), from, to);

  @override
  String toString() => 'NoteButton($markdown @$from-$to)';
}

String _service(String? to) => switch (to?.toLowerCase()) { 'discord' => 'Discord', _ => 'Slack' };

/// A value in an address: everything but letters, digits and `-._~` written in `%`s, so a space is `%20`.
String _encode(String text) => Uri.encodeComponent(text);

/// A label as a link's words hold it: a bracket escaped, so `[a]` cannot end the label early.
String _label(String text) => text.replaceAll(r'\', r'\\').replaceAll('[', r'\[').replaceAll(']', r'\]');

final RegExp _escaped = RegExp(r'\\([\\\[\]])');

/// A `ghost:` address read: its verb and its values, or null where it is not a button's.
({ButtonVerb verb, Map<String, String> values})? readAddress(String address) {
  final text = address.trim();
  final colon = text.indexOf(':');
  if (colon < 0 || text.substring(0, colon).toLowerCase() != buttonScheme) return null;
  final rest = text.substring(colon + 1);
  final ask = rest.indexOf('?');
  final verb = ButtonVerb.of(ask < 0 ? rest : rest.substring(0, ask));
  if (verb == null) return null;
  final values = <String, String>{};
  if (ask >= 0) {
    for (final pair in rest.substring(ask + 1).split('&')) {
      if (pair.isEmpty) continue;
      final equals = pair.indexOf('=');
      final key = _decode(equals < 0 ? pair : pair.substring(0, equals));
      if (key.isEmpty) continue;
      values[key] = equals < 0 ? '' : _decode(pair.substring(equals + 1));
    }
  }
  return (verb: verb, values: values);
}

/// A value read back: `%20` and `+` are spaces; a `%` that is no escape is kept as it is.
String _decode(String text) {
  final spaced = text.replaceAll('+', ' ');
  try {
    return Uri.decodeComponent(spaced);
  } on FormatException {
    return spaced;
  } on ArgumentError {
    return spaced;
  }
}

/// `[label](ghost:…)`: the label (brackets inside it escaped), and an address with no space or closing bracket, or one
/// in angle brackets, as CommonMark takes either. Not an image's (`![…]`).
final RegExp _buttonLink = RegExp(r'(?<!!)\[((?:\\.|[^\[\]\\\n])*)\]\((?:<(ghost:[^>\n]*)>|(ghost:[^\s()<>]*))\)', caseSensitive: false);

/// A fenced block's opening or closing line.
final RegExp _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// An inline code span, which a button is never read inside.
final RegExp _codeSpan = RegExp(r'(`+)[^`\n]*?\1');

/// Every button in [text], in order, with where it lies: none inside a fenced block or a code span.
List<NoteButton> buttonsIn(String text) {
  if (!text.contains('ghost:') && !text.contains('GHOST:') && !text.toLowerCase().contains('ghost:')) return const [];
  final out = <NoteButton>[];
  var at = 0;
  String? fence;
  for (final line in text.split('\n')) {
    final opens = _fence.firstMatch(line);
    if (fence != null) {
      if (opens != null && opens.group(1)!.startsWith(fence[0]) && opens.group(1)!.length >= fence.length) fence = null;
    } else if (opens != null) {
      fence = opens.group(1);
    } else {
      final spans = [for (final m in _codeSpan.allMatches(line)) (m.start, m.end)];
      for (final m in _buttonLink.allMatches(line)) {
        if (spans.any((span) => m.start >= span.$1 && m.start < span.$2)) continue;
        final read = readAddress(m.group(2) ?? m.group(3)!);
        if (read == null) continue;
        final label = m.group(1)!.replaceAllMapped(_escaped, (e) => e.group(1)!);
        out.add(NoteButton(label: label, verb: read.verb, values: read.values, from: at + m.start, to: at + m.end));
      }
    }
    at += line.length + 1;
  }
  return out;
}

/// The button whose mark starts at [from] in [text], or null.
NoteButton? buttonAt(String text, int from) {
  for (final button in buttonsIn(text)) {
    if (button.from == from) return button;
  }
  return null;
}

/// A button read from its label and its address alone, as a link's parts hand them; null where it is not one.
NoteButton? buttonOf(String label, String address) {
  final read = readAddress(address);
  return read == null ? null : NoteButton(label: label, verb: read.verb, values: read.values);
}
