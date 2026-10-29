/// A plugin's setup, step by step (Matt, 2026-10-28: "For each of the plugins add a small onboarding flow start with
/// the lovart and Claude plugins walk the user through setting up an account and getting their keys and have the
/// onboarding test setup to make sure it was successful"). This file is what a setup is made of; setup_sheet.dart
/// draws it, setup_card.dart is its way in from a plugin's page, and each plugin says its own steps beside its code
/// (lib/plugins/lovart/lovart_setup.dart, lib/plugins/claude/claude_setup.dart). A plugin offers one through
/// [GlyphPlugin.setup] (lib/plugins/types.dart), and the Market opens it as soon as the plugin is added while it still
/// needs one (lib/market/market_screen.dart).
///
/// A setup is a short run of steps, each a title, a few words, a sign on the walkthrough's colour band
/// (lib/guide/pages/band.dart [HueBand]) and what can be done there. There are five kinds, and a plugin's setup is
/// made of them in any order:
/// - [SetupIntro]: what the plugin is and what it costs, with a few points beside icons (in Advanced).
/// - [SetupOpen]: a page to open in the browser, an account's sign-up or where its keys are made, with a button each.
/// - [SetupPaste]: the keys to paste, each field with Paste and Show; checked for shape, then kept by the plugin's
///   own [SetupPaste.save], exactly where its page keeps them, so the sealed sync follows them as it always has.
/// - [SetupCheck]: a test of what was kept, run as the step shows ([SetupCheck.run]), saying it worked or, in plain
///   words, why not ([SetupResult]).
/// - [SetupDone]: the end, with what to try first or the settings that matter ([SetupDone.body]).
///
/// The words of each step are not written here but in setup_voice.dart, one place, by the plugin's id and the
/// step's ([setupWords]): they are the captions now and what a voice would say later, as the walkthrough's are.
///
/// **Where the person was** is remembered on this device, by plugin ([SetupMemory]): the step showing, kept as they
/// go, and how it ended (done or skipped). A setup put away half way (the sheet closed, the app left for the browser
/// and killed there) opens again at that step; one done or skipped starts from the beginning when it is run again.
/// What was typed in a field is never remembered: keys are kept only where the plugin keeps them.
///
/// **Simple** ([Preferences.simple]) has the same steps but those marked [SetupStep.advanced], and the shorter words
/// where a step has them (`<plugin>-<step>-simple`); an intro's points are Advanced's.
library;

import 'package:flutter/widgets.dart';

import '../../art/app_icon.dart' show LucideIcon;
import '../../core/stored.dart';
import 'setup_voice.dart';

/// A page a step opens in the browser.
@immutable
class SetupLink {
  const SetupLink(this.label, this.url, {this.verified = true});

  /// What its button says: "Open lovart.ai".
  final String label;
  final String url;

  /// Whether the address was seen to be where the words say (docs/LOVART.md, docs/CLAUDE_APP.md). Not shown; the
  /// tests hold the list, so an address no one has looked at is said as such in the docs.
  final bool verified;
}

/// A field a key is pasted into.
@immutable
class SetupField {
  const SetupField({required this.id, required this.label, required this.placeholder, this.shape, this.optional = false});

  /// The key it is handed to [SetupPaste.save] under.
  final String id;

  /// What it is called, aloud and over it: "Access key".
  final String label;
  final String placeholder;

  /// What is wrong with the shape of [text] (already trimmed), in a sentence; null where it looks right. Nothing is
  /// asked of the plugin's service for this: a key that looks right is checked by [SetupCheck].
  final String? Function(String text)? shape;

  /// Whether it may be left empty (an endpoint on the person's own computer needs no key: lib/plugins/custom_ai/). An
  /// empty one is handed to [SetupPaste.save] as ''.
  final bool optional;
}

/// How a check went.
enum SetupCheckKind {
  /// It works.
  ok,

  /// Kept and working, with something still to do that is not the app's: credit to add. Next goes on.
  warn,

  /// It did not work.
  failed,
}

/// What a check said, in a sentence a person can act on.
@immutable
class SetupResult {
  const SetupResult.ok(this.words)
      : kind = SetupCheckKind.ok,
        pasteAgain = false,
        link = null;
  const SetupResult.warn(this.words, {this.link})
      : kind = SetupCheckKind.warn,
        pasteAgain = false;
  const SetupResult.failed(this.words, {this.pasteAgain = false, this.link}) : kind = SetupCheckKind.failed;

  final SetupCheckKind kind;
  final String words;

  /// The keys were refused, and taken away again: the way on is back to [SetupPaste].
  final bool pasteAgain;

  /// A page that helps: Billing, for an account with no credit.
  final SetupLink? link;

  bool get ok => kind != SetupCheckKind.failed;
}

/// One step. The kinds are below; a setup's own words for it are [setupWords]'s.
sealed class SetupStep {
  const SetupStep({required this.id, required this.title, required this.icon, this.tiles = const [], this.advanced = false});

  /// Its name in the setup, and in its words' key (`lovart-paste`) and the memory.
  final String id;
  final String title;

  /// The sign in the middle of its band.
  final LucideIcon icon;

  /// The small icons round the sign; the setup's own when empty.
  final List<LucideIcon> tiles;

  /// Shown only in Advanced.
  final bool advanced;
}

/// What the plugin is (see the header).
class SetupIntro extends SetupStep {
  const SetupIntro({required super.id, required super.title, required super.icon, super.tiles, super.advanced, this.points = const [], this.mark = true});

  /// A few things it does, each beside an icon, under the words; Advanced's.
  final List<(LucideIcon, String)> points;

