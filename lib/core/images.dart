/// Pictures in notes. Ports `src/app/core/images.ts` and `src/app/core/imageRefs.ts`.
///
/// A note refers to a picture as `![caption](image/<name>)`: a relative path, so a folder of notes and an `image/`
/// folder beside it would still make sense anywhere markdown is read. The picture itself is a file the core keeps
/// under the app's own data (lib/core/native/files.dart, `CoreFileKind.image`).
///
/// This is the door every caller uses. On the page it decided between the phone (the `img` scheme, Rust) and a
/// browser (IndexedDB and blob URLs); here there is one device, so the door is a [PictureStore]: what draws asks it
/// for a picture by name and listens to it, where the page read `imageUrl(name)` and listened for `IMAGE_READY`.
///
/// What differs:
/// - `imageUrl(name)` answered an address for an `<img>`; [PictureStore.pictureOf] answers a [Picture] (a file's
///   path with the number of times it has landed, or bytes held in memory), or null while it is not known to be
///   here. `IMAGE_READY` on `window` is the store's own `notifyListeners`.
/// - The page asked the `img` scheme, which answered at once or failed quietly; [CorePictureStore] asks the core
///   where the file lies (`CoreFiles.where`) the first time a name is drawn, answers null until it is told, and
///   says so when it is. That is the browser's road on the page ("blank while it is fetched, then drawn").
/// - Choosing a picture (`pickImage`: Android's chooser through the activity, a file input elsewhere), shrinking
///   one (`core/imageShrink.ts`) and filing it (`save_image`, `save_image_data`) need a picker plugin and core
///   commands this stage does not have: they are the seams [PicturePicker], [PictureKeeper] and [PictureAdopter],
///   given to the store by whoever has them. Without one, [PictureStore.save] and [PictureStore.adopt] refuse in
///   the page's own words for a build that cannot.
/// - `SAMPLE_PICTURES` (the Academy's SVG tape) is not here: there is no SVG decoder to draw it with yet. A store
///   may be lent it as bytes of another kind ([MemoryPictureStore.lend]).
/// - `smallerImage` (a share's reading copy) is the share's, with the shrink.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ids.dart';
import 'native/files.dart';

/// A picture's reference in a body: the caption, then the name, as groups 1 and 2 (`IMAGE_REF`). Read it with
/// `allMatches`.
final RegExp imageRef = RegExp(r'!\[([^\]]*)\]\(image/([A-Za-z0-9_.-]+)\)');

/// The markdown for a picture, on a line of its own.
String imageMarkdown(String name, [String caption = '']) => '![$caption](image/$name)';

/// Every picture a note refers to.
List<String> imageNames(String body) => <String>[
  for (final m in imageRef.allMatches(body))
    if ((m.group(2) ?? '').isNotEmpty) m.group(2)!,
];

/// The type a picture's name says it is (`typeOf`).
String imageTypeOf(String name) => name.endsWith('.png') ? 'image/png' : (name.endsWith('.webp') ? 'image/webp' : 'image/jpeg');

/// A picture where the editor can draw it from: a file on this device, or bytes held for this run.
@immutable
class Picture {
  /// A kept file. [version] changes each time the file lands again (a sync that arrived after the page asked), so
  /// what drew the old one draws again: the page's `?v=` on the `img` address.
  const Picture.file(String this.path, [this.version = 0]) : bytes = null;

  /// Bytes held in memory: a lent picture, or one kept this run by a store with no files.
  const Picture.memory(Uint8List this.bytes, [this.version = 0]) : path = null;

  final String? path;
  final Uint8List? bytes;
  final int version;

  @override
  bool operator ==(Object other) => other is Picture && other.path == path && identical(other.bytes, bytes) && other.version == version;

  @override
  int get hashCode => Object.hash(path, bytes == null ? null : identityHashCode(bytes), version);
}

/// Lets the person choose a picture, keeps it, and answers its name; null when they chose none (`pickImage`).
/// Throws with a sentence for the note when the pick failed.
typedef PicturePicker = Future<String?> Function();

/// Keeps a picture that arrived as bytes (pasted from the clipboard), shrunk as the device shrinks one, and answers
/// its name (`saveImageFile`).
typedef PictureKeeper = Future<String> Function(Uint8List bytes, String type);

/// Adopts a picture the shell has already put in its cache, by its path, and answers its name (`adoptImagePath`).
typedef PictureAdopter = Future<String> Function(String path);

/// What a build with no way to keep a picture says (`pickNative`'s sentence for a bridge without the picker).
const String cannotAddPictures = 'This build cannot add pictures yet. Install the newest Ghost.md.';

/// Where pictures are kept and drawn from. It is a `Listenable`: it tells its listeners when a picture that was
/// asked for can now be drawn, or one drawn has landed again (`IMAGE_READY`).
abstract class PictureStore extends ChangeNotifier {
  /// Where the editor draws the picture named [name] from, or null while this device is not known to have it
  /// (`imageUrl`, which answered `''`). Asking is what starts the looking: the listeners are told when it is found.
  Picture? pictureOf(String name);

  /// A picture's bytes on this device, or null where it has none by that name (`imageBytes`).
  Future<Uint8List?> bytesOf(String name);

