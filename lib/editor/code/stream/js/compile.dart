part of 'js.dart';

// A syntax tree (acorn's, as tool/code_modes.mjs wrote it) made into Dart closures: each expression a function of
// the variables in reach that answers its value, each statement one that answers nothing, or how it was left
// (`break`, `continue`, `return`).
//
// Where a name lives is settled here, once: every function call has one list of slots for all the names
// declared anywhere in the function, and a name is read as "so many functions out, slot so-and-so". A `let` in
// a block has a slot of its own (so it may shadow), but one slot for every turn of a loop, where JavaScript
// gives each turn its own: no mode keeps a closure over a loop's `let`.

/// A compiled piece of the tree.
typedef Ev = Object? Function(Env e);

/// The variables of one call of a function (or of a module): its slots, and the call it was made in.
final class Env {
  Env(this.parent, int size, this.self) : slots = List<Object?>.filled(size, undefined);

  final Env? parent;
  final List<Object?> slots;

  /// `this`.
  final Object? self;

  /// What a `return` answered.
  Object? ret;
}

/// How a statement was left, when not by its end.
final class _Signal {
  const _Signal(this.kind, [this.label]);

  /// 0 `break`, 1 `continue`, 2 `return`.
  final int kind;
  final String? label;
}

const _Signal _break = _Signal(0), _continue = _Signal(1), _return = _Signal(2);

Object? _nothing(Env e) => null;

/// A function as written: what a [Closure] runs.
final class _Code {
  int size = 0;
  int params = 0;

  /// The values of parameters left out (`f(a = 1)`), by slot.
  List<(int, Ev)> defaults = const <(int, Ev)>[];

  /// The functions declared inside, which exist before the first statement runs.
  List<(int, _Code)> hoisted = const <(int, _Code)>[];
  List<Ev> body = const <Ev>[];
  int argumentsSlot = -1, selfSlot = -1;
}

/// A function of a mode, with the variables it was made among.
class Closure extends JsCallable {
  Closure._(this._code, this._env);

  final _Code _code;
  final Env _env;

  @override
  Object? call(Object? self, List<Object?> args) {
    final code = _code;
    final e = Env(_env, code.size, self);
    final slots = e.slots;
    final given = args.length < code.params ? args.length : code.params;
    for (var i = 0; i < given; i++) {
      slots[i] = args[i];
    }
    if (code.argumentsSlot >= 0) slots[code.argumentsSlot] = JsArray(List<Object?>.of(args));
    if (code.selfSlot >= 0) slots[code.selfSlot] = this;
    final hoisted = code.hoisted;
    for (var i = 0; i < hoisted.length; i++) {
      slots[hoisted[i].$1] = Closure._(hoisted[i].$2, e);
    }
    final defaults = code.defaults;
    for (var i = 0; i < defaults.length; i++) {
      if (identical(slots[defaults[i].$1], undefined)) slots[defaults[i].$1] = defaults[i].$2(e);
    }
    final body = code.body;
    for (var i = 0; i < body.length; i++) {
      if (body[i](e) != null) return e.ret;
    }
    return undefined;
  }
}

/// A module, run: what it exports.
typedef Exports = Map<String, Object?>;

class _Block {
  _Block(this.parent);

  final _Block? parent;
  final Map<String, int> names = <String, int>{};
}

class _Scope {
  _Scope(this.outer, this.outerBlock, {required this.isFunction});

  final _Scope? outer;
  final _Block? outerBlock;
  final bool isFunction;
  final _Block root = _Block(null);
  late _Block block = root;
  int size = 0;
  int argumentsSlot = -1;

  int declare(String name, [_Block? inBlock]) => (inBlock ?? block).names[name] ??= size++;
}

typedef _Node = Map<String, dynamic>;

/// Compiles and runs a module: `load` gives the exports of a module it imports, by the file's name.
Exports runModule(Map<String, dynamic> program, Exports Function(String file) load) => _Compiler().module(program, load);

class _Compiler {
  late _Scope _scope;

  Never _unsupported(String what) => throw UnsupportedError('JavaScript this does not read: $what');

  // ---- names ---------------------------------------------------------------------------------------------------------

  /// Where `name` lives from here: how many functions out, and the slot. Null for a name nobody declared.
  (int, int)? _resolve(String name) {
    var scope = _scope;
    _Block? block = scope.block;
    var depth = 0;
    while (true) {
      for (var b = block; b != null; b = b.parent) {
        final slot = b.names[name];
        if (slot != null) return (depth, slot);
      }
      if (name == 'arguments' && scope.isFunction) {
        scope.argumentsSlot = scope.declare(name, scope.root);
        return (depth, scope.argumentsSlot);
      }
      final outer = scope.outer;
      if (outer == null) return null;
      block = scope.outerBlock;
      scope = outer;
      depth++;
    }
  }

