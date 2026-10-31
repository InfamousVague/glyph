/// A ticket's labels and its component, and the colour each label wears (Matt, 2026-10-31, the ticket features he
/// chose: "`labels: [bug, ui]` and `component: Waitlist` in front matter", "coloured chips: colour per label kept in
/// the notebook's front matter (`label-colours:`) with sensible defaults", a label picker with type-to-create, a
/// filter everywhere and a board grouped by either).
///
///     ---                                   ---
///     type: ticket                          book: true
///     labels: [bug, ui]                     key: WAIT
///     component: Waitlist                   label-colours: {bug: red, ui: purple}
///     ---                                   ---
///
/// All of it is plain front matter, which any other app reads as it is written. A label is a word as typed, a `#`
/// before it taken off, and two labels are one whatever their case. Its colour is one of the hues the app's tokens
/// have ([labelHues]): the notebook's `label-colours:` where it names the label, else a hue a well-known label has
/// ([defaultLabelHues]: a bug is red), else one picked from its letters, the same every time, so a label wears one
/// colour wherever it is drawn.
///
/// The query core already reads both: `where: labels has bug` and `group: labels` (a ticket in each of its labels'
/// lanes), `where: component = Waitlist` and `group: component` (lib/core/query/values.dart). This is what the
/// drawing and the pickers need beside that. Pure, every rule a test (test/tickets/labels_test.dart).
library;

import '../core/front_matter.dart' show frontMatterValue, unquoted;
import '../core/item_syntax.dart' show jsTrim;
import '../core/properties.dart' show propertyList, withFrontMatterValue, withProperty;

/// The hues a label can wear: the token scales the app has (`glacier-<hue>-3` its ground, `-11` its words).
const List<String> labelHues = ['blue', 'purple', 'green', 'amber', 'red', 'teal', 'gray'];

/// What a well-known label wears where the notebook says nothing: the colours most trackers give them.
const Map<String, String> defaultLabelHues = {
  'bug': 'red',
  'defect': 'red',
  'crash': 'red',
  'urgent': 'red',
  'security': 'red',
  'regression': 'red',
  'feature': 'blue',
  'backend': 'blue',
  'api': 'blue',
  'enhancement': 'green',
  'improvement': 'green',
  'good-first-issue': 'green',
  'ui': 'purple',
  'ux': 'purple',
  'design': 'purple',
  'frontend': 'purple',
  'docs': 'teal',
  'documentation': 'teal',
  'question': 'teal',
  'test': 'teal',
  'tests': 'teal',
  'mobile': 'teal',
  'performance': 'amber',
  'perf': 'amber',
  'tech-debt': 'amber',
  'debt': 'amber',
  'blocked': 'amber',
  'chore': 'gray',
  'infra': 'gray',
  'wontfix': 'gray',
  'duplicate': 'gray',
};

final RegExp _hashes = RegExp(r'^#+');
final RegExp _spaces = RegExp(r'\s+');

/// A label as it is written back: trimmed, its `#` off, its inner spaces one.
String cleanLabel(String label) => jsTrim(label.replaceFirst(_hashes, '')).replaceAll(_spaces, ' ');

/// A label as two are compared: [cleanLabel] in lower case, a space a dash, so `Tech debt` is `tech-debt`.
String labelKey(String label) => cleanLabel(label).toLowerCase().replaceAll(' ', '-');

/// Whether two labels are one.
bool sameLabel(String a, String b) => labelKey(a) == labelKey(b) && labelKey(a).isNotEmpty;

/// A hue from a label's letters, the same every time.
String _hueFromLetters(String key) {
  var sum = 0;
  for (final unit in key.codeUnits) {
    sum = (sum * 31 + unit) % 9973;
  }
  // Gray is a hue a person picks, never one a label is given.
  return labelHues[sum % (labelHues.length - 1)];
}

/// The colours a notebook gives its labels (`label-colours: {bug: red, ui: purple}`), by [labelKey]. Read as a flow
/// map, a flow list of `name: hue` or `name=hue`, or the same without brackets; a hue the app has not got is left
/// out, so the label wears its default.
Map<String, String> labelColoursOf(String? notebook) {
  if (notebook == null) return const {};
  final said = jsTrim(frontMatterValue(notebook, 'label-colours') ?? frontMatterValue(notebook, 'label-colors') ?? '');
  if (said.isEmpty) return const {};
  final inner = (said.startsWith('{') && said.endsWith('}')) || (said.startsWith('[') && said.endsWith(']')) ? said.substring(1, said.length - 1) : said;
  final colours = <String, String>{};
  for (final item in propertyList('[$inner]')) {
    final at = item.lastIndexOf(RegExp('[:=]'));
    if (at <= 0) continue;
    final name = labelKey(unquoted(jsTrim(item.substring(0, at))));
    final hue = jsTrim(unquoted(jsTrim(item.substring(at + 1)))).toLowerCase();
    if (name.isNotEmpty && labelHues.contains(hue)) colours[name] = hue;
  }
  return colours;
}

