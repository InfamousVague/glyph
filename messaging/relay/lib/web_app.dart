import 'dart:async';
import 'dart:io';

/// The app in a browser, handed out as plain files under `/app/` (docs/OPEN_NETWORK.md, part 6; Matt: "the full web
/// client"). A page may speak only to where it came from, and the hub sends no headers that would let another site's
/// page in, so the app's files and the hub have to be one address: the relay serves the folder `flutter build web`
/// made (the app's `tool/build-web.mjs`), and anyone running a relay can serve the app with it.
///
/// It is a folder of files and nothing else:
///
/// - **Only what is in the folder.** A name is taken a part at a time: none may be `.` or `..`, start with a dot, or
///   hold a slash, a backslash or a control character however it was written in the address; and where the file
///   really is (links followed) must be inside the folder.
/// - **No lists.** A folder answers "not found", but for `/app/` itself, which is `index.html`.
/// - **What kind each file is** by its ending: a browser will not run a `.wasm` handed over as anything else, nor a
///   script handed over as text.
/// - **Kept or asked for again.** `index.html`, and every file whose name does not say what is in it, is asked for
///   again each time (`no-cache`, with a tag that answers "as you have it" in a few bytes). A file with a hash of
///   its contents in its name (`main.dart.3f9a1c2b.js`) never changes, and is kept for a year.
/// - **Packed already.** Where `name.br` or `name.gz` lies beside a file and the browser takes that packing, it is
///   what is sent: nothing is packed as it is asked for.
///
/// GET and HEAD only. Nothing is written, logged or kept about who asked.
class WebApp {
  WebApp(this.dir);

  /// The folder: what `flutter build web` wrote, `index.html` at its top.
  final Directory dir;

  /// Whether there is an app to serve: the folder is there and has its page.
  bool get there => File('${dir.path}/index.html').existsSync();

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'map': 'application/json; charset=utf-8',
    'txt': 'text/plain; charset=utf-8',
    'svg': 'image/svg+xml',
    'wasm': 'application/wasm',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'ico': 'image/x-icon',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'm4a': 'audio/mp4',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
  };

  /// What kind of file [name] is, for a browser; plain bytes where its ending says nothing.
  static String typeOf(String name) {
    final dot = name.lastIndexOf('.');
    return _types[dot < 0 ? '' : name.substring(dot + 1).toLowerCase()] ?? 'application/octet-stream';
  }

  /// Whether [name] has a hash of the file's contents in it (eight or more hex digits between dots, before its
  /// ending): such a file is never changed, only replaced by one of another name.
  static bool hashed(String name) => RegExp(r'\.[0-9a-f]{8,}\.[A-Za-z0-9]+$').hasMatch(name);

  /// One part of a path as a file's name here, or not at all.
  static bool _plain(String part) =>
      part.isNotEmpty && part != '.' && part != '..' && !part.startsWith('.') && !part.contains('/') && !part.contains(r'\') && !part.contains(':') && !part.codeUnits.any((c) => c < 0x20 || c == 0x7f);

  /// The file [parts] name inside the folder, or null: a name that isn't plain, nothing there, a folder, or
  /// something that is really somewhere else.
  File? _file(List<String> parts) {
    if (parts.isEmpty || !parts.every(_plain)) return null;
    final file = File([dir.path, ...parts].join(Platform.pathSeparator));
    try {
      if (file.statSync().type != FileSystemEntityType.file) return null;
      final root = dir.resolveSymbolicLinksSync();
      final real = file.resolveSymbolicLinksSync();
      return real.startsWith('$root${Platform.pathSeparator}') ? File(real) : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Answers a request for `/app` and what is under it. [parts] is the path after `app`, each part as the address
  /// had it once its escapes are read.
  Future<void> handle(HttpRequest request, List<String> parts) async {
    final response = request.response;
    response.headers
      ..set('X-Content-Type-Options', 'nosniff')
      // The app is never a frame in someone else's page.
      ..set('X-Frame-Options', 'DENY')
      ..set('Referrer-Policy', 'no-referrer');
    if (request.method != 'GET' && request.method != 'HEAD') {
      response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      return response.close();
    }
    // `/app` is the folder: its page's own addresses (`main.dart.js`) are read from `/app/`.
    if (parts.isEmpty && !request.uri.path.endsWith('/')) {
      response
        ..statusCode = HttpStatus.movedPermanently
        ..headers.set(HttpHeaders.locationHeader, '${request.uri.path}/${request.uri.hasQuery ? '?${request.uri.query}' : ''}');
      return response.close();
    }
    final names = parts.isEmpty ? const ['index.html'] : parts;
    final file = _file(names);
    if (file == null) {
      response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.text
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write('Not found\n');
      return response.close();
    }
    final name = names.last;
    final stat = file.statSync();
    // Which file this is now: its size and when it was written. Another build's has another tag.
    final tag = '"${stat.size.toRadixString(16)}-${stat.modified.millisecondsSinceEpoch.toRadixString(16)}"';
    response.headers
      ..set(HttpHeaders.contentTypeHeader, typeOf(name))
      ..set(HttpHeaders.etagHeader, tag)
      ..set(HttpHeaders.cacheControlHeader, hashed(name) ? 'public, max-age=31536000, immutable' : 'no-cache')
      ..set(HttpHeaders.varyHeader, 'Accept-Encoding');
    final have = request.headers[HttpHeaders.ifNoneMatchHeader]?.join(',') ?? '';
    if (have.split(',').map((t) => t.trim().replaceFirst('W/', '')).contains(tag)) {
      response.statusCode = HttpStatus.notModified;
      return response.close();
    }
    // The same file packed beforehand, where the browser reads that packing.
    final takes = (request.headers[HttpHeaders.acceptEncodingHeader]?.join(',') ?? '').split(',').map((e) => e.split(';').first.trim().toLowerCase()).toSet();
    var body = file;
    for (final (ending, coding) in const [('br', 'br'), ('gz', 'gzip')]) {
      if (!takes.contains(coding)) continue;
      final packed = _file([...names.sublist(0, names.length - 1), '$name.$ending']);
      // One left from an older build, beside a file written since, is not this file.
      if (packed == null || packed.lastModifiedSync().isBefore(stat.modified)) continue;
      body = packed;
      response.headers.set(HttpHeaders.contentEncodingHeader, coding);
      break;
    }
    response.headers.contentLength = body.lengthSync();
    if (request.method == 'HEAD') return response.close();
    await response.addStream(body.openRead());
    return response.close();
  }
}
