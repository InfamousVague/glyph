/// Something shared into Ghost.md from another app's share sheet: text, a link, pictures, any file. The phone keeps
/// each share until it is asked for (android/…/ghost_md/ShareIn.kt, over `ghost_md/share`), as it keeps a link that
/// opened the app (lib/core/phone_links.dart): a share that started the app waits for the notes to be read, and one
/// made while the app runs is said as it arrives.
///
/// What a share becomes is decided here, and is plain Markdown:
///
/// - **A link** (the text is one address, as a browser shares a page): `[the page's title](https://…)`, the title
///   being what the share carried as its subject or title; `<https://…>` with none. Nothing is fetched.
/// - **Text**: the text, as it came.
/// - **A picture**: kept among the library's pictures as the editor's own Add a picture keeps one (shrunk and turned
///   the right way up by the phone, then adopted by the core: lib/core/phone_pictures.dart) and shown,
///   `![](image/<name>)`.
/// - **Any other file**: kept beside the pictures and linked, `[Lease.pdf](file/<name>)` (lib/core/shared_files.dart
///   `storeSharedFile`, the one door the attachments will take over).
///
/// A new note is named for the share ([sharedTitle]): its subject or its page's title, else its first line, else the
/// first file's name. Added to a note, the share goes at its end, above its comments.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../comments/format.dart' show readComments;
import '../core/note_text.dart' show noteTitle;
import '../core/title_key.dart';

/// The channel ShareIn.kt answers on: `take` gives the shares made ready since the last ask; `done` sends the person
/// back to the app they shared from; `arrived` is said to Dart.
const MethodChannel shareInChannel = MethodChannel('ghost_md/share');

/// One file of a share, already copied into the app's cache by the phone.
@immutable
class SharedItem {
  const SharedItem({required this.picture, required this.path, required this.name, this.mime = '', this.size = 0});

  /// A picture the phone has shrunk among the picked, for the core to adopt; otherwise a file to keep.
  final bool picture;
  final String path;
  final String name;
  final String mime;
  final int size;
}

/// One share.
@immutable
class SharedIn {
  const SharedIn({required this.id, this.text, this.subject, this.title, this.mime = '', this.items = const [], this.unread = 0});

  /// A share as ShareIn.kt says it; null for anything that is not one.
  static SharedIn? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    String? said(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
    return SharedIn(
      id: id,
      text: said(raw['text']),
      subject: said(raw['subject']),
      title: said(raw['title']),
      mime: raw['mime'] is String ? raw['mime'] as String : '',
      items: [
        for (final item in (raw['items'] is List ? raw['items'] as List : const []))
          if (item is Map && item['path'] is String && (item['path'] as String).isNotEmpty)
            SharedItem(
              picture: item['kind'] == 'picture',
              path: item['path'] as String,
              name: item['name'] is String && (item['name'] as String).isNotEmpty ? item['name'] as String : 'Shared file',
              mime: item['mime'] is String ? item['mime'] as String : '',
              size: item['size'] is num ? (item['size'] as num).toInt() : 0,
            ),
      ],
      unread: raw['unread'] is num ? (raw['unread'] as num).toInt() : 0,
    );
  }

  final String id;

  /// What was shared as words (`EXTRA_TEXT`).
  final String? text;

  /// `EXTRA_SUBJECT`: a browser's page title, a mail's subject.
  final String? subject;

  /// `EXTRA_TITLE`.
  final String? title;
  final String mime;
  final List<SharedItem> items;

  /// What the phone could not read.
  final int unread;

  /// Nothing to keep.
  bool get empty => (text == null || text!.trim().isEmpty) && items.isEmpty;
}

final RegExp _address = RegExp(r'^https?://\S+$', caseSensitive: false);

/// The address a share is, where its words are one address and nothing else; null otherwise.
String? sharedLink(SharedIn share) {
  final text = share.text?.trim();
  if (text == null || !_address.hasMatch(text)) return null;
  return text;
}

/// The page's title a share carried with its address: its subject, or its title, where that is not the address.
String? _pageTitle(SharedIn share, String link) {
  for (final said in [share.subject, share.title]) {
    final clean = said?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean != null && clean.isNotEmpty && clean != link) return clean;
  }
  return null;
}

/// The name a new note is given for [share]: the page's title or the subject, else the first line of its words,
/// else its first file's name, else "Shared".
String sharedTitle(SharedIn share) {
  final link = sharedLink(share);
  if (link != null) {
    final page = _pageTitle(share, link);
    if (page != null) return _line(page);
    final host = Uri.tryParse(link)?.host ?? '';
    return host.isEmpty ? 'Shared link' : host.replaceFirst(RegExp(r'^www\.'), '');
  }
  for (final said in [share.subject, share.title]) {
    if (said != null && said.trim().isNotEmpty) return _line(said);
  }
  final text = share.text?.trim() ?? '';
  if (text.isNotEmpty) {
    final first = noteTitle(text);
    if (first.isNotEmpty) return _line(first);
  }
  if (share.items.isNotEmpty) {
    final name = share.items.first.name;
    final dot = name.lastIndexOf('.');
    return _line(dot > 0 ? name.substring(0, dot) : name);
  }
  return 'Shared';
}

