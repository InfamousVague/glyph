/// Evernote exports brought into the library (Settings › Import › Evernote export).
///
/// Each `.enex` is one Evernote notebook, named by its file (`Recipes.enex` is Recipes: Evernote's own export
/// metadata names no notebook). Its notes become Ghost.md notes and the notebook a Ghost.md notebook whose index
/// lists them (lib/core/book.dart `bookNoteBody`), its pages in a folder of its own on disk:
/// `workspaces/Imported from Evernote 2026-10-16/Recipes.md` and `…/Recipes/Pancakes.md`.
///
/// A note is its title as a heading, its tags as the app's tag marks (`#weeknight #breakfast`, chapter 07 of the
/// guide: a tag is a `#` against a letter, then letters, digits, `_`, `-` or `/`, so `Quick meals` is
/// `#quick-meals`), its body in Markdown (lib/importer/enml.dart), and the address it was clipped from, where it
/// says one. Its created and updated dates are Evernote's. Each resource is kept once, a picture among the
/// library's pictures and anything else beside them (lib/core/shared_files.dart), and drawn where the body named it
/// by its MD5; one the body did not name is put at the note's end.
///
/// The export is read in an isolate of its own a note at a time (lib/importer/enex.dart), and a note's body larger
/// than [inlineEnml] is turned into Markdown in another, so the screen is never held by it.
library;

import 'dart:isolate';

import '../core/book.dart' show bookNoteBody;
import '../core/shared_files.dart' show SharedBytes, sharedFileMarkdown;
import '../core/title_key.dart';
import 'enex.dart';
import 'enml.dart';
import 'import_paths.dart';
import 'import_report.dart';
import 'import_sources.dart';
import 'import_target.dart';

/// The longest body turned into Markdown on the screen's isolate.
const int inlineEnml = 256 * 1024;

final RegExp _tagLetters = RegExp(r'[^\p{L}\p{N}_/-]+', unicode: true);

/// An Evernote tag as the app's tag mark: spaces a `-`, what a tag cannot hold taken out, and a `tag-` before one
/// that does not start with a letter (`2024` is `#tag-2024`). Null for one with nothing left.
String? tagMark(String tag) {
  var name = tag.trim().replaceAll(RegExp(r'\s+'), '-').replaceAll(_tagLetters, '').replaceAll(RegExp(r'-{2,}'), '-');
  name = name.replaceFirst(RegExp(r'^[-/]+'), '').replaceFirst(RegExp(r'[-/]+$'), '');
  if (name.isEmpty) return null;
  if (!RegExp(r'^\p{L}', unicode: true).hasMatch(name)) name = 'tag-$name';
  return '#$name';
}

/// The extension a resource is kept under, from its own name or else its type.
String resourceExtension(EnexResource resource) {
  final named = resource.fileName ?? '';
  final dot = named.lastIndexOf('.');
  if (dot > 0 && dot < named.length - 1) return named.substring(dot + 1).toLowerCase();
  final mime = resource.mime.toLowerCase();
  const known = {
    'application/pdf': 'pdf',
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'audio/x-m4a': 'm4a',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/amr': 'amr',
    'image/gif': 'gif',
    'image/heic': 'heic',
    'image/svg+xml': 'svg',
    'text/plain': 'txt',
    'text/html': 'html',
    'application/msword': 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
    'application/vnd.ms-excel': 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
    'application/zip': 'zip',
  };
  if (known[mime] case final ext?) return ext;
  final sub = mime.contains('/') ? mime.substring(mime.indexOf('/') + 1) : '';
  return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(sub) ? sub : 'bin';
}

String _resourceName(EnexResource resource) {
  final named = (resource.fileName ?? '').trim();
  if (named.isNotEmpty) return named;
  return 'Attachment.${resourceExtension(resource)}';
}

