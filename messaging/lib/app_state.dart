import 'package:flutter/widgets.dart';

import 'sms.dart';

/// What the app remembers of the person's choices: Android's SharedPreferences ("ui"), read once and written through
/// the channel. The native side reads the same file where a choice is its to act on (delivery and read reports as a
/// message is sent, previews and the code button as a notification is made).
class AppState extends ChangeNotifier {
  final Map<String, String> _prefs = {};

  Future<void> load() async {
    try {
      _prefs.addAll(await Sms.instance.prefs());
    } catch (_) {}
  }

  /// Read again from Android, which changed some itself: a chat background that someone shared.
  Future<void> reload() async {
    try {
      final next = await Sms.instance.prefs();
      _prefs
        ..clear()
        ..addAll(next);
      notifyListeners();
    } catch (_) {}
  }

  String choice(String key, String fallback) => _prefs[key] ?? fallback;

  /// A switch: on unless it was switched off ([fallback] false: off unless switched on).
  bool flag(String key, {bool fallback = true}) => _prefs[key] == null ? fallback : _prefs[key] == 'on';

  void set(String key, String value) {
    _prefs[key] = value;
    Sms.instance.setPref(key, value);
    notifyListeners();
  }

  void setFlag(String key, bool on) => set(key, on ? 'on' : 'off');

  /// Something the screens draw from has changed that is not one of these choices: the phone's wallpaper palette.
  void changed() => notifyListeners();

  /// system, light, dark.
  String get theme => choice('theme', 'system');
  void setTheme(String v) => set('theme', v);

  /// The emoji set (lib/emoji_sets.dart): 'system' is the phone's own.
  String get emoji => choice('emoji', 'system');
  void setEmoji(String v) => set('emoji', v);

  /// Your own bubbles: white where nothing has been chosen (Matt, 2026-11-14: "change the default chat bubble to
  /// be white"; it was 'ghost', Ghost Keyboard's primary), 'ink' the page's ink on paper, 'wallpaper' the accent
  /// Android takes from the phone's wallpaper (lib/backgrounds.dart).
  String get bubble => choice('bubble', 'white');
  void setBubble(String v) => set('bubble', v);

  /// The size of a message's words: small, default, large, larger.
  String get textSize => choice('text_size', 'default');
  double get textScale => switch (textSize) { 'small' => 0.9, 'large' => 1.15, 'larger' => 1.3, _ => 1.0 };

  /// Whether messages set off their effects (lib/effects.dart).
  bool get effects => flag('effects');
  void setEffects(bool v) => setFlag('effects', v);

  /// One to three emoji alone are drawn large.
  bool get bigEmoji => flag('big_emoji');

  /// Reaction texts are hung on their messages (lib/reactions.dart); off shows every text as it came.
  bool get foldReactions => flag('fold_reactions');

  /// The keyboard's Enter sends, where it otherwise starts a new line.
  bool get enterSends => flag('enter_sends', fallback: false);

  /// Picture and group messages ask the other phone to say when they are read.
  bool get readReports => flag('read_reports');
  void setReadReports(bool v) => setFlag('read_reports', v);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_AppScope>()!.state;
}

class AppScope extends StatelessWidget {
  const AppScope({super.key, required this.state, required this.child});
  final AppState state;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: state, builder: (context, _) => _AppScope(state: state, version: Object(), child: child));
}

class _AppScope extends InheritedWidget {
  const _AppScope({required this.state, required this.version, required super.child});
  final AppState state;
  final Object version;

  @override
  bool updateShouldNotify(_AppScope old) => old.version != version;
}
