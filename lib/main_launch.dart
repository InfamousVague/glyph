import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'app/ghost_app.dart';
import 'app/widgets.dart';
import 'launch/launch_screen.dart';
import 'main.dart' show appStyleSheets;

/// The launch screen alone on a phone, to be judged there: `flutter run -t lib/main_launch.dart`. It opens as the app
/// will (the notes read, a check that answers, a sync that finishes), hands over to a page with one button, and the
/// button plays it again.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final sheet = await loadTokenSheet(more: appStyleSheets);
  runApp(GhostApp(sheet: sheet, home: const _Opening()));
}

class _Opening extends StatefulWidget {
  const _Opening();

  @override
  State<_Opening> createState() => _OpeningState();
}

class _OpeningState extends State<_Opening> {
  int _run = 0;
  bool _up = true;
  bool _loading = true;
  bool _checking = false;
  SyncPhase _sync = SyncPhase.syncing;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _play();
  }

  void _play() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    setState(() {
      _run += 1;
      _up = true;
      _loading = true;
      _checking = false;
      _sync = SyncPhase.syncing;
    });
    void at(int ms, VoidCallback then) => _timers.add(Timer(Duration(milliseconds: ms), () => setState(then)));
    at(700, () => _loading = false);
    at(1900, () => _checking = false);
    at(2300, () => _sync = SyncPhase.idle);
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('The app would be here.', style: t.text('md', color: t.color('glacier-text-muted'))),
              SizedBox(height: t.space(4)),
              AppPill(onPressed: _play, child: const Text('Open again')),
            ],
          ),
        ),
        if (_up)
          LaunchScreen(
            key: ValueKey(_run),
            loading: _loading,
            notes: 128,
            sync: _sync,
            updates: LaunchUpdates(checking: _checking, check: () => scheduleMicrotask(() => mounted ? setState(() => _checking = true) : null), reload: () {}),
            onDone: () => setState(() => _up = false),
          ),
      ],
    );
  }
}
