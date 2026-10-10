// Ported from @lezer/lr 1.4.10 (src/stack.ts, src/token.ts, src/parse.ts, src/decode.ts), which is:
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

/// Lezer's LR parser: what runs a grammar's tables over a block of code. The web app colours a fenced block with
/// the grammar of its language (`@codemirror/language-data`, which for the common languages is a Lezer grammar);
/// the port runs the same tables (`../grammars/*.g.dart`, copied by tool/code_grammars.mjs) with the same
/// algorithm, so the nodes it finds, and so the colours, are the web's. This is the algorithm: the stack and its
/// reductions, the token cache, error recovery by insertion and deletion, the split stacks of an ambiguous
/// grammar, dialects and context trackers.
///
/// What is the same as Lezer: every decision the parse makes. Kept line for line where it could be, the names
/// too, so the two can be read side by side.
///
/// What differs:
/// - The input is one string, where Lezer reads chunks through ranges with gaps (a block inside a list item is
///   handed over with its indentation already taken off: `../blocks.dart`).
/// - A parse does not build a `Tree`. It ends as the flat record Lezer builds its tree from (four numbers a node:
///   type, start, end, and how much of the record before it is inside it), which is all a highlighter needs:
///   `../highlight.dart` reads it backwards, as `Tree.build` does, over only the lines it is asked for.
/// - Nothing is reused from an earlier tree (`FragmentCursor`, `Stack.useNode`). What a keystroke costs is kept
///   down another way: a parse leaves [Checkpoint]s as it goes, and a block that changed is parsed again from the
///   last one before the change ([Parse.resume]). A checkpoint is `Stack.split`, Lezer's own way of letting two
///   parses share the record behind them.
/// - A parse that has not reached the end can still be read ([Parse.snapshot]): a copy of its best stack is
///   reduced to the top, as Lezer does at `stopAt`, and the parse itself goes on from where it was.
library;

import 'dart:typed_data';

// Action flags and sizes, as Lezer's constants.ts names them.
const int _reduceFlag = 1 << 16;
const int _valueMask = 65535;
const int _reduceDepthShift = 19;
const int _repeatFlag = 1 << 17;
const int _gotoFlag = 1 << 17;
const int _stayFlag = 1 << 18;

const int _stateFlagSkipped = 1;
const int _stateFlagAccepting = 2;

// ParseState slots.
const int _slotFlags = 0, _slotActions = 1, _slotSkip = 2, _slotTokenizerMask = 3, _slotDefaultReduce = 4, _slotForcedReduce = 5, _stateSize = 6;

const int _seqEnd = 0xffff, _seqNext = 1, _seqOther = 2;

const int _termErr = 0;

const int _lookaheadMargin = 25;

// Recover.
const int _recoverInsert = 200, _recoverDelete = 190, _recoverReduce = 100, _recoverMaxNext = 4;
const int _recoverMaxInsertStackDepth = 300, _recoverDampenInsertStackDepth = 120, _recoverMinBigReduction = 2000;

// Rec.
const int _recDistance = 5, _recMaxRemainingPerStep = 3, _recMinBufferLengthPrune = 500, _recForceReduceLimit = 10;
const int _recCutDepth = 2800 * 3, _recCutTo = 2000 * 3, _recMaxLeftAssociativeReductionCount = 300, _recMaxStackCount = 12;

/// A node's rule for the highlighter: the class its tags have in glyphHighlight.ts, how it reaches the nodes
/// inside ([mode]: 0 opaque, the node is one run whatever is in it; 1 inherit, the class goes down; 2 normal, the
/// class is the node's own words only), and the parents it asks for, nearest last, an empty name any parent
/// (@lezer/highlight `Rule`).
class StyleRule {
  const StyleRule(this.cls, this.mode, [this.context]);

  final String cls;
  final int mode;
  final List<String>? context;
}

/// One of a grammar's tokenizers, as its file lists them: a group of the grammar's own token table, a table of
/// its own, or a function written by hand, named for the Dart beside the grammar to supply.
class TokenizerSpec {
  const TokenizerSpec.group(int this.group) : local = null, precTable = 0, elseToken = null, external = null;
  const TokenizerSpec.local(String this.local, this.precTable, this.elseToken) : group = null, external = null;
  const TokenizerSpec.external(String this.external) : group = null, local = null, precTable = 0, elseToken = null;

  final int? group;
  final String? local;
  final int precTable;
  final int? elseToken;
  final String? external;
}

/// A token whose text decides what it is: by a table of words, or by a function written by hand.
class SpecializerSpec {
  const SpecializerSpec.table(this.term, Map<String, int> this.table) : external = null, extend = false;
  const SpecializerSpec.external(this.term, String this.external, {this.extend = false}) : table = null;

  final int term;
  final Map<String, int>? table;
  final String? external;
  final bool extend;
}

/// What `LRParser.deserialize` is given: a grammar as lezer-generator writes it.
class LRParserSpec {
  const LRParserSpec({
    required this.states,
    required this.stateData,
    required this.goto,
    required this.nodeNames,
    required this.maxTerm,
    required this.context,
    required this.skippedNodes,
    required this.repeatNodeCount,
    required this.tokenData,
    required this.tokenizers,
    required this.topRules,
    required this.dialects,
    required this.dynamicPrecedences,
    required this.specialized,
    required this.tokenPrec,
    required this.rules,
  });

  final String states, stateData, goto, nodeNames, tokenData;
  final int maxTerm;
  final String? context;
  final List<int> skippedNodes;
  final int repeatNodeCount;
  final List<TokenizerSpec> tokenizers;
  final Map<String, (int, int)> topRules;
  final Map<String, int> dialects;
  final Map<int, int> dynamicPrecedences;
  final List<SpecializerSpec> specialized;
  final int tokenPrec;
  final Map<int, List<StyleRule>> rules;
}

/// `decodeArray`: a table from the string lezer-generator packs it into.
List<int> decodeArray(String input, {bool wide = false}) {
  List<int>? array;
  var out = 0;
  for (var pos = 0; pos < input.length;) {
    var value = 0;
    for (;;) {
      var next = input.codeUnitAt(pos++);
      var stop = false;
      if (next == 126 /* Encode.BigValCode */ ) {
        value = 65535;
        break;
      }
      if (next >= 92 /* Encode.Gap2 */ ) next--;
      if (next >= 34 /* Encode.Gap1 */ ) next--;
      var digit = next - 32;
      if (digit >= 46 /* Encode.Base */ ) {
        digit -= 46;
        stop = true;
      }
      value += digit;
      if (stop) break;
      value *= 46;
    }
    if (array != null) {
      array[out++] = value;
    } else {
      array = wide ? Uint32List(value) : Uint16List(value);
    }
  }
  return array ?? Uint16List(0);
}

int _pair(List<int> data, int off) => data[off] | (data[off + 1] << 16);

// ---- Tokens ---------------------------------------------------------------------------------------------------------

class CachedToken {
  int start = -1;
  int value = -1;
  int end = -1;
  int extended = -1;
  int lookAhead = 0;
  int mask = 0;
  int context = 0;
}

final CachedToken _nullToken = CachedToken();

