/// Follow Claude (docs/CLAUDE_LIVE.md, "What a person sees", 3): while an AI is followed, the app opens the note it
/// is in, keeps its caret in view as it types, and moves to the next note with it, until Stop or until the person
/// scrolls, taps or types in the note. And the notice "Claude is editing Roadmap" with Watch, when an AI starts on a
/// note while nobody is followed.
///
/// Who is online and where is the presence rooms' (lib/live/presence.dart [Presence.aisOnline], the organizations'
/// and the account's own); the editors bound on this device are [BoundEditors] (lib/live/editor_binding.dart), whose
/// carets are the AI's as the room places them and whose `touched` is the person's own doing. How a note is opened
/// is the app's (the shell's, handed in by lib/root as [FollowAi.open]), as a member's Jump to cursor opens one.
///
/// The web app has no Follow yet: this is the app's own.
library;

import 'package:flutter/foundation.dart';

import '../editor/editor.dart';
import 'editor_binding.dart';
import 'presence.dart';

/// The AIs online, and Follow.
class FollowAi extends ChangeNotifier {
  /// [online] answers the AIs online now (`presence.aisOnline`) and [changes] says when that may be different;
  /// [bound] is where the open editors are.
  FollowAi({required this.online, required this.changes, required this.bound});

  final List<AiOnline> Function() online;
  final Listenable changes;
  final BoundEditors bound;

  /// Opens [noteId] on screen for the AI followed, as Jump to cursor opens a note: answers whether it could (a note
  /// this device does not hold yet cannot be, and is tried again when the AI is next heard).
  bool Function(AiOnline ai, String noteId)? open;

  /// An AI began editing a note while nobody is followed: the notice with Watch (lib/root).
  void Function(AiOnline ai)? onEditing;

  /// The note on screen now: an AI starting on it needs no notice, the person is watching already.
  String? Function()? shown;

  bool _started = false;
  List<AiOnline> _online = const [];

  /// The key of the AI followed ([AiOnline.key]), or null.
  String? _following;

  /// The note last opened for it, and the editor whose carets are watched.
  String? _opened;
  LiveBinding? _watching;

  /// Which note each AI was last heard editing, so a notice is given when it starts on one and not on every word.
  final Map<String, String?> _editing = {};

  /// Starts hearing the rooms. Once.
  void start() {
    if (_started) return;
    _started = true;
    changes.addListener(_heard);
    bound.addListener(_attach);
    _heard();
  }

  /// The AIs online now, in the order of their names.
  List<AiOnline> get ais => _online;

  /// The AI followed, while it is online.
  AiOnline? get following {
    final key = _following;
    if (key == null) return null;
    for (final ai in _online) {
      if (ai.key == key) return ai;
    }
    return null;
  }

  bool get isFollowing => _following != null;

  /// The AI named by its key ([AiOnline.key]) among those online, or null.
  AiOnline? find(String key) {
    for (final ai in _online) {
      if (ai.key == key) return ai;
    }
    return null;
  }

  /// Follows [ai]: the note it is on opened now, and each it goes to after.
  void follow(AiOnline ai) {
    _following = ai.key;
    _opened = null;
    _unwatch();
    notifyListeners();
    _go();
  }

  /// Stops following (the bar's Stop, or the person's own doing in the note).
  void stop() {
    if (_following == null) return;
    _following = null;
    _opened = null;
    _unwatch();
    notifyListeners();
  }

  void _heard() {
    final now = online();
    final moved = !listEquals(now, _online);
    _online = now;
    _notice(now);
    if (_following != null && following == null) {
      // The AI went: there is nothing to follow.
      stop();
      return;
    }
    if (moved) notifyListeners();
    _go();
  }

  /// The notices: an AI heard editing a note it was not editing before, while nobody is followed and the note is
  /// not the one on screen.
  void _notice(List<AiOnline> now) {
    final keys = <String>{};
    for (final ai in now) {
      keys.add(ai.key);
      final note = ai.doing == 'editing' ? ai.at?.note : null;
      final was = _editing[ai.key];
      _editing[ai.key] = note;
      if (note == null || note == was || _following != null) continue;
      if (shown?.call() == note) continue;
      onEditing?.call(ai);
    }
    _editing.removeWhere((key, _) => !keys.contains(key));
  }

  /// The note the AI followed is on, opened when it is another than the one opened for it; and its caret watched.
  void _go() {
    final ai = following;
    if (ai == null) return;
    final note = ai.at?.note;
    if (note != null && note != _opened && (open?.call(ai, note) ?? false)) {
      _opened = note;
      _unwatch();
    }
    _attach();
    _scroll();
  }

  /// The editor of the note opened for the AI, watched once it is bound: its carets as they are placed, and the
  /// person's own doing in it.
  void _attach() {
    final note = _opened;
    final binding = note == null || _following == null ? null : bound.of(note);
    if (identical(binding, _watching)) return;
    _unwatch();
    if (binding == null) return;
    _watching = binding;
    binding.carets.addListener(_scroll);
    binding.touched.addListener(stop);
    _scroll();
  }

  void _unwatch() {
    final was = _watching;
    _watching = null;
    if (was == null) return;
    was.carets.removeListener(_scroll);
    was.touched.removeListener(stop);
  }

  /// The AI's caret, where the editor has it, scrolled to the middle of the page. Said as from elsewhere, so it is
  /// not taken for the person's own doing.
  void _scroll() {
    final ai = following, binding = _watching;
    if (ai == null || binding == null || !binding.bound) return;
    RemoteCaret? caret;
    for (final each in binding.carets.value) {
      if (each.ai && each.name.toLowerCase() == ai.name.toLowerCase()) caret = each;
    }
    if (caret == null) return;
    final limit = binding.view.state.doc.length;
    final head = caret.head.clamp(0, limit);
    try {
      binding.view.dispatch(TransactionSpec(effects: EditorViewLike.scrollIntoView(head, y: ScrollStrategy.center), annotations: <Annotation<Object?>>[Transaction.remote.of(true), Transaction.addToHistory.of(false)]));
    } catch (_) {
      // The editor went first.
    }
  }

  @override
  void dispose() {
    if (_started) {
      changes.removeListener(_heard);
      bound.removeListener(_attach);
    }
    _unwatch();
    super.dispose();
  }
}
