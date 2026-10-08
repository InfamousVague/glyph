// EditorState, Transaction, Facet, StateField, StateEffect, Annotation, Compartment and Prec. First the answers
// CodeMirror gave (fixtures/state.json): characters and words, changeByRange, several specs in one update, phrases,
// and 150 random configurations taken through edits and reconfigurations. Then CodeMirror's own state, facet and
// transaction tests, in spirit.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';

import 'support.dart';

// The fixture's three facets and its field, as generate.mjs defines them.
final Facet<int, List<int>> f0 = Facet.define<int, List<int>>();
final Facet<int, int> f1 = Facet.define<int, int>(combine: (v) => v.fold(0, (a, b) => a + b));
final Facet<int, int> f2 = Facet.define<int, int>(combine: (v) => v.isNotEmpty ? v[0] : -1, isStatic: true);
final StateField<int> counter = StateField.define<int>(create: (_) => 0, update: (v, tr) => tr.docChanged ? v + 1 : v);

class Ctx {
  Ctx(this.sharedNodes);
  final List<dynamic> sharedNodes;
  final Map<int, Compartment> comps = <int, Compartment>{};
  final Map<int, Extension> shared = <int, Extension>{};
}

Extension build(Map<String, dynamic> node, Ctx ctx) {
  Extension provide(int f, int v) => f == 0
      ? f0.of(v)
      : f == 1
      ? f1.of(v)
      : f2.of(v);
  switch (node['t'] as String) {
    case 'v':
      return provide(node['f'] as int, node['v'] as int);
    case 'c':
      final dep = node['dep'], mul = node['mul'] as int;
      final deps = <Object>[
        dep == 'doc'
            ? docDependency
            : dep == 'sel'
            ? selectionDependency
            : dep == 'field'
            ? counter
            : f0,
      ];
      int get(EditorState state) =>
          mul *
          (dep == 'doc'
              ? state.doc.length
              : dep == 'sel'
              ? state.selection.main.head
              : dep == 'field'
              ? (state.fieldOrNull(counter) ?? 0)
              : state.facet(f0).length);
      return node['f'] == 0 ? f0.compute(deps, get) : f1.compute(deps, get);
    case 'n':
      final add = node['add'] as int;
      List<int> get(EditorState state) => <int>[state.doc.lines, state.doc.lines + add];
      return node['f'] == 0 ? f0.computeN(const <Object>[docDependency], get) : f1.computeN(const <Object>[docDependency], get);
    case 'field':
      return counter;
    case 'l':
      return Extension.list(<Extension>[for (final c in node['c'] as List) build(c as Map<String, dynamic>, ctx)]);
    case 'p':
      final inner = build(node['c'] as Map<String, dynamic>, ctx);
      return switch (node['p'] as String) {
        'highest' => Prec.highest(inner),
        'high' => Prec.high(inner),
        'default' => Prec.default_(inner),
        'low' => Prec.low(inner),
        _ => Prec.lowest(inner),
      };
    case 'k':
      return (ctx.comps[node['id'] as int] ??= Compartment()).of(build(node['c'] as Map<String, dynamic>, ctx));
    case 'r':
      final i = node['i'] as int;
      return ctx.shared[i] ??= build(ctx.sharedNodes[i] as Map<String, dynamic>, ctx);
  }
  throw StateError('node ${node['t']}');
}

Map<String, Object?> read(EditorState state) => <String, Object?>{
  'f0': state.facet(f0),
  'f1': state.facet(f1),
  'f2': state.facet(f2),
  'field': state.fieldOrNull(counter),
};

