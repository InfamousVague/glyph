import 'package:flutter/widgets.dart';

import '../desktop/main.dart' show desktopMain;

/// Ghost Messaging in a browser (Matt: "the full web client"): what `flutter build web -t lib/web/main.dart --release`
/// builds, with the page in web/.
///
/// For now it says that it is being built ([BeingBuilt]) and starts nothing. The app itself is in the build all the
/// same: a browser's build leaves out whatever nothing can reach, and one of this page alone would show neither that
/// the whole app compiles to JavaScript nor how big it is. So the app's own way in on a computer ([desktopMain], which
/// a browser will follow as a computer with no phone linked does, lib/standalone) is reached from here, by an address
/// that ends in `#app` ([startsApp]). It is for whoever is building the browser's half to see how far the app gets:
/// until a browser has somewhere to keep things, it stops at the first folder it asks for.
Future<void> main() async {
  if (startsApp(Uri.base)) return desktopMain();
  runApp(const BeingBuilt());
}

/// Whether [address] asks for the app itself and not the page that says it is being built: `#app` at its end.
bool startsApp(Uri address) => address.fragment == 'app';

/// The whole page for now: the ghost, and that the app is on its way.
class BeingBuilt extends StatelessWidget {
  const BeingBuilt({super.key});

  static const words = 'Ghost Messaging for the web is being built';

  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Color(0xFF000000),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The app's own mark (tool/app_icon.py), white on nothing.
                  Image(image: AssetImage('assets/art/ghost-mark.png'), width: 96, height: 96, excludeFromSemantics: true),
                  SizedBox(height: 24),
                  Text(
                    words,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Inter Variable', fontSize: 20, height: 1.4, fontWeight: FontWeight.w500, color: Color(0xFFFFFFFF), decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
