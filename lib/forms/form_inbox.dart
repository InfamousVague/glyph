/// Forms from a share link, on the device (docs/FORMS.md; lib/forms/form_def.dart says what a form is): the step of a
/// sync pass that tells glyph-api which shared notes are forms, and files each answer that came as a ticket.
///
/// **Telling the service.** A form is shared as any note is (lib/share/share.dart; the share carries only its public
/// part, [publicFormBody]). Each pass, every note this account shares that is a form is said to be one
/// (`PUT forms/<share id>`): which note defines it (its id, as sync already names it to the service), whether it takes a
/// file, and the organization whose members file it - the team's whose workspace the form's notebook is in, or none,
/// for the account's own. It is said again only when one of those changes (kept on this device), and never says the
/// form's state: open, paused or closed is the person's to set (the share sheet's rows, lib/forms/ui/form_rows.dart).
///
/// **Filing an answer.** The inbox is read a hundred at a time, oldest first. Each answer is CLAIMED for this device
/// first (`POST forms/inbox/<id>/claim`): one another device holds - this account's, or a teammate's - is passed over,
/// and is that device's to file. Claimed, it is opened: the wrap the visitor's browser made to this account's public
/// key gives a 32-byte key (the account's pair, as an organization key's wrap is opened), and that key the answers
/// (`openBytes` in `form:<form>:<answer>`). It is filed as a ticket in the form's notebook ([fileAnswer]) under an id
/// made from the answer's ([formTicketId]), so a second device filing it after a claim lapsed writes the same note, not
/// a second one; and one this device already has is not filed again. Then the service is told it is filed
/// (`DELETE forms/inbox/<id>`), and it goes. What was filed is remembered here too, so a pass cut short after the
/// ticket was written never files it twice.
///
/// **What a ticket is.** Its title from the form's `ticket:` pattern (or its first answer), its notebook's next key and
/// workflow, the ticket template the form names, filled; in its front matter `via: form`, `form: [[the form]]`,
/// `answered:` and the short answers, an email field's as `email:`; in its body each answer under its field's label, a
/// picture or a file that came with it, and the line saying it came by the form and when. It goes into its notebook's
/// index and its workspace, so a team's form files into the team's notebook for every member. And the bell says so
/// (`form-answer`, lib/core/notifications.dart).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../book/tickets.dart' show newTicketBody, nextTicketId;
import '../core/attachment_refs.dart' show attachmentMarkdown, keptExtension;
import '../core/book.dart' show bookIndex, isBookBody, placeOf, withChapter;
import '../core/bytes.dart';
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle;
import '../core/preferences.dart';
import '../core/properties.dart' show statusesOf;
import '../core/stored.dart';
import '../core/title_key.dart' show sameTitle, titleKey;
import '../mail/mail_note.dart' show pictureExtension;
import '../notes/note_templates.dart' show NoteTemplate, builtIns, fillNoteTemplate;
import '../notes/own_templates.dart' show templatesOf;
import '../sync/notes.dart' show FileKind, LocalFiles, LocalNotes;
import 'form_def.dart';

/// The contexts a browser wraps an answer's key in and seals its answers in (tauri/src/read/form.ts).
String formWrapContext(String form, String answer) => 'form-key:$form:$answer';
String formSealContext(String form, String answer) => 'form:$form:$answer';

/// An answer, opened from what the visitor's browser sealed: the wrap made to [mine] (this account's public key), the
/// key out of it with [pair], the answers out of the blob.
Future<FormAnswer> openFormAnswer(AccountCrypto crypto, EncryptionKey pair, {required String form, required String answer, required String mine, required List<Object?> wraps, required String blob}) async {
  String? wrap;
  for (final each in wraps) {
    if (each is Map && each['to'] == mine && each['wrap'] is String) wrap = each['wrap'] as String;
  }
  if (wrap == null) throw StateError('That answer was not sealed to this account.');
  final raw = await crypto.unwrapWith(pair, wrap, formWrapContext(form, answer));
  final key = await crypto.importSealKey(raw);
  final opened = await crypto.openBytes(key, fromBase64Url(blob), formSealContext(form, answer));
  return readFormAnswer(utf8.decode(opened, allowMalformed: true));
}

