import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../settings_search.dart';
import 'settings_host.dart';
import 'specification.g.dart';

/// What Settings' search finds on the specification (`findable`, src/app/settings/SpecPane.findable.ts): each base
/// specification by name, and each definition by its name and its part's title, so looking for "front matter" or
/// "fills" lands on it. Not by the characters it is written with: the cheat sheet is found by those.
List<SettingsFindable> specFindable() => [
      for (final spec in baseSpecs) SettingsFindable(spec.name, 'markdown standard'),
      for (final section in specification)
        for (final entry in section.entries) SettingsFindable(entry.name, section.title),
    ];

/// Port of `SpecPane` (src/app/settings/SpecPane.tsx with SpecPane.module.css), a page of Settings behind About's
/// Help card: the base Markdown every note is, by link, then every extension and AI fill as a definition: how it is
/// written, the rule, how any other app shows it, and where one pattern is the rule, the pattern itself, folded away.
///
/// The words are the web app's own settings/specification.ts, read off the running page into specification.g.dart
/// (the patterns there are the ones the web's modules run).
///
/// What differs from the web original:
/// - The patterns are the web app's, as text: the Flutter app has no parser of its own yet (stage 4), so nothing here
///   holds them to the code that will read a note, as the web's test does.
/// - A base specification's row opens its link through [onOpenLink]; without one it is drawn and cannot be pressed.
/// - A block of characters wraps where the page's does (`pre-wrap`, `overflow-wrap: anywhere`) and never scrolls
///   sideways.
class SpecPane extends StatelessWidget {
  const SpecPane({super.key, this.onOpenLink});

  /// Opens a link outside the app.
  final void Function(String url)? onOpenLink;

  static Widget hosted(BuildContext context) => SpecPane(onOpenLink: SettingsHost.maybeOf(context)?.onOpenLink);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final open = onOpenLink;
    final xs = t.fontSize('xs');
    final sm = t.fontSize('sm');
    return PaneBody(
      children: [
        PaneSection(
          title: 'The base',
          description: const Text('Every note is standard Markdown first. What follows only adds to it.'),
          children: [
            for (final spec in baseSpecs)
              SettingRow(
                key: ValueKey(spec.name),
                icon: const AppIcon(Lucide.externalLink, size: 20),
                label: spec.name,
                hint: Text(spec.about),
                onPress: open == null ? () {} : () => open(spec.url),
                disabled: open == null,
              ),
          ],
        ),
        for (final section in specification)
          // `.section { margin-block-start: var(--glacier-space-6) }`, over the page's own gap.
          Padding(
            key: ValueKey('spec-${section.id}'),
            padding: EdgeInsets.only(top: t.space(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  label: section.title,
                  child: ExcludeSemantics(
                    child: Text(section.title.toUpperCase(), style: pageText(t, xs, weight: 'semibold', color: t.color('glacier-text-subtle'), tracking: t.len('app-tracking-caps', em: xs))),
                  ),
                ),
                SizedBox(height: t.space(1)),
                Text(section.intro, style: pageText(t, sm, color: t.color('glacier-text-muted'))),
                SizedBox(height: t.space(3)),
                for (var i = 0; i < section.entries.length; i++) ...[
                  if (i > 0) SizedBox(height: t.space(3)),
                  SpecEntryCard(entry: section.entries[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One definition (`Entry`, `.entry`): its name, its characters in a sunken block, the rule, how other apps show it,
/// and the pattern folded away under it.
class SpecEntryCard extends StatefulWidget {
  const SpecEntryCard({super.key, required this.entry});
  final SpecEntry entry;

  @override
  State<SpecEntryCard> createState() => _SpecEntryCardState();
}

class _SpecEntryCardState extends State<SpecEntryCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final entry = widget.entry;
    final gap = t.space(2);
    final xs = t.fontSize('xs');
    final sm = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final label = pageText(t, xs, color: t.color('glacier-text-subtle'), tracking: t.len('app-tracking-caps', em: xs));

    Widget written(String text) => Container(
          width: double.infinity,
          padding: EdgeInsets.all(gap),
          decoration: BoxDecoration(color: t.color('glacier-surface-sunken'), borderRadius: BorderRadius.circular(t.radius('md'))),
          child: Text(text, style: pageText(t, sm, color: muted, mono: true)),
        );

    final pattern = entry.pattern;
    return Container(
      padding: EdgeInsets.all(t.space(3)),
      decoration: BoxDecoration(
        color: t.colorOf('color-mix(in oklch, var(--app-ink) 4%, var(--glacier-bg))'),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink) 10%, transparent)'), width: t.len('glacier-hairline')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `data-findable`: the search opens the page onto the definition's name.
          SettingsFindableMark(name: entry.name, child: Semantics(header: true, child: Text(entry.name, style: pageText(t, t.fontSize('md'), weight: 'semibold')))),
          SizedBox(height: gap),
          written(entry.written),
          SizedBox(height: gap),
          Text(entry.rule, style: pageText(t, sm, height: 1.5)),
          SizedBox(height: gap),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'ELSEWHERE', style: label, semanticsLabel: 'Elsewhere'),
                TextSpan(text: ' ${entry.elsewhere}'),
              ],
            ),
            style: pageText(t, sm, color: muted),
          ),
          if (pattern != null) ...[
            SizedBox(height: gap),
            // `<details>`: the summary is the way in, and the pattern is under it once it is open.
            GlacierPressable(
              onPressed: () => setState(() => _open = !_open),
              semanticLabel: 'The pattern',
              toggled: _open,
              builder: (context, state) => GlacierFocusRing(
                visible: state.focused,
                radius: t.radius('sm'),
                child: Padding(
                  padding: EdgeInsets.only(bottom: gap),
                  child: Row(
                    children: [
                      // The browser's own disclosure mark: a small triangle that turns down when it is open.
                      CustomPaint(size: Size(xs * 0.9, xs), painter: _Disclosure(open: _open, color: label.color!)),
                      SizedBox(width: xs * 0.3),
                      Text('THE PATTERN', style: label),
                    ],
                  ),
                ),
              ),
            ),
            if (_open) written(pattern),
          ],
        ],
      ),
    );
  }
}

class _Disclosure extends CustomPainter {
  const _Disclosure({required this.open, required this.color});
  final bool open;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width * 0.72;
    final centre = size.center(Offset.zero);
    final path = Path();
    if (open) {
      path
        ..moveTo(centre.dx - side / 2, centre.dy - side * 0.36)
        ..lineTo(centre.dx + side / 2, centre.dy - side * 0.36)
        ..lineTo(centre.dx, centre.dy + side * 0.5)
        ..close();
    } else {
      path
        ..moveTo(centre.dx - side * 0.36, centre.dy - side / 2)
        ..lineTo(centre.dx - side * 0.36, centre.dy + side / 2)
        ..lineTo(centre.dx + side * 0.5, centre.dy)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Disclosure old) => old.open != open || old.color != color;
}
