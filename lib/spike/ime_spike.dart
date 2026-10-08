// Piece 0 of stage 4, the IME spike. A throwaway: does an Android keyboard tolerate one
// DeltaTextInputClient that shows it only a WINDOW of a large document?
//
// The document is 5,000 lines held as a list. The IME's editing value is always a real,
// contiguous range of the document, [_winStart, _winStart + _ime.text.length), chosen by a
// policy:
//   line      the selected line(s) only
//   sentinel  the selected line(s) plus the "\n" before them (so Backspace has something to eat)
//   nbrs      one line either side, lazily: the window is kept while the caret is in its
//             interior, so Enter and Backspace across a line start need no push at all
//   whole     the entire document (the baseline the window is meant to beat)
// Every delta and every pushed state is logged with a timestamp, on screen and to debugPrint.
//
// What the emulator's Gboard showed (2026-10-07, Flutter 3.47.6, Android 16):
//  * Typing, glide, suggestion taps, double-space full stop, Enter and cross-line selections all
//    arrive as deltas inside the window and map cleanly in every policy.
//  * Backspace arrives as a KEYCODE_DEL key event, and the engine no longer applies an unhandled
//    one to its Editable: the editor deletes (and joins lines at window offset 0) in _onKey.
//  * Swapping the window's text while selection and composing offsets stay the same tells the
//    keyboard NOTHING (InputMethodManager drops an identical updateSelection): its suggestions
//    go stale and a tapped suggestion rewrites the wrong word. Kick.reattach or Kick.nudge fix it.
//  * That Gboard never composed (not even Hangul), so composing across a window move is untested.
// Buttons: policy x4 | k: the kick | reAll: reattach on every editor move | keyBS: handle the
// Backspace key (off = see what the keyboard alone can delete) | sel: extend selection a line
// down | bench: time 40 setEditingState round trips and 40 delta decodes for the current window.
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum WindowPolicy { line, sentinel, nbrs, whole }

/// What to do when the editor swaps the window's text but the selection and composing
/// offsets come out the same: Android then tells the keyboard nothing at all.
enum Kick { none, reattach, nudge }

class ImeSpikeApp extends StatelessWidget {
  const ImeSpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.light(useMaterial3: true),
    home: const ImeSpike(),
  );
}

class ImeSpike extends StatefulWidget {
  const ImeSpike({super.key});

  @override
  State<ImeSpike> createState() => _ImeSpikeState();
}

class _Pos {
  const _Pos(this.line, this.col);
  final int line;
  final int col;
}

const double _lineHeight = 26;
const double _padLeft = 8;
const TextStyle _mono = TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.black, height: 1.0);

class _ImeSpikeState extends State<ImeSpike> with TextInputClient, DeltaTextInputClient {
  final List<String> _lines = <String>[
    for (int i = 0; i < 5000; i++) i % 5 == 3 ? '' : '${i.toString().padLeft(4, '0')} the quick brown fox jumps over a dog',
  ];
  final FocusNode _focus = FocusNode(debugLabel: 'spike');
  final ScrollController _scroll = ScrollController();
  final Stopwatch _clock = Stopwatch()..start();
  final List<String> _log = <String>[];

  WindowPolicy _policy = WindowPolicy.line;
  Kick _kick = Kick.reattach;
  bool _reattachOnMove = false; // on EVERY editor-initiated window move
  bool _keyBackspace = true; // join lines on a Backspace KEY at window offset 0

  TextInputConnection? _conn;
  int _selBase = 5; // document offsets (UTF-16), as CodeMirror's
  int _selExtent = 5;
  int _winStart = 0;
  TextEditingValue _ime = TextEditingValue.empty;
  int _prevWinStart = 0;
  String _prevImeText = '';
  TextSelection _prevSel = const TextSelection.collapsed(offset: -1);
  TextRange _prevComposing = TextRange.empty;
  int _pushes = 0;
  int _deltas = 0;
  int? _lastKeyDownMicros;
  double _charWidth = 7.8;