/// An answer's payload as the browser sealed it, `{ v, answers: [[label, words], ...], file?, at }`.
FormAnswer readFormAnswer(String opened) {
  final json = jsonDecode(opened);
  if (json is! Map || json['v'] != 1) throw const FormatException('That answer was sealed by a newer Ghost.md.');
  final answers = <(String, String)>[];
  final listed = json['answers'];
  for (final each in listed is List ? listed : const <Object?>[]) {
    if (each is List && each.length >= 2 && each[0] is String && each[1] is String && (each[1] as String).trim().isNotEmpty) answers.add((each[0] as String, (each[1] as String).trim()));
  }
  final file = json['file'];
  FormFile? sent;
  if (file is Map && file['data'] is String && file['field'] is String) {
    try {
      sent = FormFile(field: file['field'] as String, name: file['name'] is String ? file['name'] as String : 'file', type: file['type'] is String ? file['type'] as String : 'application/octet-stream', bytes: fromBase64Url(file['data'] as String));
    } on FormatException {
      sent = null;
    }
  }
  final at = json['at'];
  return FormAnswer(answers: List.unmodifiable(answers), file: sent, at: at is num ? at.toInt() : null);
}

String _uuidOf(String seed) {
  final b = Uint8List.fromList(crypto.sha256.convert(utf8.encode(seed)).bytes.sublist(0, 16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = [for (final byte in b) byte.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The id of the ticket an answer becomes: a UUID v4 drawn from the answer's id, so two devices, or a pass cut short,
/// make one.
String formTicketId(String answerId) => _uuidOf('ghost-form-ticket:$answerId');

/// The name a picture or a file that came with an answer is kept under, made from the answer's id the same way.
String formFileName(String answerId, String extension) => '${_uuidOf('ghost-form-file:$answerId')}.$extension';

/// What the forms step works with.
class FormPassContext {
  const FormPassContext({
    required this.token,
    required this.api,
    required this.crypto,
    required this.pair,
    required this.notes,
    required this.files,
    required this.now,
    required this.prefs,
    required this.kept,
    this.workspaceOf,
    this.orgOf,
    this.fileNote,
    this.told,
  });

  final String token;
  final Api api;
  final AccountCrypto crypto;

  /// The account's encryption pair, its public key registered with the service: asked for only when it is needed.
  final Future<EncryptionKey> Function() pair;
  final LocalNotes notes;
  final LocalFiles files;
  final int Function() now;

  /// The settings now: the shares, and what is in the trash.
  final Preferences Function() prefs;

  /// This device's memory: its id for claims, the forms said, the answers filed.
  final Stored kept;

  /// The workspace a note is filed in, by its id, and the organization a workspace is under; and a note filed into a
  /// workspace. Left out, nothing is filed anywhere but the library.
  final String? Function(String noteId)? workspaceOf;
  final String? Function(String workspaceId)? orgOf;
  final void Function(String noteId, String workspaceId)? fileNote;

  /// The bell told of a ticket filed: its id, its title, and the form's title.
  final Future<void> Function(String noteId, String title, String form)? told;
}

/// One forms step, as the engine is handed it: answers how many tickets it filed.
typedef FormPass = Future<int> Function(FormPassContext ctx);

const String _filedKey = 'glyph-forms-filed';
const String _saidKey = 'glyph-forms-said';
const String _deviceKey = 'glyph-forms-device';

/// How many filed answers' ids are remembered: more than a form keeps waiting (500).
const int _filedKept = 1000;

/// The most answers one page of the inbox carries.
const int formInboxPage = 100;

List<String> _filed(Stored kept) {
  final raw = kept.read<Object?>(_filedKey, null);
  return [if (raw is List) ...raw.whereType<String>()];
}

void _remember(Stored kept, List<String> ids) => kept.write(_filedKey, ids.length > _filedKept ? ids.sublist(ids.length - _filedKept) : ids);

/// This device's own id for its claims: 128 random bits, made once, kept on this device alone.
String formDevice(Stored kept, AccountCrypto random) {
  final had = kept.read<Object?>(_deviceKey, null);
  if (had is String && had.isNotEmpty) return had;
  final made = toBase64Url(random.randomBytes(16));
  kept.write(_deviceKey, made);
  return made;
}

/// The notebook a form files into: the one its `to:` names, else the one whose index lists the form, else none.
Note? formNotebook(FormDef? def, Note? form, List<Note> notes) {
  final to = def?.to;
  if (to != null && to.isNotEmpty) {
    for (final note in notes) {
      if (isBookBody(note.body) && sameTitle(noteTitle(note.body), to)) return note;
    }
  }
  if (form == null) return null;
  return placeOf(bookIndex(notes), form)?.book;
}

/// The organization whose members file a form: the one the workspace of its notebook (or of the form itself) is under.
String? formOrg(FormPassContext ctx, Note? notebook, Note? form) {
  for (final note in [?notebook, ?form]) {
    final space = ctx.workspaceOf?.call(note.id);
    final org = space == null ? null : ctx.orgOf?.call(space);
    if (org != null) return org;
  }
  return null;
}

/// Tells the service which of this account's shared notes are forms (see the header). Quiet against a service with no
/// forms yet.
Future<void> sayForms(FormPassContext ctx, List<Note> notes) async {
  final prefs = ctx.prefs();
  final said = <String, String>{};
  final raw = ctx.kept.read<Object?>(_saidKey, null);
  if (raw is Map) {
    for (final entry in raw.entries) {
      if (entry.key is String && entry.value is String) said[entry.key as String] = entry.value as String;
    }
  }
  final byId = {for (final note in notes) note.id: note};
  var keyed = false;
  for (final MapEntry(key: noteId, value: share) in prefs.shares.entries) {
    final note = byId[noteId];
    if (note == null || prefs.trash.containsKey(noteId) || !isFormBody(note.body)) continue;
    final def = formOf(note.body);
    final org = formOrg(ctx, formNotebook(def, note, notes), note);
    final digest = jsonEncode([org, def?.takesFile ?? false, noteId]);
    if (said[share.id] == digest) continue;
    // An answer to the account's own form is sealed to the account's key: there must be one, and the service must hold it.
    if (org == null && !keyed) {
      await ctx.pair();
      keyed = true;
    }
    try {
      await ctx.api.call('PUT', 'forms/${Uri.encodeComponent(share.id)}', token: ctx.token, body: {'org': org, 'files': def?.takesFile ?? false, 'note': noteId});
      said[share.id] = digest;
      ctx.kept.write(_saidKey, said);
    } catch (failure) {
      if (notYet(failure)) return;
      if (failure is ApiError && failure.status == 401) rethrow;
      debugPrint('[forms] a form was not said to the service: $failure');
    }
  }
}

/// The answer [answer] to the form [formNote] (null for one no longer here) filed as a ticket among [notes], under
/// [id]: written, put into its notebook's index and its workspace. Answers the ticket's title.
Future<String> fileAnswer(FormPassContext ctx, {required String id, required String answerId, required Note? formNote, required FormAnswer answer, required List<Note> notes, required int at}) async {
  final def = formNote == null ? null : formOf(formNote.body);
  final formTitle = formNote == null ? '' : noteTitle(formNote.body);
  final notebook = formNotebook(def, formNote, notes);
  final live = [for (final note in notes) if (note.archivedAt == null) note];
  // A page is its notebook's by its title, so a second ticket of one title takes the next number.
  var title = ticketTitleOf(def, answer);
  final taken = {for (final note in live) titleKey(noteTitle(note.body))};
  if (taken.contains(titleKey(title))) {
    var n = 2;
    while (taken.contains(titleKey('$title ($n)'))) {
      n += 1;
    }
    title = '$title ($n)';
  }
  final key = notebook == null ? null : nextTicketId(notebook.body, [for (final note in notes) note.body]);
  final when = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
  String? words;
  final templateName = def?.template;
  if (templateName != null) {
    NoteTemplate? template;
    for (final each in [...?templatesOf(notes), ...builtIns]) {
      if (titleKey(each.name) == titleKey(templateName)) {
        template = each;
        break;
      }
    }
    if (template != null) words = fillNoteTemplate(template, when.toLocal(), taken, nextId: key, title: title).body;
  }
  String? fileLink;
  final file = answer.file;
  if (file != null && file.bytes.isNotEmpty) {
    final bytes = Uint8List.fromList(file.bytes);
    final picture = pictureExtension(file.type.toLowerCase());
    try {
      if (picture != null) {
        final name = formFileName(answerId, picture);
        await ctx.files.write(FileKind.image, name, bytes);
        fileLink = '![${file.name.replaceAll(RegExp(r'[\[\]]'), '')}](image/$name)';
      } else {
        final name = formFileName(answerId, keptExtension(file.name));
        await ctx.files.write(FileKind.attachment, name, bytes);
        fileLink = attachmentMarkdown(name, file.name, bytes: bytes.length);
      }
    } catch (failure) {
      // Not what its name says (the core checks a picture's bytes): said rather than kept.
      debugPrint('[forms] a file was not kept: $failure');
      fileLink = 'Came with it, not kept: ${file.name} (${bytes.length} bytes).';
    }
  }
  final body = withAnswer(newTicketBody(title, id: key, statuses: statusesOf(notebook?.body), words: words), def, answer, formTitle: formTitle, at: when, fileLink: fileLink);
  await ctx.notes.apply(Note(id: id, body: body, createdAt: at, updatedAt: ctx.now()));
  if (notebook != null) {
    final fresh = await ctx.notes.get(notebook.id) ?? notebook;
    final listed = withChapter(fresh.body, title);
    if (listed != fresh.body) await ctx.notes.apply(fresh.copyWith(body: listed, updatedAt: ctx.now()));
  }
  final space = ctx.workspaceOf?.call(notebook?.id ?? formNote?.id ?? '');
  if (space != null) ctx.fileNote?.call(id, space);
  return title;
}

/// The forms step (see the header). Quiet against a service that has no form routes yet.
Future<int> syncForms(FormPassContext ctx) async {
  final prefs = ctx.prefs();
  var notes = [for (final note in await ctx.notes.list()) if (!prefs.trash.containsKey(note.id)) note];
  await sayForms(ctx, notes);
  final filed = _filed(ctx.kept);
  final device = formDevice(ctx.kept, ctx.crypto);
  EncryptionKey? pair;
  String? mine;
  var made = 0;

  Future<void> taken(String id) async {
    try {
      await ctx.api.call('DELETE', 'forms/inbox/${Uri.encodeComponent(id)}', token: ctx.token);
    } on ApiError catch (failure) {
      if (failure.status == 401) rethrow;
      if (failure.status != 404) debugPrint('[forms] an answer was not taken off the inbox: $failure');
    }
  }

  String? after;
  for (;;) {
    final Object? listed;
    try {
      listed = await ctx.api.call('GET', after == null ? 'forms/inbox' : 'forms/inbox?after=${Uri.encodeQueryComponent(after)}', token: ctx.token);
    } catch (failure) {
      if (notYet(failure)) return made;
      rethrow;
    }
    if (listed is! List || listed.isEmpty) break;
    for (final each in listed) {
      if (each is! Map || each['id'] is! String || each['form'] is! String) continue;
      final id = each['id'] as String, form = each['form'] as String;
      after = id;
      final ticket = formTicketId(id);
      // Filed here before, or by another device whose ticket has reached this one: only the service is to be told.
      if (filed.contains(id) || await ctx.notes.get(ticket) != null) {
        await taken(id);
        continue;
      }
      final wraps = each['wraps'] is List ? each['wraps'] as List : const <Object?>[];
      pair ??= await ctx.pair();
      mine ??= await ctx.crypto.encryptionPublicKeyOf(pair);
      // Sealed before this account was the team's, or to the owner alone: a teammate's to file, not claimed here.
      if (!wraps.any((wrap) => wrap is Map && wrap['to'] == mine)) continue;
      try {
        await ctx.api.call('POST', 'forms/inbox/${Uri.encodeComponent(id)}/claim', token: ctx.token, body: {'device': device});
      } on ApiError catch (failure) {
        if (failure.status == 401) rethrow;
        // Another device files it (409), or it is filed already (404).
        continue;
      }
      final FormAnswer answer;
      try {
        answer = await openFormAnswer(ctx.crypto, pair, form: form, answer: id, mine: mine, wraps: wraps, blob: '${each['blob']}');
      } catch (failure) {
        // Left waiting: a teammate it was sealed to, or a newer app, may open what this one cannot.
        debugPrint('[forms] an answer would not open: $failure');
        continue;
      }
      final noteId = each['note'];
      Note? formNote;
      for (final note in notes) {
        if (note.id == noteId) formNote = note;
      }
      if (formNote == null) {
        // From an older service that names no note: the account's own share of it, by its id.
        for (final MapEntry(key: noteId, value: share) in prefs.shares.entries) {
          if (share.id == form) formNote = notes.where((note) => note.id == noteId).firstOrNull;
        }
      }
      final listedAt = each['at'];
      final at = answer.at ?? (listedAt is num ? listedAt.toInt() : ctx.now());
      final title = await fileAnswer(ctx, id: ticket, answerId: id, formNote: formNote, answer: answer, notes: notes, at: at);
      made += 1;
      filed.add(id);
      _remember(ctx.kept, filed);
      notes = [for (final note in await ctx.notes.list()) if (!prefs.trash.containsKey(note.id)) note];
      try {
        await ctx.told?.call(ticket, title, formNote == null ? 'a form' : noteTitle(formNote.body));
      } catch (_) {
        // The bell is told on the next change; the ticket is filed either way.
      }
      await taken(id);
    }
    if (listed.length < formInboxPage) break;
  }
  return made;
}
