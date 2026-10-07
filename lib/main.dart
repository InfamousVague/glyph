import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'app/ghost_app.dart';
import 'core/preferences.dart';
import 'core/stored.dart';
import 'core/stored_device.dart';
import 'root/ghost_root.dart';

/// The stylesheets the token engine reads after the kit's own, in the order the web app's page loads them
/// (tool/sync-design.sh copies them from ../glyph).
const appStyleSheets = ['assets/css/ink.css', 'assets/css/app.css', 'assets/css/typefaces.css'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge to edge, as the web app's page is under Android's bars: the page pads itself by the safe areas.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final sheet = await loadTokenSheet(more: appStyleSheets);
  // What this device chose and how it left things, before anything is drawn. Storage that will not answer is not
  // waited for: the app opens on its defaults and remembers nothing this run.
  try {
    await preferences.load().timeout(const Duration(seconds: 2));
    useStored(await DeviceStored.open().timeout(const Duration(seconds: 2)));
  } catch (_) {
    // Refused (core/stored.dart): a device that cannot remember, not an error.
  }
  runApp(GhostApp(sheet: sheet, home: const GhostRoot()));
}
