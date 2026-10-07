import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/ghost_app.dart';
import '../main.dart' show appStyleSheets;
import 'art_gallery.dart';

/// The art layer alone on a phone, to be judged there: `flutter run -t lib/art/main.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final sheet = await loadTokenSheet(more: appStyleSheets);
  runApp(GhostApp(sheet: sheet, home: const ArtGallery()));
}
