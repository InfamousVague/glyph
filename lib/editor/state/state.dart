/// The editor's state and everything that configures it: CodeMirror's `EditorState`, `Transaction`,
/// `TransactionSpec`, `StateField`, `StateEffect`, `Annotation`, `Facet`, `Compartment`, `Prec` and the extension
/// tree (@codemirror/state: state.ts, transaction.ts, facet.ts, extension.ts), ported by structure and by name so an
/// extension file from ../glyph ports line by line.
///
/// A configuration is resolved exactly as CodeMirror resolves one: the extension tree is flattened by precedence
/// (five buckets, a value seen twice kept at its higher precedence), every field and every facet gets an address,
/// static facets are combined once, and dynamic slots are recomputed lazily, each only when something it depends on
/// changed. A reconfiguration keeps every value whose inputs are the same.
///
/// What Dart makes different (each is noted again where it is declared):
/// - an extension array is `Extension.list([...])`; anything with an `extension` getter extends
///   [ExtensionProvider];
/// - `state.field(f, false)` is [EditorState.fieldOrNull];
/// - `effect.is(type)` is [StateEffect.isOf] (`is` is a keyword), and [StateEffectType.cast] gives the typed effect;
/// - an effect's `map` returns [StateEffect.dropped] where CodeMirror's returns `undefined`;
/// - `state.update({...})` takes a [TransactionSpec]; several specs go to [EditorState.updateAll];
/// - "one or an array" parameters (`changes`, `effects`, `annotations`) are `Object?`: one value or a `List`;
/// - `Facet.define({static: true})` is `isStatic: true`, `Prec.default` is [Prec.default_], and the static facets
///   `EditorState.readOnly` and `EditorState.tabSize` are [EditorState.readOnlyFacet] and
///   [EditorState.tabSizeFacet], because Dart will not have a static beside an instance member of the same name;
///   for the same reason `Compartment.reconfigure` (the effect type) is [Compartment.reconfigureEffect].
library;

import 'change.dart';
import 'char.dart';
import 'selection.dart';
import 'text.dart';

int _nextId = 0;

/// Whether this build measures itself (`--dart-define=GHOST_PERF=true`, lib/perf): a constant, asked before every
/// use of [StateProbe], so a build that does not measure has none of it.
const bool _measured = bool.fromEnvironment('GHOST_PERF');

/// A measured build's ear in the state: told when a field's update or a computed facet's begins and ends, and
/// which (by where it was defined). Set by lib/editor/view/measured.dart; never in any other build.
abstract final class StateProbe {
  static int Function()? enter;
  static void Function(String what, int began)? leave;

  /// Where the thing defined under `stack` was written: the first frame outside this file, as
  /// `editor/media/images.dart:270`. Read from the stack only when the thing is first timed: naming the frames is
  /// slow, and a facet computed for one editor and never worked out again is never named.
  static String _site(String kind, StackTrace? stack) {
    if (stack == null) return kind;
    for (final line in stack.toString().split('\n')) {
      if (line.contains('editor/state/state.dart')) continue;
      final found = _siteOf.firstMatch(line);
      if (found != null) return '$kind ${found.group(1)}';
    }
    return kind;
  }

  static final RegExp _siteOf = RegExp(r'package:ghost_md/([^:)]+:\d+)');
}

// JavaScript's `===` for what a facet or field holds: the same object, or the same number, string or boolean.
bool _same(Object? a, Object? b) => identical(a, b) || ((a is num || a is String || a is bool) && a == b);

bool _sameArray(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is! List || b is! List || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_same(a[i], b[i])) return false;
  }
  return true;
}

List<Object?> _asArray(Object? value) => value == null
    ? const <Object?>[]
    : value is List
    ? value
    : <Object?>[value];

// ---------------------------------------------------------------------------------------------------------------
// Extensions
// ---------------------------------------------------------------------------------------------------------------

/// CodeMirror's `Extension`: a value that configures a state. Fields, facet providers, [Prec] and [Compartment]
/// wrappers are extensions; so is a list of extensions ([Extension.list]) and anything that hands one out
/// ([ExtensionProvider]).
abstract interface class Extension {
  /// CodeMirror's extension array: `[a, b, c]` there, `Extension.list([a, b, c])` here. Nests as deep as it likes.
  const factory Extension.list(List<Extension> extensions) = ExtensionList;
}

/// An array of extensions; see [Extension.list]. Told apart by identity, as a JavaScript array is: the same list
/// object given twice is resolved once.
class ExtensionList implements Extension {
  const ExtensionList(this.extensions);

  final List<Extension> extensions;
}

/// CodeMirror's `{extension: Extension}`: an object that is not an extension itself but carries one (a view plugin,
/// a language).
abstract class ExtensionProvider implements Extension {
  Extension get extension;
}

// Prec_
const int _precHighest = 0, _precHigh = 1, _precDefault = 2, _precLow = 3, _precLowest = 4;

/// CodeMirror's `Prec`: wraps an extension so it sorts before or after the others, whatever its place in the tree.
abstract final class Prec {
  /// Before everything else.
  static Extension highest(Extension ext) => _PrecExtension(ext, _precHighest);

  /// Before the default.
  static Extension high(Extension ext) => _PrecExtension(ext, _precHigh);

  /// The default precedence, where an extension lands when nothing says otherwise (CodeMirror's `Prec.default`).
  static Extension default_(Extension ext) => _PrecExtension(ext, _precDefault);

  /// After the default.
  static Extension low(Extension ext) => _PrecExtension(ext, _precLow);

  /// After everything else.
  static Extension lowest(Extension ext) => _PrecExtension(ext, _precLowest);
}

class _PrecExtension implements Extension {
  _PrecExtension(this.inner, this.prec);

  final Extension inner;
  final int prec;
}

/// CodeMirror's `Compartment`: a key under which part of a configuration can be swapped later. One compartment
/// serves every editor; each state keeps its own value under it.
class Compartment {
  /// This compartment holding `ext`, to put in a configuration.
  Extension of(Extension ext) => _CompartmentInstance(this, ext);

  /// The effect that replaces this compartment's content.
  StateEffect<({Compartment compartment, Extension extension})> reconfigure(Extension content) =>
      reconfigureEffect.of((compartment: this, extension: content));

  /// What this compartment holds in `state`, or null when the state does not use it.
  Extension? get(EditorState state) => state._config.compartments[this];

  /// CodeMirror's static `Compartment.reconfigure`: the type of the effects [reconfigure] makes.
  static final StateEffectType<({Compartment compartment, Extension extension})> reconfigureEffect = StateEffect.define();
}

class _CompartmentInstance implements Extension {
  _CompartmentInstance(this.compartment, this.inner);

  final Compartment compartment;
  final Extension inner;
}

// ---------------------------------------------------------------------------------------------------------------
// Facets
// ---------------------------------------------------------------------------------------------------------------

// Provider
const int _providerStatic = 0, _providerSingle = 1, _providerMulti = 2;

// SlotStatus
const int _slotUnresolved = 0, _slotChanged = 1, _slotComputed = 2, _slotComputing = 4;

