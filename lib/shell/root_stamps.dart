import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

/// `data-*` attributes on the page's root, there for the subtree while they are in [stamps] and gone when their
/// value is null: the web app's shell/useRootStamp.ts, by which the shell tells the stylesheets about its layout
/// without handing them a number. app.css asks `[data-tabs]` how tall the tab bar is, `[data-topbar]` which way it
/// is drawn and `[data-split]` whether the window is in two panes; a stamp has no number in it, so the chrome that
/// reads it can only agree with the shell that wrote it.
///
/// Differs from the web: the page had one root to write on. The kit's [GlacierTheme] is given its attributes where
/// the app is built (lib/app), and has no way to be told more from below, so this lays a second root over the
/// subtree: the same sheet, the attributes in force with [stamps] over them. It needs the [sheet] for that, which
/// the tokens do not hand back. A token that hangs on a stamp (`--app-tabs`, `--app-safe-top`) is right under this
/// and stale above it.
class RootStamps extends StatelessWidget {
  const RootStamps({super.key, required this.sheet, required this.stamps, required this.child});

  final TokenSheet sheet;

  /// Each attribute without its `data-`, and its value; null takes it off.
  final Map<String, String?> stamps;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final outer = context.tokens.rootTokens;
    final attrs = {...outer.attrs};
    for (final stamp in stamps.entries) {
      final value = stamp.value;
      if (value == null) {
        attrs.remove(stamp.key);
      } else {
        attrs[stamp.key] = value;
      }
    }
    return GlacierTheme(sheet: sheet, attrs: attrs, typography: outer.typography, child: child);
  }
}
