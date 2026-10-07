import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'app/ghost_app.dart';
import 'gallery/kit_gallery.dart';
import 'main.dart' show appStyleSheets;

/// The kit's gallery alone on a phone (stage 1's screen): `flutter run -t lib/main_kit.dart`. The art's is
/// lib/art/main.dart, the launch screen's lib/main_launch.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final sheet = await loadTokenSheet(more: appStyleSheets);
  runApp(GhostApp(sheet: sheet, home: const KitGallery()));
}