void main() {
  final data = fixture('state');

  group('against CodeMirror', () {
    test('cluster breaks, code points and columns', () {
      for (final c in data['clusters'] as List) {
        final s = c['s'] as String;
        final reason = jsonEncode(s);
        expect(<int>[for (var i = 0; i <= s.length; i++) findClusterBreak(s, i)], c['fwd'], reason: reason);
        expect(<int>[for (var i = 0; i <= s.length; i++) findClusterBreak(s, i, false)], c['back'], reason: reason);
        expect(<int>[for (var i = 0; i <= s.length; i++) findClusterBreak(s, i, true, false)], c['fwdNoExt'], reason: reason);
        expect(<int>[for (var i = 0; i <= s.length; i++) findClusterBreak(s, i, false, false)], c['backNoExt'], reason: reason);
        expect(<int>[for (var i = 0; i < s.length; i++) codePointAt(s, i)], c['points'], reason: reason);
        expect(<int>[for (var i = 0; i <= s.length; i++) countColumn(s, 4, i)], c['column'], reason: reason);
        expect(
          <List<int>>[
            for (var i = 0; i < s.length + 4; i++) <int>[findColumn(s, i, 4), findColumn(s, i, 4, true)],
          ],
          c['find'],
          reason: reason,
        );
      }
      expect(fromCodePoint(0x1F600), '😀');
      expect(fromCodePoint(0xe9), 'é');
      expect(codePointSize(0x1F600), 2);
      expect(codePointSize(0xffff), 1);
    });

    test('wordAt, at every position of every sample', () {
      for (final w in data['words'] as List) {
        final s = w['s'] as String;
        final state = EditorState.create(doc: 'first\n$s\nlast');
        final got = <List<int>?>[
          for (var i = 0; i <= s.length; i++)
            () {
              final word = state.wordAt(6 + i);
              return word == null ? null : <int>[word.from, word.to];
            }(),
        ];
        expect(got, w['r'], reason: jsonEncode(s));
      }
    });

    test('changeByRange and replaceSelection over several ranges', () {
      for (final c in data['byRange'] as List) {
        final doc = c['doc'] as String, kind = c['kind'] as String, arg = c['arg'] as String;
        final r = c['r'] as Map<String, dynamic>;
        final reason = jsonEncode(<String, Object?>{'doc': doc, 'pairs': c['pairs'], 'main': c['main'], 'kind': kind, 'arg': arg});
        final mark = StateEffect.define<int>(map: (v, m) => m.mapPos(v, 1));
        final state = EditorState.create(
          doc: doc,
          selection: EditorSelection.create(<SelectionRange>[
            for (final p in c['pairs'] as List) EditorSelection.range(p[0] as int, p[1] as int),
          ], c['main'] as int),
          extensions: EditorState.allowMultipleSelections.of(true),
        );
        final spec = kind == 'replace'
            ? state.replaceSelection(arg)
            : state.changeByRange((range) {
                if (kind == 'wrap') {
                  return RangeChange(
                    changes: <ChangeSpec>[ChangeSpec(from: range.from, insert: arg), ChangeSpec(from: range.to, insert: arg)],
                    range: EditorSelection.range(range.anchor + arg.length, range.head + arg.length),
                  );
                }
                if (kind == 'backspace') {
                  final from = range.empty ? (range.from - 1 < 0 ? 0 : range.from - 1) : range.from;
                  return RangeChange(changes: ChangeSpec(from: from, to: range.to), range: EditorSelection.cursor(from));
                }
                return RangeChange(
                  changes: ChangeSpec(from: range.from, insert: arg),
                  range: EditorSelection.cursor(range.from),
                  effects: mark.of(range.to),
                );
              });
        final tr = state.update(spec);
        expect((spec.changes as ChangeSet).toJson(), r['changes'], reason: reason);
        expect(selJson(spec.selection!), r['sel'], reason: reason);
        expect(tr.newDoc.toString(), r['doc'], reason: reason);
        expect(selJson(tr.state.selection), r['stateSel'], reason: reason);
        expect(<Object?>[for (final e in spec.effects as List) (e as StateEffect).value], r['effects'], reason: reason);
      }
    });

    test('several specs in one update, some of them sequential', () {
      for (final c in data['multi'] as List) {
        final doc = c['doc'] as String;
        final r = c['r'] as Map<String, dynamic>;
        final reason = jsonEncode(<String, Object?>{'doc': doc, 'specs': c['specs']});
        final state = EditorState.create(doc: doc);
        final tr = state.updateAll(<TransactionSpec>[
          for (final s in c['specs'] as List)
            TransactionSpec(
              changes: specsOf(s['changes'] as List),
              sequential: s['sequential'] as bool,
              selection: s['selection'] == null ? null : EditorSelection.single(s['selection']['anchor'] as int, s['selection']['head'] as int),
              scrollIntoView: s['scroll'] as bool,
              userEvent: s['userEvent'] as String?,
            ),
        ]);
        expect(tr.changes.toJson(), r['changes'], reason: reason);
        expect(tr.selection == null ? null : selJson(tr.selection!), r['sel'], reason: reason);
        expect(tr.newDoc.toString(), r['doc'], reason: reason);
        expect(selJson(tr.newSelection), r['newSel'], reason: reason);
        expect(tr.scrollIntoView, r['scroll'], reason: reason);
        expect(tr.annotation(Transaction.userEvent), r['userEvent'], reason: reason);
        expect(tr.isUserEvent('input.type'), r['isType'], reason: reason);
        expect(tr.isUserEvent('input'), r['isInput'], reason: reason);
        expect(tr.isUserEvent('delete'), r['isDelete'], reason: reason);
      }
    });

    test('phrases', () {
      final state = EditorState.create(
        extensions: Extension.list(<Extension>[
          EditorState.phrases.of(const <String, String>{'Hello': 'Bonjour', r'Go to $': r'Aller à $', r'from $1 to $2': r'de $1 à $2'}),
          EditorState.phrases.of(const <String, String>{'Hello': 'Hallo', 'Bye': 'Tschüss'}),
        ]),
      );
      for (final p in data['phrases'] as List) {
        final args = p['args'] as List;
        expect(state.phrase(args[0] as String, args.sublist(1)), p['r'], reason: jsonEncode(args));
      }
    });

    final configs = data['configs'] as List;
    test('${configs.length} random configurations: precedence, compartments, shared extensions, reconfiguring', () {
      for (var n = 0; n < configs.length; n++) {
        final c = configs[n] as Map<String, dynamic>;
        final ctx = Ctx(c['shared'] as List);
        var state = EditorState.create(doc: 'one\ntwo', extensions: build(c['root'] as Map<String, dynamic>, ctx));
        final reason = 'configuration $n: ${jsonEncode(c['root'])} shared ${jsonEncode(c['shared'])}';
        expect(read(state), c['start'], reason: reason);
        final done = <Object?>[];
        for (final step in c['steps'] as List) {
          done.add(<String, Object?>{for (final k in (step as Map<String, dynamic>).keys) if (k != 'r') k: step[k]});
          switch (step['s'] as String) {
            case 'edit':
              state = state.update(TransactionSpec(changes: ChangeSpec(from: step['from'] as int, insert: step['insert'] as String))).state;
            case 'sel':
              state = state.update(TransactionSpec(selection: EditorSelection.single(step['anchor'] as int))).state;
            case 'reconf':
              final comp = ctx.comps[step['id'] as int] ??= Compartment();
              state = state.update(TransactionSpec(effects: comp.reconfigure(build(step['tree'] as Map<String, dynamic>, ctx)))).state;
            case 'append':
              state = state.update(TransactionSpec(effects: StateEffect.appendConfig.of(build(step['tree'] as Map<String, dynamic>, ctx)))).state;
            case 'full':
              state = state.update(TransactionSpec(effects: StateEffect.reconfigure.of(build(step['tree'] as Map<String, dynamic>, ctx)))).state;
          }
          expect(read(state), step['r'], reason: '$reason after ${jsonEncode(done)}');
        }
      }
    });
  });

  group('EditorState', () {
    test('holds doc and selection', () {
      final state = EditorState.create(doc: 'hello');
      expect(state.doc.toString(), 'hello');
      expect(state.selection.main.from, 0);
      expect(state.sliceDoc(1, 3), 'el');
      expect(state.sliceDoc(), 'hello');
      expect(EditorState.create().doc.length, 0);
      expect(EditorState.create(doc: Doc.ofString('a\nb')).doc.lines, 2);
    });

    test('applies transaction changes, and maps the selection through them', () {
      final state = EditorState.create(doc: 'hello', selection: EditorSelection.single(5));
      final tr = state.update(const TransactionSpec(changes: <ChangeSpec>[ChangeSpec(from: 2, to: 3, insert: 'w'), ChangeSpec(from: 4, insert: '!')]));
      expect(tr.state.doc.toString(), 'hewl!o');
      expect(tr.startState, same(state));
      expect(tr.docChanged, isTrue);
      expect(tr.state.selection.main.head, 6);
      expect(tr.newDoc, same(tr.state.doc));
      final typed = state.update(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'So '), selection: EditorSelection.single(3)));
      expect(typed.state.selection.main.head, 3);
      expect(typed.selection, isNotNull);
      expect(tr.selection, isNull);
    });

    test('throws when a change or a selection is outside the document', () {
      final state = EditorState.create(doc: '1234');
      expect(() => state.update(const TransactionSpec(changes: ChangeSpec(from: -1, to: 1))), throwsRangeError);
      expect(() => state.update(const TransactionSpec(changes: ChangeSpec(from: 2, to: 1))), throwsRangeError);
      expect(() => state.update(const TransactionSpec(changes: ChangeSpec(from: 2, to: 10, insert: 'x'))), throwsRangeError);
      expect(() => state.update(TransactionSpec(selection: EditorSelection.single(5))), throwsRangeError);
      expect(() => EditorState.create(doc: 'ab', selection: EditorSelection.single(3)), throwsRangeError);
    });

    test('keeps one range unless it is told it may keep several', () {
      final many = EditorSelection.create(<SelectionRange>[EditorSelection.cursor(1), EditorSelection.cursor(3)], 1);
      expect(EditorState.create(doc: 'abcd', selection: many).selection.ranges, hasLength(1));
      expect(EditorState.create(doc: 'abcd', selection: many).selection.main.head, 3);
      final allowed = EditorState.create(doc: 'abcd', selection: many, extensions: EditorState.allowMultipleSelections.of(true));
      expect(allowed.selection.ranges, hasLength(2));
      expect(EditorState.create(doc: 'abcd').update(TransactionSpec(selection: many)).state.selection.ranges, hasLength(1));
    });

    test('stores and updates tab size, the line separator and read-only', () {
      final deflt = EditorState.create(), two = EditorState.create(extensions: EditorState.tabSizeFacet.of(2));
      expect(deflt.tabSize, 4);
      expect(two.tabSize, 2);
      expect(deflt.readOnly, isFalse);
      expect(EditorState.create(extensions: EditorState.readOnlyFacet.of(true)).readOnly, isTrue);

      expect(deflt.lineBreak, '\n');
      final crlf = EditorState.create(doc: 'one\r\ntwo\nthree', extensions: EditorState.lineSeparator.of('\r\n'));
      expect(crlf.doc.lines, 2);
      expect(crlf.lineBreak, '\r\n');
      expect(crlf.sliceDoc(), 'one\r\ntwo\nthree');
      expect(crlf.toText('a\r\nb\nc').lines, 2);
      expect(crlf.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x\ny\r\n'))).state.doc.lines, 3);
      expect(deflt.toText('a\r\nb\rc').lines, 3);
    });

    test('stores and updates fields', () {
      final field1 = StateField.define<int>(create: (_) => 0, update: (v, _) => v + 1);
      final field2 = StateField.define<int>(create: (state) => state.field(field1) + 10, update: (v, _) => v);
      final state = EditorState.create(extensions: Extension.list(<Extension>[field1, field2]));
      expect(state.field(field1), 0);
      expect(state.field(field2), 10);
      final next = state.update().state;
      expect(next.field(field1), 1);
      expect(next.field(field2), 10);
      final absent = StateField.define<int>(create: (_) => 0, update: (v, _) => v);
      expect(() => state.field(absent), throwsRangeError);
      expect(state.fieldOrNull(absent), isNull);
    });

    test('a field sees the new state while it updates', () {
      final lengths = <int>[];
      final field = StateField.define<int>(
        create: (state) => state.doc.length,
        update: (v, tr) {
          lengths.add(tr.state.doc.length);
          return tr.state.doc.length;
        },
      );
      final state = EditorState.create(doc: 'abc', extensions: field);
      expect(state.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'xy'))).state.field(field), 5);
      expect(lengths, <int>[5]);
    });

    test('allows fields to have an initializer', () {
      final field = StateField.define<int>(create: (_) => 0, update: (v, _) => v + 1);
      final state = EditorState.create(extensions: field.init((_) => 10));
      expect(state.field(field), 10);
      expect(state.update().state.field(field), 11);
    });

    test('can be serialized to JSON', () {
      final field = StateField.define<Map<String, int>>(
        create: (_) => <String, int>{'n': 5},
        update: (v, _) => <String, int>{'n': v['n']! + 1},
        toJson: (v, _) => <String, Object?>{'number': v['n']},
        fromJson: (j, _) => <String, int>{'n': (j as Map)['number'] as int},
      );
      final fields = <String, StateField<Object?>>{'f': field};
      final state = EditorState.create(doc: 'one\ntwo', extensions: field).update(TransactionSpec(selection: EditorSelection.single(1, 4))).state;
      final json = jsonDecode(jsonEncode(state.toJson(fields)));
      expect(json, <String, Object?>{
        'doc': 'one\ntwo',
        'selection': <String, Object?>{
          'ranges': <Object?>[
            <String, Object?>{'anchor': 1, 'head': 4},
          ],
          'main': 0,
        },
        'f': <String, Object?>{'number': 6},
      });
      final back = EditorState.fromJson(json, fields: fields);
      expect(back.doc.toString(), 'one\ntwo');
      expect(back.selection.main.head, 4);
      expect(back.field(field), <String, int>{'n': 6});
      expect(back.update().state.field(field), <String, int>{'n': 7});
      expect(EditorState.fromJson(jsonDecode(jsonEncode(state.toJson()))).fieldOrNull(field), isNull);
      expect(() => EditorState.fromJson(<String, Object?>{'doc': 3}), throwsRangeError);
    });

    test('can preserve fields across reconfiguration, and makes newly added ones', () {
      final field = StateField.define<int>(create: (_) => 0, update: (v, _) => v + 1);
      final other = StateField.define<String>(create: (state) => 'made at ${state.doc.length}', update: (v, _) => v);
      final start = EditorState.create(extensions: field).update().state;
      expect(start.field(field), 1);
      final tr = start.update(
        TransactionSpec(
          changes: const ChangeSpec(from: 0, insert: 'abc'),
          effects: StateEffect.reconfigure.of(Extension.list(<Extension>[field, other])),
        ),
      );
      expect(tr.reconfigured, isTrue);
      expect(tr.state.field(field), 2);
      // A field added by a reconfiguration is created against the old document, then updated by the transaction.
      expect(tr.state.field(other), 'made at 0');
      expect(start.update().reconfigured, isFalse);
      final dropped = tr.state.update(TransactionSpec(effects: StateEffect.reconfigure.of(other))).state;
      expect(dropped.fieldOrNull(field), isNull);
      expect(dropped.field(other), 'made at 0');
    });

    test('a field that provides a facet', () {
      final total = Facet.define<int, int>(combine: (v) => v.fold(0, (a, b) => a + b));
      final words = Facet.define<String, List<String>>();
      final field = StateField.define<int>(
        create: (_) => 3,
        update: (v, tr) => tr.docChanged ? v + 1 : v,
        provide: (f) => Extension.list(<Extension>[total.from(f), words.from(f, (v) => 'n$v')]),
      );
      var state = EditorState.create(extensions: Extension.list(<Extension>[field, total.of(10)]));
      expect(state.facet(total), 13);
      expect(state.facet(words), <String>['n3']);
      state = state.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x'))).state;
      expect(state.facet(total), 14);
      expect(state.facet(words), <String>['n4']);
    });
  });

  group('Facet', () {
    final num = Facet.define<int, List<int>>(), str = Facet.define<String, List<String>>();
    final bool_ = Facet.define<bool, List<bool>>();

    EditorState mk(List<Extension> extensions) => EditorState.create(extensions: Extension.list(extensions));

    test('allows querying of facets', () {
      final st = mk(<Extension>[num.of(10), num.of(20), str.of('x'), str.of('y')]);
      expect(st.facet(num), <int>[10, 20]);
      expect(st.facet(str), <String>['x', 'y']);
      expect(st.facet(bool_), isEmpty);
    });

    test('includes sub-extenders', () {
      final e = Extension.list(<Extension>[
        num.of(1),
        Extension.list(<Extension>[num.of(2), str.of('a')]),
      ]);
      final st = mk(<Extension>[num.of(5), e, num.of(4)]);
      expect(st.facet(num), <int>[5, 1, 2, 4]);
      expect(st.facet(str), <String>['a']);
    });

    test('only includes duplicated extensions once', () {
      final e = num.of(50);
      expect(mk(<Extension>[num.of(1), e, num.of(4), e]).facet(num), <int>[1, 50, 4]);
    });

    test('returns an empty array for absent facet, and a combined facet its default', () {
      expect(mk(<Extension>[]).facet(num), isEmpty);
      final first = Facet.define<int, int>(combine: (v) => v.isNotEmpty ? v[0] : 99);
      expect(mk(<Extension>[]).facet(first), 99);
      expect(mk(<Extension>[first.of(1), first.of(2)]).facet(first), 1);
    });

    test('sorts extensions by priority', () {
      final st = mk(<Extension>[
        str.of('a'),
        str.of('b'),
        Prec.high(str.of('c')),
        Prec.highest(str.of('d')),
        Prec.low(str.of('e')),
        Prec.high(str.of('f')),
        str.of('g'),
        Prec.lowest(str.of('h')),
        Prec.default_(str.of('i')),
      ]);
      expect(st.facet(str).join(), 'dcfabgieh');
    });

    test('lets sub-extensions inherit their parent\'s priority, and an inner one override it', () {
      final e = Extension.list(<Extension>[num.of(2), Prec.highest(num.of(5))]);
      final st = mk(<Extension>[num.of(1), Prec.high(e), num.of(4), Prec.low(Extension.list(<Extension>[num.of(9), Prec.high(num.of(8))]))]);
      expect(st.facet(num), <int>[5, 2, 8, 1, 4, 9]);
    });

    test('keeps a twice-given extension at its higher precedence', () {
      final e = num.of(7);
      expect(mk(<Extension>[num.of(1), Prec.low(e), Prec.high(e)]).facet(num), <int>[7, 1]);
      expect(mk(<Extension>[Prec.high(e), num.of(1), Prec.low(e)]).facet(num), <int>[7, 1]);
      expect(mk(<Extension>[Prec.low(e), num.of(1), e]).facet(num), <int>[1, 7]);
    });

    test('supports dynamic facet', () {
      final st = mk(<Extension>[num.of(1), num.compute(const <Object>[], (_) => 88)]);
      expect(st.facet(num), <int>[1, 88]);
    });

    test('only recomputes a facet value when necessary', () {
      var count = 0;
      final st = mk(<Extension>[
        num.compute(<Object>[str], (s) {
          count++;
          return s.facet(str).join().length;
        }),
        str.of('hello'),
      ]);
      expect(st.facet(num), <int>[5]);
      expect(count, 1);
      final next = st.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x'))).state;
      expect(next.facet(num), <int>[5]);
      expect(count, 1);
      expect(next.facet(num), same(st.facet(num)));
    });

    test('recomputes on the document or the selection as asked', () {
      var docs = 0, sels = 0;
      final st = mk(<Extension>[
        num.compute(const <Object>[docDependency], (s) {
          docs++;
          return s.doc.length;
        }),
        num.compute(const <Object>[selectionDependency], (s) {
          sels++;
          return s.selection.main.head;
        }),
      ]);
      expect(<int>[docs, sels], <int>[1, 1]);
      final moved = st.update(TransactionSpec(selection: EditorSelection.single(0))).state;
      expect(<int>[docs, sels], <int>[1, 2]);
      final typed = moved.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'ab'))).state;
      expect(<int>[docs, sels], <int>[2, 3]);
      expect(typed.facet(num), <int>[2, 0]);
      typed.update(TransactionSpec(effects: StateEffect.define<int>().of(1))).state;
      expect(<int>[docs, sels], <int>[2, 3]);
    });

    test('can handle dependencies on facets that aren\'t present in the state', () {
      final st = mk(<Extension>[
        num.compute(<Object>[str], (s) => s.facet(str).join().length),
        str.compute(<Object>[bool_], (s) => s.facet(bool_).toString()),
      ]);
      expect(st.update().state.facet(num), <int>[2]);
    });

    test('can specify multiple values at once', () {
      final st = mk(<Extension>[
        num.computeN(const <Object>[docDependency], (s) => <int>[s.doc.length, s.doc.lines]),
        num.of(7),
      ]);
      expect(st.facet(num), <int>[0, 1, 7]);
      expect(st.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'a\nb'))).state.facet(num), <int>[3, 2, 7]);
    });

    test('keeps the same value object when a recomputed input is equal', () {
      final list = Facet.define<List<int>, List<List<int>>>(compareInput: (a, b) => a.join(',') == b.join(','));
      final st = mk(<Extension>[
        list.compute(const <Object>[docDependency], (s) => <int>[s.doc.lines]),
      ]);
      final next = st.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x'))).state;
      expect(next.facet(list), same(st.facet(list)));
      final more = next.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: '\n'))).state;
      expect(more.facet(list), isNot(same(st.facet(list))));
      expect(more.facet(list), <List<int>>[<int>[2]]);
    });

    test('works with a static combined facet, and refuses to compute one', () {
      final f = Facet.define<int, int>(combine: (v) => v.fold(0, (a, b) => a + b), isStatic: true);
      expect(mk(<Extension>[f.of(1), f.of(2), f.of(3)]).facet(f), 6);
      expect(() => f.compute(const <Object>[], (_) => 1), throwsStateError);
      expect(() => f.computeN(const <Object>[], (_) => <int>[1]), throwsStateError);
    });

    test('survives reconfiguration: values with the same inputs stay the same objects', () {
      final st = mk(<Extension>[
        num.compute(const <Object>[docDependency], (s) => s.doc.length),
        num.of(2),
        str.of('3'),
      ]);
      final st2 = st.update(TransactionSpec(effects: StateEffect.reconfigure.of(Extension.list(<Extension>[num.compute(const <Object>[docDependency], (s) => s.doc.length), num.of(2)])))).state;
      expect(st2.facet(num), same(st.facet(num)));
      expect(st2.facet(str), isEmpty);
    });

    test('preserves static facets across reconfiguration', () {
      final st = mk(<Extension>[num.of(1), num.of(2), str.of('3')]);
      final st2 = st.update(TransactionSpec(effects: StateEffect.reconfigure.of(Extension.list(<Extension>[num.of(1), num.of(2)])))).state;
      expect(st2.facet(num), same(st.facet(num)));
    });

    test('creates newly added fields when reconfiguring, and updates facets that read them', () {
      var count = 0;
      final field = StateField.define<int>(
        create: (_) {
          count++;
          return 0;
        },
        update: (v, _) => v,
      );
      final st = mk(<Extension>[]).update(TransactionSpec(effects: StateEffect.reconfigure.of(field))).state;
      expect(count, 1);
      final st2 = st.update(TransactionSpec(effects: StateEffect.appendConfig.of(num.from(field)))).state;
      expect(count, 1);
      expect(st2.facet(num), <int>[0]);
    });

    test('errors on cyclic dependencies', () {
      expect(
        () => mk(<Extension>[
          num.compute(<Object>[str], (s) => s.facet(str).length),
          str.compute(<Object>[num], (s) => s.facet(num).join()),
        ]),
        throwsStateError,
      );
    });

    test('can enable other extensions with a facet', () {
      final enabling = Facet.define<int, List<int>>(enables: str.of('ok'));
      final self = Facet.define<int, List<int>>(enablesFrom: (f) => str.compute(<Object>[f], (s) => 'n${s.facet(f).length}'));
      expect(mk(<Extension>[]).facet(str), isEmpty);
      expect(mk(<Extension>[enabling.of(1), enabling.of(2)]).facet(str), <String>['ok']);
      expect(mk(<Extension>[self.of(1), self.of(2)]).facet(str), <String>['n2']);
    });

    test('a facet enabled at high precedence still lands at the default', () {
      final enabling = Facet.define<int, List<int>>(enables: str.of('enabled'));
      expect(mk(<Extension>[str.of('a'), Prec.highest(enabling.of(1)), str.of('b')]).facet(str), <String>['a', 'enabled', 'b']);
    });

    test('compares outputs with the facet\'s own compare', () {
      final parity = Facet.define<int, Map<String, int>>(
        combine: (v) => <String, int>{'odd': v.where((n) => n.isOdd).length},
        compare: (a, b) => a['odd'] == b['odd'],
      );
      final st = mk(<Extension>[parity.compute(const <Object>[docDependency], (s) => s.doc.length)]);
      final plus2 = st.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'ab'))).state;
      expect(plus2.facet(parity), same(st.facet(parity)));
      final plus1 = plus2.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'c'))).state;
      expect(plus1.facet(parity), <String, int>{'odd': 1});
    });

    test('refuses a value that is not an extension it knows', () {
      expect(() => mk(<Extension>[_Looping()]), throwsStateError);
    });
  });

  group('Compartment', () {
    final num = Facet.define<int, List<int>>();

    test('can replace extension groups', () {
      final comp = Compartment();
      var state = EditorState.create(extensions: Extension.list(<Extension>[comp.of(num.of(10)), num.of(20)]));
      expect(state.facet(num), <int>[10, 20]);
      expect(comp.get(state), isNotNull);
      final content = Extension.list(<Extension>[num.of(1), num.of(2)]);
      state = state.update(TransactionSpec(effects: comp.reconfigure(content))).state;
      expect(state.facet(num), <int>[1, 2, 20]);
      expect(comp.get(state), same(content));
      state = state.update(TransactionSpec(effects: comp.reconfigure(const Extension.list(<Extension>[])))).state;
      expect(state.facet(num), <int>[20]);
    });

    test('raises an error on multiple instances of a compartment', () {
      final comp = Compartment();
      expect(() => EditorState.create(extensions: Extension.list(<Extension>[comp.of(num.of(1)), comp.of(num.of(2))])), throwsRangeError);
      expect(
        () => EditorState.create(
          extensions: Extension.list(<Extension>[
            comp.of(Extension.list(<Extension>[comp.of(num.of(1))])),
          ]),
        ),
        throwsRangeError,
      );
    });

    test('preserves compartments on reconfigure', () {
      final comp = Compartment();
      final init = comp.of(num.of(10));
      var state = EditorState.create(extensions: Extension.list(<Extension>[init, num.of(2)]));
      state = state.update(TransactionSpec(effects: comp.reconfigure(num.of(100)))).state;
      state = state.update(TransactionSpec(effects: StateEffect.reconfigure.of(Extension.list(<Extension>[init, num.of(3)])))).state;
      expect(state.facet(num), <int>[100, 3]);
    });

    test('forgets dropped compartments', () {
      final comp = Compartment();
      final init = comp.of(num.of(10));
      var state = EditorState.create(extensions: Extension.list(<Extension>[init, num.of(2)]));
      state = state.update(TransactionSpec(effects: comp.reconfigure(num.of(100)))).state;
      state = state.update(TransactionSpec(effects: StateEffect.reconfigure.of(num.of(3)))).state;
      expect(comp.get(state), isNull);
      state = state.update(TransactionSpec(effects: StateEffect.reconfigure.of(Extension.list(<Extension>[init, num.of(4)])))).state;
      expect(state.facet(num), <int>[10, 4]);
    });

    test('one compartment keeps a value of its own in each state', () {
      final comp = Compartment();
      final a = EditorState.create(extensions: comp.of(num.of(1))), b = EditorState.create(extensions: comp.of(num.of(2)));
      final a2 = a.update(TransactionSpec(effects: comp.reconfigure(num.of(5)))).state;
      expect(a2.facet(num), <int>[5]);
      expect(b.facet(num), <int>[2]);
      expect(a.facet(num), <int>[1]);
    });

    test('a compartment swapped after a full reconfigure in one transaction leaves the old state alone', () {
      final comp = Compartment();
      final init = comp.of(num.of(1));
      final state = EditorState.create(extensions: init);
      final next = state.update(
        TransactionSpec(effects: <StateEffect<Object?>>[StateEffect.reconfigure.of(Extension.list(<Extension>[init, num.of(9)])), comp.reconfigure(num.of(2))]),
      ).state;
      expect(next.facet(num), <int>[2, 9]);
      expect(state.update(TransactionSpec(effects: StateEffect.appendConfig.of(num.of(7)))).state.facet(num), <int>[1, 7]);
    });

    test('keeps fields inside it across a swap that still has them', () {
      final comp = Compartment();
      final field = StateField.define<int>(create: (_) => 0, update: (v, _) => v + 1);
      var state = EditorState.create(extensions: comp.of(field));
      state = state.update().state.update(TransactionSpec(effects: comp.reconfigure(Extension.list(<Extension>[field, num.of(1)])))).state;
      expect(state.field(field), 2);
    });
  });

  group('Transaction', () {
    test('always has a time, and keeps one it was given', () {
      final state = EditorState.create();
      expect(state.update().annotation(Transaction.time), isNotNull);
      expect(state.update(TransactionSpec(annotations: Transaction.time.of(77))).annotation(Transaction.time), 77);
    });

    test('carries annotations and reads user events by prefix', () {
      final note = Annotation.define<String>();
      final tr = EditorState.create().update(
        TransactionSpec(annotations: <Annotation<Object?>>[note.of('hi'), Transaction.addToHistory.of(false)], userEvent: 'select.pointer'),
      );
      expect(tr.annotation(note), 'hi');
      expect(tr.annotation(Transaction.addToHistory), isFalse);
      expect(tr.annotation(Transaction.remote), isNull);
      expect(tr.isUserEvent('select'), isTrue);
      expect(tr.isUserEvent('select.pointer'), isTrue);
      expect(tr.isUserEvent('select.pointer.x'), isFalse);
      expect(tr.isUserEvent('sel'), isFalse);
      expect(EditorState.create().update().isUserEvent('select'), isFalse);
    });

    test('maps effects through the changes made beside them', () {
      final at = StateEffect.define<int>(map: (v, m) => m.mapPos(v));
      final gone = StateEffect.define<int>(map: (v, m) => m.mapPosTracked(v, -1, MapMode.trackDel) ?? StateEffect.dropped);
      final nothing = StateEffect.define<Object?>(map: (v, _) => v);
      final plain = StateEffect.define<String>();
      final state = EditorState.create(doc: 'abcdef');
      final tr = state.updateAll(<TransactionSpec>[
        TransactionSpec(effects: <StateEffect<Object?>>[at.of(4), gone.of(4), nothing.of(null), plain.of('p')]),
        const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'XX')),
        const TransactionSpec(changes: ChangeSpec(from: 3, to: 6)),
      ]);
      // The second effect's position was deleted, so it is gone; the null one is a value and stays.
      expect(<Object?>[for (final e in tr.effects) e.value], <Object?>[5, null, 'p']);
      expect(tr.effects[0].isOf(at), isTrue);
      expect(tr.effects[0].isOf(plain), isFalse);
      expect(at.cast(tr.effects[0])!.value + 1, 6);
      expect(plain.cast(tr.effects[0]), isNull);
      final same = plain.of('x');
      expect(same.map(tr.changes), same);
    });

    test('a spec may hold one effect, one annotation, or lists', () {
      final ping = StateEffect.define<int>();
      final state = EditorState.create();
      expect(state.update(TransactionSpec(effects: ping.of(1))).effects, hasLength(1));
      expect(state.update(TransactionSpec(effects: <StateEffect<Object?>>[ping.of(1), ping.of(2)])).effects, hasLength(2));
      expect(state.update().effects, isEmpty);
    });

    test('scrollIntoView is kept when any spec asks', () {
      final state = EditorState.create();
      expect(state.update().scrollIntoView, isFalse);
      expect(state.updateAll(const <TransactionSpec>[TransactionSpec(), TransactionSpec(scrollIntoView: true)]).scrollIntoView, isTrue);
    });
  });

  group('filters and extenders', () {
    test('changeFilter can cancel changes', () {
      final state = EditorState.create(doc: 'one two', extensions: EditorState.changeFilter.of((_) => false));
      final tr = state.update(TransactionSpec(changes: const ChangeSpec(from: 0, to: 3, insert: 'x'), selection: EditorSelection.single(1)));
      expect(tr.state.doc.toString(), 'one two');
      expect(tr.state.selection.main.head, 3);
    });

    test('changeFilter can split changes', () {
      final state = EditorState.create(doc: 'one two', extensions: EditorState.changeFilter.of((_) => <int>[0, 3]));
      final tr = state.update(const TransactionSpec(changes: <ChangeSpec>[ChangeSpec(from: 5, insert: 'ok'), ChangeSpec(from: 2, insert: '!')]));
      expect(tr.state.doc.toString(), 'one tokwo');
    });

    test('changeFilter combines filter masks', () {
      final state = EditorState.create(
        doc: '0123456789',
        extensions: Extension.list(<Extension>[
          EditorState.changeFilter.of((_) => <int>[0, 2]),
          EditorState.changeFilter.of((_) => <int>[4, 6]),
          EditorState.changeFilter.of((_) => true),
        ]),
      );
      final tr = state.update(const TransactionSpec(changes: <ChangeSpec>[ChangeSpec(from: 1, insert: 'A'), ChangeSpec(from: 3, insert: 'B'), ChangeSpec(from: 5, insert: 'C'), ChangeSpec(from: 9, insert: 'D')]));
      expect(tr.state.doc.toString(), '012B345678D9');
    });

    test('changeFilter can be turned off', () {
      final state = EditorState.create(doc: 'one two', extensions: EditorState.changeFilter.of((_) => false));
      final tr = state.update(const TransactionSpec(changes: ChangeSpec(from: 0, to: 3, insert: 'x'), filter: false));
      expect(tr.state.doc.toString(), 'x two');
    });

    test('transactionFilter can constrain the selection', () {
      final state = EditorState.create(
        doc: 'one two',
        extensions: EditorState.transactionFilter.of((tr) {
          if (tr.selection != null && tr.selection!.main.to > 4) return <Object>[tr, TransactionSpec(selection: EditorSelection.single(4))];
          return tr;
        }),
      );
      expect(state.update(TransactionSpec(selection: EditorSelection.single(7))).state.selection.main.to, 4);
      expect(state.update(TransactionSpec(selection: EditorSelection.single(2))).state.selection.main.to, 2);
    });

    test('transactionFilter can append sequential changes', () {
      final state = EditorState.create(
        doc: 'one two',
        extensions: EditorState.transactionFilter.of((tr) {
          if (tr.docChanged) return <Object>[tr, TransactionSpec(changes: ChangeSpec(from: tr.changes.newLength, insert: '!'), sequential: true)];
          return tr;
        }),
      );
      expect(state.update(const TransactionSpec(changes: ChangeSpec(from: 3, insert: ','))).state.doc.toString(), 'one, two!');
      expect(state.update(const TransactionSpec(changes: ChangeSpec(from: 3, insert: ','), filter: false)).state.doc.toString(), 'one, two');
    });

    test('transactionFilter may answer with a single spec, replacing the transaction', () {
      final state = EditorState.create(
        doc: 'abc',
        extensions: EditorState.transactionFilter.of((tr) => tr.docChanged ? const TransactionSpec(changes: ChangeSpec(from: 0, insert: '>')) : tr),
      );
      expect(state.update(const TransactionSpec(changes: ChangeSpec(from: 3, insert: 'zzz'))).state.doc.toString(), '>abc');
    });

    test('transactionExtender can add annotations and effects, even to an unfiltered transaction', () {
      final ann = Annotation.define<int>();
      final eff = StateEffect.define<int>();
      final state = EditorState.create(
        extensions: Extension.list(<Extension>[
          EditorState.transactionExtender.of((_) => TransactionSpec(annotations: ann.of(100))),
          EditorState.transactionExtender.of((tr) => tr.docChanged ? TransactionSpec(effects: eff.of(1)) : null),
        ]),
      );
      final plain = state.update(const TransactionSpec(filter: false));
      expect(plain.annotation(ann), 100);
      expect(plain.effects, isEmpty);
      final typed = state.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x')));
      expect(typed.annotation(ann), 100);
      expect(typed.effects.single.isOf(eff), isTrue);
      expect(typed.state.doc.toString(), 'x');
    });
  });

  group('the rest', () {
    test('combineConfig merges, combines and defaults', () {
      expect(
        combineConfig(
          <Map<String, Object?>>[
            <String, Object?>{'a': 1, 'b': 5},
            <String, Object?>{'a': 1, 'c': 'x', 'b': 9},
          ],
          <String, Object?>{'d': true, 'a': 0},
          <String, Object? Function(Object?, Object?)>{'b': (a, b) => (a as int) < (b as int) ? b : a},
        ),
        <String, Object?>{'a': 1, 'b': 9, 'c': 'x', 'd': true},
      );
      expect(
        () => combineConfig(<Map<String, Object?>>[<String, Object?>{'a': 1}, <String, Object?>{'a': 2}], const <String, Object?>{}),
        throwsStateError,
      );
    });

    test('languageData and the characters it adds to words', () {
      final state = EditorState.create(
        doc: 'foo-bar baz',
        extensions: EditorState.languageData.of((state, pos, side) => <Map<String, Object?>>[
          <String, Object?>{'wordChars': '-', 'closeBrackets': 'x'},
        ]),
      );
      expect(state.languageDataAt<String>('wordChars', 0), <String>['-']);
      expect(state.languageDataAt<String>('missing', 0), isEmpty);
      final word = state.wordAt(2)!;
      expect(<int>[word.from, word.to], <int>[0, 7]);
      final cat = state.charCategorizer(0);
      expect(cat('-'), CharCategory.word);
      expect(cat(' '), CharCategory.space);
      expect(cat('!'), CharCategory.other);
      expect(EditorState.create().charCategorizer(0)('-'), CharCategory.other);
    });

    test('a command runs on a plain target', () {
      var state = EditorState.create(doc: 'x');
      final target = StateCommandTarget(state, (tr) => state = tr.state);
      target.dispatch(state.update(const TransactionSpec(changes: ChangeSpec(from: 1, insert: 'y'))));
      expect(state.doc.toString(), 'xy');
      StateCommandTarget(state, (tr) => state = tr.state).dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: '>')));
      expect(state.doc.toString(), '>xy');
    });
  });
}

class _Looping extends ExtensionProvider {
  @override
  Extension get extension => this;
}
