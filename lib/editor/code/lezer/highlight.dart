/// The classes a parse gives a stretch of code: `highlightTree` of @lezer/highlight 1.2.3, read off the parser's
/// flat record rather than a tree (`lr.dart`).
///
/// On the web a node's tags come from the grammar's `styleTags`, a tag's class from `glyphHighlight`, and
/// `highlightTree` walks the tree handing out one span for each run of text with the classes of the node it is
/// in: a node's own class on the words that are in no node inside it, and, when its rule says `/...`, on the
/// nodes inside too; a rule ending `!` makes the node one run whatever is inside. The class of each rule is worked
/// out when the tables are copied (tool/code_grammars.mjs), so here a rule is a class, a mode and the parents it
/// asks for.
///
/// A node may be another language's to read (the text of a `<script>`, the value of a `style=""`, the HTML
/// outside `<?php ?>`): Lezer mounts that language's tree on the node, over all of it or over stretches of it
/// (an overlay), and `highlightTree` reads the mounted tree there, the outer node's own nodes between the
/// stretches, and hands the inner tree no class from outside an overlay. Here a [Nester] says which nodes are
/// mounted and gives the inner language's runs.
///
/// What differs: the record is read backwards, last node first, as `Tree.build` reads it, and only the nodes over
/// the stretch asked for are opened: a node wholly to one side is stepped over by its size. So the cost is the
/// nodes on the lines being drawn, and the nodes beside them at each depth, whatever the length of the block.
/// The nodes a repeat makes have no name and no rules, and are read as if their contents stood in their place,
/// which is how a tree's cursor passes them.
library;

import 'lr.dart';

/// Where a run of classes is sent: from, to, and the classes, space between them.
typedef SpanSink = void Function(int from, int to, String cls);

/// Another language over a node: over all of it ([ranges] null), or over the stretches `ranges` lists, a start
/// and an end for each, in order. `key` names the mount among the others of the same parse.
class Mount<L> {
  const Mount(this.language, [this.ranges]);

  final L language;
  final List<int>? ranges;
}

/// Who knows which nodes of a parse are another language's, and what that language makes of them.
abstract class Nester<L> {
  /// The mount on the node `cursor` is on (`id`, from `start` to `end`), or null. The cursor must be left where
  /// it is: look around with [RecordCursor.fork].
  Mount<L>? mountOn(int id, int start, int end, RecordCursor? cursor);

  /// The runs of `mount`'s language between `from` and `to`, in order; `start` and `end` are the node's.
  void nested(Mount<L> mount, int start, int end, int from, int to, String inherited, SpanSink sink);
}

/// Not a class: what keeps two runs apart that nothing else does.
const String _apart = '\u0001';

class _Walk<L> {
  _Walk(this.code, this.nester) : parser = code.parser;

  final ParsedCode code;
  final LRParser parser;
  final Nester<L>? nester;

  // The runs, last first.
  final List<int> froms = <int>[], tos = <int>[];
  final List<String> classes = <String>[];

  // One frame for each node being read: where its record starts, where it starts in the code, how far back its
  // words have been read, its class, and the class it hands down.
  final List<int> until = <int>[], start = <int>[], pos = <int>[];
  final List<String> cls = <String>[], down = <String>[];

  /// The names of the nodes around the one being read, outermost first.
  final List<String> names = <String>[];

  /// A run. One with nothing in it is kept: where a class starts is what the runs are joined and parted by
  /// (`HighlightBuilder.startSpan`), and a node with no words of its own between two others still parts them.
  void put(int a, int b, String cls, int from, int to) {
    if (a < from) a = from;
    if (b > to) b = to;
    if (a > b) return;
    froms.add(a);
    tos.add(b);
    classes.add(cls);
  }

  /// `getStyleTags`: the first of a node's rules whose parents are the ones around it.
  StyleRule? ruleFor(int id) {
    final list = parser.rules[id];
    if (list == null) return null;
    for (final rule in list) {
      final context = rule.context;
      if (context == null) return rule;
      var name = names.length - 1, ok = true;
      for (var i = context.length - 1; i >= 0; i--, name--) {
        if (name < 0 || (context[i].isNotEmpty && context[i] != names[name])) {
          ok = false;
          break;
        }
      }
      if (ok) return rule;
    }
    return null;
  }

