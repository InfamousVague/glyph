import 'dart:convert';
import 'dart:io';

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';

/// The token engine against the web app itself. `fixtures/web_tokens_375.json` is what Ghost.md's page computed for
/// these custom properties in a 375 x 812 window (lengths by a probe element's width, colours by the pixel a canvas
/// painted), in light, in dark, and inside `.app-inverse` in dark. The same stylesheets are read here.
void main() {
  final app = Directory('../../assets/css');
  final sheet = TokenSheet.parseAll([
    File('assets/css/tokens.css').readAsStringSync(),
    for (final name in ['ink.css', 'app.css', 'typefaces.css']) File('${app.path}/$name').readAsStringSync(),
  ]);
  final web = jsonDecode(File('test/fixtures/web_tokens_375.json').readAsStringSync()) as Map<String, dynamic>;
  final attrs = (web['attrs'] as Map).cast<String, String>();
  final css = CssContext(vw: (web['vw'] as num).toDouble(), vh: (web['vh'] as num).toDouble());
  Tokens root(String theme) => Tokens.root(sheet, attrs: {...attrs, 'theme': theme}, css: css, env: const {
        'safe-area-inset-top': '0px',
        'safe-area-inset-bottom': '0px',
        'safe-area-inset-left': '0px',
        'safe-area-inset-right': '0px',
      });

  void check(String label, Tokens tokens, Map<String, dynamic> expected) {
    final wrong = <String>[];
    expected.forEach((name, value) {
      if (value is num) {
        final got = tokens.len(name);
        if ((got - value).abs() > 0.02) wrong.add('$name: web $value, here ${got.toStringAsFixed(3)}');
      } else {
        final want = (value as String).split(',').map(int.parse).toList();
        final c = tokens.color(name);
        final got = [(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), (c.a * 255).round()];
        // A canvas keeps a see-through pixel premultiplied in eight bits, so its colour comes back a few steps out.
        final slack = want[3] == 255 ? 1 : 3;
        final off = [for (var i = 0; i < 4; i++) (got[i] - want[i]).abs()];
        if (off[3] > 1 || off.take(3).any((d) => d > slack)) wrong.add('$name: web $want, here $got');
      }
    });
    expect(wrong, isEmpty, reason: '$label\n${wrong.join('\n')}');
  }

  test('resolves what the page resolves, in light', () => check('light', root('light'), (web['light'] as Map).cast()));
  test('resolves what the page resolves, in dark', () => check('dark', root('dark'), (web['dark'] as Map).cast()));
  test('inherits and overrides as the page does inside .app-inverse', () {
    check('dark, inverse', root('dark').child(classes: {'app-inverse'}), (web['darkInverse'] as Map).cast());
  });

  test('reads motion, shadows, gradients and fonts', () {
    final t = root('light');
    expect(t.duration('glacier-duration-fast'), const Duration(milliseconds: 150));
    final ease = t.curve('glacier-ease-out') as Cubic;
    expect([ease.a, ease.b, ease.c, ease.d], [0.16, 1, 0.3, 1]);
    expect(t.transition('app-turn').duration, const Duration(milliseconds: 420));
    expect(t.shadow('glacier-shadow-2'), isNotEmpty);
    expect(t.shadow('glacier-shadow-0'), isEmpty);
    expect(t.gradient('glacier-gradient-accent'), isA<LinearGradient>());
    expect(t.families('glacier-font-sans').first, 'Inter Variable');
    expect(t.families('glacier-font-mono').first, 'Maple Mono');
    expect(t.text('sm').fontSize, closeTo(13.375, 0.02));
    expect(t.lenOf('calc(var(--glacier-space-10) * 0.74)'), closeTo(32.922, 0.02));
  });

  test('follows density and reduced motion', () {
    final compact = Tokens.root(sheet, attrs: {...attrs, 'theme': 'light', 'density': 'compact'}, css: css);
    expect(compact.len('glacier-control-height-md'), 36);
    expect(compact.len('glacier-space-4'), lessThan(root('light').len('glacier-space-4')));
    final still = Tokens.root(sheet, attrs: {...attrs, 'theme': 'light'}, css: css, reducedMotion: true);
    expect(still.duration('glacier-duration-normal').inMilliseconds, 0);
  });

  test('a rule is a whole number of device pixels, rounded down and never none, as a browser snaps a border', () {
    expect(const CssContext(dpr: 2.625).border(1), closeTo(2 / 2.625, 1e-9));
    expect(const CssContext(dpr: 2.625).border(1.5), closeTo(3 / 2.625, 1e-9));
    expect(const CssContext(dpr: 3).border(1), 1);
    expect(const CssContext(dpr: 1).border(1.5), 1);
    expect(const CssContext(dpr: 4).border(0.1), 0.25);
    expect(const CssContext().border(0), 0);
  });

  test('mixes colours where CSS mixes them', () {
    final half = evalColor('color-mix(in oklch, oklch(0.6 0.2 30) 50%, oklch(0.8 0.1 90))');
    expect(half.l, closeTo(0.7, 1e-9));
    expect(half.h, closeTo(60, 1e-9));
    final faded = evalColor('color-mix(in oklch, oklch(0.5 0.1 200) 25%, transparent)');
    expect(faded.alpha, closeTo(0.25, 1e-9));
    expect(faded.l, closeTo(0.5, 1e-9));
    expect(evalColor('#ff0000').toColor().r, closeTo(1, 0.002));
    expect(evalNumber('clamp(1rem, 0.9671rem + 0.1645vw, 1.125rem)', const CssContext(vw: 375)), closeTo(16.09, 0.01));
  });

  test('a compound selector is about one element: a swatch that says only its accent inside a dark page keeps the light ramp', () {
    // tokens.css: `[data-accent='red'] { --glacier-accent-9: oklch(0.627 0.19 25) }` and
    // `[data-theme='dark'][data-accent='red'] { … oklch(0.64 0.2052 25) }`. On the page the dark rule is the root's
    // alone (it carries both attributes); Settings' accent swatches are spans with `data-accent` and nothing else,
    // and were measured beside the page at 228,75,73 (the light ramp) where this engine gave 239,71,71.
    final dark = root('dark');
    expect(dark.child(attrs: const {'accent': 'red'}).raw('glacier-accent-9'), 'oklch(0.627 0.19 25)');
    final chosen = Tokens.root(sheet, attrs: {...attrs, 'theme': 'dark', 'accent': 'red'}, css: css);
    expect(chosen.raw('glacier-accent-9'), 'oklch(0.64 0.2052 25)');
    // A scope that says both itself is the element the dark rule is about.
    expect(root('light').child(attrs: const {'theme': 'dark', 'accent': 'red'}).raw('glacier-accent-9'), 'oklch(0.64 0.2052 25)');
    // A descendant selector still reaches a scope under a dark page.
    final hues = TokenSheet.parse("[data-hue] { --hue: 1; } [data-theme='dark'] [data-hue] { --hue: 2; }");
    expect(Tokens.root(hues, attrs: const {'theme': 'dark'}).child(attrs: const {'hue': 'x'}).raw('hue'), '2');
  });

  test('a property whose var() stands for nothing has no value, so a var() of it takes its fallback, as on the page', () {
    // settings.css on the dark side: every [data-hue] is given its --hue-dark, and a hue it does not name has none.
    final hues = TokenSheet.parse('''
:root { --ink: #111111; }
[data-hue='blue'] { --hue: #0a6fe0; --hue-dark: #4ea1ff; }
:root[data-theme='dark'] [data-hue] { --hue: var(--hue-dark); }
''');
    final dark = Tokens.root(hues, attrs: const {'theme': 'dark'});
    expect(dark.child(attrs: const {'hue': 'blue'}).resolve('var(--hue, var(--ink))'), '#4ea1ff');
    final amber = dark.child(attrs: const {'hue': 'amber'});
    expect(amber.raw('hue'), isNull);
    expect(amber.resolve('var(--hue, var(--ink))'), '#111111');
    expect(amber.colorOf('color-mix(in srgb, var(--hue, var(--ink)) 16%, transparent)').a, closeTo(0.16, 0.005));
  });
}