/// What a tokenizer reads the code through: the character at the position ([next], -1 at the end), a look ahead
/// or behind ([peek]), a step ([advance]), and the token it settles on ([acceptToken]).
class InputStream {
  InputStream(this.input) : end = input.length {
    _readNext();
  }

  final String input;
  final int end;

  /// The character at [pos], or -1 at the end of the code.
  int next = -1;
  int pos = 0;
  CachedToken token = _nullToken;

  /// `resolveOffset`: the position `offset` characters from here, or -1 where there is none.
  int _resolveOffset(int offset, int assoc) {
    final at = pos + offset;
    if (at < 0) return -1;
    if (assoc < 0 ? at > end : at >= end) return -1;
    return at;
  }

  int clipPos(int at) => at < end ? (at < 0 ? 0 : at) : end;

  /// The character `offset` from the current one: 0 is [next], -1 the one before.
  int peek(int offset) {
    final at = pos + offset;
    if (at < 0 || at >= end) return -1;
    if (at >= token.lookAhead) token.lookAhead = at + 1;
    return input.codeUnitAt(at);
  }

  /// Settles on `token`, ending `endOffset` characters from the current position.
  void acceptToken(int token, [int endOffset = 0]) {
    final at = endOffset != 0 ? _resolveOffset(endOffset, -1) : pos;
    if (at < 0 || at < this.token.start) throw RangeError('Token end out of bounds');
    this.token.value = token;
    this.token.end = at;
  }

  void acceptTokenTo(int token, int endPos) {
    this.token.value = token;
    this.token.end = endPos;
  }

  int _readNext() => next = pos < end ? input.codeUnitAt(pos) : -1;

  int advance([int n = 1]) {
    if (pos + n >= end) {
      pos = end;
      return next = -1;
    }
    pos += n;
    if (pos >= token.lookAhead) token.lookAhead = pos + 1;
    return _readNext();
  }

  InputStream reset(int at, [CachedToken? token]) {
    if (token != null) {
      this.token = token;
      token.start = at;
      token.lookAhead = at + 1;
      token.value = token.extended = -1;
    } else {
      this.token = _nullToken;
    }
    if (pos != at) {
      pos = at > end ? end : at;
      _readNext();
    }
    return this;
  }

  String read(int from, int to) => input.substring(from, to > end ? end : to);
}

/// One of the parser's ways of reading a token.
abstract class Tokenizer {
  bool get contextual;
  bool get fallback;
  bool get extend;
  void token(InputStream input, Stack stack);
}

class TokenGroup implements Tokenizer {
  TokenGroup(this.data, this.id);

  final List<int> data;
  final int id;

  @override
  bool get contextual => false;
  @override
  bool get fallback => false;
  @override
  bool get extend => false;

  @override
  void token(InputStream input, Stack stack) {
    final parser = stack.p.parser;
    _readToken(data, input, stack, id, parser.data, parser.tokenPrecTable);
  }
}

class LocalTokenGroup implements Tokenizer {
  LocalTokenGroup(String data, this.precTable, this.elseToken) : data = decodeArray(data);

  final List<int> data;
  final int precTable;
  final int? elseToken;

  @override
  bool get contextual => false;
  @override
  bool get fallback => false;
  @override
  bool get extend => false;

  @override
  void token(InputStream input, Stack stack) {
    final start = input.pos;
    var skipped = 0;
    for (;;) {
      final atEof = input.next < 0, nextPos = input._resolveOffset(1, 1);
      _readToken(data, input, stack, 0, data, precTable);
      if (input.token.value > -1) break;
      if (elseToken == null) return;
      if (!atEof) skipped++;
      if (nextPos < 0) break;
      input.reset(nextPos, input.token);
    }
    if (skipped != 0) {
      input.reset(start, input.token);
      input.acceptToken(elseToken!, skipped);
    }
  }
}

/// A tokenizer written by hand, for what a grammar's own token table cannot say.
class ExternalTokenizer implements Tokenizer {
  ExternalTokenizer(this._token, {this.contextual = false, this.fallback = false, this.extend = false});

  final void Function(InputStream input, Stack stack) _token;

  @override
  final bool contextual;
  @override
  final bool fallback;
  @override
  final bool extend;

  @override
  void token(InputStream input, Stack stack) => _token(input, stack);
}

void _readToken(List<int> data, InputStream input, Stack stack, int group, List<int> precTable, int precOffset) {
  var state = 0;
  final groupMask = 1 << group, dialect = stack.p.parser.dialect;
  scan:
  for (;;) {
    if ((groupMask & data[state]) == 0) break;
    final accEnd = data[state + 1];
    // Check whether this state can lead to a token in the current group. Accept tokens in this state, possibly
    // overwriting lower-precedence / shorter tokens.
    for (var i = state + 3; i < accEnd; i += 2) {
      if ((data[i + 1] & groupMask) > 0) {
        final term = data[i];
        if (dialect.allows(term) && (input.token.value == -1 || input.token.value == term || _overrides(term, input.token.value, precTable, precOffset))) {
          input.acceptToken(term);
          break;
        }
      }
    }
    final next = input.next;
    var low = 0, high = data[state + 2];
    // Special case for EOF.
    if (input.next < 0 && high > low && data[accEnd + high * 3 - 3] == _seqEnd) {
      state = data[accEnd + high * 3 - 1];
      continue scan;
    }
    // Do a binary search on the state's edges.
    for (; low < high;) {
      final mid = (low + high) >> 1;
      final index = accEnd + mid + (mid << 1);
      final from = data[index];
      var to = data[index + 1];
      if (to == 0) to = 0x10000;
      if (next < from) {
        high = mid;
      } else if (next >= to) {
        low = mid + 1;
      } else {
        state = data[index + 2];
        input.advance();
        continue scan;
      }
    }
    break;
  }
}

int _findOffset(List<int> data, int start, int term) {
  for (var i = start;; i++) {
    final next = data[i];
    if (next == _seqEnd) return -1;
    if (next == term) return i - start;
  }
}

bool _overrides(int token, int prev, List<int> tableData, int tableOffset) {
  final iPrev = _findOffset(tableData, tableOffset, prev);
  return iPrev < 0 || _findOffset(tableData, tableOffset, token) < iPrev;
}

// ---- Context --------------------------------------------------------------------------------------------------------

/// What a grammar keeps beside the stack as it parses (whether a newline was passed, how deep the indentation
/// is, which element is open) for its tokenizers to read. A context is never changed in place: two stacks may
/// hold the same one.
class ContextTracker {
  const ContextTracker({required this.start, this.shift, this.reduce, this.hash, this.strict = true});

  final Object? start;
  final Object? Function(Object? context, int term, Stack stack, InputStream input)? shift;
  final Object? Function(Object? context, int term, Stack stack, InputStream input)? reduce;
  final int Function(Object? context)? hash;
  final bool strict;
}

class _StackContext {
  _StackContext(this.tracker, this.context) : hash = tracker.strict ? (tracker.hash?.call(context) ?? 0) : 0;

  final ContextTracker tracker;
  final Object? context;
  final int hash;
}

// ---- The stack ------------------------------------------------------------------------------------------------------

