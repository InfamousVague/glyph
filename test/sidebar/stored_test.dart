import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';

/// `core/stored.test.ts`, case for case, over a [MemoryStored] where the page had `localStorage`.

/// Storage that will not answer: a private window, a device with its storage switched off.
class _Refusing extends Stored {
  Never _no() => throw StateError('The operation is insecure.');

  @override
  String? getItem(String key) => _no();

  @override
  void setItem(String key, String text) => _no();

  @override
  void removeItem(String key) => _no();

  @override
  Iterable<String> get allKeys => _no();
}

void main() {
  late MemoryStored local;
  setUp(() => local = MemoryStored());

  group('reading and writing a value', () {
    List<String>? list(Object? raw) => raw is List ? [...raw.whereType<String>()] : null;

    test('answers the fallback for nothing kept, for text that is not JSON, and for a shape the caller will not have', () {
      expect(local.read('glyph-t', ['none'], list), ['none']);
      local.setItem('glyph-t', 'not json');
      expect(local.read('glyph-t', ['none'], list), ['none']);
      local.setItem('glyph-t', '{"a":1}');
      expect(local.read('glyph-t', ['none'], list), ['none']);
      local.setItem('glyph-t', '["a",2,"b"]');
      expect(local.read('glyph-t', ['none'], list), ['a', 'b']);
    });

    test('reads a check that throws as nothing kept, and takes the value as it is without one', () {
      local.setItem('glyph-t', 'null');
      expect(local.read<String>('glyph-t', 'fallback', (raw) => (raw as Map)['x'] as String), 'fallback');
      expect(local.read<Object?>('glyph-t', 'fallback'), isNull);
    });

    test('writes JSON, and removes the key for null', () {
      local.write('glyph-t', {
        'a': [1, 2],
      });
      expect(local.getItem('glyph-t'), '{"a":[1,2]}');
      expect(local.read<Object?>('glyph-t', const {}), {
        'a': [1, 2],
      });
      local.write('glyph-t', null);
      expect(local.getItem('glyph-t'), isNull);
    });

    test('keeps text as text: a bare word or number is not JSON', () {
      local.writeText('glyph-t', 'on');
      expect(local.getItem('glyph-t'), 'on');
      expect(local.readText('glyph-t'), 'on');
      local.writeText('glyph-t', null);
      expect(local.readText('glyph-t'), isNull);
    });

    test('answers the fallback and keeps quiet when storage refuses', () {
      final refusing = _Refusing();
      expect(refusing.read('glyph-t', 'fallback'), 'fallback');
      expect(refusing.readShared('glyph-t', 'fallback'), 'fallback');
      expect(refusing.readText('glyph-t'), isNull);
      expect(() => refusing.write('glyph-t', [2]), returnsNormally);
      expect(() => refusing.writeText('glyph-t', null), returnsNormally);
      expect(refusing.keys(), isEmpty);
      expect(refusing.flag('glyph-t', unreadable: true).isMarked, isTrue);
    });

    test('keeps quiet about a value JSON cannot say', () {
      expect(() => local.write('glyph-t', Object()), returnsNormally);
      expect(local.getItem('glyph-t'), isNull);
    });
  });

  group('a shared read', () {
    test('parses once while the text stays the same, and again the moment it changes', () {
      var parses = 0;
      Map<String, Object?>? parse(Object? raw) {
        parses += 1;
        return (raw as Map).cast<String, Object?>();
      }

      local.write('glyph-shared', {'n': 1});
      final first = local.readShared('glyph-shared', const <String, Object?>{'n': 0}, parse);
      expect(identical(local.readShared('glyph-shared', const <String, Object?>{'n': 0}, parse), first), isTrue);
      expect(parses, 1);
      // Written behind its back, by hand: the text is asked every time, so it is never stale.
      local.setItem('glyph-shared', '{"n":2}');
      expect(local.readShared('glyph-shared', const <String, Object?>{'n': 0}, parse), {'n': 2});
      expect(parses, 2);
    });
  });

  group('the keys kept', () {
    test('lists every key on the device, the app’s and anybody else’s', () {
      local.setItem('glyph-a', '1');
      local.setItem('other', '2');
      expect(local.keys()..sort(), ['glyph-a', 'other']);
    });
  });

  group('a once-flag', () {
    test('is marked with the moment it was, and cleared', () {
      final flag = local.flag('glyph-once');
      expect(flag.isMarked, isFalse);
      flag.mark();
      expect(flag.isMarked, isTrue);
      expect(DateTime.tryParse(local.getItem('glyph-once') ?? ''), isNotNull);
      flag.clear();
      expect(flag.isMarked, isFalse);
    });

    test('with a value, writes it and counts only it', () {
      final flag = local.flag('glyph-once', value: '1');
      flag.mark();
      expect(local.getItem('glyph-once'), '1');
      local.setItem('glyph-once', '0');
      expect(flag.isMarked, isFalse);
    });

    test('answers its own judgement when storage cannot be read, and nothing is thrown', () {
      final refusing = _Refusing();
      expect(refusing.flag('glyph-once').isMarked, isFalse);
      expect(refusing.flag('glyph-once', unreadable: true).isMarked, isTrue);
      expect(() => refusing.flag('glyph-once').mark(), returnsNormally);
    });
  });

  group('the app’s own memory', () {
    test('is in memory until one is put in its place', () {
      final was = stored;
      addTearDown(() => useStored(was));
      expect(was, isA<MemoryStored>());
      useStored(local);
      stored.writeText('glyph-t', 'here');
      expect(local.getItem('glyph-t'), 'here');
    });
  });
}
