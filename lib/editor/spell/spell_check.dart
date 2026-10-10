/// The phone's spell checker, asked about a stretch of words: the seam the note's underlines are drawn from
/// (spell.dart), and the phone's own behind it.
///
/// On the page the WebView did all of this by itself: the editor's content says `spellcheck="true"` while the
/// keyboard's aids are on (Editor.tsx `PROSE_ATTRS`, Settings' `assist`) and `"false"` while they are off
/// (`PLAIN_ATTRS`), and Chromium asks Android's spell checker about the words being edited and draws a red wave
/// under each one it would have otherwise. This app's editor has its own text client (input/ime.dart), which
/// Android's checker never sees, so the asking is done here.
///
/// [PhoneSpellChecker] asks through the engine's own bridge (`flutter/spellcheck`; on Android the engine's
/// `SpellCheckPlugin`, a `TextServicesManager` session asked for sentence suggestions with
/// `SpellCheckerSession.getSentenceSuggestions`, in the language the phone's spell checker is set to; on an
/// iPhone, `UITextChecker`). The same bridge Flutter's own text fields use, so nothing is added on the phone's
/// side. It takes one question at a time and refuses a second while the first is out: a refusal is null here, and
/// whoever asked asks again later.
library;

import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A word the checker would have otherwise: where it is in the text that was asked about, and what is offered in
/// its place, best first (five at most from Android).
@immutable
class Misspelling {
  const Misspelling(this.from, this.to, [this.suggestions = const <String>[]]);

  final int from;
  final int to;
  final List<String> suggestions;

  @override
  bool operator ==(Object other) => other is Misspelling && other.from == from && other.to == to && listEquals(other.suggestions, suggestions);

  @override
  int get hashCode => Object.hash(from, to, Object.hashAll(suggestions));

  @override
  String toString() => 'Misspelling($from-$to, $suggestions)';
}

/// Something that can say which words of a text are misspelled.
abstract interface class SpellChecker {
  /// The misspellings in [text], in the order they stand. Null where nothing could be asked: no checker on this
  /// device, the phone's turned off, or one question already out.
  Future<List<Misspelling>?> check(String text, {required Locale locale});
}

/// The phone's own spell checker, through the engine's bridge. Nothing on a desktop, where the engine has none.
class PhoneSpellChecker implements SpellChecker {
  const PhoneSpellChecker({MethodChannel? channel, bool? supported}) : _channel = channel, _supported = supported;

  final MethodChannel? _channel;
  final bool? _supported;

  /// Whether this platform's engine answers `flutter/spellcheck`.
  bool get supported => _supported ?? (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<List<Misspelling>?> check(String text, {required Locale locale}) async {
    if (!supported || text.trim().isEmpty) return supported ? const <Misspelling>[] : null;
    final Object? raw;
    try {
      raw = await (_channel ?? SystemChannels.spellCheck).invokeMethod<Object?>('SpellCheck.initiateSpellCheck', <String>[locale.toLanguageTag(), text]);
    } on PlatformException {
      // One question already out, or the phone has no spell checker to make a session with.
      return null;
    } on MissingPluginException {
      return null;
    }
    if (raw is! List) return null;
    final found = <Misspelling>[];
    for (final each in raw) {
      if (each is! Map) continue;
      final from = each['startIndex'], to = each['endIndex'], offered = each['suggestions'];
      if (from is! int || to is! int || from < 0 || to > text.length || from >= to) continue;
      found.add(Misspelling(from, to, offered is List ? List<String>.unmodifiable(offered.whereType<String>()) : const <String>[]));
    }
    found.sort((a, b) => a.from.compareTo(b.from));
    return found;
  }
}