  // ---------------------------------------------------------------- document

  int get _docLength {
    var n = _lines.length - 1;
    for (final String l in _lines) {
      n += l.length;
    }
    return n;
  }

  int _offsetOf(int line, int col) {
    var n = 0;
    for (var i = 0; i < line; i++) {
      n += _lines[i].length + 1;
    }
    return n + col;
  }

  _Pos _posOf(int offset) {
    var n = offset;
    for (var i = 0; i < _lines.length; i++) {
      final int len = _lines[i].length;
      if (n <= len) return _Pos(i, n);
      n -= len + 1;
    }
    return _Pos(_lines.length - 1, _lines.last.length);
  }

  String _slice(int from, int to) {
    if (from == 0 && to == _docLength) return _lines.join('\n');
    final _Pos a = _posOf(from);
    final _Pos b = _posOf(to);
    if (a.line == b.line) return _lines[a.line].substring(a.col, b.col);
    final StringBuffer out = StringBuffer(_lines[a.line].substring(a.col));
    for (var i = a.line + 1; i < b.line; i++) {
      out
        ..write('\n')
        ..write(_lines[i]);
    }
    out
      ..write('\n')
      ..write(_lines[b.line].substring(0, b.col));
    return out.toString();
  }

  void _replaceDoc(int from, int to, String text) {
    final _Pos a = _posOf(from);
    final _Pos b = _posOf(to);
    final String joined = _lines[a.line].substring(0, a.col) + text + _lines[b.line].substring(b.col);
    _lines.replaceRange(a.line, b.line + 1, joined.split('\n'));
  }

  // ---------------------------------------------------------------- the window

  /// The document range the IME should be shown for the current selection.
  (int, int) _desiredWindow() {
    final int lo = math.min(_selBase, _selExtent);
    final int hi = math.max(_selBase, _selExtent);
    final int a = _posOf(lo).line;
    final int b = _posOf(hi).line;
    final int last = _lines.length - 1;
    switch (_policy) {
      case WindowPolicy.whole:
        return (0, _docLength);
      case WindowPolicy.line:
        return (_offsetOf(a, 0), _offsetOf(b, _lines[b].length));
      case WindowPolicy.sentinel:
        return (_offsetOf(a, 0) - (a > 0 ? 1 : 0), _offsetOf(b, _lines[b].length));
      case WindowPolicy.nbrs:
        // Lazy: keep the window while the selection is strictly inside it (or at a document
        // edge) and it has not grown past a dozen lines.
        final int winEnd = _winStart + _ime.text.length;
        final _Pos ws = _posOf(_winStart);
        final _Pos we = _posOf(winEnd);
        final bool canonical = ws.col == 0 && we.col == _lines[we.line].length && _offsetOf(we.line, we.col) == winEnd;
        if (canonical &&
            (ws.line < a || (a == 0 && ws.line == 0)) &&
            (we.line > b || (b == last && we.line == last)) &&
            we.line - ws.line <= 12) {
          return (_winStart, winEnd);
        }
        final int from = math.max(0, a - 1);
        final int to = math.min(last, b + 1);
        return (_offsetOf(from, 0), _offsetOf(to, _lines[to].length));
    }
  }

