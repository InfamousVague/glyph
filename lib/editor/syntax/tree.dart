// Ported from @lezer/common 1.5 (src/tree.ts), which is:
//
// MIT License
//
// Copyright (C) 2018 by Marijn Haverbeke <marijn@haverbeke.berlin> and others
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

/// The syntax tree the editor's extensions read: the part of `@lezer/common` the web app calls on `syntaxTree(state)`.
///
/// Lezer keeps a tree as [Tree] objects (a type, children, and each child's start **relative to its parent**), packs
/// small subtrees into flat `TreeBuffer`s, and balances long child lists under anonymous nodes. A [SyntaxNode] is a
/// view of one node at an absolute position with a way back to its parent, made as the tree is walked. The first
/// and last of those are kept here, since relative positions are what lets a reparse lift an unchanged block out of
/// the old tree without touching it ([TreeFragment]); the buffers and the balancing are not, and what they bought is
/// had another way: a node with many children (a long note's `Document`) finds the child at a position by binary
/// search.
///
/// What differs from Lezer, all of it out of sight of the Markdown tree the app reads: no anonymous nodes, no
/// mounted or overlaid trees (a fenced block's own language, the HTML inside an `HTMLBlock`), no per-type props
/// beyond a node's groups, and no `IterMode`. Positions are UTF-16 code units, as CodeMirror's are.
library;

/// A kind of node: Lezer's `NodeType`, with the `NodeProp.group` names it is in.
class NodeType {
  const NodeType(this.id, this.name, {this.groups = const [], this.isTop = false});

  /// Its index in the parser's node set.
  final int id;

  /// Lezer's node name: `Paragraph`, `ATXHeading1`, `EmphasisMark`.
  final String name;

  /// `NodeProp.group`: `Block` with `LeafBlock` or `BlockContext` for a block, and `Heading` for a heading.
  final List<String> groups;

  /// Whether this is the type of a whole tree (`Document`).
  final bool isTop;

  /// `NodeType.is`: whether [name] is this type's name or one of its groups.
  bool isA(String name) => this.name == name || groups.contains(name);

  @override
  String toString() => name;
}

/// Lezer's `Tree`: a node, its children, and where each child starts counted from this node's own start.
///
/// Immutable, and never knows where it is: the same [Tree] sits in the tree before an edit and in the one after it.
class Tree {
  Tree(this.type, this.children, this.positions, this.length, [this.contextHash]);

  /// A node with nothing inside it.
  Tree.leaf(this.type, this.length, [this.contextHash]) : children = const [], positions = const [];

  final NodeType type;
  final List<Tree> children;

  /// The start of each of [children], relative to this node's start.
  final List<int> positions;
  final int length;

  /// `NodeProp.contextHash`: a hash of the blocks a block-level node was parsed inside, so a reparse only reuses it
  /// inside the same ones. Null for a node inside a leaf block, which is never reused by itself.
  final int? contextHash;

  /// Whether the children start in order and end in order, which is when a position can be found by halving.
  late final bool _ordered = _checkOrdered();

  bool _checkOrdered() {
    var start = -1, end = -1;
    for (var i = 0; i < children.length; i++) {
      final from = positions[i], to = from + children[i].length;
      if (from < start || to < end) return false;
      start = from;
      end = to;
    }
    return true;
  }

  /// The node at the top, covering the whole document.
  SyntaxNode get topNode => SyntaxNode._(this, 0, 0, null);

  /// A cursor at the top of the tree.
  TreeCursor cursor() => TreeCursor._(topNode);

  /// `Tree.resolve`: the innermost node around [pos]. [side] says which way a position at a node's edge leans: -1
  /// into a node that ends there, 1 into one that starts there, 0 into neither.
  SyntaxNode resolve(int pos, [int side = 0]) => _resolveNode(topNode, pos, side);

  /// `Tree.resolveInner`. The same as [resolve] here, there being no overlaid trees to step into.
  SyntaxNode resolveInner(int pos, [int side = 0]) => _resolveNode(topNode, pos, side);

  /// `Tree.iterate`: calls [enter] for every node touching [from]..[to], parents before children, and [leave] after
  /// a node's children. A node whose [enter] answers `false` has its children passed over and no [leave].
  ///
  /// [enter] may be a function that answers nothing, which is why it is typed `dynamic`: only `false` means
  /// anything.
  void iterate({
    int from = 0,
    int? to,
    required dynamic Function(SyntaxNode node) enter,
    void Function(SyntaxNode node)? leave,
  }) {
    _iterate(topNode, from, to ?? length, enter, leave);
  }

