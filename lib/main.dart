import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'app/ghost_app.dart';

/// The stylesheets the token engine reads after the kit's own, in the order the web app's page loads them
/// (tool/sync-design.sh copies them from ../glyph).
const appStyleSheets = ['assets/css/ink.css', 'assets/css/app.css', 'assets/css/typefaces.css'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge to edge, as the web app's page is under Android's bars: the page pads itself by the safe areas.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final sheet = await loadTokenSheet(more: appStyleSheets);
  runApp(GhostApp(sheet: sheet));
}
