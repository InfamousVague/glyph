import 'css_value.dart';

/// One thing a rule's selector asks of where it applies: an attribute (`[data-theme='dark']`, `[data-split]`,
/// `:not([data-accent])`) or a class (`.app-inverse`).
class TokenCondition {
  const TokenCondition.attr(this.key, this.value, {this.negated = false}) : isClass = false;
  const TokenCondition.cls(this.key)
      : value = null,
        negated = false,
        isClass = true;

  /// The attribute's name without `data-`, or the class's name.
  final String key;

  /// The value asked for, or null where being present is enough.
  final String? value;
  final bool negated;
  final bool isClass;

  bool holds(Map<String, String> attrs, Set<String> classes) {
    if (isClass) return classes.contains(key);
    final has = value == null ? attrs.containsKey(key) : attrs[key] == value;
    return negated ? !has : has;
  }
}

/// A rule of a token sheet that declares custom properties: where it applies, what it declares, and where it stands
/// in the cascade.
class TokenRule {
  const TokenRule({required this.conditions, required this.declarations, required this.specificity, required this.order, this.reducedMotion = false});

  final List<TokenCondition> conditions;

  /// Custom properties by their whole name, `--glacier-space-2`.
  final Map<String, String> declarations;
  final int specificity;
  final int order;

  /// Inside `@media (prefers-reduced-motion: reduce)`.
  final bool reducedMotion;

  bool matches(Map<String, String> attrs, Set<String> classes) => conditions.every((c) => c.holds(attrs, classes));

  /// Whether the rule answers to something a scope brings of its own: one of its classes or attributes.
  bool asksFor(Set<String> attrKeys, Set<String> classes) =>
      conditions.any((c) => !c.negated && (c.isClass ? classes.contains(c.key) : attrKeys.contains(c.key)));
}

/// The custom properties of one or more stylesheets, as rules in cascade order.
///
/// This reads the very CSS the web app ships (`@glacier/tokens`' tokens.css, then the app's own ink.css, app.css and
/// typefaces.css) and keeps every rule whose selector is made only of `:root`, `data-` attributes and classes.
/// Rules for particular elements are a widget's to port; rules inside `prefers-color-scheme` are left out, because
/// the theme is always named here (`data-theme` is set from the system's when the person chose "system") and each of
/// those rules has a `[data-theme='dark']` twin.
class TokenSheet {
  TokenSheet._(this.rules);

  final List<TokenRule> rules;

  factory TokenSheet.parse(String css) => TokenSheet.parseAll([css]);

  /// Several stylesheets, in the order the page loads them.
  factory TokenSheet.parseAll(Iterable<String> sheets) {
    final rules = <TokenRule>[];
    for (final css in sheets) {
      final clean = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '').replaceAll(RegExp(r'@(import|charset)[^;]*;'), '');
      _block(clean, rules, reducedMotion: false);
    }
    rules.sort((a, b) => a.specificity != b.specificity ? a.specificity.compareTo(b.specificity) : a.order.compareTo(b.order));
    return TokenSheet._(rules);
  }

  static void _block(String css, List<TokenRule> out, {required bool reducedMotion}) {
    var i = 0;
    while (i < css.length) {
      final open = css.indexOf('{', i);
      if (open < 0) return;
      var depth = 1, close = open + 1;
      while (close < css.length && depth > 0) {
        final ch = css[close];
        if (ch == '{') depth++;
        if (ch == '}') depth--;
        close++;
      }
      final prelude = css.substring(i, open).trim();
      final body = css.substring(open + 1, close - 1);
      i = close;
      if (prelude.startsWith('@')) {
        if (prelude.startsWith('@media') && prelude.contains('prefers-reduced-motion')) _block(body, out, reducedMotion: true);
        continue;
      }
      if (body.contains('{')) continue;
      final declarations = _declarations(body);
      if (declarations.isEmpty) continue;
      for (final selector in splitTop(prelude, ',')) {
        final parsed = _selector(selector);
        if (parsed == null) continue;
        out.add(TokenRule(conditions: parsed.conditions, declarations: declarations, specificity: parsed.specificity, order: out.length, reducedMotion: reducedMotion));
      }
    }
  }

  static Map<String, String> _declarations(String body) {
    final out = <String, String>{};
    for (final part in splitTop(body, ';')) {
      if (!part.startsWith('--')) continue;
      final colon = part.indexOf(':');
      if (colon < 0) continue;
      out[part.substring(0, colon).trim()] = part.substring(colon + 1).trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    return out;
  }

  static final _piece = RegExp(
    r'''\s+|:root|:not\(\[data-([\w-]+)(?:=['"]?([^'"\]]*)['"]?)?\]\)|\[data-([\w-]+)(?:=['"]?([^'"\]]*)['"]?)?\]|\.([A-Za-z_][\w-]*)''',
  );

  static ({List<TokenCondition> conditions, int specificity})? _selector(String selector) {
    final conditions = <TokenCondition>[];
    var specificity = 0;
    var i = 0;
    while (i < selector.length) {
      final m = _piece.matchAsPrefix(selector, i);
      if (m == null) return null;
      i = m.end;
      final text = m.group(0)!;
      if (text.trim().isEmpty) continue;
      specificity++;
      if (text == ':root') continue;
      if (m.group(1) != null) {
        conditions.add(TokenCondition.attr(m.group(1)!, m.group(2), negated: true));
      } else if (m.group(3) != null) {
        conditions.add(TokenCondition.attr(m.group(3)!, m.group(4)));
      } else {
        conditions.add(TokenCondition.cls(m.group(5)!));
      }
    }
    return (conditions: conditions, specificity: specificity);
  }
}
