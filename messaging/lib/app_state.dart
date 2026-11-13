import 'package:flutter/widgets.dart';

import 'sms.dart';

/// What the app remembers of the person's choices (kept in Android's SharedPreferences through the channel).
class AppState extends ChangeNotifier {
  String theme = 'system';

  /// The emoji set (lib/emoji_sets.dart): 'system' is the phone's own.
  String emoji = 'system';

  /// Whether messages set off their effects (lib/effects.dart).
  bool effects = true;

  /// Whether picture and group messages ask the other phone to say when they are read (android/.../Messaging.kt
  /// reads the same preference as it sends).
  bool readReports = true;

  Future<void> load() async {
    try {
      final p = await Sms.instance.prefs();
      theme = p['theme'] ?? 'system';
      emoji = p['emoji'] ?? 'system';
      effects = p['effects'] != 'off';
      readReports = p['read_reports'] != 'off';
    } catch (_) {}
  }

  void setTheme(String value) {
    theme = value;
    Sms.instance.setPref('theme', value);
    notifyListeners();
  }

  void setEmoji(String value) {
    emoji = value;
    Sms.instance.setPref('emoji', value);
    notifyListeners();
  }

  void setEffects(bool value) {
    effects = value;
    Sms.instance.setPref('effects', value ? 'on' : 'off');
    notifyListeners();
  }

  void setReadReports(bool value) {
    readReports = value;
    Sms.instance.setPref('read_reports', value ? 'on' : 'off');
    notifyListeners();
  }

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