/// The hue [label] wears: [colours]'s (a notebook's [labelColoursOf]), else its well-known one, else one from its
/// letters.
String labelHue(String label, [Map<String, String> colours = const {}]) {
  final key = labelKey(label);
  return colours[key] ?? defaultLabelHues[key] ?? _hueFromLetters(key);
}

final RegExp _plainName = RegExp(r'^[\p{L}\p{N}_ -]+$', unicode: true);

String _written(String name) => _plainName.hasMatch(name) && name == jsTrim(name) ? name : '"${name.replaceAll('"', "'")}"';

/// The notebook with [label]'s colour set to [hue], or taken off for null (the label wears its default again):
/// written as one flow map, `label-colours: {bug: red, ui: purple}`, in the order the labels were given colours.
String withLabelColour(String notebook, String label, String? hue) {
  final name = labelKey(label);
  if (name.isEmpty || (hue != null && !labelHues.contains(hue))) return notebook;
  final colours = Map<String, String>.of(labelColoursOf(notebook));
  if (hue == null) {
    colours.remove(name);
  } else {
    colours[name] = hue;
  }
  final key = frontMatterValue(notebook, 'label-colors') != null && frontMatterValue(notebook, 'label-colours') == null ? 'label-colors' : 'label-colours';
  if (colours.isEmpty) return withFrontMatterValue(notebook, key, null);
  return withFrontMatterValue(notebook, key, '{${[for (final MapEntry(:key, :value) in colours.entries) '${_written(key)}: $value'].join(', ')}}');
}

// ---- a ticket's own -----------------------------------------------------------------------------------------------

/// A ticket's labels as its front matter has them, cleaned, each once.
List<String> labelsOf(String body) {
  final labels = <String>[];
  for (final item in propertyList(frontMatterValue(body, 'labels'))) {
    final label = cleanLabel(item);
    if (label.isNotEmpty && !labels.any((each) => sameLabel(each, label))) labels.add(label);
  }
  return labels;
}

/// The ticket with [labels] as its labels, `labels: [bug, ui]`, or the key taken off for none.
String withLabels(String body, List<String> labels) {
  final kept = <String>[];
  for (final label in labels.map(cleanLabel)) {
    if (label.isNotEmpty && !kept.any((each) => sameLabel(each, label))) kept.add(label);
  }
  return withProperty(body, 'labels', kept);
}

/// The ticket with [label] added where it has not got it, and taken off where it has.
String withLabelToggled(String body, String label) {
  final now = labelsOf(body);
  final has = now.any((each) => sameLabel(each, label));
  return withLabels(body, has ? [for (final each in now) if (!sameLabel(each, label)) each] : [...now, label]);
}

/// The ticket with [add] added and [remove] taken off, as a bulk edit writes many at once.
String withLabelsChanged(String body, {Iterable<String> add = const [], Iterable<String> remove = const []}) {
  final kept = [for (final each in labelsOf(body)) if (!remove.any((gone) => sameLabel(gone, each))) each];
  for (final label in add) {
    if (!kept.any((each) => sameLabel(each, label))) kept.add(cleanLabel(label));
  }
  return withLabels(body, kept);
}

/// A ticket's component (`component: Waitlist`), or null for none.
String? componentOf(String body) {
  final said = jsTrim(frontMatterValue(body, 'component') ?? '');
  return said.isEmpty ? null : said;
}

// ---- the library's ------------------------------------------------------------------------------------------------

/// Every label the [bodies] name, the most used first, then by name; each written as it is written most.
List<String> labelsIn(Iterable<String> bodies) => _named(bodies, labelsOf);

/// Every component the [bodies] name, the most used first.
List<String> componentsIn(Iterable<String> bodies) => _named(bodies, (body) => [?componentOf(body)]);

List<String> _named(Iterable<String> bodies, List<String> Function(String body) read) {
  final counts = <String, int>{};
  final spelt = <String, Map<String, int>>{};
  for (final body in bodies) {
    for (final name in read(body)) {
      final key = labelKey(name);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      final ways = spelt.putIfAbsent(key, () => {});
      ways[name] = (ways[name] ?? 0) + 1;
    }
  }
  String shown(String key) {
    final ways = spelt[key]!.entries.toList()..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
    return ways.first.key;
  }

  final keys = counts.keys.toList()..sort((a, b) => counts[b] != counts[a] ? counts[b]! - counts[a]! : a.compareTo(b));
  return [for (final key in keys) shown(key)];
}
