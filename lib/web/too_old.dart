/// What the web build shows in a browser too old for it (docs/WEB.md).
///
/// The page is the app compiled to WebAssembly with garbage collection (Chrome and Edge 119, Firefox 120, Safari
/// 18.2 and later), where a Dart `int` is 64 bits as it is on the phone: the hashes a note is kept against
/// (format/body_hash.dart), a reminder's id and a diagram's file are FNV-1a over 64 bits, and in JavaScript, whose
/// numbers are doubles, every one of them would come out another number than the phone's. Flutter builds a
/// JavaScript copy beside it for the browsers without, and that copy opens this and nothing else: no notes are read
/// or written by an app that would hash them wrongly.
library;

import 'package:flutter/widgets.dart';

class TooOldBrowser extends StatelessWidget {
  const TooOldBrowser({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQueryData.fromView(View.of(context)).platformBrightness == Brightness.dark;
    final ink = dark ? const Color(0xFFEDEDED) : const Color(0xFF161616);
    return WidgetsApp(
      color: ink,
      debugShowCheckedModeBanner: false,
      title: 'Ghost.md',
      builder: (context, _) => ColoredBox(
        color: dark ? const Color(0xFF0E0E0E) : const Color(0xFFFAFAFA),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DefaultTextStyle(
                style: TextStyle(color: ink, fontSize: 15, height: 1.5, fontFamily: 'Inter Variable'),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This browser is too old for Ghost.md', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    SizedBox(height: 12),
                    Text(
                      'The web version needs a browser from the last two years: Chrome or Edge 119, Firefox 120, '
                      'or Safari 18.2 and later. Update this one, or use the apps for Android, iPhone and the Mac.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