  /// Keeps a picture that came from elsewhere under its own name, by sync or in a shared copy saved here, and
  /// draws it wherever a page is waiting for it (`keepImage`).
  Future<void> keep(String name, Uint8List bytes);

  /// Keeps a picture that arrived as bytes and answers its name (`saveImageFile`).
  Future<String> save(Uint8List bytes, {String type = 'image/jpeg'});

  /// Adopts a picture from a path in the shell's cache and answers its name (`adoptImagePath`).
  Future<String> adopt(String path);
}

/// The device's pictures, through the core (`CoreFiles`): the phone's half of core/images.ts.
class CorePictureStore extends PictureStore {
  CorePictureStore(this._files, {PictureKeeper? keeper, PictureAdopter? adopter}) : _keeper = keeper, _adopter = adopter;

  final CoreFiles _files;
  final PictureKeeper? _keeper;
  final PictureAdopter? _adopter;

  /// What is known of each name asked for this run: its file, or null where the core had none.
  final Map<String, Picture?> _known = <String, Picture?>{};
  final Set<String> _asking = <String>{};

  /// How many times each picture has landed this run (`arrived`).
  final Map<String, int> _arrived = <String, int>{};
  bool _disposed = false;

  @override
  Picture? pictureOf(String name) {
    if (_known.containsKey(name)) return _known[name];
    _known[name] = null;
    _look(name);
    return null;
  }

  void _look(String name) {
    if (!_asking.add(name)) return;
    unawaited(
      _files
          .where(CoreFileKind.image, name)
          .then<void>((found) {
            if (found == null) return;
            _known[name] = Picture.file(found.path, _arrived[name] ?? 0);
            if (!_disposed) notifyListeners();
          })
          // A name the core will not have, or a core that would not answer: the picture stays blank.
          .catchError((Object _) {})
          .whenComplete(() => _asking.remove(name)),
    );
  }

  @override
  Future<Uint8List?> bytesOf(String name) async {
    try {
      return await _files.read(CoreFileKind.image, name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> keep(String name, Uint8List bytes) async {
    await _files.write(CoreFileKind.image, name, bytes);
    arrived(name);
  }

  /// A picture was written to this device's store (by sync, lib/sync/engine.dart): every page drawing it draws it
  /// again (`imageArrived`).
  void arrived(String name) {
    _arrived[name] = (_arrived[name] ?? 0) + 1;
    final known = _known[name];
    if (known?.path != null) {
      _known[name] = Picture.file(known!.path!, _arrived[name]!);
      if (!_disposed) notifyListeners();
    } else {
      _known.remove(name);
      // Asked for before it landed: looked for again, and said when found. Never asked for: found when it is.
      _known[name] = null;
      _look(name);
    }
  }

  @override
  Future<String> save(Uint8List bytes, {String type = 'image/jpeg'}) {
    final keeper = _keeper;
    if (keeper == null) throw StateError(cannotAddPictures);
    return keeper(bytes, type);
  }

  @override
  Future<String> adopt(String path) {
    final adopter = _adopter;
    if (adopter == null) throw StateError(cannotAddPictures);
    return adopter(path);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Pictures held for this run and nowhere else: the browser's half of core/images.ts with its database a map (a
/// test's store, and a shared page's, whose pictures are lent to it).
class MemoryPictureStore extends PictureStore {
  MemoryPictureStore([Map<String, Uint8List>? kept]) : _kept = <String, Uint8List>{...?kept};

  /// The database: what `webPut` kept.
  final Map<String, Uint8List> _kept;

  /// What the editor draws from this run, by name; null while a picture is fetched (`urls`).
  final Map<String, Picture?> _drawn = <String, Picture?>{};

  /// What is kept, by name: for a test to read.
  Map<String, Uint8List> get kept => Map<String, Uint8List>.unmodifiable(_kept);

  @override
  Picture? pictureOf(String name) {
    if (_drawn.containsKey(name)) return _drawn[name];
    _drawn[name] = null;
    // The database answers a turn later, as IndexedDB does.
    scheduleMicrotask(() {
      final bytes = _kept[name];
      if (bytes == null) return;
      _drawn[name] = Picture.memory(bytes);
      notifyListeners();
    });
    return null;
  }

  @override
  Future<Uint8List?> bytesOf(String name) async => _kept[name];

  @override
  Future<void> keep(String name, Uint8List bytes) async {
    _kept[name] = bytes;
    _drawn[name] = Picture.memory(bytes, (_drawn[name]?.version ?? -1) + 1);
    notifyListeners();
  }

  @override
  Future<String> save(Uint8List bytes, {String type = 'image/jpeg'}) async {
    final name = '${randomId('img')}.jpg';
    _kept[name] = bytes;
    // Seen this run, so the editor has it without waiting for the database.
    _drawn[name] = Picture.memory(bytes);
    return name;
  }

  @override
  Future<String> adopt(String path) => throw StateError(cannotAddPictures);

  /// Pictures lent for as long as the store lives, by name: a shared page's, drawn from the share itself. Nothing
  /// is kept (`lendImages`).
  void lend(Map<String, Uint8List> pictures) {
    for (final entry in pictures.entries) {
      _drawn[entry.key] = Picture.memory(entry.value);
    }
    if (pictures.isNotEmpty) notifyListeners();
  }
}