/// A parse stack: the states entered and not yet reduced, and the record of the nodes made so far. Several are
/// alive at once where the grammar is ambiguous or the parse is recovering from an error.
class Stack {
  Stack._(this.p, this.stack, this.state, this.reducePos, this.pos, this.score, this.buffer, this.bufferBase, this._curContext, this.lookAhead, this.parent);

  factory Stack._start(Parse p, int state, [int pos = 0]) {
    final cx = p.parser.context;
    return Stack._(p, <int>[], state, pos, pos, 0, <int>[], 0, cx != null ? _StackContext(cx, cx.start) : null, 0, null);
  }

  /// The parse this stack is part of.
  Parse p;

  /// Three numbers for each state entered: the state, where in the code it was entered, and how long the record
  /// was then.
  List<int> stack;
  int state;
  int reducePos;

  /// How far into the code the stack has read.
  int pos;
  int score;

  /// The record: four numbers a node, a node after the nodes inside it. A split stack shares the record before
  /// [bufferBase] with its [parent].
  List<int> buffer;
  int bufferBase;
  _StackContext? _curContext;
  int lookAhead;
  Stack? parent;

  /// How much of this stack's own record a checkpoint has moved behind it. Lezer chooses between two stacks that
  /// are otherwise even by the length of each one's own record, and a checkpoint must not change the choice.
  int _extra = 0;

  /// The length Lezer would find this stack's own record to be.
  int get _ownLength => buffer.length + _extra;

  /// A split that goes on in this stack's place: what it leaves behind it still counts as its own.
  Stack _carryOn() {
    final next = _split();
    return next.._extra = _extra + buffer.length - next.buffer.length;
  }

  /// The grammar's context here: what its [ContextTracker] has made of the tokens so far.
  Object? get context => _curContext?.context;

  void _pushState(int state, int start) {
    stack
      ..add(this.state)
      ..add(start)
      ..add(bufferBase + buffer.length);
    this.state = state;
  }

  void _reduce(int action) {
    final depth = action >> _reduceDepthShift, type = action & _valueMask;
    final parser = p.parser;
    final lookaheadRecord = reducePos < pos - _lookaheadMargin && _setLookAhead(pos);
    final dPrec = parser.dynamicPrecedence(type);
    if (dPrec != 0) score += dPrec;
    if (depth == 0) {
      // Zero-depth reductions are a special case: they add stuff to the stack without popping anything off.
      if (type < parser.minRepeatTerm && reducePos < pos) reducePos = pos;
      _pushState(parser.getGoto(state, type, true), reducePos);
      if (type < parser.minRepeatTerm) _storeNode(type, reducePos, reducePos, lookaheadRecord ? 8 : 4, true);
      _reduceContext(type, reducePos);
      return;
    }
    // Find the base index into `stack`, content after which will be dropped. Note that with `StayFlag`
    // reductions we need to consume two extra frames (the dummy parent node for the skipped expression and the
    // state that we'll be staying in, which should be moved to `state`).
    final base = stack.length - ((depth - 1) * 3) - ((action & _stayFlag) != 0 ? 6 : 0);
    final start = base != 0 ? stack[base - 2] : 0;
    if (type < parser.minRepeatTerm && start == reducePos && reducePos < pos) reducePos = pos;
    final size = reducePos - start;
    // This is a kludge to try and detect overly deep left-associative trees, which will not increase the parse
    // stack depth and thus won't be caught by the regular stack-depth limit check.
    if (size >= _recoverMinBigReduction && (type < parser.minRepeatTerm || type > parser.maxNode)) {
      if (start == p._lastBigReductionStart) {
        p._bigReductionCount++;
        p._lastBigReductionSize = size;
      } else if (p._lastBigReductionSize < size) {
        p._bigReductionCount = 1;
        p._lastBigReductionStart = start;
        p._lastBigReductionSize = size;
      }
    }
    final baseBuffer = base != 0 ? stack[base - 1] : 0, count = bufferBase + buffer.length - baseBuffer;
    // Store normal terms or `R -> R R` repeat reductions.
    if (type < parser.minRepeatTerm || (action & _repeatFlag) != 0) {
      final at = parser.stateFlag(state, _stateFlagSkipped) ? pos : reducePos;
      _storeNode(type, start, at, count + 4, true);
    }
    if ((action & _stayFlag) != 0) {
      state = stack[base];
    } else {
      final baseStateID = stack[base - 3];
      state = parser.getGoto(baseStateID, type, true);
    }
    stack.length = base;
    _reduceContext(type, start);
  }

  void _storeNode(int term, int start, int end, [int size = 4, bool mustSink = false]) {
    if (term == _termErr && (stack.isEmpty || stack[stack.length - 1] < buffer.length + bufferBase)) {
      // Try to omit/merge adjacent error nodes.
      final top = buffer.length;
      if (top > 0 && buffer[top - 4] == _termErr && buffer[top - 1] > -1) {
        if (start == end) return;
        if (buffer[top - 2] >= start) {
          buffer[top - 2] = end;
          return;
        }
      }
    }
    if (!mustSink || pos == end) {
      // Simple case, just append.
      buffer
        ..add(term)
        ..add(start)
        ..add(end)
        ..add(size);
    } else {
      // There may be skipped nodes that have to be moved forward.
      var index = buffer.length;
      buffer
        ..add(0)
        ..add(0)
        ..add(0)
        ..add(0);
      if (index > 0 && (buffer[index - 4] != _termErr || buffer[index - 1] < 0)) {
        var mustMove = false;
        for (var scan = index; scan > 0 && buffer[scan - 2] > end; scan -= 4) {
          if (buffer[scan - 1] >= 0) {
            mustMove = true;
            break;
          }
        }
        if (mustMove) {
          while (index > 0 && buffer[index - 2] > end) {
            // Move this record forward.
            buffer[index] = buffer[index - 4];
            buffer[index + 1] = buffer[index - 3];
            buffer[index + 2] = buffer[index - 2];
            buffer[index + 3] = buffer[index - 1];
            index -= 4;
            if (size > 4) size -= 4;
          }
        }
      }
      buffer[index] = term;
      buffer[index + 1] = start;
      buffer[index + 2] = end;
      buffer[index + 3] = size;
    }
  }

  void _shift(int action, int type, int start, int end) {
    if ((action & _gotoFlag) != 0) {
      _pushState(action & _valueMask, pos);
    } else if ((action & _stayFlag) == 0) {
      // Regular shift.
      final nextState = action, parser = p.parser;
      pos = end;
      final skipped = parser.stateFlag(nextState, _stateFlagSkipped);
      if (!skipped && (end > start || type <= parser.maxNode)) reducePos = end;
      _pushState(nextState, skipped ? start : (start < reducePos ? start : reducePos));
      _shiftContext(type, start);
      if (type <= parser.maxNode) {
        buffer
          ..add(type)
          ..add(start)
          ..add(end)
          ..add(4);
      }
    } else {
      // Shift-and-stay, which means this is a skipped token.
      pos = end;
      _shiftContext(type, start);
      if (type <= p.parser.maxNode) {
        buffer
          ..add(type)
          ..add(start)
          ..add(end)
          ..add(4);
      }
    }
  }