  Ev _read(String name) {
    final at = _resolve(name);
    if (at == null) {
      if (globals.containsKey(name)) {
        final value = globals[name];
        return (e) => value;
      }
      return (e) => throw _error('ReferenceError', '$name is not defined');
    }
    final (depth, slot) = at;
    switch (depth) {
      case 0:
        return (e) => e.slots[slot];
      case 1:
        return (e) => e.parent!.slots[slot];
      case 2:
        return (e) => e.parent!.parent!.slots[slot];
    }
    return (e) {
      var env = e;
      for (var i = 0; i < depth; i++) {
        env = env.parent!;
      }
      return env.slots[slot];
    };
  }

  /// Something that puts a value in `name`'s slot.
  void Function(Env e, Object? value) _write(String name) {
    final at = _resolve(name);
    if (at == null) return (e, value) => throw _error('ReferenceError', '$name is not defined');
    final (depth, slot) = at;
    switch (depth) {
      case 0:
        return (e, value) => e.slots[slot] = value;
      case 1:
        return (e, value) => e.parent!.slots[slot] = value;
    }
    return (e, value) {
      var env = e;
      for (var i = 0; i < depth; i++) {
        env = env.parent!;
      }
      env.slots[slot] = value;
    };
  }

  /// Declares what a function's body declares for the whole function, wherever in it: each `var`, and each
  /// function declared, which are gathered in `functions`.
  void _hoist(Object? node, List<_Node> functions) {
    if (node is List) {
      for (final item in node) {
        _hoist(item, functions);
      }
      return;
    }
    if (node is! Map<String, dynamic>) return;
    switch (node['type'] as String) {
      case 'VariableDeclaration':
        if (node['kind'] == 'var') {
          for (final declarator in node['declarations'] as List) {
            _scope.declare(_name((declarator as _Node)['id']), _scope.root);
          }
        }
      case 'FunctionDeclaration':
        _scope.declare(_name(node['id']), _scope.root);
        functions.add(node);
      case 'ExportNamedDeclaration':
        _hoist(node['declaration'], functions);
      case 'BlockStatement' || 'Program':
        _hoist(node['body'], functions);
      case 'IfStatement':
        _hoist(node['consequent'], functions);
        _hoist(node['alternate'], functions);
      case 'ForStatement':
        _hoist(node['init'], functions);
        _hoist(node['body'], functions);
      case 'ForInStatement':
        _hoist(node['left'], functions);
        _hoist(node['body'], functions);
      case 'WhileStatement' || 'DoWhileStatement' || 'LabeledStatement':
        _hoist(node['body'], functions);
      case 'SwitchStatement':
        for (final c in node['cases'] as List) {
          _hoist((c as _Node)['consequent'], functions);
        }
      case 'TryStatement':
        _hoist(node['block'], functions);
        _hoist((node['handler'] as _Node?)?['body'], functions);
        _hoist(node['finalizer'], functions);
    }
  }

  /// Declares what a block's own statements declare for the block: `let`, `const`, `class`.
  void _declareLexical(List<dynamic> statements) {
    for (var statement in statements) {
      statement as _Node;
      if (statement['type'] == 'ExportNamedDeclaration' && statement['declaration'] != null) statement = statement['declaration'] as _Node;
      if (statement['type'] == 'VariableDeclaration' && statement['kind'] != 'var') {
        for (final declarator in statement['declarations'] as List) {
          _newSlot(_name((declarator as _Node)['id']));
        }
      } else if (statement['type'] == 'ClassDeclaration') {
        _newSlot(_name(statement['id']));
      }
    }
  }

  /// A slot of its own for `name` in the block being compiled, whatever a block around it calls so.
  int _newSlot(String name) => _scope.block.names[name] = _scope.size++;

  String _name(Object? id) {
    final node = id as _Node;
    if (node['type'] != 'Identifier') _unsupported('a ${node['type']} where a name is declared');
    return node['name'] as String;
  }

  T _inBlock<T>(T Function() compile) {
    final outer = _scope.block;
    _scope.block = _Block(outer);
    try {
      return compile();
    } finally {
      _scope.block = outer;
    }
  }

  // ---- modules and functions -----------------------------------------------------------------------------------------

