/// Stage 9's native pieces alone on a phone (docs/STAGES_5_6_8_9.md, 9A to 9C, and the three small channels), to be
/// proved there before the root wires them: `flutter build apk --debug --no-pub --target-platform android-arm64
/// -t lib/main_files.dart`. A column of buttons over a log:
///
/// - **Open web / mail / map / refused**: an address handed to the phone (`ghost_md/open`, OpenLink.kt): the
///   browser, the mail app, the maps app, and a `javascript:` address, which goes nowhere.
/// - **Links**: every `ghostmd://` link that opened the app is logged as it is taken and sorted
///   (`ghost_md/links`, AppLinks.kt): `adb shell am start -a android.intent.action.VIEW -d "ghostmd://note/abc"
///   com.mattssoftware.glyph.flutter`, cold and with the app up.
/// - **Recording?**, **Reset (keep models)**: the phone's half of starting over (`ghost.md/reset`,
///   ResetChannel.kt) with the core's `reset_local_data`; **Seed** writes a note and a secret first, and **Count**
///   says what is there.
///
/// Every line of the log is also printed as `[files] …`, for `adb logcat -s flutter`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'account/device_keys.dart';
import 'core/native/device_paths.dart';
import 'core/native/ghost_core.dart';
import 'core/open_link.dart';
import 'core/phone_links.dart';
import 'core/reset_native.dart';
import 'share/app_links.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // So each button has a name `uiautomator` can find.
  SemanticsBinding.instance.ensureSemantics();
  runApp(const _FilesApp());
}

class _FilesApp extends StatefulWidget {
  const _FilesApp();

  @override
  State<_FilesApp> createState() => _FilesState();
}

class _FilesState extends State<_FilesApp> {
  final List<String> _log = [];
  late GhostCore _core;
  late DevicePaths _paths;
  late PhoneReset _reset;
  final PhoneLinks _links = PhoneLinks();
  final SecureStore _secrets = deviceSecureStore();
  void Function()? _stopLinks;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _stopLinks?.call();
    _links.dispose();
    super.dispose();
  }

  void _say(String line) {
    debugPrint('[files] $line');
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> _guard(String what, Future<void> Function() work) async {
    try {
      await work();
    } catch (failure) {
      _say('$what FAILED: $failure');
    }
  }

  Future<void> _open() => _guard('open', () async {
        _core = await GhostCore.open();
        _paths = await DevicePaths.find();
        await _core.init(dataDir: _paths.dataDir, cacheDir: _paths.cacheDir);
        _reset = PhoneReset(invoke: _core.invoke);
        _say('core open on ${_paths.dataDir}');
        setState(() => _ready = true);
        // Once the notes can be read, as the root will: every link that opened the app, sorted.
        _stopLinks = followAppLinks((link) => _say('link $link -> ${_sorted(link)}'), _links);
      });

  String _sorted(String link) => switch (readAppLink(link)) {
        JoinAppLink(:final code) => 'join $code',
        NoteAppLink(:final noteId) => 'note $noteId',
        PlaceAppLink(:final place) => place is OrganizationPlace ? 'organization ${place.orgId}' : 'notifications',
        ShareAppLink(:final id) => 'share $id',
        null => 'none of the app\'s',
      };

  Future<void> _openAddress(String url) => _guard('open', () async {
        _say('open $url: may be handed over ${canOpenLink(url)}');
        await openLink(url);
        // The channel's own answer, which `openLink` drops as the page's callers do.
        if (canOpenLink(url)) _say('the phone took it: ${await openLinkChannel.invokeMethod<bool>('open', {'url': url})}');
      });

  Future<void> _seed() => _guard('seed', () async {
        final id = await _core.newId();
        await _core.invoke('create_note', {'id': id, 'body': '# Kept until the reset\n\nA line.\n', 'source': 'editor'});
        await File('${_paths.dataDir}/recordings/$id.wav').create(recursive: true);
        await _secrets.write('walk-secret', 'kept');
        await _count();
      });

  Future<void> _count() => _guard('count', () async {
        final notes = await _core.invoke('list_notes') as List<Object?>;
        final recordings = Directory('${_paths.dataDir}/recordings');
        _say('${notes.length} notes; recordings folder ${recordings.existsSync() ? 'holds ${recordings.listSync().length}' : 'is not there'}; secret ${await _secrets.read('walk-secret')}');
      });

  Future<void> _resetNow() => _guard('reset', () async {
        _reset.cancelWriteUps();
        await _reset.resetLocalData(models: false);
        _say('reset done');
        await _count();
      });

  @override
  Widget build(BuildContext context) {
    final buttons = <(String, VoidCallback)>[
      ('Open web', () => _openAddress('https://example.com/')),
      ('Open mail', () => _openAddress('mailto:someone@example.com')),
      ('Open map', () => _openAddress('geo:51.5,-0.12')),
      ('Open refused', () => _openAddress('javascript:alert(1)')),
      ('Seed', _seed),
      ('Count', _count),
      ('Recording?', () => _guard('recording', () async => _say('recording: ${await resetChannel.invokeMethod<bool>('recording')}'))),
      ('Reset (keep models)', _resetNow),
    ];
    const ink = Color(0xFFEDEDED), paper = Color(0xFF111111), line = Color(0xFF3A3A3A);
    const text = TextStyle(color: ink, fontSize: 13, height: 1.3, decoration: TextDecoration.none);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: paper,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ghost Flutter · files', style: text.copyWith(fontSize: 15), maxLines: 1),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, action) in buttons)
                      Semantics(
                        button: true,
                        label: label,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _ready ? action : null,
                          child: DecoratedBox(
                            decoration: BoxDecoration(border: Border.all(color: _ready ? ink : line), borderRadius: BorderRadius.circular(8)),
                            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text(label, style: text)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _log.length,
                    itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_log[index], style: text)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