  void _apply(int action, int next, int nextStart, int nextEnd) {
    if ((action & _reduceFlag) != 0) {
      _reduce(action);
    } else {
      _shift(action, next, nextStart, nextEnd);
    }
  }

  /// A copy that goes its own way from here, sharing the record already settled with this one.
  Stack _split() {
    Stack? parent = this;
    var off = buffer.length;
    // Because the top of the buffer (after this.pos) may be mutated to reorder reductions and skipped tokens, and
    // shared buffers should be immutable, this copies any outstanding skipped tokens to the new buffer, and puts
    // the base pointer before them.
    if (off > 0 && buffer[off - 4] == _termErr) off -= 4;
    while (off > 0 && buffer[off - 2] > reducePos) {
      off -= 4;
    }
    final copy = buffer.sublist(off), base = bufferBase + off;
    // Make sure parent points to an actual parent with content, if there is such a parent.
    while (parent != null && base == parent.bufferBase) {
      parent = parent.parent;
    }
    return Stack._(p, List<int>.of(stack), state, reducePos, pos, score, copy, base, _curContext, lookAhead, parent);
  }

  void _recoverByDelete(int next, int nextEnd) {
    final isNode = next <= p.parser.maxNode;
    if (isNode) _storeNode(next, pos, nextEnd, 4);
    _storeNode(_termErr, pos, nextEnd, isNode ? 8 : 4);
    pos = reducePos = nextEnd;
    score -= _recoverDelete;
  }

  /// Whether the parser could take the token `term` here, after whatever reductions it would do first. For a
  /// tokenizer that has to choose between two readings of the same characters.
  bool canShift(int term) {
    final parser = p.parser;
    for (final sim = _SimulatedStack(this);;) {
      var action = parser.stateSlot(sim.state, _slotDefaultReduce);
      if (action == 0) action = parser.hasAction(sim.state, term);
      if (action == 0) return false;
      if ((action & _reduceFlag) == 0) return true;
      sim.reduce(action);
    }
  }

  List<Stack> _recoverByInsert(int next) {
    if (stack.length >= _recoverMaxInsertStackDepth) return const <Stack>[];
    var nextStates = p.parser.nextStates(state);
    if (nextStates.length > _recoverMaxNext << 1 || stack.length >= _recoverDampenInsertStackDepth) {
      final best = <int>[];
      for (var i = 0; i < nextStates.length; i += 2) {
        final s = nextStates[i + 1];
        if (s != state && p.parser.hasAction(s, next) != 0) {
          best
            ..add(nextStates[i])
            ..add(s);
        }
      }
      if (stack.length < _recoverDampenInsertStackDepth) {
        for (var i = 0; best.length < _recoverMaxNext << 1 && i < nextStates.length; i += 2) {
          final s = nextStates[i + 1];
          var has = false;
          for (var j = 1; j < best.length; j += 2) {
            if (best[j] == s) has = true;
          }
          if (!has) {
            best
              ..add(nextStates[i])
              ..add(s);
          }
        }
      }
      nextStates = best;
    }
    final result = <Stack>[];
    for (var i = 0; i < nextStates.length && result.length < _recoverMaxNext; i += 2) {
      final s = nextStates[i + 1];
      if (s == state) continue;
      final stack = _split();
      stack._pushState(s, pos);
      stack._storeNode(_termErr, stack.pos, stack.pos, 4, true);
      stack._shiftContext(nextStates[i], pos);
      stack.reducePos = pos;
      stack.score -= _recoverInsert;
      result.add(stack);
    }
    return result;
  }

  bool _forceReduce() {
    final parser = p.parser;
    var reduce = parser.stateSlot(state, _slotForcedReduce);
    if ((reduce & _reduceFlag) == 0) return false;
    if (!parser.validAction(state, reduce)) {
      final depth = reduce >> _reduceDepthShift, term = reduce & _valueMask;
      final target = stack.length - depth * 3;
      if (target < 0 || parser.getGoto(stack[target], term, false) < 0) {
        final backup = _findForcedReduction();
        if (backup == null) return false;
        reduce = backup;
      }
      _storeNode(_termErr, pos, pos, 4, true);
      score -= _recoverReduce;
    }
    reducePos = pos;
    _reduce(reduce);
    return true;
  }

  /// Try to scan through the automaton to find some kind of reduction that can be applied. Used when the regular
  /// ForcedReduce field isn't a valid action.
  int? _findForcedReduction() {
    final parser = p.parser, seen = <int>[];
    int? explore(int state, int depth) {
      if (seen.contains(state)) return null;
      seen.add(state);
      return parser.allActions<int>(state, (action) {
        if ((action & (_stayFlag | _gotoFlag)) != 0) {
          return null;
        } else if ((action & _reduceFlag) != 0) {
          final rDepth = (action >> _reduceDepthShift) - depth;
          if (rDepth > 1) {
            final term = action & _valueMask, target = stack.length - rDepth * 3;
            if (target >= 0 && parser.getGoto(stack[target], term, false) >= 0) return (rDepth << _reduceDepthShift) | _reduceFlag | term;
          }
          return null;
        } else {
          return explore(action, depth + 1);
        }
      });
    }

    return explore(state, 0);
  }

  Stack _forceAll() {
    while (!p.parser.stateFlag(state, _stateFlagAccepting)) {
      if (!_forceReduce()) {
        _storeNode(_termErr, pos, pos, 4, true);
        break;
      }
    }
    return this;
  }

  /// Check whether this state has no further actions (assumed to be a direct descendant of the top state, since
  /// any other states must be able to continue somehow).
  bool get _deadEnd {
    if (stack.length != 3) return false;
    final parser = p.parser;
    return parser.data[parser.stateSlot(state, _slotActions)] == _seqEnd && parser.stateSlot(state, _slotDefaultReduce) == 0;
  }

  void _restart() {
    _storeNode(_termErr, pos, pos, 4, true);
    state = stack[0];
    stack.length = 0;
  }

  bool _sameState(Stack other) {
    if (state != other.state || stack.length != other.stack.length) return false;
    for (var i = 0; i < stack.length; i += 3) {
      if (stack[i] != other.stack[i]) return false;
    }
    return true;
  }

  /// Whether the dialect numbered `dialectID` in the grammar is switched on in this parse.
  bool dialectEnabled(int dialectID) => p.parser.dialect.flags[dialectID];

  void _shiftContext(int term, int start) {
    final cx = _curContext;
    if (cx != null && cx.tracker.shift != null) _updateContext(cx.tracker.shift!(cx.context, term, this, p.stream.reset(start)));
  }

  void _reduceContext(int term, int start) {
    final cx = _curContext;
    if (cx != null && cx.tracker.reduce != null) _updateContext(cx.tracker.reduce!(cx.context, term, this, p.stream.reset(start)));
  }

  void _emitContext() {
    final last = buffer.length - 1;
    if (last < 0 || buffer[last] != -3) {
      buffer
        ..add(_curContext!.hash)
        ..add(pos)
        ..add(pos)
        ..add(-3);
    }
  }

