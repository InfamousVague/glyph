import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// What an app's own stylesheet does to the kit's parts by selector, for a whole subtree.
///
/// Most of an app's restyling arrives through the tokens. The rest is rules that reach into a component
/// (`[role='switch'] + span > span { background: var(--app-paper) }`), which no token carries. Each is a function of
/// the tokens here, so it follows the theme; a component uses its own parameter first, then this, then the kit's.
class GlacierOverrides extends InheritedWidget {
  const GlacierOverrides({super.key, this.switchThumbColor, this.segmentedSelectedLabelColor, this.segmentedThumbShadow, required super.child});

  /// The switch's thumb.
  final Color Function(Tokens tokens)? switchThumbColor;

  /// The label of a segmented control's selected option.
  final Color Function(Tokens tokens)? segmentedSelectedLabelColor;

  /// The shadows of a segmented control's thumb, outer and inset together; an empty list is `box-shadow: none`.
  final List<BoxShadow> Function(Tokens tokens)? segmentedThumbShadow;

  static GlacierOverrides? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlacierOverrides>();

  @override
  bool updateShouldNotify(GlacierOverrides old) =>
      old.switchThumbColor != switchThumbColor || old.segmentedSelectedLabelColor != segmentedSelectedLabelColor || old.segmentedThumbShadow != segmentedThumbShadow;
}