/// What [Facet.compute] may depend on, beside facets and fields: CodeMirror's `"doc"`.
const String docDependency = 'doc';

/// What [Facet.compute] may depend on, beside facets and fields: CodeMirror's `"selection"`.
const String selectionDependency = 'selection';

/// CodeMirror's `Facet`: a labelled value that any number of extensions give inputs to, combined into one output.
/// `I` is what a provider gives, `O` what a reader gets.
class Facet<I, O> {
  Facet._(this.combine, this.compareInput, this.compare, this.isStatic, Extension? enables, Extension Function(Facet<I, O>)? enablesFrom)
    : id = _nextId++ {
    extensions = enablesFrom != null ? enablesFrom(this) : enables;
  }

  /// Turns the inputs, highest precedence first, into the facet's value.
  final O Function(List<I> values) combine;

  /// Whether two inputs are the same, so a provider that computes an equal value does not count as a change.
  final bool Function(I a, I b) compareInput;

  /// Whether two outputs are the same.
  final bool Function(O a, O b) compare;

  /// A static facet takes no computed providers, so its value is known while the configuration is resolved.
  final bool isStatic;

  final int id;

  /// The value with no providers: CodeMirror's `default`.
  late final O defaultValue = combine(<I>[]);

  /// Extensions a provider of this facet brings with it (the `enables` option).
  Extension? extensions;

  /// CodeMirror's `reader`: the facet itself.
  Facet<I, O> get reader => this;

  /// Defines a facet. Without `combine` the value is the list of inputs, so `O` must be `List<I>`:
  /// `Facet.define<int, List<int>>()`. `isStatic` is the `static` option; `enables` is an extension that comes with
  /// every provider, or `enablesFrom` when it needs the facet itself.
  static Facet<I, O> define<I, O>({
    O Function(List<I> values)? combine,
    bool Function(I a, I b)? compareInput,
    bool Function(O a, O b)? compare,
    bool isStatic = false,
    Extension? enables,
    Extension Function(Facet<I, O> self)? enablesFrom,
  }) {
    return Facet<I, O>._(
      combine ?? ((List<I> a) => a as O),
      compareInput ?? _same,
      compare ?? (combine == null ? _sameArray : _same),
      isStatic,
      enables,
      enablesFrom,
    );
  }

  /// A provider with a fixed value.
  Extension of(I value) => _FacetProvider(const <Object>[], this, _providerStatic, value, null);

  /// A provider whose value is computed from the state, again whenever one of `deps` changed. A dependency is a
  /// [Facet], a [StateField], [docDependency] or [selectionDependency].
  Extension compute(List<Object> deps, I Function(EditorState state) get) {
    if (isStatic) throw StateError("Can't compute a static facet");
    return _FacetProvider(deps, this, _providerSingle, null, get);
  }

  /// As [compute], for a provider that gives several inputs at once.
  Extension computeN(List<Object> deps, List<I> Function(EditorState state) get) {
    if (isStatic) throw StateError("Can't compute a static facet");
    return _FacetProvider(deps, this, _providerMulti, null, get);
  }

  /// A provider that reads its input from a field: the field's value itself, or `get` of it.
  Extension from<T>(StateField<T> field, [I Function(T value)? get]) =>
      compute(<Object>[field], (state) => get != null ? get(state.field(field)) : state.field(field) as I);

  // The untyped side, for the configuration. A function-typed field read through `Facet<Object?, Object?>` fails
  // Dart's check, so the fields are only ever read here, where `I` and `O` are the real ones.
  Object? _combineDyn(List<Object?> values) => combine(List<I>.from(values));
  bool _compareDyn(Object? a, Object? b) => compare(a as O, b as O);
  bool _compareInputDyn(Object? a, Object? b) => compareInput(a as I, b as I);
}

class _FacetProvider implements Extension {
  _FacetProvider(this.dependencies, this.facet, this.type, this.value, this.getter) : id = _nextId++, _defined = _measured && getter != null ? StackTrace.current : null;

  /// Where it was defined, in a build that measures itself.
  final StackTrace? _defined;
  late final String _site = StateProbe._site('compute', _defined);

  final List<Object> dependencies;
  final Facet<dynamic, dynamic> facet;
  final int type;
  final Object? value;
  final Object? Function(EditorState state)? getter;
  final int id;

  _DynamicSlot dynamicSlot(Map<int, int> addresses) {
    final getter = this.getter!;
    final facet = this.facet;
    final idx = addresses[id]! >> 1, multi = type == _providerMulti;
    var depDoc = false, depSel = false;
    final depAddrs = <int>[];
    for (final dep in dependencies) {
      if (dep == docDependency) {
        depDoc = true;
      } else if (dep == selectionDependency) {
        depSel = true;
      } else {
        final addr = addresses[_dependencyId(dep)];
        if (((addr ?? 1) & 1) == 0) depAddrs.add(addr!);
      }
    }
    bool compare(Object? a, Object? b) => multi ? _compareArray(a as List, b as List, facet._compareInputDyn) : facet._compareInputDyn(a, b);

    return _DynamicSlot(
      create: (state) {
        state._values[idx] = getter(state);
        return _slotChanged;
      },
      update: (state, tr) {
        if ((depDoc && tr.docChanged) || (depSel && (tr.docChanged || tr.selection != null)) || _ensureAll(state, depAddrs)) {
          final began = _measured ? (StateProbe.enter?.call() ?? 0) : 0;
          final newVal = getter(state);
          if (_measured) StateProbe.leave?.call(_site, began);
          if (!compare(newVal, state._values[idx])) {
            state._values[idx] = newVal;
            return _slotChanged;
          }
        }
        return 0;
      },
      reconfigure: (state, oldState) {
        Object? newVal;
        final oldAddr = oldState._config.address[id];
        if (oldAddr != null) {
          final oldVal = _getAddr(oldState, oldAddr);
          var keep = dependencies.every(
            (dep) => dep is Facet
                ? _same(oldState.facet(dep), state.facet(dep))
                : dep is StateField
                ? _same(oldState.fieldOrNull<Object?>(dep), state.fieldOrNull<Object?>(dep))
                : true,
          );
          if (!keep) {
            newVal = getter(state);
            keep = compare(newVal, oldVal);
          }
          if (keep) {
            state._values[idx] = oldVal;
            return 0;
          }
        } else {
          newVal = getter(state);
        }
        state._values[idx] = newVal;
        return _slotChanged;
      },
    );
  }
}

int _dependencyId(Object dep) {
  if (dep is Facet) return dep.id;
  if (dep is StateField) return dep.id;
  throw ArgumentError.value(dep, 'deps', 'A dependency is a Facet, a StateField, "doc" or "selection"');
}

bool _compareArray(List<Object?> a, List<Object?> b, bool Function(Object?, Object?) compare) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!compare(a[i], b[i])) return false;
  }
  return true;
}

bool _ensureAll(EditorState state, List<int> addrs) {
  var changed = false;
  for (final addr in addrs) {
    if (_ensureAddr(state, addr) & _slotChanged != 0) changed = true;
  }
  return changed;
}

