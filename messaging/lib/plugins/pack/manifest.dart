/// A pack as the app holds it once it has been checked (A.1 to A.14 of the format), and the checking: [parsePack] takes
/// a file's bytes and gives the pack, or every issue found, in plain words for the developer and the reviewer.
library;

import 'dart:typed_data';

import '../plugin.dart' show SettingOption;
import 'format.dart';
import 'phrases.dart';

enum PackSeverity { error, warning }

/// One thing wrong with a pack (an error, which stops it loading or being sent) or worth a second look (a warning).
class PackIssue {
  const PackIssue(this.code, this.path, this.message, {this.severity = PackSeverity.error});

  /// What kind of problem, as the format names it ('bad_text', 'phrase_bad_token', 'needs_permission').
  final String code;

  /// Where, dotted and indexed from the top (`rules.tags[0].any[2]`); '' for the whole file.
  final String path;

  /// Plain words for a developer, e.g. 'rules.tags[0].any[2]: "{foo}" is not a token.'
  final String message;
  final PackSeverity severity;

  bool get isError => severity == PackSeverity.error;

  Map<String, Object?> toJson() => {'code': code, 'path': path, 'message': message, 'severity': severity.name};

  /// The relay's invalid_package issues come back in this shape. Anything it doesn't say reads as an error, so a
  /// refusal is never shown as a mere warning.
  factory PackIssue.fromJson(Map j) => PackIssue('${j['code'] ?? 'invalid'}', '${j['path'] ?? ''}', '${j['message'] ?? ''}', severity: j['severity'] == 'warning' ? PackSeverity.warning : PackSeverity.error);

  @override
  String toString() => '${severity.name} $code at "$path": $message';
}

/// A condition (`when`, and a section's `takes`): every part given must hold.
class PackWhen {
  const PackWhen({this.from = const [], this.tagged = const [], this.untagged = const [], this.setting, this.settingIs, this.section});

  /// The senders it holds for, each as compared: only digits for a number, else trimmed and lower-cased.
  final List<String> from;

  /// Own tag names (without the `x<id>.` prefix) that must all be there, and that must all be missing.
  final List<String> tagged;
  final List<String> untagged;

  /// A setting's key: with no [settingIs], that toggle is on; else the choice's value (or a toggle's 'on' or 'off').
  final String? setting;
  final String? settingIs;

  /// An action's alone: the section of the place it is offered in, an own section key or 'main' for the main list.
  final String? section;
}

/// One tag rule (`rules.tags`): the phrases that give the tag, the person's own words joining them where [wordsFrom]
/// names a words setting, and what the tag says with it.
class PackTagRule {
  const PackTagRule({required this.tag, this.any = const [], this.atLeast = 1, this.all = const [], this.none = const [], this.wordsFrom, this.when, this.detail, this.detailFrom});
  final String tag;

  /// Compiled when the pack was checked, once: the pack's plugin never compiles them again.
  final List<Phrase> any;
  final int atLeast;
  final List<Phrase> all;
  final List<Phrase> none;
  final String? wordsFrom;
  final PackWhen? when;

  /// The tag's words where the rule gives fixed ones.
  final String? detail;

  /// 'token' (the first token's capture) or 'match' (the whole match), where the words come from the text instead.
  final String? detailFrom;
}

/// How a pack's section draws its rows: [value] and [caption] are templates of its tags (`{tag:bill}`); [end],
/// [word] and [tap] name its actions. Never a title: the row keeps the conversation's own name.
class PackRow {
  const PackRow({this.value, this.caption, this.faceName, this.faceColor, this.end, this.word, this.tap});
  final String? value;
  final String? caption;

  /// A face of plain words on a colour (0xRRGGBB), never a company's mark.
  final String? faceName;
  final int? faceColor;
  final String? end;
  final String? word;
  final String? tap;
}

/// One of a pack's sections (`rules.sections`): a tab of its own or a kind in the list's filter.
class PackSection {
  const PackSection({required this.key, required this.label, required this.icon, required this.kind, this.leavesMain = true, this.takes = const PackWhen(), this.row});

  /// Letters only: the registry knows it as `x<id>0<key>` (format.dart sectionIdOf).
  final String key;
  final String label;

  /// An icon's name (a key of Lucide.all).
  final String icon;

  /// 'tab' or 'filter'.
  final String kind;
  final bool leavesMain;
  final PackWhen takes;
  final PackRow? row;
}

/// One of a pack's buttons (`rules.actions`): where it is offered, when, and its one verb with that verb's fields.
class PackAction {
  const PackAction({required this.id, required this.label, required this.icon, required this.verb, required this.slots, this.when, this.text, this.say, this.to, this.url});
  final String id;
  final String label;
  final String icon;

  /// 'say', 'copy', 'write', 'markread', 'move' or 'link'.
  final String verb;

