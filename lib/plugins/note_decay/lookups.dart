/// What GitHub and Figma say of the links a page holds (docs/NOTE_DECAY.md §1.1, the `github` and `figma` signals;
/// Matt, 2026-11-02: "a merged PR on GitHub" among what makes a page "may be out of date"). The one part of the
/// plugin that reaches outside the phone: only with the GitHub or Figma plugin connected, with their own tokens, never
/// with Local only on, and each answer kept an hour in memory so a page opened twice asks once.
///
/// [DecayLookups] is the seam: the app's is [AppDecayLookups], over the two plugins' clients; a test's answers what it
/// is given and reaches nothing.
library;

import 'package:flutter/foundation.dart';

/// A GitHub issue or pull request a page links.
@immutable
class GithubRef {
  const GithubRef({required this.owner, required this.repo, required this.pull, required this.number, this.line, this.quote = ''});
  final String owner;
  final String repo;
  final bool pull;
  final int number;

  /// The page's line it is on, and that line's words.
  final int? line;
  final String quote;

  /// `owner/repo#12`.
  String get key => '$owner/$repo#$number';
}

enum GithubStateKind { open, closed, merged }

/// What GitHub says of one: open, closed or merged, and when it closed or merged.
@immutable
class GithubState {
  const GithubState(this.state, {this.at, this.title});
  final GithubStateKind state;
  final DateTime? at;
  final String? title;
}

/// The lookups the signals ask (see the header).
abstract interface class DecayLookups {
  /// Whether GitHub may be asked now: the GitHub plugin on with a token, the plugin's lookups on, Local only off.
  bool get githubOn;

  /// Whether Figma may be asked now, as [githubOn].
  bool get figmaOn;

  /// What GitHub says of [ref]; null where it would not say.
  Future<GithubState?> github(GithubRef ref);

  /// Whether Figma says the frame or file at [url] is not there: true for a 404, false where it is, null where it
  /// would not say (no token, no connection).
  Future<bool?> figmaGone(String url);
}

/// No lookups at all: Local only, the lookups switched off, or a test that asks none.
class NoDecayLookups implements DecayLookups {
  const NoDecayLookups();
  @override
  bool get githubOn => false;
  @override
  bool get figmaOn => false;
  @override
  Future<GithubState?> github(GithubRef ref) async => null;
  @override
  Future<bool?> figmaGone(String url) async => null;
}

/// Answers kept an hour, by what was asked, so the same page opened again asks nothing.
class _Kept<T> {
  _Kept(this.value, this.at);
  final T value;
  final DateTime at;
}

/// The app's lookups: [githubOn] and [figmaOn] asked as each check is made, [askGithub] and [askFigma] the two
/// plugins' clients (wired by note_decay.dart), and an hour's memory over them.
class AppDecayLookups implements DecayLookups {
  AppDecayLookups({required bool Function() githubOn, required bool Function() figmaOn, required Future<GithubState?> Function(GithubRef ref) askGithub, required Future<bool?> Function(String url) askFigma, DateTime Function()? clock})
      : _githubOn = githubOn,
        _figmaOn = figmaOn,
        _askGithub = askGithub,
        _askFigma = askFigma,
        _clock = clock ?? DateTime.now;

  final bool Function() _githubOn;
  final bool Function() _figmaOn;
  final Future<GithubState?> Function(GithubRef ref) _askGithub;
  final Future<bool?> Function(String url) _askFigma;
  final DateTime Function() _clock;
  final Map<String, _Kept<GithubState?>> _github = {};
  final Map<String, _Kept<bool?>> _figma = {};

  static const Duration kept = Duration(hours: 1);

  @override
  bool get githubOn => _githubOn();

  @override
  bool get figmaOn => _figmaOn();

  bool _fresh(DateTime at) => _clock().difference(at) < kept;

  @override
  Future<GithubState?> github(GithubRef ref) async {
    if (!githubOn) return null;
    final had = _github[ref.key];
    if (had != null && _fresh(had.at)) return had.value;
    final state = await _askGithub(ref).catchError((Object _) => null);
    _github[ref.key] = _Kept(state, _clock());
    return state;
  }

  @override
  Future<bool?> figmaGone(String url) async {
    if (!figmaOn) return null;
    final had = _figma[url];
    if (had != null && _fresh(had.at)) return had.value;
    final gone = await _askFigma(url).catchError((Object _) => null);
    _figma[url] = _Kept(gone, _clock());
    return gone;
  }

  /// Forgets every answer: Check now.
  void forget() {
    _github.clear();
    _figma.clear();
  }
}