  Exports module(_Node program, Exports Function(String file) load) {
    _scope = _Scope(null, null, isFunction: false);
    final body = program['body'] as List;
    final imports = <(int, String, String)>[];
    final exported = <String, String>{};
    for (final statement in body.cast<_Node>()) {
      switch (statement['type']) {
        case 'ImportDeclaration':
          final file = (statement['source'] as _Node)['value'] as String;
          for (final specifier in (statement['specifiers'] as List).cast<_Node>()) {
            if (specifier['type'] != 'ImportSpecifier') _unsupported('${specifier['type']}');
            imports.add((_scope.declare(_name(specifier['local'])), file.replaceFirst(RegExp(r'^\./'), '').replaceFirst(RegExp(r'\.js$'), ''), _name(specifier['imported'])));
          }
        case 'ExportNamedDeclaration':
          final declaration = statement['declaration'] as _Node?;
          if (declaration == null) {
            for (final specifier in (statement['specifiers'] as List).cast<_Node>()) {
              exported[_name(specifier['exported'])] = _name(specifier['local']);
            }
          } else if (declaration['type'] == 'VariableDeclaration') {
            for (final declarator in (declaration['declarations'] as List).cast<_Node>()) {
              exported[_name(declarator['id'])] = _name(declarator['id']);
            }
          } else {
            exported[_name(declaration['id'])] = _name(declaration['id']);
          }
        case 'ExportDefaultDeclaration' || 'ExportAllDeclaration':
          _unsupported('${statement['type']}');
      }
    }
    final functions = <_Node>[];
    _hoist(body, functions);
    _declareLexical(body);
    final hoisted = <(int, _Code)>[for (final f in functions) (_scope.root.names[_name(f['id'])]!, _function(f))];
    final statements = <Ev>[
      for (final statement in body.cast<_Node>())
        if (statement['type'] != 'ImportDeclaration') _statement(statement),
    ];
    final slots = <String, int>{for (final entry in exported.entries) entry.key: _resolve(entry.value)!.$2};

    final e = Env(null, _scope.size, undefined);
    for (final (slot, file, name) in imports) {
      final from = load(file);
      if (!from.containsKey(name)) throw _error('SyntaxError', '$file does not export $name');
      e.slots[slot] = from[name];
    }
    for (final (slot, code) in hoisted) {
      e.slots[slot] = Closure._(code, e);
    }
    for (final statement in statements) {
      statement(e);
    }
    return <String, Object?>{for (final entry in slots.entries) entry.key: e.slots[entry.value]};
  }

  _Code _function(_Node node, {bool named = false}) {
    if (node['generator'] == true || node['async'] == true) _unsupported('a generator or an async function');
    final code = _Code();
    final scope = _Scope(_scope, _scope.block, isFunction: true);
    final outer = _scope;
    _scope = scope;
    try {
      final params = (node['params'] as List).cast<_Node>();
      final defaults = <(int, _Node)>[];
      for (final param in params) {
        if (param['type'] == 'AssignmentPattern') {
          // A slot of its own even where two parameters share a name, so that slots and arguments stay in step.
          final slot = scope.size++;
          scope.root.names[_name(param['left'])] = slot;
          defaults.add((slot, param['right'] as _Node));
        } else {
          final slot = scope.size++;
          scope.root.names[_name(param)] = slot;
        }
      }
      code.params = params.length;
      final body = ((node['body'] as _Node)['body'] as List).cast<_Node>();
      final functions = <_Node>[];
      _hoist(body, functions);
      // A function expression's own name, unless something inside is called the same.
      final id = node['id'] as _Node?;
      if (named && id != null && !scope.root.names.containsKey(id['name'])) code.selfSlot = scope.declare(id['name'] as String);
      _declareLexical(body);
      code.defaults = <(int, Ev)>[for (final (slot, value) in defaults) (slot, _expression(value))];
      code.hoisted = <(int, _Code)>[for (final f in functions) (scope.root.names[_name(f['id'])]!, _function(f))];
      code.body = <Ev>[for (final statement in body) _statement(statement)];
      code.argumentsSlot = scope.argumentsSlot;
      code.size = scope.size;
    } finally {
      _scope = outer;
    }
    return code;
  }

  // ---- statements ----------------------------------------------------------------------------------------------------

  Ev _sequence(List<Ev> list) {
    final all = <Ev>[
      for (final item in list)
        if (item != _nothing) item,
    ];
    switch (all.length) {
      case 0:
        return _nothing;
      case 1:
        return all[0];
      case 2:
        final a = all[0], b = all[1];
        return (e) => a(e) ?? b(e);
      case 3:
        final a = all[0], b = all[1], c = all[2];
        return (e) => a(e) ?? b(e) ?? c(e);
    }
    final n = all.length;
    return (e) {
      for (var i = 0; i < n; i++) {
        final signal = all[i](e);
        if (signal != null) return signal;
      }
      return null;
    };
  }

