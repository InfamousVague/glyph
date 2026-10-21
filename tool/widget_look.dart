// Makes the home-screen widgets' look (android/app/src/main/res, docs/WIDGETS_ANDROID.md) from the app's own: the colours,
// lengths and type sizes the token engine resolves from the stylesheets, in the paper look and the dark one, and the
// icons from the very paths the app draws (lib/art/lucide.g.dart, lib/art/icons.dart).
//
//   GHOST_WRITE=1 flutter test test/home_screen/widget_look_test.dart    writes the files
//   flutter test test/home_screen/widget_look_test.dart                  says whether they are what it would write
//
// The token engine is Flutter's (dart:ui's colours), so this runs under `flutter test` rather than `dart run`. Run it
// again whenever ink.css, app.css or the kit's tokens.css changes (the test fails until it is).
//
// What is written:
// - res/values/ghost_widget_tokens.xml: each colour in the paper look (`ghost_w_light_*`) and the dark one
//   (`ghost_w_dark_*`); an attribute for each (`?attr/ghost_w_ink`), which every widget layout and drawable names; the
//   themes that say which look the attributes are (GhostW.Theme.Light, .Dark, and .System, Light here); and every
//   length and size (the same in both looks). A CSS pixel is a dp; a type size is an sp, so the phone's own text size
//   still applies.
// - res/values-night/ghost_widget_tokens.xml: GhostW.Theme.System where the phone is dark.
// - res/drawable/ghost_w_ic_*.xml: each icon in white with its wash a third of white inside, so an ImageView's tint
//   (SRC_IN) paints both in one ink, as AppIcon paints them in the one colour it is given; the few nothing can tint, in
//   their attribute's colour.
import 'package:flutter/painting.dart' show Color;
import 'package:ghost_md/app/token_sheet.g.dart';
import 'package:ghost_md/art/app_icon.dart' show LucideIcon;
import 'package:ghost_md/art/icon_wash.dart' show iconWash;
import 'package:ghost_md/art/icons.dart' show AppIcons, DrawnIcon;
import 'package:ghost_md/art/lucide.g.dart' show Lucide;
import 'package:glacier/glacier.dart';

const String res = 'android/app/src/main/res';

/// The window the lengths are worked out for: the Fold's cover screen and most phones, 412 CSS pixels across, where
/// the kit's clamped sizes land.
const CssContext window = CssContext(vw: 412, vh: 915, dpr: 2.625);

Tokens tokensFor(String theme) => Tokens.root(appTokenSheet(), attrs: {'theme': theme}, css: window);

/// Each colour the widgets draw with: its resource name, and what it is in the stylesheets' words.
const List<(String, String, String)> colours = [
  ('ghost_w_paper', 'var(--glacier-bg)', 'the page'),
  ('ghost_w_press', 'color-mix(in oklch, var(--app-ink) 6%, transparent)', "a pressed row: the card's hover wash, 6% of the ink"),
  ('ghost_w_rule', 'var(--glacier-border-subtle)', "a card's hairline"),
  ('ghost_w_line', 'var(--glacier-border-strong)', "a ring's edge (the dock's round buttons)"),
  ('ghost_w_ink', 'var(--app-ink)', 'text, solid controls'),
  ('ghost_w_ink_2', 'var(--app-ink-2)', 'secondary text'),
  ('ghost_w_ink_3', 'var(--app-ink-3)', 'tertiary text, marks'),
  ('ghost_w_ink_4', 'var(--app-ink-4)', 'faint marks: an event\'s ring'),
  ('ghost_w_on_ink', 'var(--app-paper)', 'what is drawn on the ink: the mic in the filled ring, a ticked box\'s check'),
  ('ghost_w_red_9', 'var(--glacier-red-9)', "an overdue to-do's ring"),
  ('ghost_w_red_11', 'var(--glacier-red-11)', 'an overdue day, said'),
  ('ghost_w_amber_11', 'var(--glacier-amber-11)', 'a day that is today, on its chip'),
  ('ghost_w_chip', 'color-mix(in srgb, var(--app-ink-2) 9%, transparent)', "a field chip's ground (field_chips.dart, `.cm-field`)"),
  ('ghost_w_chip_overdue', 'color-mix(in oklch, var(--glacier-red-9) 16%, transparent)', "an overdue day's chip"),
  ('ghost_w_chip_today', 'color-mix(in oklch, var(--glacier-amber-9) 18%, transparent)', "today's chip"),
];