  void _emitLookAhead() {
    final last = buffer.length - 1;
    if (last < 0 || buffer[last] != -4) {
      buffer
        ..add(lookAhead)
        ..add(pos)
        ..add(pos)
        ..add(-4);
    }
  }

  void _updateContext(Object? context) {
    final cx = _curContext!;
    if (context != cx.context) {
      final newCx = _StackContext(cx.tracker, context);
      if (newCx.hash != cx.hash) _emitContext();
      _curContext = newCx;
    }
  }

  bool _setLookAhead(int lookAhead) {
    if (lookAhead <= this.lookAhead) return false;
    _emitLookAhead();
    this.lookAhead = lookAhead;
    return true;
  }

  void _close() {
    if (_curContext != null && _curContext!.tracker.strict) _emitContext();
    if (lookAhead > 0) _emitLookAhead();
  }
}

// Used to cheaply run some reductions to scan ahead without mutating an entire stack.
class _SimulatedStack {
  _SimulatedStack(this.start) : state = start.state, stack = start.stack, base = start.stack.length;

  final Stack start;
  int state;
  List<int> stack;
  int base;

  void reduce(int action) {
    final term = action & _valueMask, depth = action >> _reduceDepthShift;
    if (depth == 0) {
      if (identical(stack, start.stack)) stack = List<int>.of(stack);
      stack
        ..add(state)
        ..add(0)
        ..add(0);
      base += 3;
    } else {
      base -= (depth - 1) * 3;
    }
    state = start.p.parser.getGoto(stack[base - 3], term, true);
  }
}

// ---- The token cache ------------------------------------------------------------------------------------------------

class _TokenCache {
  _TokenCache(LRParser parser, this.stream) : tokens = <CachedToken>[for (var i = 0; i < parser.tokenizers.length; i++) CachedToken()];

  final InputStream stream;
  final List<CachedToken> tokens;
  CachedToken? mainToken;
  List<int> actions = <int>[];
  int _actionCount = 0;

  List<int> getActions(Stack stack) {
    var actionIndex = 0;
    CachedToken? main;
    final parser = stack.p.parser, tokenizers = parser.tokenizers;
    final mask = parser.stateSlot(stack.state, _slotTokenizerMask);
    final context = stack._curContext?.hash ?? 0;
    var lookAhead = 0;
    for (var i = 0; i < tokenizers.length; i++) {
      if (((1 << i) & mask) == 0) continue;
      final tokenizer = tokenizers[i], token = tokens[i];
      if (main != null && !tokenizer.fallback) continue;
      if (tokenizer.contextual || token.start != stack.pos || token.mask != mask || token.context != context) {
        _updateCachedToken(token, tokenizer, stack);
        token.mask = mask;
        token.context = context;
      }
      if (token.lookAhead > token.end + _lookaheadMargin && token.lookAhead > lookAhead) lookAhead = token.lookAhead;
      if (token.value != _termErr) {
        final startIndex = actionIndex;
        if (token.extended > -1) actionIndex = _addActions(stack, token.extended, token.end, actionIndex);
        actionIndex = _addActions(stack, token.value, token.end, actionIndex);
        if (!tokenizer.extend) {
          main = token;
          if (actionIndex > startIndex) break;
        }
      }
    }
    _actionCount = actionIndex;
    if (lookAhead != 0) stack._setLookAhead(lookAhead);
    if (main == null && stack.pos == stream.end) {
      main = CachedToken()
        ..value = stack.p.parser.eofTerm
        ..start = stack.pos
        ..end = stack.pos;
      actionIndex = _addActions(stack, main.value, main.end, actionIndex);
      _actionCount = actionIndex;
    }
    mainToken = main;
    return actions;
  }

  /// How many numbers of [actions] the last [getActions] filled: three for each action.
  int get actionCount => _actionCount;

  CachedToken getMainToken(Stack stack) {
    if (mainToken != null) return mainToken!;
    final main = CachedToken(), pos = stack.pos, p = stack.p;
    main.start = pos;
    main.end = pos + 1 < p.stream.end ? pos + 1 : p.stream.end;
    main.value = pos == p.stream.end ? p.parser.eofTerm : _termErr;
    return main;
  }

  void _updateCachedToken(CachedToken token, Tokenizer tokenizer, Stack stack) {
    final start = stream.clipPos(stack.pos);
    tokenizer.token(stream.reset(start, token), stack);
    if (token.value > -1) {
      final parser = stack.p.parser;
      for (var i = 0; i < parser.specialized.length; i++) {
        if (parser.specialized[i] == token.value) {
          final result = parser.specializers[i](stream.read(token.start, token.end), stack);
          if (result >= 0 && parser.dialect.allows(result >> 1)) {
            if ((result & 1) == 0 /* Specialize.Specialize */ ) {
              token.value = result >> 1;
            } else {
              token.extended = result >> 1;
            }
            break;
          }
        }
      }
    } else {
      token.value = _termErr;
      token.end = stream.clipPos(start + 1);
    }
  }

  int _putAction(int action, int token, int end, int index) {
    // Don't add duplicate actions.
    for (var i = 0; i < index; i += 3) {
      if (actions[i] == action) return index;
    }
    while (actions.length < index + 3) {
      actions.add(0);
    }
    actions[index++] = action;
    actions[index++] = token;
    actions[index++] = end;
    return index;
  }

  int _addActions(Stack stack, int token, int end, int index) {
    final state = stack.state, parser = stack.p.parser, data = parser.data;
    for (var set = 0; set < 2; set++) {
      for (var i = parser.stateSlot(state, set != 0 ? _slotSkip : _slotActions);; i += 3) {
        if (data[i] == _seqEnd) {
          if (data[i + 1] == _seqNext) {
            i = _pair(data, i + 2);
          } else {
            if (index == 0 && data[i + 1] == _seqOther) index = _putAction(_pair(data, i + 2), token, end, index);
            break;
          }
        }
        if (data[i] == token) index = _putAction(_pair(data, i + 1), token, end, index);
      }
    }
    return index;
  }
}

// ---- The parse ------------------------------------------------------------------------------------------------------

/// A place a parse can be taken up again from: its one stack as it stood at [pos], sharing the record behind it.
class Checkpoint {
  Checkpoint._(this._stack, this.pos, this.safe, this._bigStart, this._bigSize, this._bigCount);

  final Stack _stack;

  // The parse's count of long reductions from one start, as it stood: part of what the parse does next.
  final int _bigStart, _bigSize, _bigCount;

  /// How far the stack had read.
  final int pos;

  /// The code before this position is all the stack ever looked at: a change at or after it leaves the checkpoint
  /// good.
  final int safe;
}

/// What a parse has found so far, to be read by `../highlight.dart`: the record of a stack reduced to the top.
class ParsedCode {
  ParsedCode._(this.parser, this._stack, this.length);

  final LRParser parser;
  final Stack _stack;

  /// How much of the code the record covers, from its start.
  final int length;

  /// A cursor at the end of the record, on its last node (the top one).
  RecordCursor cursor() => RecordCursor._(_stack, _stack.bufferBase + _stack.buffer.length);
}