  Ev _block(List<dynamic> statements) => _inBlock(() {
    _declareLexical(statements);
    return _sequence(<Ev>[for (final statement in statements) _statement(statement as _Node)]);
  });

  /// What a loop does with how its body was left: 0 go on to the next turn, 1 leave the loop, 2 leave it and
  /// hand the signal on.
  static int _loop(Object signal, List<String> labels) {
    if (identical(signal, _continue)) return 0;
    if (identical(signal, _break)) return 1;
    final s = signal as _Signal;
    if (s.label != null && labels.contains(s.label)) return s.kind == 1 ? 0 : 1;
    return 2;
  }

  Ev _statement(_Node node, [List<String> labels = const <String>[]]) {
    switch (node['type'] as String) {
      case 'ExpressionStatement':
        final x = _expression(node['expression'] as _Node);
        return (e) {
          x(e);
          return null;
        };
      case 'VariableDeclaration':
        return _declaration(node);
      case 'FunctionDeclaration' || 'EmptyStatement':
        return _nothing;
      case 'ExportNamedDeclaration':
        final declaration = node['declaration'] as _Node?;
        return declaration == null ? _nothing : _statement(declaration);
      case 'ReturnStatement':
        final argument = node['argument'] as _Node?;
        if (argument == null) {
          return (e) {
            e.ret = undefined;
            return _return;
          };
        }
        final x = _expression(argument);
        return (e) {
          e.ret = x(e);
          return _return;
        };
      case 'IfStatement':
        final test = _expression(node['test'] as _Node), then = _statement(node['consequent'] as _Node);
        final otherwise = node['alternate'] == null ? null : _statement(node['alternate'] as _Node);
        if (otherwise == null) return (e) => truthy(test(e)) ? then(e) : null;
        return (e) => truthy(test(e)) ? then(e) : otherwise(e);
      case 'BlockStatement':
        return _block(node['body'] as List);
      case 'WhileStatement':
        final test = _expression(node['test'] as _Node), body = _statement(node['body'] as _Node);
        return (e) {
          while (truthy(test(e))) {
            if (--_fuel < 0) _spent();
            final signal = body(e);
            if (signal != null) {
              final what = _loop(signal, labels);
              if (what == 1) break;
              if (what == 2) return signal;
            }
          }
          return null;
        };
      case 'DoWhileStatement':
        final test = _expression(node['test'] as _Node), body = _statement(node['body'] as _Node);
        return (e) {
          do {
            if (--_fuel < 0) _spent();
            final signal = body(e);
            if (signal != null) {
              final what = _loop(signal, labels);
              if (what == 1) break;
              if (what == 2) return signal;
            }
          } while (truthy(test(e)));
          return null;
        };
      case 'ForStatement':
        return _inBlock(() {
          final first = node['init'] as _Node?;
          Ev? init;
          if (first != null) {
            if (first['type'] == 'VariableDeclaration') {
              _declareLexical(<dynamic>[first]);
              init = _declaration(first);
            } else {
              init = _expression(first);
            }
          }
          final test = node['test'] == null ? null : _expression(node['test'] as _Node);
          final update = node['update'] == null ? null : _expression(node['update'] as _Node);
          final body = _statement(node['body'] as _Node);
          return (e) {
            if (init != null) init(e);
            while (test == null || truthy(test(e))) {
              if (--_fuel < 0) _spent();
              final signal = body(e);
              if (signal != null) {
                final what = _loop(signal, labels);
                if (what == 1) break;
                if (what == 2) return signal;
              }
              if (update != null) update(e);
            }
            return null;
          };
        });
      case 'ForInStatement':
        return _inBlock(() {
          final left = node['left'] as _Node;
          final void Function(Env e, Object? value) put;
          if (left['type'] == 'VariableDeclaration') {
            _declareLexical(<dynamic>[left]);
            put = _write(_name(((left['declarations'] as List)[0] as _Node)['id']));
          } else {
            put = _target(left);
          }
          final of = _expression(node['right'] as _Node), body = _statement(node['body'] as _Node);
          return (e) {
            for (final key in forInKeys(of(e))) {
              if (--_fuel < 0) _spent();
              put(e, key);
              final signal = body(e);
              if (signal != null) {
                final what = _loop(signal, labels);
                if (what == 1) break;
                if (what == 2) return signal;
              }
            }
            return null;
          };
        });
      case 'BreakStatement' || 'ContinueStatement':
        final label = (node['label'] as _Node?)?['name'] as String?;
        final isBreak = node['type'] == 'BreakStatement';
        final signal = label == null ? (isBreak ? _break : _continue) : _Signal(isBreak ? 0 : 1, label);
        return (e) => signal;
      case 'LabeledStatement':
        final label = _name(node['label']);
        final body = _statement(node['body'] as _Node, <String>[...labels, label]);
        // A `break` to this label from a statement that is no loop: the loops take theirs themselves.
        return (e) {
          final signal = body(e);
          if (signal is _Signal && signal.kind == 0 && signal.label == label) return null;
          return signal;
        };
      case 'SwitchStatement':
        return _inBlock(() {
          final on = _expression(node['discriminant'] as _Node);
          final cases = (node['cases'] as List).cast<_Node>();
          for (final c in cases) {
            _declareLexical(c['consequent'] as List);
          }
          final tests = <Ev?>[for (final c in cases) c['test'] == null ? null : _expression(c['test'] as _Node)];
          final bodies = <Ev>[
            for (final c in cases) _sequence(<Ev>[for (final statement in c['consequent'] as List) _statement(statement as _Node)]),
          ];
          final otherwise = tests.indexOf(null);
          return (e) {
            final value = on(e);
            var at = otherwise;
            for (var i = 0; i < tests.length; i++) {
              final test = tests[i];
              if (test != null && strictEquals(value, test(e))) {
                at = i;
                break;
              }
            }
            if (at < 0) return null;
            for (var i = at; i < bodies.length; i++) {
              final signal = bodies[i](e);
              if (signal != null) return identical(signal, _break) ? null : signal;
            }
            return null;
          };
        });
      case 'ThrowStatement':
        final x = _expression(node['argument'] as _Node);
        return (e) => throw JsThrow(x(e));
      case 'TryStatement':
        final block = _statement(node['block'] as _Node);
        final handler = node['handler'] as _Node?;
        void Function(Env e, Object? value)? caught;
        Ev? recover;
        if (handler != null) {
          _inBlock(() {
            if (handler['param'] != null) {
              _newSlot(_name(handler['param']));
              caught = _write(_name(handler['param']));
            }
            recover = _statement(handler['body'] as _Node);
          });
        }
        final last = node['finalizer'] == null ? null : _statement(node['finalizer'] as _Node);
        return (e) {
          Object? signal;
          try {
            signal = block(e);
          } on JsThrow catch (thrown) {
            if (recover == null) {
              if (last != null) last(e);
              rethrow;
            }
            caught?.call(e, thrown.value);
            signal = recover!(e);
          }
          if (last != null) {
            final after = last(e);
            if (after != null) return after;
          }
          return signal;
        };
      case 'ClassDeclaration':
        return _class(node);
    }
    _unsupported(node['type'] as String);
  }

