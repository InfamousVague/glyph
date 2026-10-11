/// What a plugin has read back about the things a note links to (a Notion task, a GitHub issue), kept, paced and
/// refreshed the one way both do it, for their [MarkDetailsProvider]s. A port of `src/app/plugins/detailsCache.ts`.
///
/// - **Reads are paced**: `atOnce` at a time, the rest queued, so a long list scrolled past doesn't fire a read per
///   line at a service that allows a few a second.
/// - **An answer is fresh for `fresh`**, so the same line drawn again doesn't read it again; `want(…, fresh: true)`
///   is a Refresh by hand, and reads whatever is kept.
/// - **A read that failed is tried again once it is as old as a stale answer**, not only by hand. A failure over an
///   answer already had keeps the answer.
/// - **The last `keep` answers are kept** in the plugin's own storage, newest first, so a note opened offline shows
///   what its links last said, with when they were read. What is kept is checked as it is read back: an entry from
///   another build's shape is left out, not trusted.
///
/// Every change tells the pills and cards showing a link to look again ([markDetailsChanged]).
///
/// What differs: the clock is [DetailsCache.now], so a test moves time without faking the system's; a failure's
/// words are [failureWords]'s.
library;

import 'dart:async';
import 'dart:collection';

import 'types.dart';

/// What a failure says on a card or a note (`core/failure.ts` `failureText`): its message when it carries one, its
/// own words otherwise, without Dart's "Exception: " in front.
String failureWords(Object? failure) {
  if (failure == null) return 'Something went wrong.';
  if (failure is String) return failure;
  try {
    final message = (failure as dynamic).message;
    if (message is String && message.isNotEmpty) return message;
  } catch (_) {
    // No message of its own: its words as it prints.
  }
  return failure.toString().replaceFirst(RegExp(r'^(Exception|Error): '), '');
}

class _Known {
  _Known({this.details, this.failed, this.failedAt, required this.loading});
  final MarkDetails? details;
  final String? failed;

  /// When the last read failed: a link never read is tried again once this is as old as a stale answer.
  final int? failedAt;
  final bool loading;
}

/// See the header (`DetailsCache`, made by `detailsCache(options)`).
class DetailsCache {
  DetailsCache({
    required this.host,
    required this.storageKey,
    required Future<MarkDetails> Function(String key, String url) read,
    bool Function()? ready,
    Duration fresh = const Duration(seconds: 45),
    int keep = 300,
    this.atOnce = 2,
    int Function()? now,
  })  : _read = read,
        _ready = ready ?? _always,
        _freshMs = fresh.inMilliseconds,
        _most = keep,
        now = now ?? _clock;

  final PluginHost host;

  /// The plugin's storage key the answers are kept under (it must be in the plugin's manifest).
  final String storageKey;
  final Future<MarkDetails> Function(String key, String url) _read;
  final bool Function() _ready;
  final int _freshMs;
  final int _most;

  /// How many reads run at once.
  final int atOnce;

  /// The time, in milliseconds.
  final int Function() now;

  static bool _always() => true;
  static int _clock() => DateTime.now().millisecondsSinceEpoch;

  // In the order they were first known, as a JS Map keeps them: what is kept is sorted from this order.
  final LinkedHashMap<String, _Known> _known = LinkedHashMap();
  final Queue<({String key, String url})> _queue = Queue();
  int _running = 0;
  bool _restored = false;

  /// What was kept, read back the first time anything is asked: a page that never shows a link never reads it.
  void _restore() {
    if (_restored) return;
    _restored = true;
    final Object? saved = host.storage.get<Object?>(storageKey, const <String, Object?>{});
    if (saved is! Map) return;
    for (final MapEntry(:key, :value) in saved.entries) {
      if (key is! String || value is! Map || value['fields'] is! List) continue;
      final details = MarkDetails.fromJson(value);
      if (details != null) _known[key] = _Known(details: details, loading: false);
    }
  }

  void _persist() {
    final kept = [
      for (final MapEntry(:key, :value) in _known.entries)
        if (value.details != null) (key: key, details: value.details!),
    ];
    // Stable, as the page's sort is: answers read in the same millisecond keep the order they were known in.
    final order = {for (var i = 0; i < kept.length; i++) kept[i].key: i};
    kept.sort((a, b) {
      final by = b.details.readAt.compareTo(a.details.readAt);
      return by != 0 ? by : order[a.key]!.compareTo(order[b.key]!);
    });
    host.storage.set(storageKey, {for (final entry in kept.take(_most)) entry.key: entry.details.toJson()});
  }

  Future<void> _load(String key, String url) async {
    final entry = _known[key];
    try {
      final details = await _read(key, url);
      _known[key] = _Known(details: details, loading: false);
      _persist();
    } catch (failure) {
      _known[key] = _Known(details: entry?.details, failed: entry?.details != null ? null : failureWords(failure), failedAt: now(), loading: false);
    }
    markDetailsChanged();
  }

  void _pump() {
    while (_running < atOnce && _queue.isNotEmpty) {
      final next = _queue.removeFirst();
      _running += 1;
      unawaited(_load(next.key, next.url).whenComplete(() {
        _running -= 1;
        _pump();
      }));
    }
  }

  /// What is known about [key] now, for a pill: the answer, a failure, a read under way, or nothing yet.
  MarkEntry? peek(String key) {
    _restore();
    final entry = _known[key];
    if (entry?.details case final details?) return MarkReady(details, loading: entry!.loading);
    if (entry?.failed case final failed? when failed.isNotEmpty) return MarkFailed(failed);
    return entry?.loading ?? false ? const MarkLoading() : null;
  }

  /// Asks for [key] to be read, unless it is being read or its answer (or its failure) is fresh; [fresh] reads anyway.
  void want(String key, String url, {bool fresh = false}) {
    if (!_ready()) return;
    _restore();
    final entry = _known[key];
    if (entry?.loading ?? false) return;
    final at = now();
    if (!fresh && entry?.details != null && at - entry!.details!.readAt < _freshMs) return;
    if (!fresh && (entry?.failed?.isNotEmpty ?? false) && at - (entry!.failedAt ?? 0) < _freshMs) return;
    _known[key] = _Known(details: entry?.details, loading: true);
    _queue.add((key: key, url: url));
    _pump();
  }

  /// Reads [key] now, outside the queue: after a write, to show what the write did.
  Future<void> reread(String key, String url) => _load(key, url);

  /// Keeps an answer that was not read (what a create or a write just answered), and tells everything showing it.
  void keep(String key, MarkDetails details) {
    _restore();
    _known[key] = _Known(details: details, loading: false);
    _persist();
    markDetailsChanged();
  }

  /// The answer kept for [key], if there is one. As the page: only what this run has restored or read.
  MarkDetails? details(String key) => _known[key]?.details;

  /// Forgets every answer, kept or not: for signing out, when another account's links are not this one's.
  void forget() {
    _known.clear();
    host.storage.remove(storageKey);
    markDetailsChanged();
  }
}