String _stem(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

/// A title as a notebook's index links it: what a `[[link]]` cannot hold taken out (book.dart's `_link`).
String _linkTitle(String title) {
  final clean = title.replaceAll(RegExp(r'[\[\]|#^\n]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.length > 120 ? clean.substring(0, 120).trim() : clean;
}

/// The note's body: its title, its tags, its words, and where it was clipped from.
String evernoteBody(EnexNote note, String markdown, List<String> loose) {
  final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim().replaceAll('\n', ' ');
  final tags = [for (final tag in note.tags) ?tagMark(tag)];
  final parts = [
    '# $title',
    if (tags.isNotEmpty) tags.join(' '),
    if (markdown.trim().isNotEmpty) markdown.trim(),
    ...loose,
    if (note.sourceUrl case final url? when url.startsWith('http')) '[Source]($url)',
  ];
  return '${parts.join('\n\n')}\n';
}

/// Imports the exports [files] through [target]: each a notebook. [progress] hears each note as it is written
/// (its total is 0: an export is read as it streams, and how many it holds is not known until its end); [stopped]
/// is asked between notes, and an import stopped keeps what it made.
Future<ImportReport> importEvernote(List<ImportFile> files, ImportTarget target, {void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
  final run = target.begin('Evernote');
  final report = run.report;
  var done = 0;
  var encrypted = 0;
  try {
    for (final file in files) {
      if (stopped?.call() ?? false) break;
      final notebook = cleanStem(_stem(file.name));
      final pages = <String>[];
      final seen = <String>{};
      EnexReader? reader;
      try {
        reader = await EnexReader.open(await file.localPath());
        while (!(stopped?.call() ?? false)) {
          final note = await reader.next();
          if (note == null) break;
          // Each resource kept once, by its MD5; what the body says for it.
          final said = <String, String>{};
          for (final resource in note.resources) {
            if (said.containsKey(resource.hash)) continue;
            try {
              final picture = await run.picture(resource.data);
              said[resource.hash] = picture != null
                  ? ImportRun.pictureMarkdown(picture)
                  : sharedFileMarkdown(_resourceName(resource), await run.file(SharedBytes(resource.data), _resourceName(resource)));
            } catch (_) {
              report.skipped.add('an attachment of ${note.title.isEmpty ? 'a note' : note.title}, which could not be kept');
            }
          }
          final EnmlMarkdown converted;
          var unknown = 0;
          if (note.content.length > inlineEnml) {
            final answer = await Isolate.run(() {
              var away = 0;
              final made = enmlToMarkdown(note.content, media: (hash, type) {
                final found = said[hash];
                if (found == null) away += 1;
                return found;
              });
              return (made, away);
            });
            converted = answer.$1;
            unknown = answer.$2;
          } else {
            converted = enmlToMarkdown(note.content, media: (hash, type) {
              final found = said[hash];
              if (found == null) unknown += 1;
              return found;
            });
          }
          report.missing += unknown;
          encrypted += converted.encrypted;
          final loose = [
            for (final MapEntry(:key, :value) in said.entries)
              if (!converted.used.contains(key)) value,
          ];
          final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
          final path = run.paths.place([notebook], title, original: '${cleanStem(title)}.md');
          await run.note(body: evernoteBody(note, converted.markdown, loose), path: path, createdAt: note.created, updatedAt: note.updated ?? note.created);
          final link = _linkTitle(title);
          if (link.isNotEmpty && seen.add(titleKey(link))) pages.add(link);
          done += 1;
          progress?.call((done: done, total: 0, on: title));
        }
      } catch (failure) {
        report.skipped.add('${file.name}${pages.isEmpty ? '' : ' after ${pages.length} notes'}, which could not be read${failure is StateError ? ': ${failure.message}' : ''}');
      } finally {
        await reader?.close();
        await file.done();
      }
      if (pages.isNotEmpty) {
        await run.note(body: bookNoteBody(notebook, pages), path: run.paths.place(const [], notebook, original: file.name), notebook: true);
      }
    }
  } finally {
    if (encrypted > 0) report.skipped.add(encrypted == 1 ? 'one encrypted passage, which Evernote keeps locked' : '$encrypted encrypted passages, which Evernote keeps locked');
    run.finish();
  }
  return report;
}

