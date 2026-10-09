import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import 'css_value.dart';
import 'sheet.dart';
import 'tokens.dart';

/// The kit's own token sheet, as `@glacier/tokens` ships it.
const String glacierTokensAsset = 'packages/glacier/assets/css/tokens.css';

/// Reads the kit's tokens and then [more] stylesheets of the app's, in the order a page would load them.
Future<TokenSheet> loadTokenSheet({List<String> more = const [], AssetBundle? bundle}) async {
  final from = bundle ?? rootBundle;
  final sheets = <String>[];
  for (final asset in [glacierTokensAsset, ...more]) {
    sheets.add(await from.loadString(asset));
  }
  return TokenSheet.parseAll(sheets);
}

/// The device pixel ratio a test's lines of text are rounded at, in place of its window's. A page's engine rounds a
/// line of `line-height: normal` in device pixels (line_height.dart), so a rectangle measured on a desktop's page
/// (ratio 1) is only met by lines rounded at 1, whatever density the test draws its picture at. A test says the ratio
/// its fixture was measured at here (the app's `pumpApp(measuredAt:)`) and puts null back after; the app never sets
/// it. A border keeps the window's ratio ([CssContext.border]): at 1 and at 2 a 1px rule is the same.
double? debugFixturePixelRatio;

/// Puts the design tokens over a subtree, as `<html data-theme=... data-density=...>` does on the page.
///
/// [attrs] are the page's `data-` attributes without the prefix. `theme` may be left out to follow the system's
/// light or dark. The tokens are worked out again when the window's width changes (the type and space scales are
/// fluid) or its safe areas do.
class GlacierTheme extends StatefulWidget {
  const GlacierTheme({super.key, required this.sheet, this.attrs = const {}, this.typography = const GlacierTypography(), required this.child});

  final TokenSheet sheet;
  final Map<String, String> attrs;

  /// The page's own type settings (`html { font-feature-settings }`, a web font's subsets).
  final GlacierTypography typography;
  final Widget child;

  /// The tokens in force at [context].
  static Tokens of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_TokensScope>();
    assert(scope != null, 'No GlacierTheme above this widget.');
    return scope!.tokens;
  }

  static Tokens? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_TokensScope>()?.tokens;

  @override
  State<GlacierTheme> createState() => _GlacierThemeState();
}

class _GlacierThemeState extends State<GlacierTheme> {
  Tokens? _tokens;
  Object? _key;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = widget.attrs['theme'] ?? (media.platformBrightness == Brightness.dark ? 'dark' : 'light');
    final attrs = {...widget.attrs, 'theme': theme};
    final pad = media.viewPadding;
    final env = {
      'safe-area-inset-top': '${pad.top}px',
      'safe-area-inset-bottom': '${pad.bottom}px',
      'safe-area-inset-left': '${pad.left}px',
      'safe-area-inset-right': '${pad.right}px',
    };
    final css = CssContext(vw: media.size.width, vh: media.size.height, dpr: media.devicePixelRatio, lineDpr: debugFixturePixelRatio ?? media.devicePixelRatio);
    final key = Object.hash(widget.sheet, Object.hashAll(attrs.entries.map((e) => Object.hash(e.key, e.value))), Object.hashAll(env.values), css, media.disableAnimations, widget.typography);
    if (_tokens == null || key != _key) {
      _key = key;
      _tokens = Tokens.root(widget.sheet, attrs: attrs, env: env, reducedMotion: media.disableAnimations, css: css, typography: widget.typography);
    }
    return _TokensScope(tokens: _tokens!, child: widget.child);
  }
}

/// An element with classes or attributes of its own inside the theme: `.app-inverse`, `data-hue`.
class GlacierScope extends StatefulWidget {
  const GlacierScope({super.key, this.classes = const {}, this.attrs = const {}, required this.child});

  final Set<String> classes;
  final Map<String, String> attrs;
  final Widget child;

  @override
  State<GlacierScope> createState() => _GlacierScopeState();
}

class _GlacierScopeState extends State<GlacierScope> {
  Tokens? _from;
  Tokens? _tokens;
  Object? _key;

  @override
  Widget build(BuildContext context) {
    final parent = GlacierTheme.of(context);
    final key = Object.hash(Object.hashAllUnordered(widget.classes), Object.hashAllUnordered(widget.attrs.entries.map((e) => Object.hash(e.key, e.value))));
    if (!identical(parent, _from) || key != _key) {
      _from = parent;
      _key = key;
      _tokens = parent.child(attrs: widget.attrs, classes: widget.classes);
    }
    return _TokensScope(tokens: _tokens!, child: widget.child);
  }
}

class _TokensScope extends InheritedWidget {
  const _TokensScope({required this.tokens, required super.child});
  final Tokens tokens;

  @override
  bool updateShouldNotify(_TokensScope old) => !identical(old.tokens, tokens);
}

extension GlacierContext on BuildContext {
  /// The design tokens in force here.
  Tokens get tokens => GlacierTheme.of(this);
}
