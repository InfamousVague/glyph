/// What an item's mark links to, read back: a task's status and a few facts about it, for the pill at the end of
/// the item and the card a tap on the pill opens. A port of `src/app/core/markDetails.ts`.
///
/// A mark (lib/core/item_links.dart) only says what an item is linked to and where; the plugin that owns the mark's
/// name knows how to read the thing behind it. So the editor asks here by the mark's name and address, and a plugin
/// answers through a provider it registers (registry.dart). Nothing here names a plugin, and a switched-off
/// plugin's provider answers nothing, which leaves its pills plain.
///
/// Reads are the provider's to pace and cache. `peek` is synchronous and cheap, called on every redraw; `want` asks
/// it to read again when what it has is old, and it says so through [markDetailsChanged] when an answer arrives.
///
/// What differs: it lives beside the plugins, not in lib/core (the core is somebody else's folder this stage);
/// `externalStore(0)` is a [ChangeNotifier] ([markDetailsListenable]); times are milliseconds since the epoch, as
/// the page's.
library;

import 'package:flutter/foundation.dart';

/// Where a task is in its life, however its board names the stages (`Stage`).
enum Stage { todo, doing, done }

/// A stage by the word the page uses for it ('todo' | 'doing' | 'done').
Stage? stageNamed(Object? name) => switch (name) { 'todo' => Stage.todo, 'doing' => Stage.doing, 'done' => Stage.done, _ => null };

/// The board's own word for the stage ("In progress"), and which stage that is.
@immutable
class MarkStatus {
  const MarkStatus(this.label, this.stage);
  final String label;
  final Stage stage;

  Map<String, Object?> toJson() => {'label': label, 'stage': stage.name};

  static MarkStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final stage = stageNamed(raw['stage']);
    final label = raw['label'];
    return stage == null || label is! String ? null : MarkStatus(label, stage);
  }

  @override
  bool operator ==(Object other) => other is MarkStatus && other.label == label && other.stage == stage;

  @override
  int get hashCode => Object.hash(label, stage);
}

/// One property with a value, for the card.
@immutable
class MarkField {
  const MarkField(this.label, this.value);
  final String label;
  final String value;

  Map<String, Object?> toJson() => {'label': label, 'value': value};

  @override
  bool operator ==(Object other) => other is MarkField && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);
}

/// What is known of a linked thing (`MarkDetails`).
@immutable
class MarkDetails {
  const MarkDetails({required this.url, required this.title, this.status, this.brief = const [], this.fields = const [], this.editedAt, required this.readAt, this.gone = false});

  final String url;
  final String title;

  /// Null on a board without a stage.
  final MarkStatus? status;

  /// At most two short facts for the pill, most telling first: "P1", "Due Sep 20".
  final List<String> brief;

  /// Every property with a value, in the board's order, for the card.
  final List<MarkField> fields;

  /// When the task last changed, in milliseconds, if the service says.
  final int? editedAt;

  /// When Ghost.md last read it.
  final int readAt;

  /// In the service's trash: shown, but not as a live task.
  final bool gone;

  MarkDetails copyWith({String? title, MarkStatus? status, bool clearStatus = false, List<String>? brief, List<MarkField>? fields, int? editedAt, int? readAt, bool? gone}) => MarkDetails(
        url: url,
        title: title ?? this.title,
        status: clearStatus ? null : status ?? this.status,
        brief: brief ?? this.brief,
        fields: fields ?? this.fields,
        editedAt: editedAt ?? this.editedAt,
        readAt: readAt ?? this.readAt,
        gone: gone ?? this.gone,
      );

  /// As the page keeps one (`gone` only when true).
  Map<String, Object?> toJson() => {
        'url': url,
        'title': title,
        'status': status?.toJson(),
        'brief': brief,
        'fields': [for (final field in fields) field.toJson()],
        'editedAt': editedAt,
        'readAt': readAt,
        if (gone) 'gone': true,
      };

  /// Null for anything that is not the shape [toJson] writes.
  static MarkDetails? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'], title = raw['title'], readAt = raw['readAt'], editedAt = raw['editedAt'];
    if (url is! String || title is! String || readAt is! num) return null;
    final brief = raw['brief'], fields = raw['fields'];
    return MarkDetails(
      url: url,
      title: title,
      status: MarkStatus.fromJson(raw['status']),
      brief: brief is List ? [for (final b in brief) if (b is String) b] : const [],
      fields: fields is List ? [for (final f in fields) if (f is Map && f['label'] is String && f['value'] is String) MarkField(f['label'] as String, f['value'] as String)] : const [],
      editedAt: editedAt is num ? editedAt.toInt() : null,
      readAt: readAt.toInt(),
      gone: raw['gone'] == true,
    );
  }
}