/// Each length: its resource name, the token, and how it is written (dp or sp).
const List<(String, String, String)> lengths = [
  ('ghost_w_space_1', 'glacier-space-1', 'dp'),
  ('ghost_w_space_2', 'glacier-space-2', 'dp'),
  ('ghost_w_space_3', 'glacier-space-3', 'dp'),
  ('ghost_w_space_4', 'glacier-space-4', 'dp'),
  ('ghost_w_space_5', 'glacier-space-5', 'dp'),
  ('ghost_w_space_6', 'glacier-space-6', 'dp'),
  ('ghost_w_space_8', 'glacier-space-8', 'dp'),
  ('ghost_w_space_10', 'glacier-space-10', 'dp'),
  ('ghost_w_space_12', 'glacier-space-12', 'dp'),
  ('ghost_w_radius_sm', 'glacier-radius-sm', 'dp'),
  ('ghost_w_radius_md', 'glacier-radius-md', 'dp'),
  ('ghost_w_radius_lg', 'glacier-radius-lg', 'dp'),
  ('ghost_w_ring', 'app-ring', 'dp'),
  ('ghost_w_text_xs', 'glacier-font-size-xs', 'sp'),
  ('ghost_w_text_sm', 'glacier-font-size-sm', 'sp'),
  ('ghost_w_text_md', 'glacier-font-size-md', 'sp'),
  ('ghost_w_text_lg', 'glacier-font-size-lg', 'sp'),
  ('ghost_w_text_xl', 'glacier-font-size-xl', 'sp'),
];

/// The icons: the resource's name, the drawing, its stroke in the drawing's 24 units, and the colour it is drawn in
/// where nothing can tint it (a chip's compound drawable, the tick's check inside its disc); null for white, tinted
/// by the ImageView it is in.
final List<(String, Object, double, String?)> icons = [
  ('ghost_w_ic_tick_check', Lucide.check, 3, 'ghost_w_on_ink'),
  ('ghost_w_ic_due', Lucide.calendarDays, 2, 'ghost_w_ink_2'),
  ('ghost_w_ic_due_overdue', Lucide.calendarDays, 2, 'ghost_w_red_11'),
  ('ghost_w_ic_due_today', Lucide.calendarDays, 2, 'ghost_w_amber_11'),
  for (final (name, icon, stroke) in _tinted) (name, icon, stroke, null),
];

final List<(String, Object, double)> _tinted = [
  ('ghost_w_ic_mic', Lucide.mic, 2.2),
  ('ghost_w_ic_plus', Lucide.plus, 2),
  ('ghost_w_ic_pen', Lucide.squarePen, 2),
  ('ghost_w_ic_note', Lucide.fileText, 2),
  ('ghost_w_ic_todos', Lucide.listTodo, 2),
  ('ghost_w_ic_calendar', Lucide.calendarDays, 2),
  ('ghost_w_ic_book', Lucide.bookOpen, 2),
  ('ghost_w_ic_canvas', Lucide.workflow, 2),
  ('ghost_w_ic_tape', AppIcons.cassette, 2.4),
];

String _hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