  /// The inner language's runs, added last first as the rest are.
  void nested(Mount<L> mount, int nodeStart, int nodeEnd, int from, int to, String inherited) {
    if (from >= to) return;
    final at = froms.length;
    void add(int a, int b, String cls) {
      froms.add(a);
      tos.add(b);
      classes.add(cls);
    }

    // The inner language's runs come already joined and parted as its own nodes part them. On the web its nodes
    // go through the one builder with the outer ones, so a run of it never joins the outer run beside it nor the
    // inner run after it: a class that is no class stands at each end of each.
    nester!.nested(mount, nodeStart, nodeEnd, from, to, inherited, (a, b, cls) {
      add(a, a, _apart);
      add(a, b, cls);
      add(b, b, _apart);
    });
    // They came in order: turn them round. What they leave bare is bare.
    for (var i = at, j = froms.length - 1; i < j; i++, j--) {
      final f = froms[i], t = tos[i];
      final c = classes[i];
      froms[i] = froms[j];
      tos[i] = tos[j];
      classes[i] = classes[j];
      froms[j] = f;
      tos[j] = t;
      classes[j] = c;
    }
  }

  /// A mounted node: the inner language over its stretches, the node's own nodes between them. `outer` reads the
  /// node itself over a stretch.
  void mounted(Mount<L> mount, int nodeStart, int nodeEnd, int from, int to, String inherited, void Function(int from, int to) outer) {
    final ranges = mount.ranges;
    if (ranges == null) {
      nested(mount, nodeStart, nodeEnd, from < nodeStart ? nodeStart : from, to > nodeEnd ? nodeEnd : to, inherited);
      return;
    }
    var at = nodeEnd;
    for (var i = ranges.length - 2; i >= 0; i -= 2) {
      final a = ranges[i], b = ranges[i + 1];
      if (b < at && at > from && b < to) outer(b < from ? from : b, at > to ? to : at);
      nested(mount, nodeStart, nodeEnd, a < from ? from : a, b > to ? to : b, '');
      at = a;
    }
    if (nodeStart < at && at > from && nodeStart < to) outer(nodeStart < from ? from : nodeStart, at > to ? to : at);
  }

  /// Opens the node the cursor is on. A node with nothing to open (a token, an opaque node, a mounted one) is
  /// read whole and the cursor left before it; otherwise a frame is pushed and the cursor is on its last child.
  void enter(RecordCursor cursor, int from, int to, String inherited, bool mayMount) {
    final id = cursor.id, size = cursor.size, a = cursor.start, b = cursor.end;
    if (mayMount && nester != null) {
      final mount = nester!.mountOn(id, a, b, cursor);
      if (mount != null) {
        mounted(mount, a, b, from, to, inherited, (f, t) => node(cursor.fork(), f, t, inherited, false));
        cursor.moveTo(cursor.pos - size);
        return;
      }
    }
    var own = inherited, handed = inherited;
    final rule = ruleFor(id);
    if (rule != null && rule.cls.isNotEmpty) {
      own = inherited.isEmpty ? rule.cls : '$inherited ${rule.cls}';
      if (rule.mode == 1) handed = own;
    }
    if (size == 4 || (rule != null && rule.mode == 0)) {
      put(a, b, own, from, to);
      cursor.moveTo(cursor.pos - size);
      return;
    }
    until.add(cursor.pos - size);
    start.add(a);
    pos.add(b);
    cls.add(own);
    down.add(handed);
    names.add(parser.nodeNames[id]);
    cursor.next();
  }

  /// Ends the innermost frame: nothing more inside the node, or nothing more of it in the stretch, and its own
  /// words before the last node read are what is left.
  void close(RecordCursor cursor, int from, int to) {
    final f = until.length - 1;
    put(start[f], pos[f], cls[f], from, to);
    cursor.moveTo(until[f]);
    until.removeLast();
    start.removeLast();
    pos.removeLast();
    cls.removeLast();
    down.removeLast();
    names.removeLast();
  }