/// What a provider knows of an address now (`MarkEntry`).
sealed class MarkEntry {
  const MarkEntry();
}

/// A cached answer; [loading] while it is being read again.
class MarkReady extends MarkEntry {
  const MarkReady(this.details, {this.loading = false});
  final MarkDetails details;
  final bool loading;
}

/// A first read in flight.
class MarkLoading extends MarkEntry {
  const MarkLoading();
}

/// Why it cannot be read.
class MarkFailed extends MarkEntry {
  const MarkFailed(this.message);
  final String message;
}

/// How the menu draws an action: a ticked circle, a turn back, a pen.
enum MarkActionIcon { done, reopen, rename }

/// Something to do with a linked thing, offered on its menu (lib/editor/items/mark_menu.dart) (`MarkAction`).
class MarkAction {
  const MarkAction({required this.id, required this.label, required this.icon, required this.busyLabel, required this.run});
  final String id;
  final String label;
  final MarkActionIcon icon;

  /// The words while it runs: "Marking done…".
  final String busyLabel;

  /// Answers the sentence to show when it's done, if any.
  final Future<String?> Function() run;
}

/// A plugin's reading of what its marks link to (`MarkDetailsProvider`).
abstract class MarkDetailsProvider {
  const MarkDetailsProvider();

  /// What is known about [url] now. Null when there is nothing to show.
  MarkEntry? peek(String url);

  /// Reads [url] again if what is known is old, or now with [fresh].
  void want(String url, {bool fresh = false});

  /// Opens the thing itself, in the service's app or the browser.
  Future<void> open(String url);

  /// Whether an ordinary link to [url] is one of this provider's, so a link written the old way shows its details
  /// too, not only a mark.
  bool reads(String url) => false;

  /// What can be done with it from the menu, beyond Open, Refresh and Unlink; [words] are the item's own.
  List<MarkAction> actions(String url, String words) => const [];
}

final Map<String, MarkDetailsProvider? Function()> _providers = {};

class _Changes extends ChangeNotifier {
  void tell() => notifyListeners();
}

final _Changes _changes = _Changes();

/// `get` answers the provider for marks called [name], or null while it can't answer (its plugin off).
void provideMarkDetails(String name, MarkDetailsProvider? Function() get) => _providers[name.toLowerCase()] = get;

/// For the tests: no provider answers any more.
void forgetMarkProviders() => _providers.clear();

MarkDetailsProvider? _provider(String name) => _providers[name.toLowerCase()]?.call();

MarkEntry? peekMarkDetails(String name, String url) => _provider(name)?.peek(url);

void wantMarkDetails(String name, String url, {bool fresh = false}) => _provider(name)?.want(url, fresh: fresh);

Future<void> openMarked(String name, String url) => _provider(name)?.open(url) ?? Future<void>.value();

bool hasMarkDetails(String name) => _provider(name) != null;

/// The mark name of the provider that reads an ordinary link to [url], if one does.
String? markNameFor(String url) {
  for (final MapEntry(:key, :value) in _providers.entries) {
    if (value()?.reads(url) ?? false) return key;
  }
  return null;
}

List<MarkAction> markActions(String name, String url, String words) => _provider(name)?.actions(url, words) ?? const [];

/// A provider has something new: every pill and card reads again.
void markDetailsChanged() => _changes.tell();

/// Called after every [markDetailsChanged]; answers the way to stop (`onMarkDetails`).
VoidCallback onMarkDetails(VoidCallback listener) {
  _changes.addListener(listener);
  return () => _changes.removeListener(listener);
}

/// The same, for a widget that listens.
Listenable get markDetailsListenable => _changes;

/// "3 min ago", for when a task changed or was read.
String agoText(int ms, [int? now]) {
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  final seconds = ((at - ms) / 1000).round().clamp(0, 1 << 52);
  if (seconds < 45) return 'just now';
  final minutes = _round(seconds / 60);
  if (minutes < 60) return '$minutes min ago';
  final hours = _round(minutes / 60);
  if (hours < 24) return '$hours hr ago';
  final days = _round(hours / 24);
  return days == 1 ? 'yesterday' : '$days days ago';
}

/// `Math.round`: halves go up.
int _round(double n) => (n + 0.5).floor();
