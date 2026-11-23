import 'package:flutter/widgets.dart';

import 'looks.dart';
import 'sms.dart';

/// What the app remembers of the person's choices: Android's SharedPreferences ("ui"), read once and written through
/// the channel. The native side reads the same file where a choice is its to act on (delivery and read reports as a
/// message is sent, previews and the code button as a notification is made).
class AppState extends ChangeNotifier {
  /// Every choice, a string under its key, as last read or set.
  final Map<String, String> _prefs = {};

  /// Reads the choices, once, before anything is drawn. Where they cannot be read every choice is its default.
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
      pluginsStamp++;
      choicesChanged?.call(this);
      notifyListeners();
    } catch (_) {}
  }

  /// What was chosen under [key], or [fallback] where nothing was.
  String choice(String key, String fallback) => _prefs[key] ?? fallback;

  /// The choices whose keys start with [prefix] (Ghost's own lists of a network's chats: lib/kept_lists.dart).
  Map<String, String> withPrefix(String prefix) => {for (final e in _prefs.entries) if (e.key.startsWith(prefix)) e.key: e.value};

  /// A switch: on unless it was switched off ([fallback] false: off unless switched on).
  bool flag(String key, {bool fallback = true}) => _prefs[key] == null ? fallback : _prefs[key] == 'on';

  /// A choice changed: kept, and everything drawn from the choices drawn again. One set to what it already is changes
  /// nothing and draws nothing (docs/performance-audit.md: every write used to rebuild the whole app).
  void set(String key, String value) {
    if (_prefs[key] == value) return;
    _prefs[key] = value;
    if (key.startsWith('plugin')) pluginsStamp++;
    Sms.instance.setPref(key, value);
    if (key.startsWith('plugin') || key.startsWith('filter_')) choicesChanged?.call(this);
    notifyListeners();
  }

  /// Told when a plugin's choice, a filter choice or a filing changes, or the choices are read again: the rules that
  /// hush a hidden kind's notifications are written again from them (lib/plugins/notify_hush.dart, GMFB-18).
  static void Function(AppState app)? choicesChanged;

  /// Something kept here that no screen draws from these choices: a store's own bookkeeping (when a space was last
  /// seen, a space's messages), whose owner tells its own listeners. Kept as [set] keeps, and nothing is drawn again
  /// for it: a write a second while the app is open must not rebuild the app.
  void keep(String key, String value) {
    if (_prefs[key] == value) return;
    _prefs[key] = value;
    Sms.instance.setPref(key, value);
  }

  void setFlag(String key, bool on) => set(key, on ? 'on' : 'off');

  /// Plugins (lib/plugins/registry.dart) keep their switches and their own choices here, under `plugin…`. This goes
  /// up whenever one of those changes, so that what was worked out from them is worked out again.
  int pluginsStamp = 0;

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

  /// The look of the whole app (lib/looks.dart): Ghost, the app's own, where none was chosen.
  Look get look => Look.of(this);

  /// Choosing a look makes your bubbles the look's own ('theme'); going back to Ghost puts back the colour they had
  /// under Ghost (white where none was chosen), unless a colour was chosen since. Leaving Ghost keeps that colour
  /// (`bubble_before_look`), where it was thrown away and Pink came back as white, and Ghost Keyboard's enter key with
  /// it. The look already chosen changes nothing, so a tap on its card keeps a colour picked under it. Ghost Keyboard
  /// is told the nearest of its colours first (`theme_bubble`, AccentSync.kt), so the 'theme' that follows already has
  /// a colour it knows.
  void setLook(Look l) {
    if (l == look) return;
    if (look == Look.ghost && bubble != 'theme') set('bubble_before_look', bubble);
    set('theme_bubble', l.keyboard);
    set(Look.pref, l.name);
    if (l != Look.ghost) {
      if (bubble != 'theme') setBubble('theme');
    } else if (bubble == 'theme') {
      setBubble(choice('bubble_before_look', 'white'));
    }
  }

  /// The size of a message's words: small, default, large, larger.
  String get textSize => choice('text_size', 'default');
  /// What a message's words are multiplied by for that size.
  double get textScale => switch (textSize) { 'small' => 0.9, 'large' => 1.15, 'larger' => 1.3, _ => 1.0 };

  /// The face everything is drawn in: 'default', each look's own, or 'readable', Atkinson Hyperlegible Next, for
  /// anyone who finds letters hard to tell apart (GMFB-41; lib/looks.dart stamps it).
  String get font => choice('font', 'default');
  void setFont(String v) => set('font', v);

  /// Whether messages set off their effects (lib/effects.dart).
  bool get effects => flag('effects');
  void setEffects(bool v) => setFlag('effects', v);

  /// One to three emoji alone are drawn large.
  bool get bigEmoji => flag('big_emoji');

  /// Reaction texts are hung on their messages (lib/reactions.dart); off shows every text as it came.
  bool get foldReactions => flag('fold_reactions');

  /// The keyboard's Enter sends, where it otherwise starts a new line.
  /// Settings › Messages › Enter sends: on a computer unless turned off, as every desktop messenger has it; on a phone
  /// off unless turned on.
  bool get enterSends => flag('enter_sends', fallback: Sms.computer);

  /// Picture and group messages ask the other phone to say when they are read.
  bool get readReports => flag('read_reports');
  void setReadReports(bool v) => setFlag('read_reports', v);

  /// The app's choices from anywhere under [AppScope]; whatever asks is built again when one changes.
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_AppScope>()!.state;
  static AppState? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_AppScope>()?.state;
}

/// Puts [state] over the app, for [AppState.of], and rebuilds what reads it each time the state says it changed.
class AppScope extends StatelessWidget {
  const AppScope({super.key, required this.state, required this.child});
  final AppState state;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: state, builder: (context, _) => _AppScope(state: state, version: Object(), child: child));
}

/// The inherited half of [AppScope].
class _AppScope extends InheritedWidget {
  const _AppScope({required this.state, required this.version, required super.child});
  final AppState state;

  /// A new object each time the state changed: the state itself is the same one, so it cannot show the change.
  final Object version;

  @override
  bool updateShouldNotify(_AppScope old) => old.version != version;
}