  Ev _declaration(_Node node) {
    final lexical = node['kind'] != 'var';
    final all = <Ev>[];
    for (final declarator in (node['declarations'] as List).cast<_Node>()) {
      final put = _write(_name(declarator['id']));
      final init = declarator['init'] as _Node?;
      if (init != null) {
        final x = _expression(init);
        all.add((e) {
          put(e, x(e));
          return null;
        });
      } else if (lexical) {
        // `let x` in a loop starts each turn undefined; `var x` leaves what was there.
        all.add((e) {
          put(e, undefined);
          return null;
        });
      }
    }
    return _sequence(all);
  }

  Ev _class(_Node node) {
    if (node['superClass'] != null) _unsupported('a class that extends another');
    final put = _write(_name(node['id']));
    _Code? constructor;
    final methods = <(String, _Code)>[];
    for (final member in ((node['body'] as _Node)['body'] as List).cast<_Node>()) {
      if (member['type'] != 'MethodDefinition' || member['static'] == true || member['computed'] == true) _unsupported('a class with ${member['type']}');
      final code = _function(member['value'] as _Node);
      if (member['kind'] == 'constructor') {
        constructor = code;
      } else if (member['kind'] == 'method') {
        methods.add((_name(member['key']), code));
      } else {
        _unsupported('a class with a ${member['kind']}');
      }
    }
    return (e) {
      final JsCallable made = constructor != null ? Closure._(constructor, e) : Native((self, args) => undefined);
      final prototype = JsObject()..listed = false;
      for (final (name, code) in methods) {
        prototype.props[name] = Closure._(code, e);
      }
      made.props['prototype'] = prototype;
      put(e, made);
      return null;
    };
  }

  // ---- expressions ---------------------------------------------------------------------------------------------------