  /// Reads the frames above `base` to their ends.
  void run(RecordCursor cursor, int from, int to, int base) {
    final minRepeat = parser.minRepeatTerm;
    while (until.length > base) {
      final f = until.length - 1;
      if (cursor.pos <= until[f] || pos[f] <= from) {
        close(cursor, from, to);
        continue;
      }
      final size = cursor.size;
      if (size < 0 || cursor.id >= minRepeat) {
        // A note the parser left for a later parse to reuse this one by, or a repeat's node, whose contents are
        // read as this node's own.
        cursor.next();
        continue;
      }
      final a = cursor.start, b = cursor.end;
      if (a >= to) {
        cursor.moveTo(cursor.pos - size);
        if (a < pos[f]) pos[f] = a;
        continue;
      }
      if (b <= from) {
        // This node and the ones before it are outside the stretch.
        close(cursor, from, to);
        continue;
      }
      // The node's own words between this child and the one after it.
      put(b, pos[f], cls[f], from, to);
      if (a < pos[f]) pos[f] = a;
      enter(cursor, from, to, down[f], true);
    }
  }

  /// Reads the node the cursor is on, between `from` and `to`.
  void node(RecordCursor cursor, int from, int to, String inherited, bool mayMount) {
    final base = until.length;
    enter(cursor, from, to, inherited, mayMount);
    run(cursor, from, to, base);
  }

  /// Reads the top node, which is not in the record: it is everything in it (`Tree.build`'s `topID`).
  void top(int from, int to, String inherited, bool mayMount) {
    final id = parser.top.$2;
    if (mayMount && nester != null) {
      final mount = nester!.mountOn(id, 0, code.length, null);
      if (mount != null) {
        mounted(mount, 0, code.length, from, to, inherited, (f, t) => top(f, t, inherited, false));
        return;
      }
    }
    var own = inherited, handed = inherited;
    final rule = ruleFor(id);
    if (rule != null && rule.cls.isNotEmpty) {
      own = inherited.isEmpty ? rule.cls : '$inherited ${rule.cls}';
      if (rule.mode == 1) handed = own;
    }
    if (rule != null && rule.mode == 0) {
      put(0, code.length, own, from, to);
      return;
    }
    final base = until.length;
    until.add(0);
    start.add(0);
    pos.add(code.length);
    cls.add(own);
    down.add(handed);
    names.add(parser.nodeNames[id]);
    run(code.cursor(), from, to, base);
  }
}

/// Calls `sink` for each run of `code` between `from` and `to` that has a class, in order, as `highlightTree`
/// calls its `putStyle`. `inherited` is the class the code starts with (none, for a block in a note). Nothing is said of the code past [ParsedCode.length], which is not parsed yet.
void highlightCode<L>(ParsedCode code, int from, int to, SpanSink sink, {String inherited = '', Nester<L>? nester}) {
  if (to > code.length) to = code.length;
  if (from >= to) return;
  final walk = _Walk<L>(code, nester)..top(from, to, inherited, true);
  // `HighlightBuilder`: the runs in order, each one's start a `startSpan`. A run is joined to the one before it
  // only when no other class started between them, were it for no words at all.
  final froms = walk.froms, tos = walk.tos, classes = walk.classes;
  var at = from, end = from;
  var cls = '';
  void startSpan(int pos, String next) {
    if (next == cls) return;
    if (pos > at && cls.isNotEmpty && cls != _apart) sink(at, pos, cls);
    if (pos > at) at = pos;
    cls = next;
  }

  for (var i = froms.length - 1; i >= 0; i--) {
    final a = froms[i], b = tos[i];
    // Bare code between two runs of an inner language.
    if (a > end) startSpan(end, '');
    startSpan(a, classes[i]);
    if (b > end) end = b;
  }
  if (end > at && cls.isNotEmpty && cls != _apart) sink(at, end, cls);
}
