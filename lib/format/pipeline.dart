/// A note as the model should see it, and the way back. A port of `src/app/format/pipeline.ts`.
///
/// Matt chose one pass by the chosen model, landing in the note itself as it is written (ai/runs.dart,
/// ai/landing.dart). What every run shares is the preparation: the tidy-up before the model (clean.dart), places and
/// videos, tables and links swapped for tokens it can copy and put back after (embeds.dart, tables.dart,
/// links.dart), and the hash of the body a run was written from.
///
/// What differs: the page asks its plugin registry (`plugins/registry.ts`) what plugins know about a note. Plugins
/// are a later stage here, so that is a [PluginContext] with the registry's two functions: [noteHash] and
/// [noteContext] take one, and left out it is [pluginContext], which is [noPlugins] until [usePluginContext] is
/// given the real one. `restore` takes `isFinal` in the place of the page's `final`.
library;

import '../core/item_syntax.dart' show jsTrim;
import 'body_hash.dart';
import 'clean.dart';
import 'embeds.dart';
import 'links.dart';
import 'modes.dart';
import 'tables.dart';

/// What plugins know about a note, in the registry's shape: the context for the system message (`pluginContextFor`:
/// null for none) and its version (`pluginContextVersion`: 0 for none).
class PluginContext {
  const PluginContext({required this.contextFor, required this.contextVersion});

  final String? Function(String noteId) contextFor;
  final int Function(String noteId) contextVersion;
}

String? _noContext(String noteId) => null;
int _noVersion(String noteId) => 0;

/// No plugin has anything to say.
const PluginContext noPlugins = PluginContext(contextFor: _noContext, contextVersion: _noVersion);

PluginContext _plugins = noPlugins;

/// What [noteHash] and [noteContext] ask when they are given nothing else.
PluginContext get pluginContext => _plugins;

/// Makes [next] what plugins know: called once the plugin registry exists, and by a test.
void usePluginContext(PluginContext next) => _plugins = next;

/// What a run was written from: the body, and the version of the context plugins gave with it (the Projects plugin's
/// briefing), so a note whose project was re-read reads as edited.
int noteHash(String id, String body, {PluginContext? plugins}) {
  final version = (plugins ?? _plugins).contextVersion(id);
  return bodyHash(version != 0 ? '$body\u0000project:$version' : body);
}

/// What plugins know about the note (a linked project's briefing), for the system message, where it is snapshotted.
String? noteContext(String id, {PluginContext? plugins}) => (plugins ?? _plugins).contextFor(id);

final RegExp _fenced = RegExp(r'^```[a-z]*\n([\s\S]*?)\n```$', caseSensitive: false);

/// What a model still gets wrong at the edges: a code fence around the whole note, and blank lines at either end.
/// The words are left alone.
String _tidy(String text) {
  var out = jsTrim(text);
  final inside = _fenced.firstMatch(out)?.group(1);
  if (inside != null && inside.isNotEmpty) out = jsTrim(inside);
  return '$out\n';
}

/// A note ready for the model: what to send, and the way back.
class PreparedNote {
  const PreparedNote({required this.prompt, required this.restore});

  /// The note as the model sees it.
  final String prompt;

  /// The model's words as the note's: with `isFinal`, the tidy-up of the whole answer once it has finished; without,
  /// the text so far, for the lines as they land.
  final String Function(String text, bool isFinal) restore;
}

/// Tables and links go in as tokens the model can copy (tables first, so a link in a cell is inside the block) and
/// come back out in reverse; the tidy-up before (clean.dart) keeps the hash the note's own. A summary may leave a
/// table out.
PreparedNote prepareNote(String body, Mode mode) {
  // Places and videos first (embeds.dart): a line that is one is swapped whole, before a table or a link can take part of it.
  final withoutEmbeds = protectEmbeds(cleanNote(body));
  final withoutTables = protectTables(withoutEmbeds.text);
  final withoutLinks = protectLinks(withoutTables.text);
  final keepAll = mode != RunKind.summarize;
  String put(String text, bool isFinal) => restoreEmbeds(
        restoreTables(restoreLinks(text, withoutLinks.links, isFinal: isFinal, lostBlanks: keepAll), withoutTables.tables, isFinal: isFinal, appendMissing: keepAll),
        withoutEmbeds.embeds,
        isFinal: isFinal,
        appendMissing: keepAll,
      );
  return PreparedNote(
    prompt: withoutLinks.text,
    restore: (text, isFinal) => isFinal ? _tidy(cleanRewrite(put(_tidy(text), true))) : put(text, false),
  );
}