  /// Something that puts a value where `node` names: a variable, or a property of an object.
  void Function(Env e, Object? value) _target(_Node node) {
    if (node['type'] == 'Identifier') return _write(node['name'] as String);
    if (node['type'] != 'MemberExpression') _unsupported('assigning to a ${node['type']}');
    final object = _expression(node['object'] as _Node);
    if (node['computed'] == true) {
      final key = _expression(node['property'] as _Node);
      return (e, value) => setComputed(object(e), key(e), value);
    }
    final name = _name(node['property']);
    return (e, value) => setNamed(object(e), name, value);
  }

  static List<Object?> _arguments(List<Ev> args, Env e) {
    switch (args.length) {
      case 0:
        return const <Object?>[];
      case 1:
        return <Object?>[args[0](e)];
      case 2:
        return <Object?>[args[0](e), args[1](e)];
    }
    return <Object?>[for (var i = 0; i < args.length; i++) args[i](e)];
  }

  List<Ev> _each(Object? nodes) => <Ev>[
    for (final node in (nodes! as List).cast<_Node>())
      if (node['type'] == 'SpreadElement') _unsupported('a spread among arguments') else _expression(node),
  ];

  Ev _expression(_Node node) {
    switch (node['type'] as String) {
      case 'Literal':
        final regex = node['regex'] as _Node?;
        if (regex != null) {
          final source = regex['pattern'] as String, flags = regex['flags'] as String;
          // A pattern that keeps its place (`g`, `y`) is a new one each time it is come to, as in JavaScript;
          // one that keeps nothing may as well be the same one.
          if (flags.contains('g') || flags.contains('y')) return (e) => JsRegExp(source, flags);
          final one = JsRegExp(source, flags);
          return (e) => one;
        }
        final value = node['value'] as Object?;
        return (e) => value;
      case 'Identifier':
        return _read(node['name'] as String);
      case 'ThisExpression':
        return (e) => e.self;
      case 'ArrayExpression':
        final items = <Ev>[
          for (final item in node['elements'] as List)
            if (item == null) ((e) => undefined) else if ((item as _Node)['type'] == 'SpreadElement') _unsupported('a spread in an array') else _expression(item),
        ];
        return (e) => JsArray(<Object?>[for (var i = 0; i < items.length; i++) items[i](e)]);
      case 'ObjectExpression':
        return _objectLiteral(node);
      case 'FunctionExpression':
        final code = _function(node, named: true);
        return (e) => Closure._(code, e);
      case 'UnaryExpression':
        return _unary(node);
      case 'UpdateExpression':
        return _update(node);
      case 'BinaryExpression':
        return _binary(node['operator'] as String, _expression(node['left'] as _Node), _expression(node['right'] as _Node));
      case 'LogicalExpression':
        final left = _expression(node['left'] as _Node), right = _expression(node['right'] as _Node);
        switch (node['operator']) {
          case '&&':
            return (e) {
              final l = left(e);
              return truthy(l) ? right(e) : l;
            };
          case '||':
            return (e) {
              final l = left(e);
              return truthy(l) ? l : right(e);
            };
          case '??':
            return (e) {
              final l = left(e);
              return l == null || identical(l, undefined) ? right(e) : l;
            };
        }
        _unsupported('${node['operator']}');
      case 'AssignmentExpression':
        return _assignment(node);
      case 'ConditionalExpression':
        final test = _expression(node['test'] as _Node), then = _expression(node['consequent'] as _Node), otherwise = _expression(node['alternate'] as _Node);
        return (e) => truthy(test(e)) ? then(e) : otherwise(e);
      case 'CallExpression':
        return _callOf(node);
      case 'NewExpression':
        final callee = _expression(node['callee'] as _Node);
        final args = _each(node['arguments']);
        return (e) {
          final f = callee(e);
          if (f is JsCallable) return f.construct(_arguments(args, e));
          _typeError('${toStr(f)} is not a constructor');
        };
      case 'MemberExpression':
        final object = _expression(node['object'] as _Node);
        if (node['computed'] == true) {
          final property = node['property'] as _Node;
          if (property['type'] == 'Literal' && property['value'] is String) {
            final name = property['value'] as String;
            return (e) => getNamed(object(e), name);
          }
          final key = _expression(property);
          return (e) => getComputed(object(e), key(e));
        }
        final name = _name(node['property']);
        return (e) => getNamed(object(e), name);
      case 'SequenceExpression':
        final all = <Ev>[for (final x in (node['expressions'] as List).cast<_Node>()) _expression(x)];
        return (e) {
          Object? value;
          for (var i = 0; i < all.length; i++) {
            value = all[i](e);
          }
          return value;
        };
    }
    _unsupported(node['type'] as String);
  }