/// `StackBufferCursor`: reads a stack's record backwards, through the stacks it was split from.
class RecordCursor {
  RecordCursor._(this._stack, this.pos) : _index = pos - _stack.bufferBase, _buffer = _stack.buffer {
    _settle();
  }

  Stack _stack;

  /// Where the cursor is in the whole record: the entry it reads ends here.
  int pos;
  int _index;
  List<int> _buffer;

  void _settle() {
    while (_index <= 0) {
      final next = _stack.parent;
      if (next == null) return;
      _index += _stack.bufferBase - next.bufferBase;
      _stack = next;
      _buffer = next.buffer;
    }
  }

  int get id => _buffer[_index - 4];
  int get start => _buffer[_index - 3];
  int get end => _buffer[_index - 2];
  int get size => _buffer[_index - 1];

  /// To the entry before this one: the last node inside it, or the node before it when it has none.
  void next() {
    _index -= 4;
    pos -= 4;
    if (_index <= 0) _settle();
  }

  /// Another cursor at the same place, to look around with.
  RecordCursor fork() => RecordCursor._(_stack, pos);

  /// To the entry that ends at `to` in the whole record: past everything inside a node.
  void moveTo(int to) {
    _index -= pos - to;
    pos = to;
    if (_index <= 0) _settle();
  }
}

/// One parse of one block of code. [advance] takes it a step; it is done when [advance] answers the record.
class Parse {
  Parse(this.parser, String input) : stream = InputStream(input) {
    _tokens = _TokenCache(parser, stream);
    stacks = <Stack>[Stack._start(this, parser.top.$1, 0)];
  }

  /// A parse of `input` that starts where an earlier parse of a text with the same beginning stood at
  /// `checkpoint`. The text up to [Checkpoint.safe] must be the same in both.
  Parse.resume(this.parser, String input, Checkpoint checkpoint, List<Checkpoint> earlier) : stream = InputStream(input) {
    _tokens = _TokenCache(parser, stream);
    // Every stack kept from the earlier parses is this parse's now, so that none of them holds the parse it was
    // made in, and with it a whole copy of the code as it was then.
    for (final kept in earlier) {
      kept._stack.p = this;
    }
    for (Stack? shared = checkpoint._stack; shared != null; shared = shared.parent) {
      shared.p = this;
    }
    final stack = checkpoint._stack._carryOn();
    stacks = <Stack>[stack];
    _minStackPos = stack.pos;
    checkpoints.addAll(earlier);
    _lastCheckpoint = checkpoint.pos;
    _lastBigReductionStart = checkpoint._bigStart;
    _lastBigReductionSize = checkpoint._bigSize;
    _bigReductionCount = checkpoint._bigCount;
  }

  final LRParser parser;
  final InputStream stream;
  late final _TokenCache _tokens;
  late List<Stack> stacks;
  int _recovering = 0;
  int _minStackPos = 0;
  int _lastBigReductionStart = -1;
  int _lastBigReductionSize = 0;
  int _bigReductionCount = 0;

  /// The places this parse can be taken up again from, in order.
  final List<Checkpoint> checkpoints = <Checkpoint>[];
  int _lastCheckpoint = 0;

  /// How much code there is between one checkpoint and the next, at least.
  static const int checkpointEvery = 1024;

  /// The record when the parse is done.
  ParsedCode? done;

  /// How far every live stack has read.
  int get parsedPos => _minStackPos;

  /// Takes the parse one step: every stack that is furthest behind reads a token. Answers the record when the
  /// end of the code is reached.
  ParsedCode? advance() {
    if (done != null) return done;
    final stacks = this.stacks, pos = _minStackPos;
    // This will hold stacks beyond `pos`.
    final newStacks = this.stacks = <Stack>[];
    List<Stack>? stopped;
    List<int>? stoppedTokens;
    // If a large amount of reductions happened with the same start position, force the stack out of that
    // production in order to avoid creating a tree too deep to recurse through. (This is an ugly kludge, because
    // unfortunately there is no straightforward, cheap way to check for this happening, due to the history of
    // reductions only being available in an expensive-to-access format in the stack buffers.)
    if (_bigReductionCount > _recMaxLeftAssociativeReductionCount && stacks.length == 1) {
      final s = stacks[0];
      while (s._forceReduce() && s.stack.isNotEmpty && s.stack[s.stack.length - 2] >= _lastBigReductionStart) {}
      _bigReductionCount = _lastBigReductionSize = 0;
    }
    // Keep advancing any stacks at `pos` until they either move forward or can't be advanced. Gather stacks that
    // can't be advanced further in `stopped`.
    for (var i = 0; i < stacks.length; i++) {
      final stack = stacks[i];
      for (;;) {
        _tokens.mainToken = null;
        if (stack.pos > pos) {
          newStacks.add(stack);
        } else if (_advanceStack(stack, newStacks, stacks)) {
          continue;
        } else {
          stopped ??= <Stack>[];
          stoppedTokens ??= <int>[];
          stopped.add(stack);
          final tok = _tokens.getMainToken(stack);
          stoppedTokens
            ..add(tok.value)
            ..add(tok.end);
        }
        break;
      }
    }
    if (newStacks.isEmpty) {
      final finished = stopped == null ? null : _findFinished(stopped);
      if (finished != null) return _finish(finished);
      if (_recovering == 0) _recovering = _recDistance;
    }
    if (_recovering != 0 && stopped != null) {
      final finished = _runRecovery(stopped, stoppedTokens!, newStacks);
      if (finished != null) return _finish(finished._forceAll());
    }
    if (_recovering != 0) {
      final maxRemaining = _recovering == 1 ? 1 : _recovering * _recMaxRemainingPerStep;
      if (newStacks.length > maxRemaining) {
        _sortByScore(newStacks);
        newStacks.length = maxRemaining;
      }
      if (newStacks.any((s) => s.reducePos > pos)) _recovering--;
    } else if (newStacks.length > 1) {
      // Prune stacks that are in the same state, or that have been running without splitting for a while, to
      // avoid getting stuck with multiple successful stacks running endlessly on.
      outer:
      for (var i = 0; i < newStacks.length - 1; i++) {
        final stack = newStacks[i];
        for (var j = i + 1; j < newStacks.length; j++) {
          final other = newStacks[j];
          if (stack._sameState(other) || stack._ownLength > _recMinBufferLengthPrune && other._ownLength > _recMinBufferLengthPrune) {
            var order = stack.score - other.score;
            if (order == 0) order = stack._ownLength - other._ownLength;
            if (order > 0) {
              newStacks.removeAt(j--);
            } else {
              newStacks.removeAt(i--);
              continue outer;
            }
          }
        }
      }
      if (newStacks.length > _recMaxStackCount) {
        _sortByScore(newStacks);
        newStacks.length = _recMaxStackCount;
      }
    }
    _minStackPos = newStacks[0].pos;
    for (var i = 1; i < newStacks.length; i++) {
      if (newStacks[i].pos < _minStackPos) _minStackPos = newStacks[i].pos;
    }
    if (newStacks.length == 1 && _recovering == 0 && _minStackPos - _lastCheckpoint >= checkpointEvery) _checkpoint();
    return null;
  }

