import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';

/// The token sheets the app loads, read from disk for a test: the kit's tokens.css, then Ghost.md's ink.css, app.css
/// and typefaces.css (../../assets/css), in the page's order.
final TokenSheet testSheet = TokenSheet.parseAll([
  File('assets/css/tokens.css').readAsStringSync(),
  for (final name in ['ink.css', 'app.css', 'typefaces.css']) File('../../assets/css/$name').readAsStringSync(),
]);

/// The page's own attributes on a phone, as Ghost.md stamps them.
const Map<String, String> testAttrs = {'platform': 'android', 'note-font': 'maple', 'tabs': 'on'};

/// Pumps [child] under the theme in a 390 x 844 window, light unless [theme] says dark, with a text direction and a
/// place for overlays, as a page has.
Future<void> pumpKit(WidgetTester tester, Widget child, {String theme = 'light', Map<String, String> attrs = const {}, bool haptics = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: GlacierTheme(
          sheet: testSheet,
          attrs: {...testAttrs, 'theme': theme, ...attrs},
          child: HapticsProvider(
            enabled: haptics,
            child: _Host(child: child),
          ),
        ),
      ),
    ),
  );
}

/// The tokens the harness resolves, for a test to compare a widget's paint against.
Tokens testTokens({String theme = 'light', Map<String, String> attrs = const {}}) =>
    Tokens.root(testSheet, attrs: {...testAttrs, 'theme': theme, ...attrs}, css: const CssContext(vw: 390, vh: 844));

/// The overlay a page has, with the widget under test as its one entry: pumped again, it shows the new widget in
/// the same place, so state carries over as it would on a rebuild.
class _Host extends StatefulWidget {
  const _Host({required this.child});
  final Widget child;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final OverlayEntry _entry = OverlayEntry(builder: (context) => Align(alignment: Alignment.topLeft, child: widget.child));

  @override
  void didUpdateWidget(_Host old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entry.markNeedsBuild();
    });
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