  Ev _objectLiteral(_Node node) {
    final names = <String?>[];
    final keys = <Ev?>[];
    final values = <Ev>[];
    for (final property in (node['properties'] as List).cast<_Node>()) {
      if (property['type'] == 'SpreadElement') {
        names.add(null);
        keys.add(null);
        values.add(_expression(property['argument'] as _Node));
        continue;
      }
      if (property['kind'] != 'init') _unsupported('a getter or a setter');
      final key = property['key'] as _Node;
      if (property['computed'] == true) {
        names.add(null);
        keys.add(_expression(key));
      } else {
        names.add(key['type'] == 'Identifier' ? key['name'] as String : toStr(key['value']));
        keys.add(null);
      }
      values.add(_expression(property['value'] as _Node));
    }
    final n = values.length;
    return (e) {
      final made = JsObject();
      final props = made.props;
      for (var i = 0; i < n; i++) {
        final name = names[i], key = keys[i];
        if (name != null) {
          props[name] = values[i](e);
        } else if (key != null) {
          props[toStr(key(e))] = values[i](e);
        } else {
          // `...other`: its own properties, as they stand.
          final from = values[i](e);
          if (from is JsObject) {
            for (final k in from.ownKeys()) {
              props[k] = from.get(k);
            }
          }
        }
      }
      return made;
    };
  }

  Ev _unary(_Node node) {
    final argument = node['argument'] as _Node;
    final op = node['operator'] as String;
    if (op == 'typeof' && argument['type'] == 'Identifier' && _resolve(argument['name'] as String) == null && !globals.containsKey(argument['name'])) {
      return (e) => 'undefined';
    }
    if (op == 'delete') {
      if (argument['type'] != 'MemberExpression') _unsupported('delete of a ${argument['type']}');
      final object = _expression(argument['object'] as _Node);
      final key = argument['computed'] == true ? _expression(argument['property'] as _Node) : null;
      final name = key == null ? _name(argument['property']) : null;
      return (e) {
        final o = object(e);
        if (o is JsObject) o.delete(name ?? toStr(key!(e)));
        return true;
      };
    }
    final x = _expression(argument);
    switch (op) {
      case '!':
        return (e) => !truthy(x(e));
      case '-':
        return (e) {
          final v = x(e);
          return v is num ? -v : -toNum(v);
        };
      case '+':
        return (e) => toNum(x(e));
      case 'typeof':
        return (e) => typeOf(x(e));
      case 'void':
        return (e) {
          x(e);
          return undefined;
        };
      case '~':
        return (e) => ~_int32(x(e));
    }
    _unsupported('the operator $op');
  }

  Ev _update(_Node node) {
    final argument = node['argument'] as _Node;
    final by = node['operator'] == '++' ? 1 : -1;
    final prefix = node['prefix'] == true;
    if (argument['type'] == 'Identifier') {
      final get = _read(argument['name'] as String), put = _write(argument['name'] as String);
      return (e) {
        final was = toNum(get(e)), now = was + by;
        put(e, now);
        return prefix ? now : was;
      };
    }
    if (argument['type'] != 'MemberExpression') _unsupported('++ of a ${argument['type']}');
    final object = _expression(argument['object'] as _Node);
    final key = argument['computed'] == true ? _expression(argument['property'] as _Node) : null;
    final name = key == null ? _name(argument['property']) : null;
    return (e) {
      final o = object(e);
      final k = name ?? key!(e);
      final was = toNum(getComputed(o, k)), now = was + by;
      setComputed(o, k, now);
      return prefix ? now : was;
    };
  }

  Ev _assignment(_Node node) {
    final left = node['left'] as _Node;
    final operator = node['operator'] as String;
    final value = _expression(node['right'] as _Node);
    if (operator == '=') {
      if (left['type'] == 'Identifier') {
        final put = _write(left['name'] as String);
        return (e) {
          final v = value(e);
          put(e, v);
          return v;
        };
      }
      if (left['type'] != 'MemberExpression') _unsupported('assigning to a ${left['type']}');
      final object = _expression(left['object'] as _Node);
      if (left['computed'] == true) {
        final key = _expression(left['property'] as _Node);
        return (e) {
          final o = object(e), k = key(e), v = value(e);
          setComputed(o, k, v);
          return v;
        };
      }
      final name = _name(left['property']);
      return (e) {
        final o = object(e), v = value(e);
        setNamed(o, name, v);
        return v;
      };
    }
    // `a += b` and its like: the operator between what is there and the value. `&&=` and its like are not used.
    final op = operator.substring(0, operator.length - 1);
    if (op == '&&' || op == '||' || op == '??') _unsupported('the operator $operator');
    if (left['type'] == 'Identifier') {
      final get = _read(left['name'] as String), put = _write(left['name'] as String);
      final combined = _binary(op, get, value);
      return (e) {
        final v = combined(e);
        put(e, v);
        return v;
      };
    }
    if (left['type'] != 'MemberExpression') _unsupported('assigning to a ${left['type']}');
    final object = _expression(left['object'] as _Node);
    final key = left['computed'] == true ? _expression(left['property'] as _Node) : null;
    final name = key == null ? _name(left['property']) : null;
    final apply = _operator(op);
    return (e) {
      final o = object(e);
      final k = name ?? key!(e);
      final v = apply(getComputed(o, k), value(e));
      setComputed(o, k, v);
      return v;
    };
  }

