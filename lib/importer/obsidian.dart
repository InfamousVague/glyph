/// An Obsidian vault brought into the library (Settings › Import › Obsidian vault).
///
/// - **Every `.md`** becomes a note, word for word: its front matter, its `[[wiki links]]` and its `![[embeds]]` of
///   notes are kept as written. Two things are added where Ghost.md would read the note otherwise than Obsidian
///   does (lib/importer/obsidian_names.dart): a `title:` of its file's name where its first line is not that name,
///   so a `[[link]]` to it finds it, and a front matter list written across where it was written down the page. Its file keeps its name and its folder: `Projects/Alpha.md` in the vault is
///   `workspaces/Imported from Obsidian 2026-10-16/Projects/Alpha.md` in the library (lib/importer/import_paths.dart),
///   and its dates are the file's.
/// - **Every `.canvas`** becomes a canvas note: its JSON Canvas 1.0 as it is, under a `title:` of its file's name
///   (lib/canvas/json_canvas.dart `canvasNoteBody`), with a picture card's file pointed at the picture's kept copy.
/// - **Every attachment a note names** (a picture, a PDF, anything) is kept once, a picture among the library's
///   pictures and anything else beside them (lib/core/shared_files.dart), and every reference to it rewritten to
///   where it landed (lib/importer/obsidian_links.dart). Attachments no note names are kept too, and listed in one
///   note, "Files from" and the vault's name, so nothing in the vault is lost.
/// - **Left out**: the folders whose names start with a dot (`.obsidian/`, Obsidian's settings; `.trash/`, its
///   trash; `.git/`), and a file over [largestImport]. The report says each.
///
/// Nothing in the library is written over (lib/importer/import_paths.dart), and everything lands in one workspace
/// that can be taken away in one go (lib/importer/import_target.dart).
///
/// Heavy work is kept off the screen's isolate: a note larger than [inlineRewrite] has its references rewritten in
/// an isolate of its own. A smaller one takes well under a frame.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/shared_files.dart' show SharedBytes;
import 'import_report.dart';
import 'import_sources.dart';
import 'import_target.dart';
import 'obsidian_links.dart';
import 'obsidian_names.dart';

/// The largest file an import brings in: anything larger is left out and said.
const int largestImport = 512 * 1024 * 1024;

/// The longest note rewritten on the screen's isolate.
const int inlineRewrite = 256 * 1024;

/// A dot folder as the report says it was left out.
String skippedFolderSaid(String path) {
  final name = path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;
  return switch (name) {
    '.obsidian' => '$path/, Obsidian’s settings',
    '.trash' => '$path/, Obsidian’s trash',
    _ => '$path/, a hidden folder',
  };
}