  /// The plugin's own mark in the band in place of [icon], where the setup has one.
  final bool mark;
}

/// A page to open (see the header).
class SetupOpen extends SetupStep {
  const SetupOpen({required super.id, required super.title, required super.icon, super.tiles, super.advanced, required this.links});

  /// The first is the step's own button; the rest stand beside it, quieter.
  final List<SetupLink> links;
}

/// The keys to paste (see the header).
class SetupPaste extends SetupStep {
  const SetupPaste({required super.id, required super.title, required super.icon, super.tiles, super.advanced, required this.fields, required this.save});

  final List<SetupField> fields;

  /// Keeps the values, by [SetupField.id], each trimmed and in the right shape, where the plugin keeps them. Answers
  /// what went wrong, or null.
  final Future<String?> Function(Map<String, String> values) save;
}

/// The test (see the header).
class SetupCheck extends SetupStep {
  const SetupCheck({required super.id, required super.title, required super.icon, super.tiles, super.advanced, required this.run, this.checking = 'Checking…'});

  /// Tests what is kept now. Never throws: a failure is a [SetupResult.failed] in words.
  final Future<SetupResult> Function() run;

  /// What is said while it runs.
  final String checking;
}

/// The end (see the header).
class SetupDone extends SetupStep {
  const SetupDone({required super.id, required super.title, required super.icon, super.tiles, super.advanced, this.body});

  /// What stands under the words: the settings that matter, or a first thing to try. Handed whether it is Simple.
  final Widget Function(BuildContext context, bool simple)? body;
}

/// A plugin's setup: its steps, its look, and whether it is needed.
class PluginSetup {
  const PluginSetup({required this.id, required this.name, required this.hues, required this.steps, required this.ready, required this.watch, this.tiles = const [], this.mark, this.prepare});

  /// The plugin's id: its words' and its memory's key.
  final String id;

  /// Its name: "Set up Lovart".
  final String name;

  /// The wash its bands and its card wear, by the names `marketHues` keeps (lib/market/market_items.dart); the first
  /// is its own colour, the dots' and the buttons'.
  final List<String> hues;

  /// The icons floating round each band's sign, where a step gives none.
  final List<LucideIcon> tiles;

  /// The plugin's own mark, white, at a size: for the intro's band and the card. Its icon where null.
  final Widget Function(double size)? mark;

  final List<SetupStep> steps;

  /// Whether nothing more is needed: the keys are kept. The Market offers the setup only while this is false, and the
  /// plugin's page says Set up while it is, Run setup again once it is not.
  final bool Function() ready;

  /// Tells [listener] when [ready] may have changed (the keys kept or forgotten, here or by the sync); answers the way
  /// to stop.
  final VoidCallback Function(VoidCallback listener) watch;

  /// Read before [ready] is first asked: the stores the keys are in. Null where they are read already.
  final Future<void> Function()? prepare;

  /// The steps shown, [simple] or not.
  List<SetupStep> stepsFor({required bool simple}) => [for (final step in steps) if (!simple || !step.advanced) step];

  /// [step]'s words, [simple] or not.
  String wordsOf(SetupStep step, {required bool simple}) => setupWords('$id-${step.id}', simple: simple);
}

/// How a setup ended.
enum SetupEnd { done, skipped }

/// Where each plugin's setup is, on this device (see the header): `{"lovart": {"at": "paste"}, "claude": {"at":
/// "done", "end": "done"}}`.
class SetupMemory {
  SetupMemory([Stored? on]) : _own = on;

  /// The key in the device's memory.
  static const String key = 'glyph-plugin-setup';

  final Stored? _own;
  Stored get _on => _own ?? stored;

  Map<String, Object?> _all() {
    final raw = _on.read<Object?>(key, null);
    return raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{};
  }

  ({String? at, SetupEnd? end}) _of(String plugin) {
    final one = _all()[plugin];
    if (one is! Map) return (at: null, end: null);
    final at = one['at'], end = one['end'];
    return (at: at is String ? at : null, end: SetupEnd.values.where((e) => e.name == end).firstOrNull);
  }

  /// The step [plugin]'s setup was left at, while it is neither done nor skipped.
  String? leftAt(String plugin) {
    final kept = _of(plugin);
    return kept.end == null ? kept.at : null;
  }

  /// How [plugin]'s setup ended, if it has.
  SetupEnd? ended(String plugin) => _of(plugin).end;

  /// [plugin]'s setup is at [step] now, and not over.
  void at(String plugin, String step) => _put(plugin, {'at': step});

  /// [plugin]'s setup ended at [step].
  void end(String plugin, String step, SetupEnd end) => _put(plugin, {'at': step, 'end': end.name});

  void forget(String plugin) => _put(plugin, null);

  void _put(String plugin, Map<String, Object?>? value) {
    final all = _all();
    if (value == null) {
      all.remove(plugin);
    } else {
      all[plugin] = value;
    }
    _on.write(key, all);
  }
}

/// The step a setup opens at: where it was left, unless it ended or [fromStart]; and never past the keys while none
/// are kept, so a setup left at its check, whose keys were since forgotten, asks for them again.
int setupStartIndex(PluginSetup setup, List<SetupStep> steps, SetupMemory memory, {bool fromStart = false}) {
  if (fromStart) return 0;
  final left = memory.leftAt(setup.id);
  if (left == null) return 0;
  final at = steps.indexWhere((s) => s.id == left);
  if (at < 0) return 0;
  final paste = steps.indexWhere((s) => s is SetupPaste);
  if (paste >= 0 && at > paste && !setup.ready()) return paste;
  return at;
}