  /// Makes the IME's value the desired window. Pushes nothing when the IME already holds it.
  void _resync(String reason, {bool keepComposing = true, bool force = false, bool editorMoved = false}) {
    final (int start, int end) = _desiredWindow();
    final String text = _slice(start, end);
    TextRange composing = TextRange.empty;
    if (keepComposing && _ime.composing.isValid && !_ime.composing.isCollapsed) {
      final int cs = _winStart + _ime.composing.start - start;
      final int ce = _winStart + _ime.composing.end - start;
      if (cs >= 0 && ce <= text.length) composing = TextRange(start: cs, end: ce);
    }
    final TextEditingValue next = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: (_selBase - start).clamp(0, text.length),
        extentOffset: (_selExtent - start).clamp(0, text.length),
      ),
      composing: composing,
    );
    if (!force && start == _winStart && next == _ime) return;
    final bool textMoved = start != _winStart || next.text != _ime.text;
    _prevWinStart = _winStart;
    _prevImeText = _ime.text;
    _prevSel = _ime.selection;
    _prevComposing = _ime.composing;
    _winStart = start;
    _ime = next;
    if (_conn == null || !_conn!.attached) return;
    final bool unseen = textMoved && next.selection == _prevSel && next.composing == _prevComposing;
    if (textMoved && ((_reattachOnMove && editorMoved) || (unseen && _kick == Kick.reattach))) {
      _attach(show: false);
      _say('REATTACH (forces restartInput)${unseen ? ' — same offsets, new text' : ''}');
    } else if (unseen && _kick == Kick.nudge && next.text.isNotEmpty) {
      final int o = next.selection.extentOffset;
      _push(next.copyWith(selection: TextSelection.collapsed(offset: o > 0 ? o - 1 : 1)), 'nudge');
    } else if (unseen) {
      _say('!! UNSEEN SWAP: new text, same offsets, the keyboard is told nothing');
    }
    _push(next, reason);
  }

  void _push(TextEditingValue v, String reason) {
    final int n = ++_pushes;
    final int t0 = dev.Timeline.now;
    _say(
      'PUSH#$n $reason win@$_winStart len=${v.text.length} sel=${v.selection.baseOffset}..${v.selection.extentOffset} '
      'comp=${_range(v.composing)} "${_clip(v.text)}"',
    );
    // The same message TextInputConnection.setEditingState sends, sent by hand so the round
    // trip to the platform thread and back can be timed.
    SystemChannels.textInput.invokeMethod<void>('TextInput.setEditingState', v.toJSON()).then((_) {
      _say('PUSH#$n acked in ${((dev.Timeline.now - t0) / 1000).toStringAsFixed(2)}ms');
    });
  }

  void _attach({bool show = true}) {
    _conn = TextInput.attach(
      this,
      TextInputConfiguration(
        viewId: View.of(context).viewId,
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        enableDeltaModel: true,
      ),
    );
    if (show) _conn!.show();
  }

  // ---------------------------------------------------------------- TextInputClient

  @override
  TextEditingValue? get currentTextEditingValue => _ime;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    _say('!! updateEditingValue (non-delta) len=${value.text.length}');
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    final int t0 = dev.Timeline.now;
    final String lag = _lastKeyDownMicros == null
        ? ''
        : ' key→delta ${((t0 - _lastKeyDownMicros!) / 1000).toStringAsFixed(2)}ms';
    _lastKeyDownMicros = null;
    var diverged = false;
    for (final TextEditingDelta d in deltas) {
      _deltas++;
      var base = _winStart;
      if (d.oldText != _ime.text) {
        if (d.oldText == _prevImeText) {
          // A delta the keyboard made before our last push reached it.
          _say('!! delta against the PREVIOUS window (race), mapped there, will re-push');
          base = _prevWinStart;
        } else {
          _say('!! oldText mismatch: ime has ${d.oldText.length} "${_clip(d.oldText)}", we think ${_ime.text.length}');
        }
        diverged = true;
      }
      switch (d) {
        case TextEditingDeltaInsertion():
          _say('Δins @${d.insertionOffset} "${_esc(d.textInserted)}" ${_tail(d)}');
          _replaceDoc(base + d.insertionOffset, base + d.insertionOffset, d.textInserted);
        case TextEditingDeltaDeletion():
          _say('Δdel ${_range(d.deletedRange)} "${_esc(d.textDeleted)}" ${_tail(d)}');
          _replaceDoc(base + d.deletedRange.start, base + d.deletedRange.end, '');
        case TextEditingDeltaReplacement():
          _say('Δrep ${_range(d.replacedRange)} "${_esc(d.textReplaced)}"→"${_esc(d.replacementText)}" ${_tail(d)}');
          _replaceDoc(base + d.replacedRange.start, base + d.replacedRange.end, d.replacementText);
        case TextEditingDeltaNonTextUpdate():
          _say('Δnon ${_tail(d)}');
      }
      if (!diverged) {
        _ime = d.apply(_ime);
        _selBase = _winStart + _ime.selection.baseOffset;
        _selExtent = _winStart + _ime.selection.extentOffset;
      } else {
        // Our picture of the keyboard's text is wrong: take the selection from the delta in
        // the frame it was made in, then force the window back.
        final TextEditingValue after = d.apply(TextEditingValue(text: d.oldText));
        _selBase = base + after.selection.baseOffset;
        _selExtent = base + after.selection.extentOffset;
      }
    }
    if (!diverged && _slice(_winStart, _winStart + _ime.text.length) != _ime.text) {
      _say('!! INVARIANT BROKEN: the window is not the document range');
      diverged = true;
    }
    _resync('after-delta', force: diverged, keepComposing: !diverged);
    final _Pos p = _posOf(_selExtent);
    _say(
      '  = L${p.line}:${p.col} "${_clip(_lines[p.line])}" comp=${_range(_ime.composing)} '
      'handled ${((dev.Timeline.now - t0) / 1000).toStringAsFixed(2)}ms oldLen=${deltas.last.oldText.length}$lag',
    );
    setState(() {});
  }

  @override
  void performAction(TextInputAction action) {
    _say('performAction $action');
    if (action == TextInputAction.newline) {
      final int lo = math.min(_selBase, _selExtent);
      _replaceDoc(lo, math.max(_selBase, _selExtent), '\n');
      _selBase = _selExtent = lo + 1;
      _resync('newline-action', keepComposing: false, editorMoved: true);
      setState(() {});
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) => _say('privateCommand $action');

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) => _say('autocorrectionPromptRect $start..$end');

  @override
  void connectionClosed() {
    _say('connectionClosed');
    _conn = null;
  }

  // ---------------------------------------------------------------- keys and taps

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    final bool collapsed = _selBase == _selExtent;
    if (key == LogicalKeyboardKey.backspace) {
      final bool atWindowStart = collapsed && _selBase == _winStart;
      _say('KEY backspace (atWindowStart=$atWindowStart docOffset=$_selBase)');
      if (atWindowStart && _selBase > 0 && _keyBackspace) {
        _replaceDoc(_selBase - 1, _selBase, '');
        _selBase = _selExtent = _selBase - 1;
        _resync('key-backspace-join', keepComposing: false, editorMoved: true);
        setState(() {});
        return KeyEventResult.handled;
      }
      if (!_keyBackspace) return KeyEventResult.ignored;
      // Found by this spike: the engine no longer applies an unhandled KEYCODE_DEL to its
      // Editable, and Gboard sends every plain Backspace as that key event. So the editor
      // deletes, always, and pushes the result.
      if (!collapsed) {
        final int lo = math.min(_selBase, _selExtent);
        _replaceDoc(lo, math.max(_selBase, _selExtent), '');
        _selBase = _selExtent = lo;
      } else if (_selBase > 0) {
        var n = 1;
        if (_selBase > 1) {
          final String two = _slice(_selBase - 2, _selBase);
          if (two.codeUnitAt(1) & 0xFC00 == 0xDC00 && two.codeUnitAt(0) & 0xFC00 == 0xD800) n = 2;
        }
        _replaceDoc(_selBase - n, _selBase, '');
        _selBase = _selExtent = _selBase - n;
      }
      _resync('key-backspace', keepComposing: false);
      final _Pos q = _posOf(_selExtent);
      _say('  = L${q.line}:${q.col} "${_clip(_lines[q.line])}"');
      setState(() {});
      return KeyEventResult.handled;
    }
    int? to;
    final _Pos p = _posOf(_selExtent);
    if (key == LogicalKeyboardKey.arrowLeft) to = math.max(0, _selExtent - 1);
    if (key == LogicalKeyboardKey.arrowRight) to = math.min(_docLength, _selExtent + 1);
    if (key == LogicalKeyboardKey.arrowUp && p.line > 0) {
      to = _offsetOf(p.line - 1, math.min(p.col, _lines[p.line - 1].length));
    }
    if (key == LogicalKeyboardKey.arrowDown && p.line < _lines.length - 1) {
      to = _offsetOf(p.line + 1, math.min(p.col, _lines[p.line + 1].length));
    }
    if (to != null) {
      _say('KEY ${key.keyLabel}');
      _selExtent = to;
      if (!HardwareKeyboard.instance.isShiftPressed) _selBase = to;
      _resync('key-move', keepComposing: false, editorMoved: true);
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) _say('KEY enter (left to the engine)');
    // Left to the engine, which types it into its Editable and answers with a delta.
    _lastKeyDownMicros = dev.Timeline.now;
    return KeyEventResult.ignored;
  }

  void _tapLine(int line, double dx) {
    final int col = ((dx - _padLeft) / _charWidth).round().clamp(0, _lines[line].length);
    _say('TAP L$line:$col (composing was ${_range(_ime.composing)})');
    _focus.requestFocus();
    _selBase = _selExtent = _offsetOf(line, col);
    if (_conn == null || !_conn!.attached) {
      _attach();
      _resync('attach', keepComposing: false, force: true);
    } else {
      _conn!.show();
      _resync('tap', keepComposing: false, editorMoved: true);
    }
    setState(() {});
  }

  void _extendDown() {
    final _Pos p = _posOf(_selExtent);
    if (p.line >= _lines.length - 1) return;
    _selExtent = _offsetOf(p.line + 1, math.min(p.col, _lines[p.line + 1].length));
    _say('SEL extend to L${p.line + 1}');
    _resync('extend', keepComposing: false, editorMoved: true);
    setState(() {});
  }

  void _setPolicy(WindowPolicy p) {
    _policy = p;
    _say('POLICY ${p.name}');
    _resync('policy', keepComposing: false, force: true);
    setState(() {});
  }

  // ---------------------------------------------------------------- measuring

  Future<void> _bench() async {
    if (_conn == null) return;
    final TextEditingValue v = _ime;
    final int o = v.selection.baseOffset.clamp(0, math.max(0, v.text.length - 1));
    final List<int> out = <int>[];
    for (var i = 0; i < 40; i++) {
      final TextEditingValue alt = v.copyWith(
        selection: TextSelection.collapsed(offset: (o + (i.isEven ? 1 : 0)).clamp(0, v.text.length)),
        composing: TextRange.empty,
      );
      final int t0 = dev.Timeline.now;
      await SystemChannels.textInput.invokeMethod<void>('TextInput.setEditingState', alt.toJSON());
      out.add(dev.Timeline.now - t0);
    }
    // What decoding one inbound delta costs on the UI thread: the engine sends oldText (the
    // whole editing value) with every delta. Synthetic, the same shape the engine sends.
    const JSONMethodCodec codec = JSONMethodCodec();
    final ByteData msg = codec.encodeMethodCall(
      MethodCall('TextInputClient.updateEditingStateWithDeltas', <dynamic>[
        1,
        <String, dynamic>{
          'deltas': <dynamic>[
            <String, dynamic>{
              'oldText': v.text,
              'deltaText': 'a',
              'deltaStart': o,
              'deltaEnd': o,
              'selectionBase': o + 1,
              'selectionExtent': o + 1,
              'selectionAffinity': 'TextAffinity.downstream',
              'selectionIsDirectional': false,
              'composingBase': -1,
              'composingExtent': -1,
            },
          ],
        },
      ]),
    );
    final List<int> inn = <int>[];
    for (var i = 0; i < 40; i++) {
      final int t0 = dev.Timeline.now;
      final MethodCall call = codec.decodeMethodCall(msg);
      final Map<String, dynamic> encoded = (call.arguments as List<dynamic>)[1] as Map<String, dynamic>;
      final TextEditingDelta d = TextEditingDelta.fromJSON(
        (encoded['deltas'] as List<dynamic>).first as Map<String, dynamic>,
      );
      d.apply(v);
      inn.add(dev.Timeline.now - t0);
    }
    _say(
      'BENCH ${_policy.name} valueLen=${v.text.length} msgBytes=${msg.lengthInBytes} | '
      'setEditingState round trip ${_stats(out)} | delta decode+apply ${_stats(inn)}',
    );
    _push(v, 'bench-restore');
    if (mounted) setState(() {});
  }

  String _stats(List<int> micros) {
    final List<int> s = List<int>.of(micros)..sort();
    String ms(int u) => (u / 1000).toStringAsFixed(2);
    return 'median ${ms(s[s.length ~/ 2])}ms min ${ms(s.first)} max ${ms(s.last)} (n=${s.length})';
  }

  // ---------------------------------------------------------------- logging

  void _say(String s) {
    final String line = '[${(_clock.elapsedMicroseconds / 1000).toStringAsFixed(1).padLeft(9)}] $s';
    _log.add(line);
    if (_log.length > 400) _log.removeRange(0, 200);
    debugPrint('IME $line');
    if (mounted) setState(() {});
  }

  String _esc(String s) => s.replaceAll('\n', r'\n');
  String _clip(String s) {
    final String e = _esc(s);
    return e.length <= 60 ? e : '${e.substring(0, 28)}…${e.substring(e.length - 28)}';
  }

  String _range(TextRange r) => r.isValid ? '${r.start}..${r.end}' : '-';
  String _tail(TextEditingDelta d) =>
      'sel=${d.selection.baseOffset}..${d.selection.extentOffset} comp=${_range(d.composing)}';

  // ---------------------------------------------------------------- widgets

  @override
  void initState() {
    super.initState();
    final TextPainter tp = TextPainter(
      text: const TextSpan(text: '0000000000', style: _mono),
      textDirection: TextDirection.ltr,
    )..layout();
    _charWidth = tp.width / 10;
    tp.dispose();
    _say('charWidth=$_charWidth lineHeight=$_lineHeight padLeft=$_padLeft lines=${_lines.length} docLen=$_docLength');
  }

  @override
  void dispose() {
    _conn?.close();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _button(String label, VoidCallback onTap, {bool on = false}) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        color: on ? Colors.black : Colors.black12,
        child: Text(label, style: TextStyle(fontSize: 10, color: on ? Colors.white : Colors.black)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final int lo = math.min(_selBase, _selExtent);
    final int hi = math.max(_selBase, _selExtent);
    final _Pos a = _posOf(lo);
    final _Pos b = _posOf(hi);
    final _Pos caret = _posOf(_selExtent);
    _Pos? ca;
    _Pos? cb;
    if (_ime.composing.isValid && !_ime.composing.isCollapsed) {
      ca = _posOf(_winStart + _ime.composing.start);
      cb = _posOf(_winStart + _ime.composing.end);
    }
    final _Pos ws = _posOf(_winStart);
    final _Pos we = _posOf(_winStart + _ime.text.length);
    final int from = math.max(0, _log.length - 7);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                for (final WindowPolicy p in WindowPolicy.values)
                  _button(p.name, () => _setPolicy(p), on: _policy == p),
                _button('k:${_kick.name}', () {
                  _kick = Kick.values[(_kick.index + 1) % Kick.values.length];
                  _say('KICK ${_kick.name}');
                }),
                _button('reAll', () {
                  _reattachOnMove = !_reattachOnMove;
                  _say('REATTACH-ON-EVERY-MOVE $_reattachOnMove');
                }, on: _reattachOnMove),
                _button('keyBS', () {
                  _keyBackspace = !_keyBackspace;
                  _say('KEY-BACKSPACE-JOIN $_keyBackspace');
                }, on: _keyBackspace),
                _button('sel↓', _extendDown),
                _button('bench', _bench),
              ],
            ),
            Container(
              height: 96,
              width: double.infinity,
              color: const Color(0xFFF2F2F2),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'win L${ws.line}:${ws.col}–L${we.line}:${we.col} @$_winStart len=${_ime.text.length} '
                'sel=${_ime.selection.baseOffset}..${_ime.selection.extentOffset} comp=${_range(_ime.composing)} '
                'pushes=$_pushes deltas=$_deltas\n${_log.sublist(from).join('\n')}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 7.5, height: 1.25),
                maxLines: 9,
                overflow: TextOverflow.clip,
                softWrap: false,
              ),
            ),
            Expanded(
              child: Focus(
                focusNode: _focus,
                autofocus: true,
                onKeyEvent: _onKey,
                child: ListView.builder(
                  controller: _scroll,
                  itemExtent: _lineHeight,
                  itemCount: _lines.length,
                  itemBuilder: (BuildContext context, int i) {
                    int? selFrom;
                    int? selTo;
                    if (lo != hi && i >= a.line && i <= b.line) {
                      selFrom = i == a.line ? a.col : 0;
                      selTo = i == b.line ? b.col : _lines[i].length + 1;
                    }
                    int? compFrom;
                    int? compTo;
                    if (ca != null && cb != null && i >= ca.line && i <= cb.line) {
                      compFrom = i == ca.line ? ca.col : 0;
                      compTo = i == cb.line ? cb.col : _lines[i].length;
                    }
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (TapDownDetails d) => _tapLine(i, d.localPosition.dx),
                      child: CustomPaint(
                        painter: _LinePainter(
                          text: _lines[i],
                          caret: i == caret.line ? caret.col : null,
                          selFrom: selFrom,
                          selTo: selTo,
                          compFrom: compFrom,
                          compTo: compTo,
                          inWindow: i >= ws.line && i <= we.line,
                          charWidth: _charWidth,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.text,
    required this.caret,
    required this.selFrom,
    required this.selTo,
    required this.compFrom,
    required this.compTo,
    required this.inWindow,
    required this.charWidth,
  });

  final String text;
  final int? caret;
  final int? selFrom;
  final int? selTo;
  final int? compFrom;
  final int? compTo;
  final bool inWindow;
  final double charWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (inWindow) {
      // The lines the keyboard can see, tinted.
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x14FF9800));
    }
    double x(int col) => _padLeft + col * charWidth;
    if (selFrom != null) {
      canvas.drawRect(Rect.fromLTRB(x(selFrom!), 2, x(selTo!), size.height - 2), Paint()..color = const Color(0x553390FF));
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: _mono),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, Offset(_padLeft, (size.height - tp.height) / 2));
    tp.dispose();
    if (compFrom != null) {
      canvas.drawRect(Rect.fromLTRB(x(compFrom!), size.height - 4, x(compTo!), size.height - 2), Paint()..color = Colors.black);
    }
    if (caret != null) {
      canvas.drawRect(Rect.fromLTWH(x(caret!) - 1, 3, 2, size.height - 6), Paint()..color = const Color(0xFFE53935));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.text != text ||
      old.caret != caret ||
      old.selFrom != selFrom ||
      old.selTo != selTo ||
      old.compFrom != compFrom ||
      old.compTo != compTo ||
      old.inWindow != inWindow;
}