  static void _iterate(
    SyntaxNode node,
    int from,
    int to,
    dynamic Function(SyntaxNode node) enter,
    void Function(SyntaxNode node)? leave,
  ) {
    if (!(node.from <= to && node.to >= from)) return;
    if (enter(node) == false) return;
    final tree = node.tree, children = tree.children, positions = tree.positions;
    var i = 0, ordered = false;
    if (children.length > _searchFrom && tree._ordered) {
      ordered = true;
      i = tree._firstEndingAtOrAfter(from - node.from);
    }
    for (; i < children.length; i++) {
      final start = positions[i] + node.from;
      if (ordered && start > to) break;
      _iterate(SyntaxNode._(children[i], start, i, node), from, to, enter, leave);
    }
    if (leave != null) leave(node);
  }

  /// The first child that ends at or after [pos] (relative to this node), where the children are in order.
  int _firstEndingAtOrAfter(int pos) {
    var low = 0, high = children.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (positions[mid] + children[mid].length < pos) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// One past the last child that starts before [pos] (relative to this node), where the children are in order.
  int _firstStartingAtOrAfter(int pos) {
    var low = 0, high = children.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (positions[mid] < pos) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Lezer's notation: `Document(Paragraph(Emphasis(EmphasisMark,EmphasisMark)),HorizontalRule)`.
  @override
  String toString() {
    if (children.isEmpty) return type.name;
    return '${type.name}(${children.join(',')})';
  }
}

/// A child list longer than this is searched by halving rather than walked.
const int _searchFrom = 12;

/// Lezer's `Side`, the test `nextChild` puts to a child's range.
const int _before = -2, _after = 2, _dontCare = 4;

bool _checkSide(int side, int pos, int from, int to) {
  switch (side) {
    case _before:
      return from < pos;
    case -1:
      return to >= pos && from < pos;
    case 0:
      return from < pos && to > pos;
    case 1:
      return from <= pos && to > pos;
    case _after:
      return to > pos;
    default:
      return true;
  }
}

/// Lezer's `resolveNode`, without the overlays.
SyntaxNode _resolveNode(SyntaxNode node, int pos, int side) {
  // Move up to a node that actually holds the position, if possible.
  while (node.from == node.to ||
      (side < 1 ? node.from >= pos : node.from > pos) ||
      (side > -1 ? node.to <= pos : node.to < pos)) {
    final parent = node.parent;
    if (parent == null) return node;
    node = parent;
  }
  for (;;) {
    final inner = node.enter(pos, side);
    if (inner == null) return node;
    node = inner;
  }
}

/// Lezer's `SyntaxNode` (its `TreeNode`): one node of a [Tree] at its place in the document.
///
/// It is also what [Tree.iterate] hands to `enter`, where Lezer hands a `SyntaxNodeRef`: [node] answers itself, so
/// `node.node.parent` ports as written.
class SyntaxNode {
  SyntaxNode._(this.tree, this.from, this.index, this.parent);

  /// The node's own subtree (`SyntaxNode.tree`, `toTree()`).
  final Tree tree;

  /// Where it starts in the document.
  final int from;

  /// Its index among its parent's children.
  final int index;

  /// The node around it; null for the `Document`.
  final SyntaxNode? parent;

  /// Where it ends in the document.
  int get to => from + tree.length;
  NodeType get type => tree.type;
  String get name => tree.type.name;

  /// `SyntaxNodeRef.node`.
  SyntaxNode get node => this;

  /// `SyntaxNode.toTree`.
  Tree toTree() => tree;

  /// Lezer's `TreeNode.nextChild`: the first child from [i], going [dir], whose range passes [side] against [pos].
  SyntaxNode? _nextChild(int i, int dir, int pos, int side) {
    final children = tree.children, positions = tree.positions;
    final end = dir > 0 ? children.length : -1;
    var ordered = false;
    if (side != _dontCare && children.length > _searchFrom && tree._ordered) {
      ordered = true;
      if (dir > 0 && i == 0) {
        // Every side that looks forward wants a child ending at or after the position.
        if (side != _before) i = tree._firstEndingAtOrAfter(pos - from);
      } else if (dir < 0 && i == children.length - 1 && side != _after) {
        // And every side that looks back wants one starting at or before it.
        final at = tree._firstStartingAtOrAfter(pos - from + 1) - 1;
        if (at < i) i = at;
      }
    }
    for (; i != end; i += dir) {
      final next = children[i], start = positions[i] + from;
      if (!_checkSide(side, pos, start, start + next.length)) {
        // In order, no later child can hold a position this one starts beyond, nor an earlier one a position this
        // one ends short of.
        if (ordered && (dir > 0 ? start > pos && side != _after : start + next.length < pos && side != _before)) {
          return null;
        }
        continue;
      }
      return SyntaxNode._(next, start, i, this);
    }
    return null;
  }

  SyntaxNode? get firstChild => tree.children.isEmpty ? null : _nextChild(0, 1, 0, _dontCare);
  SyntaxNode? get lastChild => tree.children.isEmpty ? null : _nextChild(tree.children.length - 1, -1, 0, _dontCare);
  SyntaxNode? get nextSibling => parent?._nextChild(index + 1, 1, 0, _dontCare);
  SyntaxNode? get prevSibling => parent?._nextChild(index - 1, -1, 0, _dontCare);

  /// The first child that ends after [pos].
  SyntaxNode? childAfter(int pos) => _nextChild(0, 1, pos, _after);

  /// The last child that starts before [pos].
  SyntaxNode? childBefore(int pos) => _nextChild(tree.children.length - 1, -1, pos, _before);

  /// `SyntaxNode.enter`: the child that holds [pos], leaning as [side] says; null when none does.
  SyntaxNode? enter(int pos, int side) => _nextChild(0, 1, pos, side);

  /// `SyntaxNode.resolve`: the innermost node around [pos], starting the search from this node.
  SyntaxNode resolve(int pos, [int side = 0]) => _resolveNode(this, pos, side);

  /// `SyntaxNode.resolveInner`; see [Tree.resolveInner].
  SyntaxNode resolveInner(int pos, [int side = 0]) => _resolveNode(this, pos, side);

  /// A cursor at this node.
  TreeCursor cursor() => TreeCursor._(this);

  /// `SyntaxNode.getChild`: the first child of the named type or group; see [getChildren] for [before] and [after].
  SyntaxNode? getChild(String type, [String? before, String? after]) {
    final found = getChildren(type, before, after);
    return found.isEmpty ? null : found.first;
  }

  /// `SyntaxNode.getChildren`: the children of the named type or group. With [before], only those after the first
  /// child of that type; with [after], only those before the first child of that one, and none if there is no such
  /// child.
  List<SyntaxNode> getChildren(String type, [String? before, String? after]) {
    final result = <SyntaxNode>[];
    var child = firstChild;
    if (child == null) return result;
    if (before != null) {
      for (var found = false; !found;) {
        found = child!.type.isA(before);
        child = child.nextSibling;
        if (child == null) return result;
      }
    }
    for (;;) {
      if (after != null && child!.type.isA(after)) return result;
      if (child!.type.isA(type)) result.add(child);
      child = child.nextSibling;
      if (child == null) return after == null ? result : <SyntaxNode>[];
    }
  }

  /// `SyntaxNode.matchContext`: whether the nodes around this one, innermost last, are named as [context] names
  /// them. An empty name matches any node.
  bool matchContext(List<String> context) {
    var at = parent;
    for (var i = context.length - 1; i >= 0; i--, at = at.parent) {
      if (at == null) return false;
      if (context[i].isNotEmpty && context[i] != at.name) return false;
    }
    return true;
  }

  @override
  String toString() => tree.toString();
}

/// Lezer's `TreeCursor`: a place in the tree that moves, for walking it without keeping every node.
class TreeCursor {
  TreeCursor._(this._node);

  SyntaxNode _node;

  /// The node the cursor is on.
  SyntaxNode get node => _node;
  Tree get tree => _node.tree;
  NodeType get type => _node.type;
  String get name => _node.name;
  int get from => _node.from;
  int get to => _node.to;

  bool _yield(SyntaxNode? next) {
    if (next == null) return false;
    _node = next;
    return true;
  }

  bool firstChild() => _yield(_node.firstChild);
  bool lastChild() => _yield(_node.lastChild);
  bool childAfter(int pos) => _yield(_node.childAfter(pos));
  bool childBefore(int pos) => _yield(_node.childBefore(pos));
  bool enter(int pos, int side) => _yield(_node.enter(pos, side));
  bool parent() => _yield(_node.parent);
  bool nextSibling() => _yield(_node.nextSibling);
  bool prevSibling() => _yield(_node.prevSibling);

  /// `TreeCursor.next`: on to the next node in document order, a node's children first unless [enter] is false.
  /// False, with the cursor where it was, at the last node.
  bool next([bool enter = true]) => _move(1, enter);

  /// `TreeCursor.prev`: the same walk backwards.
  bool prev([bool enter = true]) => _move(-1, enter);

  bool _move(int dir, bool enter) {
    if (enter && (dir > 0 ? firstChild() : lastChild())) return true;
    for (SyntaxNode? at = _node; at != null; at = at.parent) {
      final sibling = dir > 0 ? at.nextSibling : at.prevSibling;
      if (sibling != null) {
        _node = sibling;
        return true;
      }
    }
    return false;
  }

  /// `TreeCursor.moveTo`: to the innermost node around [pos].
  TreeCursor moveTo(int pos, [int side = 0]) {
    _node = _resolveNode(_node, pos, side);
    return this;
  }
}

/// Lezer's `ChangedRange`: `fromA`..`toA` of the old document became `fromB`..`toB` of the new one.
class ChangedRange {
  const ChangedRange(this.fromA, this.toA, this.fromB, this.toB);

  /// The one range that covers every difference between [before] and [after]: what they share at the start and at
  /// the end is left out. Null when they are the same text. For a caller with no change set to hand.
  static ChangedRange? between(String before, String after) {
    final shortest = before.length < after.length ? before.length : after.length;
    var start = 0;
    while (start < shortest && before.codeUnitAt(start) == after.codeUnitAt(start)) {
      start++;
    }
    if (start == before.length && start == after.length) return null;
    var endA = before.length, endB = after.length;
    while (endA > start && endB > start && before.codeUnitAt(endA - 1) == after.codeUnitAt(endB - 1)) {
      endA--;
      endB--;
    }
    return ChangedRange(start, endA, start, endB);
  }

  final int fromA, toA, fromB, toB;

  @override
  String toString() => 'ChangedRange($fromA-$toA -> $fromB-$toB)';
}

/// Lezer's `TreeFragment`: a stretch of the **new** document, [from]..[to], that an old [tree] still describes.
/// Add [offset] to a document position to get the position in that tree.
class TreeFragment {
  const TreeFragment(this.from, this.to, this.tree, this.offset, {this.openStart = false, this.openEnd = false});

  final int from, to;
  final Tree tree;
  final int offset;

  /// Whether the fragment starts where a change ended, rather than where a parse started.
  final bool openStart;

  /// Whether it ends where a change starts, rather than at the end of a whole parse.
  final bool openEnd;

  /// `TreeFragment.addTree`: the fragments a freshly parsed [tree] gives, in front of those of [fragments] that
  /// reach beyond it.
  static List<TreeFragment> addTree(Tree tree, [List<TreeFragment> fragments = const [], bool partial = false]) {
    return [
      TreeFragment(0, tree.length, tree, 0, openEnd: partial),
      for (final fragment in fragments)
        if (fragment.to > tree.length) fragment,
    ];
  }

  /// `TreeFragment.applyChanges`: [fragments] with the changed ranges cut out of them and what follows a change
  /// moved by its size. [changes] are in order. A stretch between two changes shorter than [minGap] is dropped.
  static List<TreeFragment> applyChanges(
    List<TreeFragment> fragments,
    List<ChangedRange> changes, [
    int minGap = 128,
  ]) {
    if (changes.isEmpty) return fragments;
    final result = <TreeFragment>[];
    var fI = 1;
    var nextF = fragments.isNotEmpty ? fragments[0] : null;
    for (var cI = 0, pos = 0, off = 0; ; cI++) {
      final nextC = cI < changes.length ? changes[cI] : null;
      final nextPos = nextC != null ? nextC.fromA : 1000000000;
      if (nextPos - pos >= minGap) {
        while (nextF != null && nextF.from < nextPos) {
          TreeFragment? cut = nextF;
          if (pos >= cut.from || nextPos <= cut.to || off != 0) {
            final fFrom = (cut.from > pos ? cut.from : pos) - off, fTo = (cut.to < nextPos ? cut.to : nextPos) - off;
            cut = fFrom >= fTo
                ? null
                : TreeFragment(fFrom, fTo, cut.tree, cut.offset + off, openStart: cI > 0, openEnd: nextC != null);
          }
          if (cut != null) result.add(cut);
          if (nextF.to > nextPos) break;
          nextF = fI < fragments.length ? fragments[fI++] : null;
        }
      }
      if (nextC == null) break;
      pos = nextC.toA;
      off = nextC.toA - nextC.toB;
    }
    return result;
  }
}