  /// Where it is offered: 'row', 'list.conversation.menu', 'conversation.header', 'conversation.message.menu'.
  final List<String> slots;
  final PackWhen? when;

  /// What a say says, a copy copies (a template) or a write writes.
  final String? text;

  /// What a copy says once it has copied.
  final String? say;

  /// Where a move files the conversation: 'main' or an own tab's key.
  final String? to;

  /// The pack's one link, for a link.
  final String? url;
}

/// One of a pack's incoming rules (`rules.incoming`): for texts its section [section] takes as they come, once the
/// toggle [setting] is on, mark them read and/or take their notification away.
class PackIncoming {
  const PackIncoming({required this.section, required this.verbs, required this.setting, this.when});

  /// The rule's `in`: an own section key.
  final String section;

  /// The rule's `do`: 'markread' and/or 'mute'.
  final List<String> verbs;
  final String setting;
  final PackWhen? when;
}

/// One of a pack's settings, as A.7 has them: 'toggle', 'choice', 'words', 'note' or 'heading'.
class PackSetting {
  const PackSetting({required this.type, this.key, required this.label, this.hint, this.icon, this.fallback = false, this.options = const [], this.choice, this.placeholder});
  final String type;
  final String? key;
  final String label;
  final String? hint;

  /// An icon's name.
  final String? icon;

  /// A toggle's default.
  final bool fallback;

  /// A choice's values, and its default.
  final List<SettingOption> options;
  final String? choice;

  /// A words field's placeholder.
  final String? placeholder;
}

/// A pack's rules: what it tags, the sections it adds, its buttons, and what it does as texts come.
class PackRules {
  const PackRules({this.tags = const [], this.sections = const [], this.actions = const [], this.incoming = const []});
  final List<PackTagRule> tags;
  final List<PackSection> sections;
  final List<PackAction> actions;
  final List<PackIncoming> incoming;
}

/// A pack that has been checked: everything it says, ready for its plugin (pack_plugin.dart) and its pages.
class PluginPack {
  const PluginPack({required this.id, required this.version, required this.name, required this.tagline, required this.description, this.symbol = 'puzzle', required this.hue, required this.shelf, this.icon, required this.labels, this.permissions = const {}, this.links = const [], this.shots = const [], this.developer, this.support, this.whatsNew, this.minApp, this.settings = const [], this.rules = const PackRules(), this.json = const {}});
  final String id, version, name, tagline, description, symbol, hue, shelf;
  final Uint8List? icon;             // the decoded PNG; null for a pack loaded in developer mode without one
  final List<String> labels;
  final Set<PackPermission> permissions;
  final List<String> links;          // 0 or 1
  final List<String> shots;          // the screenshots' SHA-256s its page shows, in order
  final String? developer, support, whatsNew, minApp;
  final List<PackSetting> settings;
  final PackRules rules;
  final Map<String, Object?> json;   // the pack as parsed; anyone who changes it works on a deep copy (D.8)
  String get registryId => registryIdOf(id);
}

/// What checking a file gave: the pack where nothing was wrong, every issue found, and the pack's canonical bytes and
/// their SHA-256 wherever the file was JSON without fractions (so a reviewer sees the hash of what they check).
class PackParse {
  const PackParse({this.pack, this.issues = const [], this.canonical, this.sha256});
  final PluginPack? pack;            // null when there is any error
  final List<PackIssue> issues;      // errors, then warnings (lintPack, run only when there is no error)
  final Uint8List? canonical;        // the canonical bytes, wherever the file was JSON without fractions
  final String? sha256;              // of canonical
  bool get ok => pack != null;
  Iterable<PackIssue> get errors => issues.where((i) => i.isError);
  Iterable<PackIssue> get warnings => issues.where((i) => !i.isError);
}

/// Checks [bytes] as a ghost-plugin/1 pack (A.1 to A.14) for an app at [appVersion]. Never throws: it runs
/// jsonDepthOk first (too_deep), then decodes, and catches anything thrown on the way, StackOverflowError included
/// (an issue bad_json at "" with the error's words). [submission]: also require what the store requires (`icon`,
/// `developer` and `support`, `missing` otherwise; an example's id is `id_example`), as the submission form and the
/// reviewer's screen ask; loading in developer mode and the store's installer leave it false. [checkMinApp] false
/// leaves `minApp` unchecked, for the Marketplace to draw a listing that needs a newer app (D.11).
PackParse parsePack(List<int> bytes, {required String appVersion, bool submission = false, bool checkMinApp = true}) => throw UnimplementedError(_later);

/// [parsePack] for a pack already decoded: the submission form's, as it is typed.
PackParse parsePackJson(Object? json, {required String appVersion, bool submission = false, bool checkMinApp = true}) => throw UnimplementedError(_later);

const String _later = 'Checking a pack comes with the Marketplace\'s runtime (lib/plugins/pack/manifest.dart).';