  /// `Array.prototype.sort` keeps the order of equals, which `List.sort` does not promise: by score, best first.
  static void _sortByScore(List<Stack> stacks) {
    for (var i = 1; i < stacks.length; i++) {
      final stack = stacks[i];
      var j = i - 1;
      while (j >= 0 && stacks[j].score < stack.score) {
        stacks[j + 1] = stacks[j];
        j--;
      }
      stacks[j + 1] = stack;
    }
  }

  /// Leaves a checkpoint at the one live stack. The stack the parse goes on with is a split of it, so what was
  /// recorded up to here is never written to again, and a later parse can stand on it.
  void _checkpoint() {
    final live = stacks[0];
    final kept = live._carryOn();
    stacks[0] = live._carryOn();
    final seen = live.pos + _lookaheadMargin > live.lookAhead ? live.pos + _lookaheadMargin : live.lookAhead;
    checkpoints.add(Checkpoint._(kept, live.pos, seen, _lastBigReductionStart, _lastBigReductionSize, _bigReductionCount));
    _lastCheckpoint = live.pos;
  }

  /// The last checkpoint that a change starting at `changeFrom` leaves good, or null when there is none; with it,
  /// the checkpoints up to it, for the parse resumed there to keep.
  (Checkpoint, List<Checkpoint>)? checkpointBefore(int changeFrom) {
    for (var i = checkpoints.length - 1; i >= 0; i--) {
      if (checkpoints[i].safe <= changeFrom) return (checkpoints[i], checkpoints.sublist(0, i + 1));
    }
    return null;
  }

  ParsedCode _finish(Stack stack) {
    stack._close();
    stacks = <Stack>[];
    return done = ParsedCode._(parser, stack, stack.pos);
  }

  /// What the parse has found up to [parsedPos], while it is still going: a copy of its best stack reduced to the
  /// top, as Lezer ends a parse it was told to stop. The parse is not disturbed.
  ParsedCode snapshot() {
    if (done != null) return done!;
    var best = stacks[0];
    for (final stack in stacks) {
      if (stack.score > best.score) best = stack;
    }
    // Forcing the copy to the top counts its reductions as the parse's own: put the counts back.
    final start = _lastBigReductionStart, size = _lastBigReductionSize, count = _bigReductionCount;
    final copy = best._split().._forceAll();
    _lastBigReductionStart = start;
    _lastBigReductionSize = size;
    _bigReductionCount = count;
    return ParsedCode._(parser, copy, copy.pos);
  }

  bool _advanceStack(Stack stack, List<Stack>? stacks, List<Stack>? split) {
    final start = stack.pos;
    final defaultReduce = parser.stateSlot(stack.state, _slotDefaultReduce);
    if (defaultReduce > 0) {
      stack._reduce(defaultReduce);
      return true;
    }
    if (stack.stack.length >= _recCutDepth) {
      while (stack.stack.length > _recCutTo && stack._forceReduce()) {}
    }
    final actions = _tokens.getActions(stack), count = _tokens.actionCount;
    for (var i = 0; i < count;) {
      final action = actions[i++], term = actions[i++], end = actions[i++];
      final last = i == count || split == null;
      final localStack = last ? stack : stack._split();
      final main = _tokens.mainToken;
      localStack._apply(action, term, main != null ? main.start : localStack.pos, end);
      if (last) {
        return true;
      } else if (localStack.pos > start) {
        stacks!.add(localStack);
      } else {
        split.add(localStack);
      }
    }
    return false;
  }

  // Advance a given stack forward as far as it will go. Returns the (possibly updated) stack if it got stuck, or
  // null if it moved forward and was given to `pushStackDedup`.
  bool _advanceFully(Stack stack, List<Stack> newStacks) {
    final pos = stack.pos;
    for (;;) {
      if (!_advanceStack(stack, null, null)) return false;
      if (stack.pos > pos) {
        _pushStackDedup(stack, newStacks);
        return true;
      }
    }
  }

  Stack? _runRecovery(List<Stack> stacks, List<int> tokens, List<Stack> newStacks) {
    Stack? finished;
    var restarted = false;
    for (var i = 0; i < stacks.length; i++) {
      final stack = stacks[i];
      var token = tokens[i << 1], tokenEnd = tokens[(i << 1) + 1];
      if (stack._deadEnd) {
        if (restarted) continue;
        restarted = true;
        stack._restart();
        final done = _advanceFully(stack, newStacks);
        if (done) continue;
      }
      final force = stack._split();
      for (var j = 0; j < _recForceReduceLimit && force._forceReduce(); j++) {
        final done = _advanceFully(force, newStacks);
        if (done) break;
      }
      for (final insert in stack._recoverByInsert(token)) {
        _advanceFully(insert, newStacks);
      }
      if (stream.end > stack.pos) {
        if (tokenEnd == stack.pos) {
          tokenEnd++;
          token = _termErr;
        }
        stack._recoverByDelete(token, tokenEnd);
        _pushStackDedup(stack, newStacks);
      } else if (finished == null || finished.score < force.score) {
        finished = force;
      }
    }
    return finished;
  }

  Stack? _findFinished(List<Stack> stacks) {
    Stack? best;
    for (final stack in stacks) {
      if (stack.pos == stream.end && parser.stateFlag(stack.state, _stateFlagAccepting) && (best == null || best.score < stack.score)) best = stack;
    }
    return best;
  }
}

void _pushStackDedup(Stack stack, List<Stack> newStacks) {
  for (var i = 0; i < newStacks.length; i++) {
    final other = newStacks[i];
    if (other.pos == stack.pos && other._sameState(stack)) {
      if (newStacks[i].score < stack.score) newStacks[i] = stack;
      return;
    }
  }
  newStacks.add(stack);
}

class Dialect {
  Dialect(this.source, this.flags, this.disabled);

  final String? source;
  final List<bool> flags;
  final Uint8List? disabled;

  bool allows(int term) => disabled == null || disabled![term] == 0;
}

/// A grammar ready to parse with: Lezer's `LRParser`.
class LRParser {
  LRParser._(this._base, {required this.top, required this.dialect});

  /// `LRParser.deserialize`: the parser for `spec`, with the hand-written parts the spec names: its `tokenizers`
  /// by name, its context tracker, and the specializers that are functions.
  factory LRParser.deserialize(
    LRParserSpec spec, {
    Map<String, Tokenizer> tokenizers = const <String, Tokenizer>{},
    ContextTracker? context,
    Map<String, int Function(String value, Stack stack)> specializers = const <String, int Function(String value, Stack stack)>{},
  }) {
    final base = _Tables(spec, tokenizers, context, specializers);
    final parser = LRParser._(base, top: spec.topRules.values.first, dialect: base.parseDialect(null));
    return parser;
  }

  final _Tables _base;

  /// The state a parse starts in, and the node at its top.
  final (int, int) top;
  final Dialect dialect;

  /// `LRParser.configure`: this grammar with a dialect switched on (`'jsx ts'`) or another rule at the top.
  LRParser configure({String? dialect, String? top}) {
    final topRule = top == null ? this.top : _base.spec.topRules[top];
    if (topRule == null) throw RangeError('Invalid top rule name $top');
    return LRParser._(_base, top: topRule, dialect: dialect == null ? this.dialect : _base.parseDialect(dialect));
  }

