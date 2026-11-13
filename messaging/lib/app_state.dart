import 'package:flutter/widgets.dart';

import 'sms.dart';

/// What the app remembers of the person's choices (kept in Android's SharedPreferences through the channel).
class AppState extends ChangeNotifier {
  String theme = 'system';

  Future<void> load() async {
    try {
      final p = await Sms.instance.prefs();
      theme = p['theme'] ?? 'system';
    } catch (_) {}
  }

  void setTheme(String value) {
    theme = value;
    Sms.instance.setPref('theme', value);
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