String _stem(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

String _text(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  return text.replaceAll('\r\n', '\n');
}

String _ext(ImportEntry entry) => extensionOf(entry.name);

/// Imports the vault [folder] through [target]. [progress] hears each file as it is reached; [stopped] is asked
/// between files, and an import stopped keeps what it made. Answers what it did.
Future<ImportReport> importObsidianVault(ImportFolder folder, ImportTarget target, {void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
  final run = target.begin('Obsidian');
  final report = run.report;
  try {
    final listing = await folder.list();
    report.skipped.addAll(listing.skipped.map(skippedFolderSaid));
    final notes = <ImportEntry>[], canvases = <ImportEntry>[], attachments = <ImportEntry>[];
    for (final entry in listing.entries) {
      final ext = _ext(entry);
      if (entry.size > largestImport) {
        report.skipped.add('${entry.path}, larger than ${largestImport ~/ (1024 * 1024)} MB');
      } else if (ext == 'md') {
        notes.add(entry);
      } else if (ext == 'canvas') {
        canvases.add(entry);
      } else {
        attachments.add(entry);
      }
    }
    final byPath = {for (final entry in attachments) entry.path: entry};
    final resolver = VaultResolver(listing.entries.map((e) => e.path));
    final total = notes.length + canvases.length + attachments.length;
    var done = 0;
    void step(String on) {
      done += 1;
      progress?.call((done: done, total: total, on: on));
    }

    // Each attachment kept once, the first time a note names it, by its path in the vault.
    final landed = <String, Landed>{};
    final failed = <String>{};
    Future<Landed?> land(ImportEntry entry) async {
      if (landed[entry.path] case final already?) return already;
      if (failed.contains(entry.path)) return null;
      try {
        String? picture;
        if (entry.size <= largestPicture) {
          final bytes = await folder.read(entry);
          picture = await run.picture(bytes);
          if (picture == null) {
            final ref = await run.file(SharedBytes(bytes), entry.name);
            return landed[entry.path] = (ref: ref, picture: false);
          }
          return landed[entry.path] = (ref: picture, picture: true);
        }
        final ref = await run.file(folder.source(entry), entry.name);
        return landed[entry.path] = (ref: ref, picture: false);
      } catch (_) {
        failed.add(entry.path);
        report.skipped.add('${entry.path}, which could not be read');
        return null;
      }
    }

    for (final entry in notes) {
      if (stopped?.call() ?? false) break;
      final String text;
      try {
        text = _text(await folder.read(entry));
      } catch (_) {
        report.skipped.add('${entry.path}, which could not be read');
        step(entry.path);
        continue;
      }
      // The attachments this note names, kept first, so its references can be pointed at them.
      final resolved = <String, String>{};
      for (final ref in attachmentRefs(text)) {
        final path = resolver.resolve(ref.target, entry.folders);
        final attachment = path == null ? null : byPath[path];
        if (attachment == null) continue;
        resolved[ref.target] = attachment.path;
        await land(attachment);
      }
      final targets = {for (final MapEntry(:key, :value) in resolved.entries) key: ?landed[value]};
      var missing = 0;
      String rewrite() => rewriteAttachments(text, (ref) => targets[ref.target], missing: (_) => missing += 1);
      final body = text.length > inlineRewrite
          ? await Isolate.run(() {
              var away = 0;
              final written = rewriteAttachments(text, (ref) => targets[ref.target], missing: (_) => away += 1);
              return (written, away);
            }).then((answer) {
              missing = answer.$2;
              return answer.$1;
            })
          : rewrite();
      report.missing += missing;
      final path = run.paths.place(entry.folders, _stem(entry.name), original: entry.path);
      await run.note(body: obsidianNoteBody(body, _stem(entry.name)), path: path, createdAt: entry.modified > 0 ? entry.modified : null, updatedAt: entry.modified > 0 ? entry.modified : null);
      step(entry.path);
    }

    for (final entry in canvases) {
      if (stopped?.call() ?? false) break;
      try {
        final text = _text(await folder.read(entry)).trim();
        final json = jsonDecode(text);
        if (json is! Map || (json['nodes'] is! List && json['edges'] is! List)) throw const FormatException('not a canvas');
        var changed = false;
        for (final node in (json['nodes'] as List? ?? const [])) {
          if (node is! Map || node['type'] != 'file' || node['file'] is! String) continue;
          final file = node['file'] as String;
          if (!namesAttachment(file)) continue;
          final path = resolver.resolve(file, entry.folders);
          final attachment = path == null ? null : byPath[path];
          final kept = attachment == null ? null : await land(attachment);
          // A picture card draws a picture of the library's by its bare name (lib/canvas/card_looks.dart).
          if (kept != null && kept.picture) {
            node['file'] = kept.ref.substring('image/'.length);
            changed = true;
          } else if (kept == null) {
            report.missing += 1;
          }
        }
        final canvas = changed ? const JsonEncoder.withIndent('\t').convert(json) : text;
        final title = _stem(entry.name).replaceAll(RegExp('["\n]'), "'");
        final path = run.paths.place(entry.folders, _stem(entry.name), original: entry.path);
        await run.note(body: '---\ntitle: "$title"\n---\n$canvas\n', path: path, createdAt: entry.modified > 0 ? entry.modified : null, updatedAt: entry.modified > 0 ? entry.modified : null, canvas: true);
      } catch (_) {
        report.skipped.add('${entry.path}, not a canvas Ghost.md can read');
      }
      step(entry.path);
    }

    // What no note named, kept and listed, so nothing in the vault is left behind.
    final loose = <String>[];
    for (final entry in attachments) {
      if (stopped?.call() ?? false) break;
      if (!landed.containsKey(entry.path)) {
        final kept = await land(entry);
        if (kept != null) loose.add(kept.picture ? '![${entry.name.replaceAll(RegExp(r'[\[\]]'), '')}](${kept.ref})' : '- [${entry.path.replaceAll(RegExp(r'[\[\]]'), '')}](${kept.ref})');
      }
      step(entry.path);
    }
    if (loose.isNotEmpty) {
      final title = 'Files from ${folder.name}';
      final body = '# $title\n\nWhat was in the vault that no note linked to.\n\n${loose.join('\n\n')}\n';
      await run.note(body: body, path: run.paths.place(const [], title));
    }
  } finally {
    run.finish();
  }
  return report;
}