String _number(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

const String _header = '<?xml version="1.0" encoding="utf-8"?>\n';
const String _made = 'Made by tool/widget_look.dart from the stylesheets (GHOST_WRITE=1 flutter test test/home_screen/widget_look_test.dart); do not edit by hand.';

/// `ghost_w_ink` as the light look's colour, `ghost_w_light_ink`, or the dark one's.
String colourIn(String look, String name) => name.replaceFirst('ghost_w_', 'ghost_w_${look}_');

/// The tokens file: each colour in both looks, an attribute for each that the widgets' layouts and drawables name
/// (`?attr/ghost_w_ink`), the three themes that say which look an attribute is, and the lengths.
String _tokens(Tokens light, Tokens dark) {
  final out = StringBuffer(_header)
    ..writeln('<!-- The home-screen widgets\' colours, looks and lengths (docs/WIDGETS_ANDROID.md). $_made -->')
    ..writeln('<resources>');
  for (final (name, css, about) in colours) {
    // A comment holds no "--": the properties are named without their dashes.
    out
      ..writeln('    <!-- $about: ${css.replaceAll('--', '')} -->')
      ..writeln('    <attr name="$name" format="color" />')
      ..writeln('    <color name="${colourIn('light', name)}">${_hex(light.colorOf(css))}</color>')
      ..writeln('    <color name="${colourIn('dark', name)}">${_hex(dark.colorOf(css))}</color>');
  }
  out
    ..writeln('    <!-- The looks: the app\'s Light and Dark, and System, which is Light here and Dark in values-night. A widget')
    ..writeln('         is drawn in the one the app\'s theme says (home/WidgetViews.kt). -->')
    ..writeln('    <style name="GhostW.Theme" />')
    ..write(_theme('GhostW.Theme.Light', 'light'))
    ..write(_theme('GhostW.Theme.Dark', 'dark'))
    ..write(_theme('GhostW.Theme.System', 'light'))
    ..write(_lengths(light));
  return (out..writeln('</resources>')).toString();
}

String _theme(String name, String look) {
  final out = StringBuffer()..writeln('    <style name="$name">');
  for (final (colour, _, _) in colours) {
    out.writeln('        <item name="$colour">@color/${colourIn(look, colour)}</item>');
  }
  return (out..writeln('    </style>')).toString();
}

String _night() => (StringBuffer(_header)
      ..writeln('<!-- System, the widgets\' look that follows the phone, where the phone is dark (docs/WIDGETS_ANDROID.md). $_made -->')
      ..writeln('<resources>')
      ..write(_theme('GhostW.Theme.System', 'dark'))
      ..writeln('</resources>'))
    .toString();

String _lengths(Tokens t) {
  final out = StringBuffer()..writeln('    <!-- Lengths, the same in both looks: a CSS pixel as a dp, a type size as an sp. -->');
  for (final (name, token, unit) in lengths) {
    out.writeln('    <dimen name="$name">${_number(t.len(token))}$unit</dimen>');
  }
  // A due day's chip (lib/editor/items/field_chips.dart, `.cm-field`): 0.92 of the line it is in (the row's sm),
  // 0.35em on each side and at its corners, its calendar 0.95em with a quarter em before the words.
  final chip = 0.92 * t.fontSize('sm');
  out
    ..writeln('    <!-- A due day\'s chip, `.cm-field`: 0.92 of the sm line it sits in, 0.35em at its sides and corners. -->')
    ..writeln('    <dimen name="ghost_w_text_chip">${_number(chip)}sp</dimen>')
    ..writeln('    <dimen name="ghost_w_chip_pad">${_number(0.35 * chip)}dp</dimen>')
    ..writeln('    <dimen name="ghost_w_chip_radius">${_number(0.35 * chip)}dp</dimen>')
    ..writeln('    <dimen name="ghost_w_chip_icon">${_number(0.95 * chip)}dp</dimen>')
    ..writeln('    <dimen name="ghost_w_chip_gap">${_number(0.25 * chip)}dp</dimen>');
  return out.toString();
}

final RegExp _command = RegExp('[MmLlHhVvCcSsQqTtAaZz]');
final RegExp _numberAt = RegExp(r'[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');

/// [d] as Android's path parser reads it: every number apart, and an arc's two flags each a number of its own. SVG
/// lets the flags run together and into the next number (`a2 2 0 0022 17` is flags 0 and 0, then 22), as Lucide
/// writes them, and Android reads that as one number and drops the icon.
String androidPath(String d) {
  final out = StringBuffer();
  String? command;
  var index = 0;
  var at = 0;
  while (at < d.length) {
    final c = d[at];
    if (_command.hasMatch(c)) {
      command = c;
      index = 0;
      out.write(out.isEmpty ? c : ' $c');
      at += 1;
    } else if (c == ' ' || c == ',' || c == '\n' || c == '\t') {
      at += 1;
    } else if ((command == 'a' || command == 'A') && (index % 7 == 3 || index % 7 == 4)) {
      out.write(' $c');
      at += 1;
      index += 1;
    } else {
      final number = _numberAt.matchAsPrefix(d, at);
      if (number == null) throw FormatException('not a path', d, at);
      out.write(' ${number[0]}');
      at = number.end;
      index += 1;
    }
  }
  return out.toString();
}

/// How big an icon is where it is drawn at its own size: a chip's calendar at 0.95 of the chip's words, the tick's
/// check at 14, as the To-dos view's disc draws it; 24 for one an ImageView sizes.
String _sizeOf(String name) => name.startsWith('ghost_w_ic_due') ? '@dimen/ghost_w_chip_icon' : (name == 'ghost_w_ic_tick_check' ? '14dp' : '24dp');

String _vector(String name, Object icon, double stroke, String? colour) {
  final List<String> strokes, washed;
  var evenOdd = false;
  if (icon is LucideIcon) {
    strokes = icon.shapes;
    washed = [for (final index in icon.wash) icon.shapes[index]];
  } else {
    final drawn = icon as DrawnIcon;
    strokes = [drawn.d];
    washed = [?drawn.body];
    evenOdd = true;
  }
  final wash = (iconWash * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
  final label = icon is LucideIcon ? "Lucide's ${icon.name} (lib/art/lucide.g.dart)" : "the app's own (lib/art/icons.dart)";
  final out = StringBuffer(_header)
    ..writeln(colour == null
        ? '<!-- $label, white, to be tinted: the wash a third of the ink inside, the strokes ${_number(stroke)} of 24. $_made -->'
        : '<!-- $label in ?attr/$colour (the look\'s), the wash a third of it inside, the strokes ${_number(stroke)} of 24. $_made -->')
    ..writeln('<vector xmlns:android="http://schemas.android.com/apk/res/android"')
    ..writeln('    android:width="${_sizeOf(name)}"')
    ..writeln('    android:height="${_sizeOf(name)}"')
    ..writeln('    android:viewportWidth="24"')
    ..writeln('    android:viewportHeight="24">');
  for (final d in washed) {
    out
      ..writeln('    <path')
      ..writeln('        android:pathData="${androidPath(d)}"')
      ..writeln(evenOdd ? '        android:fillType="evenOdd"' : '        android:fillType="nonZero"')
      ..writeln(colour == null ? '        android:fillColor="#${wash}FFFFFF" />' : '        android:fillColor="?attr/$colour"\n        android:fillAlpha="$iconWash" />');
  }
  for (final d in strokes) {
    out
      ..writeln('    <path')
      ..writeln('        android:pathData="${androidPath(d)}"')
      ..writeln('        android:fillColor="#00000000"')
      ..writeln('        android:strokeColor="${colour == null ? '#FFFFFFFF' : '?attr/$colour'}"')
      ..writeln('        android:strokeWidth="${_number(stroke)}"')
      ..writeln('        android:strokeLineCap="round"')
      ..writeln('        android:strokeLineJoin="round" />');
  }
  return (out..writeln('</vector>')).toString();
}

/// Every file, by its path from the repo's root, and what it is to say.
Map<String, String> generate() {
  final light = tokensFor('light'), dark = tokensFor('dark');
  return {
    '$res/values/ghost_widget_tokens.xml': _tokens(light, dark),
    '$res/values-night/ghost_widget_tokens.xml': _night(),
    for (final (name, icon, stroke, colour) in icons) '$res/drawable/$name.xml': _vector(name, icon, stroke, colour),
  };
}