  Ev _callOf(_Node node) {
    final callee = node['callee'] as _Node;
    final args = _each(node['arguments']);
    if (callee['type'] == 'MemberExpression') {
      final object = _expression(callee['object'] as _Node);
      if (callee['computed'] == true) {
        final key = _expression(callee['property'] as _Node);
        return (e) {
          final o = object(e), k = key(e);
          final f = getComputed(o, k);
          if (f is JsCallable) return f.call(o, _arguments(args, e));
          _typeError('${toStr(k)} is not a function');
        };
      }
      final name = _name(callee['property']);
      switch (args.length) {
        case 0:
          return (e) {
            final o = object(e);
            final f = getNamed(o, name);
            if (f is JsCallable) return f.call(o, const <Object?>[]);
            _typeError('$name is not a function');
          };
        case 1:
          final a = args[0];
          return (e) {
            final o = object(e);
            final f = getNamed(o, name);
            if (f is JsCallable) return f.call(o, <Object?>[a(e)]);
            _typeError('$name is not a function');
          };
      }
      return (e) {
        final o = object(e);
        final f = getNamed(o, name);
        if (f is JsCallable) return f.call(o, _arguments(args, e));
        _typeError('$name is not a function');
      };
    }
    final function = _expression(callee);
    final what = callee['type'] == 'Identifier' ? callee['name'] as String : 'that';
    return (e) {
      final f = function(e);
      if (f is JsCallable) return f.call(undefined, _arguments(args, e));
      _typeError('$what is not a function');
    };
  }

  Ev _binary(String op, Ev left, Ev right) {
    switch (op) {
      case '===':
        return (e) => strictEquals(left(e), right(e));
      case '!==':
        return (e) => !strictEquals(left(e), right(e));
      case '==':
        return (e) => looseEquals(left(e), right(e));
      case '!=':
        return (e) => !looseEquals(left(e), right(e));
      case '+':
        return (e) => _add(left(e), right(e));
      case '<':
        return (e) {
          final a = left(e), b = right(e);
          if (a is num && b is num) return a < b;
          return _compare(a, b) == -1;
        };
      case '>':
        return (e) {
          final a = left(e), b = right(e);
          if (a is num && b is num) return a > b;
          return _compare(a, b) == 1;
        };
      case '<=':
        return (e) {
          final c = _compare(left(e), right(e));
          return c != null && c <= 0;
        };
      case '>=':
        return (e) {
          final c = _compare(left(e), right(e));
          return c != null && c >= 0;
        };
    }
    final apply = _operator(op);
    return (e) => apply(left(e), right(e));
  }

  /// The rarer operators, as functions of two values.
  Object? Function(Object? a, Object? b) _operator(String op) {
    switch (op) {
      case '+':
        return _add;
      case '-':
        return (a, b) => a is num && b is num ? a - b : toNum(a) - toNum(b);
      case '*':
        return (a, b) => toNum(a) * toNum(b);
      case '/':
        return (a, b) => toNum(a) / toNum(b);
      case '%':
        return (a, b) {
          final x = toNum(a), y = toNum(b);
          return y == 0 || x != x || y != y ? double.nan : x.remainder(y);
        };
      case '|':
        return (a, b) => (_int32(a) | _int32(b)).toSigned(32);
      case '&':
        return (a, b) => (_int32(a) & _int32(b)).toSigned(32);
      case '^':
        return (a, b) => (_int32(a) ^ _int32(b)).toSigned(32);
      case '<<':
        return (a, b) => (_int32(a) << (_int32(b) & 31)).toSigned(32);
      case '>>':
        return (a, b) => _int32(a) >> (_int32(b) & 31);
      case '>>>':
        return (a, b) => _int32(a).toUnsigned(32) >> (_int32(b) & 31);
      case 'instanceof':
        return _instanceOf;
      case 'in':
        return (a, b) {
          if (b is! JsObject) _typeError("Cannot use 'in' operator to search for '${toStr(a)}' in ${toStr(b)}");
          return b.has(toStr(a));
        };
    }
    _unsupported('the operator $op');
  }
}