class _DynamicSlot {
  _DynamicSlot({required this.create, required this.update, required this.reconfigure});

  final int Function(EditorState state) create;
  final int Function(EditorState state, Transaction tr) update;
  final int Function(EditorState state, EditorState oldState) reconfigure;
}

_DynamicSlot _dynamicFacetSlot(Map<int, int> addresses, Facet<dynamic, dynamic> facet, List<_FacetProvider> providers) {
  final providerAddrs = <int>[for (final p in providers) addresses[p.id]!];
  final providerTypes = <int>[for (final p in providers) p.type];
  final dynamic_ = <int>[
    for (final p in providerAddrs)
      if (p & 1 == 0) p,
  ];
  final idx = addresses[facet.id]! >> 1;
  Object? get(EditorState state) {
    final values = <Object?>[];
    for (var i = 0; i < providerAddrs.length; i++) {
      final value = _getAddr(state, providerAddrs[i]);
      if (providerTypes[i] == _providerMulti) {
        values.addAll(value as List);
      } else {
        values.add(value);
      }
    }
    return facet._combineDyn(values);
  }

  return _DynamicSlot(
    create: (state) {
      for (final addr in providerAddrs) {
        _ensureAddr(state, addr);
      }
      state._values[idx] = get(state);
      return _slotChanged;
    },
    update: (state, tr) {
      if (!_ensureAll(state, dynamic_)) return 0;
      final value = get(state);
      if (facet._compareDyn(value, state._values[idx])) return 0;
      state._values[idx] = value;
      return _slotChanged;
    },
    reconfigure: (state, oldState) {
      final depChanged = _ensureAll(state, providerAddrs);
      final oldProviders = oldState._config.facets[facet.id], oldValue = oldState.facet(facet);
      if (oldProviders != null && !depChanged && _sameArray(providers, oldProviders)) {
        state._values[idx] = oldValue;
        return 0;
      }
      final value = get(state);
      if (facet._compareDyn(value, oldValue)) {
        state._values[idx] = oldValue;
        return 0;
      }
      state._values[idx] = value;
      return _slotChanged;
    },
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------------------------------------------

class _FieldInit {
  _FieldInit(this.field, this.create);

  final StateField<dynamic> field;
  final Object? Function(EditorState state) create;
}

final Facet<_FieldInit, List<_FieldInit>> _initField = Facet.define<_FieldInit, List<_FieldInit>>(isStatic: true);

/// CodeMirror's `StateField`: a value kept in the state and brought up to date by every transaction.
class StateField<T> implements Extension {
  StateField._(this.id, this._createF, this._updateF, this._compareF, this._toJson, this._fromJson) : _defined = _measured ? StackTrace.current : null;

  /// Where it was defined, in a build that measures itself.
  final StackTrace? _defined;
  late final String _site = StateProbe._site('field', _defined);

  final int id;
  final T Function(EditorState state) _createF;
  final T Function(T value, Transaction tr) _updateF;
  final bool Function(T a, T b) _compareF;
  final Object? Function(T value, EditorState state)? _toJson;
  final T Function(Object? json, EditorState state)? _fromJson;

  /// What the field's `provide` option returned: extensions that come with it.
  Extension? provides;

  /// Defines a field. `create` makes its first value, `update` the next from a transaction; `compare` says when a
  /// new value is no change (identity by default); `provide` gives extensions that come with the field, usually
  /// `(f) => someFacet.from(f)`; `toJson` and `fromJson` let [EditorState.toJson] keep it.
  static StateField<T> define<T>({
    required T Function(EditorState state) create,
    required T Function(T value, Transaction tr) update,
    bool Function(T a, T b)? compare,
    Extension Function(StateField<T> field)? provide,
    Object? Function(T value, EditorState state)? toJson,
    T Function(Object? json, EditorState state)? fromJson,
  }) {
    final field = StateField<T>._(_nextId++, create, update, compare ?? _same, toJson, fromJson);
    if (provide != null) field.provides = provide(field);
    return field;
  }

  Object? _create(EditorState state) {
    for (final init in state.facet(_initField)) {
      if (identical(init.field, this)) return init.create(state);
    }
    return _createF(state);
  }

  _DynamicSlot _slot(Map<int, int> addresses) {
    final idx = addresses[id]! >> 1;
    _FieldInit? find(List<_FieldInit> inits) {
      for (final i in inits) {
        if (identical(i.field, this)) return i;
      }
      return null;
    }

    return _DynamicSlot(
      create: (state) {
        final began = _measured ? (StateProbe.enter?.call() ?? 0) : 0;
        state._values[idx] = _create(state);
        if (_measured) StateProbe.leave?.call(_site, began);
        return _slotChanged;
      },
      update: (state, tr) {
        final oldVal = state._values[idx] as T;
        final began = _measured ? (StateProbe.enter?.call() ?? 0) : 0;
        final value = _updateF(oldVal, tr);
        if (_measured) StateProbe.leave?.call(_site, began);
        if (_compareF(oldVal, value)) return 0;
        state._values[idx] = value;
        return _slotChanged;
      },
      reconfigure: (state, oldState) {
        final init = state.facet(_initField), oldInit = oldState.facet(_initField);
        final reInit = find(init);
        if (reInit != null && !identical(reInit, find(oldInit))) {
          state._values[idx] = reInit.create(state);
          return _slotChanged;
        }
        if (oldState._config.address[id] != null) {
          state._values[idx] = oldState.field(this);
          return 0;
        }
        state._values[idx] = _create(state);
        return _slotChanged;
      },
    );
  }

  /// This field with its first value made by `create` instead of its own: for a state restored from somewhere.
  Extension init(T Function(EditorState state) create) => Extension.list(<Extension>[this, _initField.of(_FieldInit(this, create))]);

  /// CodeMirror's `extension`: the field itself.
  Extension get extension => this;

  // Untyped doors for the state's JSON, called on the field itself so `T` is the real one.
  Object? _toJsonDyn(Object? value, EditorState state) => _toJson!(value as T, state);
  Extension _initFromJson(Object? json) => init((state) => _fromJson!(json, state));
}

// ---------------------------------------------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------------------------------------------

class _Configuration {
  _Configuration(this.base, this.compartments, this.dynamicSlots, this.address, this.staticValues, this.facets)
    : statusTemplate = List<int>.filled(dynamicSlots.length, _slotUnresolved);

  final Extension base;
  final Map<Compartment, Extension> compartments;
  final List<_DynamicSlot> dynamicSlots;
  final Map<int, int> address;
  final List<Object?> staticValues;
  final Map<int, List<_FacetProvider>> facets;
  final List<int> statusTemplate;

  Object? staticFacet(Facet<dynamic, dynamic> facet) {
    final addr = address[facet.id];
    return addr == null ? facet.defaultValue : staticValues[addr >> 1];
  }

  static _Configuration resolve(Extension base, Map<Compartment, Extension> compartments, [EditorState? oldState]) {
    final fields = <StateField<dynamic>>[];
    final facets = <int, List<_FacetProvider>>{};
    final newCompartments = Map<Compartment, Extension>.identity();
    for (final ext in _flatten(base, compartments, newCompartments)) {
      if (ext is StateField) {
        fields.add(ext);
      } else if (ext is _FacetProvider) {
        (facets[ext.facet.id] ??= <_FacetProvider>[]).add(ext);
      }
    }
    final address = <int, int>{};
    final staticValues = <Object?>[];
    final dynamicSlots = <_DynamicSlot Function(Map<int, int>)>[];
    for (final field in fields) {
      address[field.id] = dynamicSlots.length << 1;
      dynamicSlots.add((a) => field._slot(a));
    }
    final oldFacets = oldState?._config.facets;
    // JavaScript walks an object's integer keys in ascending order; so does this.
    final ids = facets.keys.toList()..sort();
    for (final id in ids) {
      final providers = facets[id]!, facet = providers[0].facet;
      final oldProviders = oldFacets?[id] ?? const <_FacetProvider>[];
      if (providers.every((p) => p.type == _providerStatic)) {
        address[facet.id] = (staticValues.length << 1) | 1;
        if (_sameArray(oldProviders, providers)) {
          staticValues.add(oldState!.facet(facet));
        } else {
          final value = facet._combineDyn(<Object?>[for (final p in providers) p.value]);
          staticValues.add(oldState != null && facet._compareDyn(value, oldState.facet(facet)) ? oldState.facet(facet) : value);
        }
      } else {
        for (final p in providers) {
          if (p.type == _providerStatic) {
            address[p.id] = (staticValues.length << 1) | 1;
            staticValues.add(p.value);
          } else {
            address[p.id] = dynamicSlots.length << 1;
            dynamicSlots.add((a) => p.dynamicSlot(a));
          }
        }
        address[facet.id] = dynamicSlots.length << 1;
        dynamicSlots.add((a) => _dynamicFacetSlot(a, facet, providers));
      }
    }
    final dynamic_ = <_DynamicSlot>[for (final f in dynamicSlots) f(address)];
    return _Configuration(base, newCompartments, dynamic_, address, staticValues, facets);
  }
}

List<Extension> _flatten(Extension extension, Map<Compartment, Extension> compartments, Map<Compartment, Extension> newCompartments) {
  final result = <List<Extension>>[<Extension>[], <Extension>[], <Extension>[], <Extension>[], <Extension>[]];
  final seen = Map<Extension, int>.identity();
  void inner(Extension ext, int prec) {
    final known = seen[ext];
    if (known != null) {
      if (known <= prec) return;
      final found = result[known].indexWhere((e) => identical(e, ext));
      if (found > -1) result[known].removeAt(found);
      if (ext is _CompartmentInstance) newCompartments.remove(ext.compartment);
    }
    seen[ext] = prec;
    if (ext is ExtensionList) {
      for (final e in ext.extensions) {
        inner(e, prec);
      }
    } else if (ext is _CompartmentInstance) {
      if (newCompartments.containsKey(ext.compartment)) throw RangeError('Duplicate use of compartment in extensions');
      final content = compartments[ext.compartment] ?? ext.inner;
      newCompartments[ext.compartment] = content;
      inner(content, prec);
    } else if (ext is _PrecExtension) {
      inner(ext.inner, ext.prec);
    } else if (ext is StateField) {
      result[prec].add(ext);
      final provides = ext.provides;
      if (provides != null) inner(provides, prec);
    } else if (ext is _FacetProvider) {
      result[prec].add(ext);
      final enabled = ext.facet.extensions;
      if (enabled != null) inner(enabled, _precDefault);
    } else if (ext is ExtensionProvider) {
      final content = ext.extension;
      if (identical(content, ext)) throw StateError('Unrecognized extension value in extension set ($ext).');
      inner(content, prec);
    } else {
      throw StateError('Unrecognized extension value in extension set ($ext).');
    }
  }

  inner(extension, _precDefault);
  return <Extension>[for (final bucket in result) ...bucket];
}

int _ensureAddr(EditorState state, int addr) {
  if (addr & 1 != 0) return _slotComputed;
  final idx = addr >> 1;
  final status = state._status[idx];
  if (status == _slotComputing) throw StateError('Cyclic dependency between fields and/or facets');
  if (status & _slotComputed != 0) return status;
  state._status[idx] = _slotComputing;
  final changed = state._computeSlot!(state, state._config.dynamicSlots[idx]);
  return state._status[idx] = _slotComputed | changed;
}

Object? _getAddr(EditorState state, int addr) => addr & 1 != 0 ? state._config.staticValues[addr >> 1] : state._values[addr >> 1];

// ---------------------------------------------------------------------------------------------------------------
// Annotations and effects
// ---------------------------------------------------------------------------------------------------------------

/// CodeMirror's `Annotation`: a tagged value on a transaction, saying something about it (when it happened, what
/// kind of user event it was, whether history should keep it).
class Annotation<T> {
  Annotation._(this.type, this.value);

  final AnnotationType<T> type;
  final T value;

  /// Defines a kind of annotation.
  static AnnotationType<T> define<T>() => AnnotationType<T>._();
}

/// CodeMirror's `AnnotationType`: what [Annotation.define] returns.
class AnnotationType<T> {
  AnnotationType._();

  /// An annotation of this type.
  Annotation<T> of(T value) => Annotation<T>._(this, value);
}

/// CodeMirror's `StateEffectType`: what [StateEffect.define] returns.
class StateEffectType<T> {
  StateEffectType._(this._map);

  final Object? Function(T value, ChangeDesc mapping)? _map;

  /// An effect of this type.
  StateEffect<T> of(T value) => StateEffect<T>._(this, value);

  /// `effect` as an effect of this type, or null when it is of another: `effect.is(type)` with the value's type
  /// known afterwards, which TypeScript narrows by itself.
  StateEffect<T>? cast(StateEffect<Object?> effect) => identical(effect.type, this) ? effect as StateEffect<T> : null;

  Object? _mapDyn(Object? value, ChangeDesc mapping) => _map == null ? value : _map(value as T, mapping);
}

class _Dropped {
  const _Dropped();
}

/// CodeMirror's `StateEffect`: something a transaction does beside changing the document, which fields and plugins
/// look for.
class StateEffect<T> {
  StateEffect._(this.type, this.value);

  final StateEffectType<T> type;
  final T value;

  /// This effect after `mapping`, or null when its `map` dropped it.
  StateEffect<T>? map(ChangeDesc mapping) {
    final mapped = type._mapDyn(value, mapping);
    return identical(mapped, dropped)
        ? null
        : _same(mapped, value)
        ? this
        : StateEffect<T>._(type, mapped as T);
  }

  /// CodeMirror's `effect.is(type)`.
  bool isOf(StateEffectType<Object?> type) => identical(this.type, type);

  /// What a `map` function returns to drop its effect: CodeMirror's `undefined`. (A null value is a value.)
  static const Object dropped = _Dropped();

  /// Defines a kind of effect. `map` moves an effect's positions through changes made beside it; it returns the
  /// new value, or [dropped].
  static StateEffectType<T> define<T>({Object? Function(T value, ChangeDesc mapping)? map}) => StateEffectType<T>._(map);

  /// Every effect in `effects` mapped, the dropped ones left out.
  static List<StateEffect<Object?>> mapEffects(List<StateEffect<Object?>> effects, ChangeDesc mapping) {
    if (effects.isEmpty) return effects;
    final result = <StateEffect<Object?>>[];
    for (final effect in effects) {
      final mapped = effect.map(mapping);
      if (mapped != null) result.add(mapped);
    }
    return result;
  }

  /// Replaces the whole configuration with the extension given.
  static final StateEffectType<Extension> reconfigure = StateEffect.define<Extension>();

  /// Adds an extension to the end of the configuration.
  static final StateEffectType<Extension> appendConfig = StateEffect.define<Extension>();
}

// ---------------------------------------------------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------------------------------------------------

/// What a view's `dispatch` takes: a [Transaction], or a [TransactionSpec] to make one of. (In TypeScript a
/// `Transaction` is itself a `TransactionSpec`.)
sealed class Dispatchable {}

/// CodeMirror's `TransactionSpec`: what to do to a state. In TypeScript it is an object literal:
/// `{changes: {from, insert}, userEvent: 'input.type'}` is `TransactionSpec(changes: ChangeSpec(from: from, insert:
/// insert), userEvent: 'input.type')`.
final class TransactionSpec implements Dispatchable {
  const TransactionSpec({
    this.changes,
    this.selection,
    this.effects,
    this.annotations,
    this.userEvent,
    this.scrollIntoView = false,
    this.filter,
    this.sequential = false,
  });

  /// The changes: a [ChangeSpec], a [ChangeSet], or a `List` of them. Positions are in the starting document.
  final Object? changes;

  /// The new selection, in the document after the changes. Left out, the old one is mapped through them.
  /// (`{anchor, head}` in TypeScript is `EditorSelection.single(anchor, head)`.)
  final EditorSelection? selection;

  /// One [StateEffect] or a `List` of them.
  final Object? effects;

  /// One [Annotation] or a `List` of them.
  final Object? annotations;

  /// Shorthand for an annotation of [Transaction.userEvent].
  final String? userEvent;

  /// Whether the view should bring the main selection into view.
  final bool scrollIntoView;

  /// False to skip change filters and transaction filters. (Null is "not said", which filters.)
  final bool? filter;

  /// In [EditorState.updateAll]: whether this spec's positions are in the document the specs before it made, rather
  /// than in the starting document.
  final bool sequential;
}

/// CodeMirror's `Transaction`: one step from a state to the next. Made by [EditorState.update].
final class Transaction implements Dispatchable {
  Transaction._(this.startState, this.changes, this.selection, this.effects, List<Annotation<Object?>> annotations, this.scrollIntoView)
    : annotations = annotations.any((a) => identical(a.type, time))
          ? annotations
          : <Annotation<Object?>>[...annotations, time.of(DateTime.now().millisecondsSinceEpoch)] {
    if (selection != null) checkSelection(selection!, changes.newLength);
  }

  /// CodeMirror's `Transaction.create`, internal there.
  factory Transaction.create(
    EditorState startState,
    ChangeSet changes,
    EditorSelection? selection,
    List<StateEffect<Object?>> effects,
    List<Annotation<Object?>> annotations,
    bool scrollIntoView,
  ) = Transaction._;

  /// The state the transaction starts from.
  final EditorState startState;

  /// The document changes.
  final ChangeSet changes;

  /// The selection this transaction sets, or null when it only maps the old one.
  final EditorSelection? selection;

  /// The effects.
  final List<StateEffect<Object?>> effects;

  /// The annotations; there is always one of [time].
  final List<Annotation<Object?>> annotations;

  /// Whether the view should bring the selection into view.
  final bool scrollIntoView;

  Doc? _doc;
  EditorState? _state;

  /// The document after the changes. Computed when first asked for.
  Doc get newDoc => _doc ??= changes.apply(startState.doc);

  /// The selection after the transaction: the one it set, or the old one mapped.
  EditorSelection get newSelection => selection ?? startState.selection.map(changes);

  /// The state after the transaction. Computed when first asked for.
  EditorState get state {
    if (_state == null) startState._applyTransaction(this);
    return _state!;
  }

  /// The value of the annotation of `type`, or null when there is none.
  T? annotation<T>(AnnotationType<T> type) {
    for (final ann in annotations) {
      if (identical(ann.type, type)) return ann.value as T;
    }
    return null;
  }

  /// Whether the document changed.
  bool get docChanged => !changes.empty;

  /// Whether the configuration changed.
  bool get reconfigured => !identical(startState._config, state._config);

  /// Whether the transaction's user event is `event` or a more specific kind of it: `"select.pointer"` is a
  /// `"select"` event, and not the other way round.
  bool isUserEvent(String event) {
    final e = annotation(userEvent);
    return e != null && (e == event || e.length > event.length && e.substring(0, event.length) == event && e[event.length] == '.');
  }

  /// When the transaction was made, in milliseconds since the epoch. Added by itself when not given.
  static final AnnotationType<int> time = Annotation.define<int>();

  /// What the user did, as a dotted name: `input.type`, `delete.backward`, `select.pointer`, `undo`...
  static final AnnotationType<String> userEvent = Annotation.define<String>();

  /// False keeps a transaction out of the undo history.
  static final AnnotationType<bool> addToHistory = Annotation.define<bool>();

  /// True for a change that came from somewhere else (another device).
  static final AnnotationType<bool> remote = Annotation.define<bool>();
}

List<int> _joinRanges(List<int> a, List<int> b) {
  final result = <int>[];
  for (var iA = 0, iB = 0;;) {
    int from, to;
    if (iA < a.length && (iB == b.length || b[iB] >= a[iA])) {
      from = a[iA++];
      to = a[iA++];
    } else if (iB < b.length) {
      from = b[iB++];
      to = b[iB++];
    } else {
      return result;
    }
    if (result.isEmpty || result.last < from) {
      result
        ..add(from)
        ..add(to);
    } else if (result.last < to) {
      result[result.length - 1] = to;
    }
  }
}

class _Resolved {
  _Resolved(this.changes, this.selection, this.effects, this.annotations, this.scrollIntoView);

  final ChangeSet changes;
  final EditorSelection? selection;
  final List<StateEffect<Object?>> effects;
  final List<Annotation<Object?>> annotations;
  final bool scrollIntoView;
}

_Resolved _mergeTransaction(_Resolved a, _Resolved b, bool sequential) {
  ChangeDesc mapForA, mapForB;
  ChangeSet changes;
  if (sequential) {
    mapForA = b.changes;
    mapForB = ChangeSet.emptyOf(b.changes.length);
    changes = a.changes.compose(b.changes);
  } else {
    final mapped = b.changes.map(a.changes);
    mapForA = mapped;
    mapForB = a.changes.mapDesc(b.changes, true);
    changes = a.changes.compose(mapped);
  }
  return _Resolved(
    changes,
    b.selection != null ? b.selection!.map(mapForB) : a.selection?.map(mapForA),
    <StateEffect<Object?>>[...StateEffect.mapEffects(a.effects, mapForA), ...StateEffect.mapEffects(b.effects, mapForB)],
    a.annotations.isNotEmpty ? <Annotation<Object?>>[...a.annotations, ...b.annotations] : b.annotations,
    a.scrollIntoView || b.scrollIntoView,
  );
}

_Resolved _resolveTransactionInner(EditorState state, Dispatchable spec, int docSize) {
  switch (spec) {
    case Transaction():
      return _Resolved(spec.changes, spec.selection, spec.effects, spec.annotations, spec.scrollIntoView);
    case TransactionSpec():
      var annotations = List<Annotation<Object?>>.from(_asArray(spec.annotations));
      if (spec.userEvent != null && spec.userEvent!.isNotEmpty) {
        annotations = <Annotation<Object?>>[...annotations, Transaction.userEvent.of(spec.userEvent!)];
      }
      final changes = spec.changes;
      return _Resolved(
        changes is ChangeSet ? changes : ChangeSet.of(changes ?? const <Object?>[], docSize, state.facet(EditorState.lineSeparator)),
        spec.selection,
        List<StateEffect<Object?>>.from(_asArray(spec.effects)),
        annotations,
        spec.scrollIntoView,
      );
  }
}

bool _filterOff(Dispatchable spec) => spec is TransactionSpec && spec.filter == false;
bool _sequential(Dispatchable spec) => spec is TransactionSpec && spec.sequential;

Transaction _resolveTransaction(EditorState state, List<Dispatchable> specs, bool filter) {
  var s = _resolveTransactionInner(state, specs.isNotEmpty ? specs[0] : const TransactionSpec(), state.doc.length);
  if (specs.isNotEmpty && _filterOff(specs[0])) filter = false;
  for (var i = 1; i < specs.length; i++) {
    if (_filterOff(specs[i])) filter = false;
    final seq = _sequential(specs[i]);
    s = _mergeTransaction(s, _resolveTransactionInner(state, specs[i], seq ? s.changes.newLength : state.doc.length), seq);
  }
  final tr = Transaction._(state, s.changes, s.selection, s.effects, s.annotations, s.scrollIntoView);
  return _extendTransaction(filter ? _filterTransaction(tr) : tr);
}

// Finish a transaction by applying filters if necessary.
Transaction _filterTransaction(Transaction tr) {
  final state = tr.startState;
  // Change filters
  Object result = true;
  for (final filter in state.facet(EditorState.changeFilter)) {
    final value = filter(tr);
    if (value == false) {
      result = false;
      break;
    }
    if (value is List<int>) result = result == true ? value : _joinRanges(result as List<int>, value);
  }
  if (result != true) {
    ChangeSet changes;
    ChangeDesc back;
    if (result == false) {
      back = tr.changes.invertedDesc;
      changes = ChangeSet.emptyOf(state.doc.length);
    } else {
      final filtered = tr.changes.filter(result as List<int>);
      changes = filtered.changes;
      back = filtered.filtered.mapDesc(filtered.changes).invertedDesc;
    }
    tr = Transaction._(state, changes, tr.selection?.map(back), StateEffect.mapEffects(tr.effects, back), tr.annotations, tr.scrollIntoView);
  }
  // Transaction filters
  final filters = state.facet(EditorState.transactionFilter);
  for (var i = filters.length - 1; i >= 0; i--) {
    final filtered = filters[i](tr);
    if (filtered is Transaction) {
      tr = filtered;
    } else if (filtered is List && filtered.length == 1 && filtered[0] is Transaction) {
      tr = filtered[0] as Transaction;
    } else {
      tr = _resolveTransaction(state, _asArray(filtered).cast<Dispatchable>(), false);
    }
  }
  return tr;
}

Transaction _extendTransaction(Transaction tr) {
  final state = tr.startState, extenders = state.facet(EditorState.transactionExtender);
  _Resolved? spec;
  for (var i = extenders.length - 1; i >= 0; i--) {
    final extension = extenders[i](tr);
    if (extension != null) {
      spec = _mergeTransaction(
        spec ?? _resolveTransactionInner(state, tr, tr.changes.newLength),
        _resolveTransactionInner(state, extension, tr.changes.newLength),
        true,
      );
    }
  }
  return spec == null ? tr : Transaction._(state, tr.changes, tr.selection, spec.effects, spec.annotations, spec.scrollIntoView);
}

// ---------------------------------------------------------------------------------------------------------------
// Character categories
// ---------------------------------------------------------------------------------------------------------------

/// CodeMirror's `CharCategory`: what a character is for moving and selecting by word.
enum CharCategory {
  /// A letter, a digit, an underscore, or a character the language adds.
  word,

  /// Whitespace.
  space,

  /// Anything else.
  other,
}

final RegExp _wordChar = RegExp(r'[\p{Alphabetic}\p{Number}_]', unicode: true);
final RegExp _nonSpace = RegExp(r'\S');

CharCategory Function(String char) _makeCategorizer(String wordChars) {
  return (String char) {
    if (!_nonSpace.hasMatch(char)) return CharCategory.space;
    if (_wordChar.hasMatch(char)) return CharCategory.word;
    for (var i = 0; i < wordChars.length; i++) {
      if (char.contains(wordChars[i])) return CharCategory.word;
    }
    return CharCategory.other;
  };
}

// ---------------------------------------------------------------------------------------------------------------
// The state
// ---------------------------------------------------------------------------------------------------------------

/// What [EditorState.changeByRange]'s callback returns for one range: CodeMirror's `{changes, range, effects}`.
class RangeChange {
  const RangeChange({required this.range, this.changes, this.effects});

  /// The range as it should be afterwards, in the document these changes alone would make.
  final SelectionRange range;

  /// The changes for this range: a [ChangeSpec], a [ChangeSet], or a `List` of them.
  final Object? changes;

  /// One [StateEffect] or a `List` of them.
  final Object? effects;
}

/// CodeMirror's `EditorState`: the document, the selection, and every field and facet, immutable. A new one comes
/// from a [Transaction] ([update], then `tr.state`).
class EditorState {
  EditorState._(this._config, this.doc, this.selection, this._values, this._computeSlot, Transaction? tr)
    : _status = List<int>.of(_config.statusTemplate) {
    // Fill in the computed state immediately, so that further queries for it made during the update return this
    // state
    if (tr != null) tr._state = this;
    for (var i = 0; i < _config.dynamicSlots.length; i++) {
      _ensureAddr(this, i << 1);
    }
    _computeSlot = null;
  }

  final _Configuration _config;

  /// The document.
  final Doc doc;

  /// The selection.
  final EditorSelection selection;

  final List<Object?> _values;
  final List<int> _status;
  int Function(EditorState state, _DynamicSlot slot)? _computeSlot;

  /// The value of a field. Throws when the state does not have the field; see [fieldOrNull].
  T field<T>(StateField<T> field) {
    final addr = _config.address[field.id];
    if (addr == null) throw RangeError('Field is not present in this state');
    _ensureAddr(this, addr);
    return _getAddr(this, addr) as T;
  }

  /// CodeMirror's `state.field(field, false)`: the field's value, or null when the state does not have the field.
  T? fieldOrNull<T>(StateField<T> field) {
    final addr = _config.address[field.id];
    if (addr == null) return null;
    _ensureAddr(this, addr);
    return _getAddr(this, addr) as T;
  }

  /// A transaction from one spec. Filters run unless the spec says `filter: false`.
  Transaction update([TransactionSpec spec = const TransactionSpec()]) => _resolveTransaction(this, <Dispatchable>[spec], true);

  /// CodeMirror's `update(...specs)`: a transaction from several specs. Each spec's positions are in this state's
  /// document unless it is `sequential`.
  Transaction updateAll(List<TransactionSpec> specs) => _resolveTransaction(this, specs, true);

  void _applyTransaction(Transaction tr) {
    _Configuration? conf = _config;
    var base = _config.base;
    var compartments = _config.compartments;
    var copied = false;
    for (final effect in tr.effects) {
      final swap = Compartment.reconfigureEffect.cast(effect);
      if (swap != null) {
        // CodeMirror copies the map only while the configuration is still the old one, so a compartment swapped
        // after a full reconfigure in the same transaction writes into the old state's map. Copied here always.
        if (!copied) {
          compartments = Map<Compartment, Extension>.identity()..addAll(compartments);
          copied = true;
        }
        conf = null;
        compartments[swap.value.compartment] = swap.value.extension;
      } else if (effect.isOf(StateEffect.reconfigure)) {
        conf = null;
        base = effect.value as Extension;
      } else if (effect.isOf(StateEffect.appendConfig)) {
        conf = null;
        final current = base;
        base = Extension.list(<Extension>[
          if (current is ExtensionList) ...current.extensions else current,
          effect.value as Extension,
        ]);
      }
    }
    List<Object?> startValues;
    if (conf == null) {
      conf = _Configuration.resolve(base, compartments, this);
      final intermediateState = EditorState._(
        conf,
        doc,
        selection,
        List<Object?>.filled(conf.dynamicSlots.length, null),
        (state, slot) => slot.reconfigure(state, this),
        null,
      );
      startValues = intermediateState._values;
    } else {
      startValues = List<Object?>.of(tr.startState._values);
    }
    final selection_ = tr.startState.facet(allowMultipleSelections) ? tr.newSelection : tr.newSelection.asSingle();
    EditorState._(conf, tr.newDoc, selection_, startValues, (state, slot) => slot.update(state, tr), tr);
  }

  /// A spec that replaces every selection range with `text` (a `String` or a [Doc]), the caret after it.
  TransactionSpec replaceSelection(Object text) {
    final Doc inserted = text is String ? toText(text) : text as Doc;
    return changeByRange(
      (range) => RangeChange(
        changes: ChangeSpec(from: range.from, to: range.to, insert: inserted),
        range: EditorSelection.cursor(range.from + inserted.length),
      ),
    );
  }

  /// A spec made range by range: `f` is asked what to change for each selection range and where that range should
  /// end up, and the answers are combined so each one's positions come out right beside the others' changes.
  TransactionSpec changeByRange(RangeChange Function(SelectionRange range) f) {
    final sel = selection;
    final result1 = f(sel.ranges[0]);
    var changes = this.changes(result1.changes);
    final ranges = <SelectionRange>[result1.range];
    var effects = _asArray(result1.effects).cast<StateEffect<Object?>>().toList();
    for (var i = 1; i < sel.ranges.length; i++) {
      final result = f(sel.ranges[i]);
      final newChanges = this.changes(result.changes), newMapped = newChanges.map(changes);
      for (var j = 0; j < i; j++) {
        ranges[j] = ranges[j].map(newMapped);
      }
      final mapBy = changes.mapDesc(newChanges, true);
      ranges.add(result.range.map(mapBy));
      changes = changes.compose(newMapped);
      effects = <StateEffect<Object?>>[
        ...StateEffect.mapEffects(effects, newMapped),
        ...StateEffect.mapEffects(_asArray(result.effects).cast<StateEffect<Object?>>().toList(), mapBy),
      ];
    }
    return TransactionSpec(changes: changes, selection: EditorSelection.create(ranges, sel.mainIndex), effects: effects);
  }

  /// A change set for this state's document from "changes": a [ChangeSpec], a [ChangeSet], or a `List` of them.
  ChangeSet changes([Object? spec]) {
    if (spec is ChangeSet) return spec;
    return ChangeSet.of(spec ?? const <Object?>[], doc.length, facet(lineSeparator));
  }

  /// A [Doc] from a string, split on this state's line separator.
  Doc toText(String string) => Doc.of(string.split(facet(lineSeparator) ?? defaultSplit));

  /// The document between two points, as a string.
  String sliceDoc([int from = 0, int? to]) => doc.sliceString(from, to ?? doc.length, lineBreak);

  /// The value of a facet.
  O facet<O>(Facet<Object?, O> facet) {
    final addr = _config.address[facet.id];
    if (addr == null) return facet.defaultValue;
    _ensureAddr(this, addr);
    return _getAddr(this, addr) as O;
  }

  /// `{doc, selection}` and, for each field named in `fields`, what its `toJson` gives.
  Map<String, Object?> toJson([Map<String, StateField<Object?>>? fields]) {
    final result = <String, Object?>{'doc': sliceDoc(), 'selection': selection.toJson()};
    if (fields != null) {
      fields.forEach((prop, value) {
        if (_config.address[value.id] != null) result[prop] = value._toJsonDyn(field(value), this);
      });
    }
    return result;
  }

  /// Reads what [toJson] wrote. `fields` must name the same fields.
  static EditorState fromJson(Object? json, {Extension? extensions, Map<String, StateField<Object?>>? fields}) {
    if (json is! Map || json['doc'] is! String) throw RangeError('Invalid JSON representation for EditorState');
    final fieldInit = <Extension>[];
    if (fields != null) {
      fields.forEach((prop, field) {
        if (json.containsKey(prop)) {
          final value = json[prop];
          fieldInit.add(field._initFromJson(value));
        }
      });
    }
    return EditorState.create(
      doc: json['doc'] as String,
      selection: EditorSelection.fromJson(json['selection']),
      extensions: Extension.list(<Extension>[...fieldInit, ?extensions]),
    );
  }

  /// A new state. `doc` is a `String` or a [Doc]; the selection starts as a caret at 0.
  static EditorState create({Object? doc, EditorSelection? selection, Extension? extensions}) {
    final configuration = _Configuration.resolve(extensions ?? const ExtensionList(<Extension>[]), Map<Compartment, Extension>.identity());
    final Doc text = doc is Doc
        ? doc
        : Doc.of(((doc ?? '') as String).split((configuration.staticFacet(lineSeparator) as String?) ?? defaultSplit));
    var sel = selection ?? EditorSelection.single(0);
    checkSelection(sel, text.length);
    if (!(configuration.staticFacet(allowMultipleSelections) as bool)) sel = sel.asSingle();
    return EditorState._(
      configuration,
      text,
      sel,
      List<Object?>.filled(configuration.dynamicSlots.length, null),
      (state, slot) => slot.create(state),
      null,
    );
  }

  /// The width of a tab, in columns.
  int get tabSize => facet(tabSizeFacet);

  /// The line break this state writes: the line separator when one is set, `\n` otherwise.
  String get lineBreak => facet(lineSeparator) ?? '\n';

  /// Whether the document may not be changed by the user. Commands look at this; `update` does not.
  bool get readOnly => facet(readOnlyFacet);

  /// A phrase in the editor's language: looked up in [phrases], then `$` (or `$1`, `$2`...) filled from `insert`
  /// and `$$` written as a dollar sign.
  String phrase(String phrase, [List<Object?> insert = const <Object?>[]]) {
    for (final map in facet(phrases)) {
      if (map.containsKey(phrase)) {
        phrase = map[phrase]!;
        break;
      }
    }
    if (insert.isNotEmpty) {
      phrase = phrase.replaceAllMapped(RegExp(r'\$(\$|\d*)'), (m) {
        final i = m[1]!;
        if (i == r'$') return r'$';
        final n = i.isEmpty ? 1 : int.parse(i);
        return n == 0 || n > insert.length ? m[0]! : '${insert[n - 1]}';
      });
    }
    return phrase;
  }

  /// The values the language gives for `name` at `pos`.
  List<T> languageDataAt<T>(String name, int pos, [int side = -1]) {
    final values = <T>[];
    for (final provider in facet(languageData)) {
      for (final result in provider(this, pos, side)) {
        if (result.containsKey(name)) values.add(result[name] as T);
      }
    }
    return values;
  }

  /// A function that sorts a character into a [CharCategory], with the language's extra word characters at `at`.
  CharCategory Function(String char) charCategorizer(int at) {
    final chars = languageDataAt<String>('wordChars', at);
    return _makeCategorizer(chars.isNotEmpty ? chars[0] : '');
  }

  /// The word around `pos`, as a range, or null when `pos` is not in or beside one.
  SelectionRange? wordAt(int pos) {
    final line = doc.lineAt(pos);
    final text = line.text, from = line.from, length = line.length;
    final cat = charCategorizer(pos);
    var start = pos - from, end = pos - from;
    while (start > 0) {
      final prev = findClusterBreak(text, start, false);
      if (cat(text.substring(prev, start)) != CharCategory.word) break;
      start = prev;
    }
    while (end < length) {
      final next = findClusterBreak(text, end);
      if (cat(text.substring(end, next)) != CharCategory.word) break;
      end = next;
    }
    return start == end ? null : EditorSelection.range(start + from, end + from);
  }

  /// Whether a state may hold more than one selection range. Off, every transaction's selection is cut to its main
  /// range.
  static final Facet<bool, bool> allowMultipleSelections = Facet.define<bool, bool>(
    combine: (values) => values.any((v) => v),
    isStatic: true,
  );

  /// CodeMirror's `EditorState.tabSize`: the width of a tab; 4 when nothing says.
  static final Facet<int, int> tabSizeFacet = Facet.define<int, int>(combine: (values) => values.isNotEmpty ? values[0] : 4);

  /// The line separator: null (any of `\r\n`, `\r`, `\n` split a string, `\n` is written) unless one is set.
  static final Facet<String, String?> lineSeparator = Facet.define<String, String?>(
    combine: (values) => values.isNotEmpty ? values[0] : null,
    isStatic: true,
  );

  /// CodeMirror's `EditorState.readOnly`: see [readOnly].
  static final Facet<bool, bool> readOnlyFacet = Facet.define<bool, bool>(combine: (values) => values.isNotEmpty ? values[0] : false);

  /// Translations for [phrase].
  static final Facet<Map<String, String>, List<Map<String, String>>> phrases = Facet.define<Map<String, String>, List<Map<String, String>>>();

  /// What a language says about the text at a position; read by [languageDataAt].
  static final Facet<
    List<Map<String, Object?>> Function(EditorState state, int pos, int side),
    List<List<Map<String, Object?>> Function(EditorState state, int pos, int side)>
  >
  languageData = Facet.define();

  /// Change filters: each is asked about a transaction and answers `true` (let it through), `false` (drop its
  /// changes) or a `List<int>` of from/to pairs its changes may not touch.
  static final Facet<Object Function(Transaction tr), List<Object Function(Transaction tr)>> changeFilter = Facet.define();

  /// Transaction filters: each may replace a transaction, answering with a [Transaction], a [TransactionSpec], or a
  /// `List` of specs.
  static final Facet<Object Function(Transaction tr), List<Object Function(Transaction tr)>> transactionFilter = Facet.define();

  /// Transaction extenders: each may add effects and annotations (only those are read) to a transaction, whatever
  /// its `filter` says.
  static final Facet<TransactionSpec? Function(Transaction tr), List<TransactionSpec? Function(Transaction tr)>> transactionExtender =
      Facet.define();
}

/// CodeMirror's `combineConfig`: merges configuration objects into one. A key given the same value twice is fine; a
/// key given two values is an error unless `combine` has a function for it; `defaults` fill what nobody set.
Map<String, Object?> combineConfig(
  List<Map<String, Object?>> configs,
  Map<String, Object?> defaults, [
  Map<String, Object? Function(Object? a, Object? b)> combine = const <String, Object? Function(Object?, Object?)>{},
]) {
  final result = <String, Object?>{};
  for (final config in configs) {
    for (final key in config.keys) {
      final value = config[key], current = result[key];
      if (current == null) {
        result[key] = value;
      } else if (_same(current, value) || value == null) {
        // No conflict
      } else if (combine.containsKey(key)) {
        result[key] = combine[key]!(current, value);
      } else {
        throw StateError('Config merge conflict for field $key');
      }
    }
  }
  for (final key in defaults.keys) {
    result[key] ??= defaults[key];
  }
  return result;
}

/// What a command works on: CodeMirror's `{state, dispatch}`. A view is one; [StateCommandTarget.new] makes one
/// from a state and a function for tests and for anything without a view.
abstract interface class StateCommandTarget {
  /// A target from its two parts.
  factory StateCommandTarget(EditorState state, void Function(Transaction tr) dispatch) = _PlainTarget;

  /// The state the command reads.
  EditorState get state;

  /// Where the command sends what it made. A command only ever sends a [Transaction].
  void dispatch(Dispatchable tr);
}

class _PlainTarget implements StateCommandTarget {
  _PlainTarget(this.state, this._dispatch);

  @override
  final EditorState state;
  final void Function(Transaction tr) _dispatch;

  @override
  void dispatch(Dispatchable tr) => _dispatch(switch (tr) {
    Transaction() => tr,
    TransactionSpec() => state.update(tr),
  });
}

/// CodeMirror's `StateCommand`: does something to a state through `dispatch` and says whether it did.
typedef StateCommand = bool Function(StateCommandTarget target);