/// A title on one line, at most 120 characters, cut at a word.
String _line(String text) {
  final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (one.length <= 120) return one;
  final cut = one.substring(0, 120);
  final space = cut.lastIndexOf(' ');
  return '${(space > 60 ? cut.substring(0, space) : cut).trimRight()}…';
}

/// A link's words: a `]` or a line break in them kept from ending it.
String _words(String text) => text.replaceAll(r'\', r'\\').replaceAll(']', r'\]').replaceAll('[', r'\[').replaceAll(RegExp(r'\s+'), ' ').trim();

/// An address as a link's target: in angle brackets where it holds a space or a bracket that would end it.
String _target(String url) => RegExp(r'[\s()<>]').hasMatch(url) ? '<${url.replaceAll('>', '%3E').replaceAll(' ', '%20')}>' : url;

/// What [share] says, as Markdown, with [files] (each kept file's Markdown, in order) after it.
String sharedMarkdown(SharedIn share, [List<String> files = const []]) {
  final parts = <String>[];
  final link = sharedLink(share);
  if (link != null) {
    final page = _pageTitle(share, link);
    parts.add(page == null ? '<$link>' : '[${_words(page)}](${_target(link)})');
  } else if (share.text != null && share.text!.trim().isNotEmpty) {
    parts.add(share.text!.replaceAll('\r\n', '\n').trim());
  }
  parts.addAll(files);
  return parts.join('\n\n');
}

/// A new note's body: [title] as its first line, unless what was shared already opens with it.
String sharedNoteBody(String title, String markdown) {
  if (markdown.trim().isEmpty) return '# $title\n';
  if (sameTitle(noteTitle(markdown), title)) return '$markdown\n';
  return '# $title\n\n$markdown\n';
}

/// [body] with [markdown] at its end, above its comments' fence where it has one, a blank line between.
String sharedAppended(String body, String markdown) {
  final fence = readComments(body).fence;
  final head = fence == null ? body : body.substring(0, fence.from);
  final tail = fence == null ? '' : body.substring(fence.from);
  final base = head.replaceFirst(RegExp(r'\s+$'), '');
  final joined = '$base${base.isEmpty ? '' : '\n\n'}${markdown.trim()}\n';
  return tail.isEmpty ? joined : '$joined\n$tail';
}

/// Where shares come from: the phone's (ShareIn.kt), or a test's.
abstract interface class ShareSource {
  /// Every share made ready since the last ask, and kept no longer.
  Future<List<SharedIn>> take();

  /// Told each time another is ready while the app runs.
  Stream<void> get arrived;

  /// The sheet is done with: the person goes back to the app they shared from.
  Future<void> done();
}

/// The phone's shares over `ghost_md/share`. One for the life of the app, as [PhoneLinks] is: making one takes the
/// channel's handler.
class PhoneShares implements ShareSource {
  PhoneShares({MethodChannel channel = shareInChannel}) : _channel = channel {
    _channel.setMethodCallHandler(_said);
  }

  final MethodChannel _channel;
  final StreamController<void> _arrived = StreamController<void>.broadcast();

  Future<Object?> _said(MethodCall call) async {
    if (call.method == 'arrived' && !_arrived.isClosed) _arrived.add(null);
    return null;
  }

  @override
  Future<List<SharedIn>> take() async {
    final List<Object?>? kept;
    try {
      kept = await _channel.invokeListMethod<Object?>('take');
    } on MissingPluginException {
      return const [];
    }
    return [
      for (final each in kept ?? const <Object?>[])
        if (each is String) ?SharedIn.fromJson(_decoded(each)),
    ];
  }

  static Object? _decoded(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<void> get arrived => _arrived.stream;

  @override
  Future<void> done() async {
    try {
      await _channel.invokeMethod<void>('done');
    } on MissingPluginException {
      // A run with no phone half: nowhere to go back to.
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_arrived.close());
  }
}

/// Takes the shares once the app has its notes, and again whenever one arrives, and hands each to [open] once.
/// Answers the way to stop.
void Function() followShares(void Function(SharedIn share) open, ShareSource source) {
  var gone = false;
  final seen = <String>{};
  Future<void> take() async {
    List<SharedIn> shares;
    try {
      shares = await source.take();
    } catch (_) {
      shares = const [];
    }
    if (gone) return;
    for (final share in shares) {
      if (seen.add(share.id) && (!share.empty || share.unread > 0)) open(share);
    }
  }

  unawaited(take());
  final heard = source.arrived.listen((_) => unawaited(take()));
  return () {
    gone = true;
    unawaited(heard.cancel());
  };
}