  List<int> get states => _base.states;
  List<int> get data => _base.data;
  List<Tokenizer> get tokenizers => _base.tokenizers;
  List<int> get specialized => _base.specialized;
  List<int Function(String value, Stack stack)> get specializers => _base.specializers;
  ContextTracker? get context => _base.context;
  int get tokenPrecTable => _base.spec.tokenPrec;
  int get minRepeatTerm => _base.minRepeatTerm;
  int get maxNode => _base.maxNode;
  int get eofTerm => _base.maxNode + 1;

  /// The name of each node, by its number; empty for the nodes a repeat makes, which no rule can name.
  List<String> get nodeNames => _base.nodeNames;

  /// A node's rules for the highlighter, by its number.
  List<List<StyleRule>?> get rules => _base.rules;

  /// The number of the node or token named `name` in the grammar.
  int term(String name) => _base.nodeNames.indexOf(name);

  /// The name of the node numbered `term`; the empty string for a term that makes no node.
  String nameOf(int term) => term >= 0 && term < _base.nodeNames.length ? _base.nodeNames[term] : '';

  int dynamicPrecedence(int term) => _base.spec.dynamicPrecedences[term] ?? 0;

  /// Get a goto table entry.
  int getGoto(int state, int term, [bool loose = false]) {
    final table = _base.goto;
    if (term >= table[0]) return -1;
    for (var pos = table[term + 1];;) {
      final groupTag = table[pos++], last = groupTag & 1;
      final target = table[pos++];
      if (last != 0 && loose) return target;
      for (final end = pos + (groupTag >> 1); pos < end; pos++) {
        if (table[pos] == state) return target;
      }
      if (last != 0) return -1;
    }
  }

  /// Check if this state has an action for a given terminal.
  int hasAction(int state, int terminal) {
    final data = this.data;
    for (var set = 0; set < 2; set++) {
      for (var i = stateSlot(state, set != 0 ? _slotSkip : _slotActions);; i += 3) {
        var next = data[i];
        if (next == _seqEnd) {
          if (data[i + 1] == _seqNext) {
            next = data[i = _pair(data, i + 2)];
          } else if (data[i + 1] == _seqOther) {
            return _pair(data, i + 2);
          } else {
            break;
          }
        }
        if (next == terminal || next == _termErr) return _pair(data, i + 1);
      }
    }
    return 0;
  }

  int stateSlot(int state, int slot) => states[(state * _stateSize) + slot];

  bool stateFlag(int state, int flag) => (stateSlot(state, _slotFlags) & flag) > 0;

  bool validAction(int state, int action) => allActions<bool>(state, (a) => a == action ? true : null) ?? false;

  T? allActions<T>(int state, T? Function(int action) action) {
    final deflt = stateSlot(state, _slotDefaultReduce);
    var result = deflt != 0 ? action(deflt) : null;
    for (var i = stateSlot(state, _slotActions); result == null; i += 3) {
      if (data[i] == _seqEnd) {
        if (data[i + 1] == _seqNext) {
          i = _pair(data, i + 2);
        } else {
          break;
        }
      }
      result = action(_pair(data, i + 1));
    }
    return result;
  }

  /// Get the states that can follow this one through shift actions or goto jumps.
  List<int> nextStates(int state) {
    final result = <int>[];
    for (var i = stateSlot(state, _slotActions);; i += 3) {
      if (data[i] == _seqEnd) {
        if (data[i + 1] == _seqNext) {
          i = _pair(data, i + 2);
        } else {
          break;
        }
      }
      if ((data[i + 2] & (_reduceFlag >> 16)) == 0) {
        final value = data[i + 1];
        var has = false;
        for (var j = 1; j < result.length; j += 2) {
          if (result[j] == value) has = true;
        }
        if (!has) {
          result
            ..add(data[i])
            ..add(value);
        }
      }
    }
    return result;
  }
}

/// What every configuration of one grammar shares: its tables, decoded once.
class _Tables {
  _Tables(this.spec, Map<String, Tokenizer> external, this.context, Map<String, int Function(String value, Stack stack)> externalSpecializers)
    : states = decodeArray(spec.states, wide: true),
      data = decodeArray(spec.stateData),
      goto = decodeArray(spec.goto) {
    if ((spec.context != null) != (context != null)) throw StateError('The grammar names the context tracker ${spec.context}');
    nodeNames = <String>[...spec.nodeNames.split(' '), for (var i = 0; i < spec.repeatNodeCount; i++) ''];
    minRepeatTerm = nodeNames.length - spec.repeatNodeCount;
    maxNode = nodeNames.length - 1;
    final tokenArray = decodeArray(spec.tokenData);
    tokenizers = <Tokenizer>[
      for (final t in spec.tokenizers)
        if (t.group != null)
          TokenGroup(tokenArray, t.group!)
        else if (t.local != null)
          LocalTokenGroup(t.local!, t.precTable, t.elseToken)
        else
          external[t.external] ?? (throw StateError('No tokenizer given for ${t.external}')),
    ];
    specialized = Uint16List.fromList(<int>[for (final s in spec.specialized) s.term]);
    specializers = <int Function(String value, Stack stack)>[
      for (final s in spec.specialized)
        if (s.table != null) _tableSpecializer(s.table!) else _externalSpecializer(externalSpecializers[s.external] ?? (throw StateError('No specializer given for ${s.external}')), s.extend),
    ];
    rules = <List<StyleRule>?>[for (var i = 0; i < nodeNames.length; i++) spec.rules[i]];
  }

  static int Function(String value, Stack stack) _tableSpecializer(Map<String, int> table) =>
      (value, stack) => table[value] ?? -1;

  static int Function(String value, Stack stack) _externalSpecializer(int Function(String value, Stack stack) external, bool extend) {
    final mask = extend ? 1 : 0;
    return (value, stack) => (external(value, stack) << 1) | mask;
  }

  final LRParserSpec spec;
  final List<int> states, data, goto;
  final ContextTracker? context;
  late final List<String> nodeNames;
  late final int minRepeatTerm, maxNode;
  late final List<Tokenizer> tokenizers;
  late final List<int> specialized;
  late final List<int Function(String value, Stack stack)> specializers;
  late final List<List<StyleRule>?> rules;

  Dialect parseDialect(String? dialect) {
    final values = spec.dialects.keys.toList(), flags = <bool>[for (final _ in values) false];
    if (dialect != null) {
      for (final part in dialect.split(' ')) {
        final id = values.indexOf(part);
        if (id >= 0) flags[id] = true;
      }
    }
    Uint8List? disabled;
    for (var i = 0; i < values.length; i++) {
      if (!flags[i]) {
        for (var j = spec.dialects[values[i]]!;;) {
          final id = data[j++];
          if (id == _seqEnd) break;
          (disabled ??= Uint8List(spec.maxTerm + 1))[id] = 1;
        }
      }
    }
    return Dialect(dialect, flags, disabled);
  }
}
