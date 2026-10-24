import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/widgets.dart';
import 'app_icon.dart';
import 'blur_box.dart';
import 'blur_edge.dart';
import 'dock_blur.dart';
import 'ghost.dart';
import 'ghost_mark.dart';
import 'icons.dart';
import 'lucide.g.dart';
import 'shapes.dart';
import 'wisp_text.dart';
import 'working_gears.dart';

/// Every piece of the art layer, live, to be judged on a phone: each gradient blur where the web app wears its wisp
/// (a page under its header and at its foot, a column beside it, a board's lane, the tab row's ends, the dock's
/// halo), words out of a blur, the ghost in each of its scenes, the icons with their wash and without, the cogs and
/// the lid.
///
/// `flutter run -t lib/art/main.dart` opens it alone. The switch at the top is the edges' own
/// ([BlurEdgeSettings]): the blur switched off as Settings › Appearance › Motion switches it. Until Matt, 2026-10-24
/// ("replace the smoke effect with a gradient blur on all places that use the wisp smoke") it chose between the
/// smoke's drawings as well; there is one drawing now, on every platform.
class ArtGallery extends StatefulWidget {
  const ArtGallery({super.key});

  @override
  State<ArtGallery> createState() => _ArtGalleryState();
}

const _lines = [
  'Hold. Talk. Done.',
  'The notes that matter are the ones you can find again on a Monday.',
  'Oat milk, two lemons, the good bread from the place on the corner, candles.',
  'Call Sam about the boat before nine, then the long walk if the weather holds.',
  'A list that sorts itself. A page that reads back what you said, word for word.',
  'The ferry leaves at ten past four and the last one home is at eleven.',
  'Three things for the week: the letter, the garden gate, the box in the hall.',
  'Ask Ana what the place by the water was called, the one with the green door.',
  'Read the long piece on tides before Friday, and write down the one good line.',
  'Ali has the keys until Thursday. The spare is where it always is.',
  'Nothing here is urgent. That is the point of writing it down.',
  'Soup, bread, the last of the cheese. Candles again, apparently.',
];

class _ArtGalleryState extends State<ArtGallery> {
  int _words = 0;
  Timer? _turn;

  static const _headlines = ['Hold. Talk. Done.', 'Hold. Talk. Write.', 'Welcome to Ghost.md', 'Not yet, finish reading.'];

  @override
  void initState() {
    super.initState();
    BlurEdgeSettings.instance.addListener(_changed);
  }

  @override
  void dispose() {
    BlurEdgeSettings.instance.removeListener(_changed);
    _turn?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context);
    final gutter = t.len('app-gutter');
    final muted = t.color('glacier-text-muted');
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(gutter, media.padding.top + t.space(8), gutter, media.padding.bottom + t.space(16)),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.len('glacier-container-md')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppEyebrow('Ghost Flutter · the art'),
              SizedBox(height: t.space(2)),
              Text('Blur, ghosts and icons', style: t.textAt(t.len('app-title'), weight: 'bold', height: 1.15, tracking: t.len('app-tracking-title', em: t.len('app-title')))),
              SizedBox(height: t.space(2)),
              Text('Each piece of the web app’s art layer, drawn here by blurs and paths. Scroll inside a box to blur its edge.', style: t.text('md', color: muted)),

              _Section('The blur at the edges', [
                Row(
                  children: [
                    Expanded(child: Text('Blur at a page’s edges', style: t.text('md'))),
                    GlacierSwitch(checked: BlurEdgeSettings.instance.wanted, onCheckedChange: (on) => BlurEdgeSettings.instance.wanted = on, ariaLabel: 'Blur at a page’s edges'),
                  ],
                ),
              ]),

              _Section('A page under its header, and its foot', [
                _Framed(height: 340, child: _Page(under: 52, foot: true, title: 'Under a header')),
                SizedBox(height: t.space(3)),
                _Framed(height: 260, child: _Page(under: 0, foot: true, safeTop: 28, title: null)),
                _Note('The second has no header: the page fades into the status bar, 28px here, and is soft for a band below it.'),
              ]),

              _Section('A column beside a page', [
                _Framed(
                  height: 260,
                  child: Row(
                    children: [
                      SizedBox(width: 140, child: _Page(under: 44, foot: false, title: 'Column', short: true)),
                      Container(width: t.len('app-line'), color: t.color('glacier-border')),
                      const Expanded(child: _Page(under: 0, foot: false, safeTop: 0, title: null)),
                    ],
                  ),
                ),
                _Note('Each blurs only once it is scrolled off its top, and the blur turns in over a sixth of a second.'),
              ]),

              _Section('A board’s lane', [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final height in const [220.0, 96.0]) ...[
                      Expanded(child: _Lane(height: height)),
                      if (height == 220) SizedBox(width: t.space(3)),
                    ],
                  ],
                ),
                _Note('A short lane’s blur runs half its height at most. Scrolled to its end, a lane is drawn as it is.'),
              ]),

              _Section('The tab row’s ends', [const _Tabs()]),

              _Section('Words out of a blur', [
                SizedBox(
                  height: t.len('app-title') * 1.3 * 2,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: WispText(_headlines[_words % _headlines.length], pace: 16, style: t.textAt(t.len('app-title'), weight: 'bold', height: 1.2)),
                  ),
                ),
                SizedBox(height: t.space(2)),
                Wrap(
                  spacing: t.space(4),
                  children: [
                    AppPill(onPressed: () => setState(() => _words += 1), child: const Text('Next line')),
                    AppWord(onPressed: () => setState(() => _words = _words.isEven ? 1 : 0), child: const Text('Swap one word')),
                  ],
                ),
              ]),

              _Section('The dock’s halo', [const _Framed(height: 320, child: _Dock())]),

              _Section('The ghost', [
                Wrap(
                  spacing: t.space(4),
                  runSpacing: t.space(5),
                  children: [
                    for (final scene in GhostScene.values)
                      SizedBox(
                        width: 100,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Ghost(scene: scene, heightShare: 0.2),
                            SizedBox(height: t.space(1)),
                            Text(scene.name, style: t.text('xs', color: muted)),
                          ],
                        ),
                      ),
                  ],
                ),
                SizedBox(height: t.space(5)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Ghost(scene: GhostScene.update, size: GhostSize.tiny, color: t.color('app-ink')),
                    SizedBox(width: t.space(4)),
                    const GhostMark(size: 72),
                    SizedBox(width: t.space(4)),
                    Expanded(child: Text('In a card, in the page’s full ink; and the mark, drawn from its shapes.', style: t.text('sm', color: muted))),
                  ],
                ),
              ]),

              _Section('The app’s own icons', [
                for (final wash in const [true, false]) ...[
                  Text(wash ? 'With their wash' : 'Lines alone', style: t.text('sm', color: muted)),
                  SizedBox(height: t.space(2)),
                  Wrap(
                    spacing: t.space(4),
                    runSpacing: t.space(3),
                    children: [
                      const HouseIcon(size: 26),
                      for (final icon in AppIcons.all.values) DrawnIconView(icon, size: 26, wash: wash),
                    ],
                  ),
                  SizedBox(height: t.space(4)),
                ],
                Text.rich(
                  TextSpan(children: [
                    DrawnIconView.span(AppIcons.pin, em: t.fontSize('lg')),
                    const TextSpan(text: ' Pinned sits on the words’ own line, a little under it, '),
                    DrawnIconView.span(AppIcons.cassette, em: t.fontSize('lg')),
                    const TextSpan(text: ' as Tapes does.'),
                  ]),
                  style: t.text('lg', weight: 'semibold'),
                ),
              ]),

              _Section('The kit’s icons', [
                for (final (label, wash, stroke) in const [('Washed, stroke 2.2', true, 2.2), ('Outline alone, stroke 2', false, 2.0)]) ...[
                  Text(label, style: t.text('sm', color: muted)),
                  SizedBox(height: t.space(2)),
                  Wrap(
                    spacing: t.space(3),
                    runSpacing: t.space(3),
                    children: [for (final icon in Lucide.all.values) AppIcon(icon, size: 22, strokeWidth: stroke, wash: wash)],
                  ),
                  SizedBox(height: t.space(4)),
                ],
              ]),

              _Section('Cogs and a lid', [
                DefaultTextStyle.merge(
                  style: t.text('lg'),
                  child: const Row(children: [WorkingGears(label: 'Downloading'), Text('Downloading the new version')]),
                ),
                SizedBox(height: t.space(4)),
                DefaultTextStyle.merge(style: t.textAt(56), child: const Row(children: [WorkingGears(), Text('Working')])),
                SizedBox(height: t.space(4)),
                TipsShape(size: 120, color: t.color('app-ink-2')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(top: t.space(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [AppEyebrow(title), SizedBox(height: t.space(3)), ...children],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.words);
  final String words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(padding: EdgeInsets.only(top: t.space(2)), child: Text(words, style: t.text('sm', color: t.color('glacier-text-muted'))));
  }
}

/// A box on the page for one demonstration: the page's own ground, a line round it.
class _Framed extends StatelessWidget {
  const _Framed({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: t.color('glacier-bg'), border: Border.all(color: t.color('glacier-border'), width: t.len('app-line')), borderRadius: BorderRadius.circular(t.radius('lg'))),
      child: child,
    );
  }
}

/// A page of words that scrolls under a header [under] px tall (none at 0), wearing the edge's blur.
class _Page extends StatelessWidget {
  const _Page({required this.under, required this.foot, this.title, this.safeTop, this.short = false});
  final double under;
  final bool foot;
  final String? title;
  final double? safeTop;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = short ? t.space(3) : t.space(4);
    return Stack(
      children: [
        Positioned.fill(
          child: BlurEdge(
            under: under,
            foot: foot,
            safeTop: safeTop,
            child: ListView(
              padding: EdgeInsets.fromLTRB(pad, under + (safeTop ?? 0) + t.space(3), pad, t.space(6)),
              children: [
                for (var i = 0; i < _lines.length * 2; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: t.space(3)),
                    child: Text(_lines[i % _lines.length], style: i % 5 == 0 ? t.text('lg', weight: 'semibold') : t.text(short ? 'sm' : 'md')),
                  ),
              ],
            ),
          ),
        ),
        if (title != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: under,
            // `.app-headerPane`: the page's ground at the glass's mix, over what runs beneath.
            child: Container(
              color: t.color('glacier-bg').withValues(alpha: 0.66),
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Text(title!, style: t.text(short ? 'sm' : 'md', weight: 'semibold')),
            ),
          ),
      ],
    );
  }
}

/// A board's lane: cards in a column that scrolls, its foot soft while there is more below.
class _Lane extends StatefulWidget {
  const _Lane({required this.height});
  final double height;

  @override
  State<_Lane> createState() => _LaneState();
}

class _LaneState extends State<_Lane> {
  bool _more = true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: widget.height,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _look(n.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _look(n.metrics),
          child: BlurFoot(
            more: _more,
            plainFade: 1.2 * t.fontSize('sm'),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < 9; i++)
                  Container(
                    margin: EdgeInsets.only(bottom: t.space(2)),
                    padding: EdgeInsets.all(t.space(3)),
                    decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('md'))),
                    child: Text(_lines[(i + 2) % _lines.length], style: t.text('sm'), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _look(ScrollMetrics metrics) {
    final more = metrics.maxScrollExtent - metrics.pixels > 4;
    if (more != _more) scheduleMicrotask(() => mounted ? setState(() => _more = more) : null);
    return false;
  }
}

/// A row of tabs that scrolls sideways, each open end soft.
class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  bool _start = false, _end = true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const names = ['Planning the weekend', 'Shopping', 'Launch week', 'Ideas', 'The ferry', 'Reading', 'This sprint', 'Letters'];
    return SizedBox(
      height: 44,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _look(n.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _look(n.metrics),
          child: BlurSides(
            start: _start,
            end: _end,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final name in names)
                  Container(
                    margin: EdgeInsets.only(right: t.space(2)),
                    padding: EdgeInsets.symmetric(horizontal: t.space(4)),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-strong'), width: t.len('app-line')), borderRadius: BorderRadius.circular(t.radius('full'))),
                    child: Text(name, style: t.text('sm', weight: 'medium')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _look(ScrollMetrics metrics) {
    if (metrics.axis != Axis.horizontal) return false;
    final past = metrics.maxScrollExtent;
    final start = past > 1 && metrics.pixels > 1, end = past > 1 && metrics.pixels < past - 1;
    if (start != _start || end != _end) {
      scheduleMicrotask(() {
        if (mounted) {
          setState(() {
            _start = start;
            _end = end;
          });
        }
      });
    }
    return false;
  }
}

/// A page with a dock floating over its foot, the halo round it.
class _Dock extends StatelessWidget {
  const _Dock();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-ring');
    Widget round(Widget icon) => Container(
          width: ring,
          height: ring,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: t.color('glacier-bg'), shape: BoxShape.circle, border: Border.all(color: t.color('glacier-border-strong'), width: t.len('app-line'))),
          child: icon,
        );
    return DockBlur(
      padding: EdgeInsets.only(bottom: t.space(6)),
      behind: BlurEdge(
        foot: true,
        safeTop: 0,
        child: ListView(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(16)),
          children: [
            for (var i = 0; i < _lines.length * 2; i++) Padding(padding: EdgeInsets.only(bottom: t.space(3)), child: Text(_lines[i % _lines.length], style: t.text('md'))),
          ],
        ),
      ),
      dock: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          round(AppIcon(Lucide.search, size: 18, strokeWidth: 2.2, color: t.color('glacier-text'))),
          SizedBox(width: t.space(2)),
          round(DrawnIconView(AppIcons.plus, size: 18, color: t.color('glacier-text'))),
          SizedBox(width: t.space(2)),
          AppPill(onPressed: () {}, child: const Text('Speak')),
        ],
      ),
    );
  }
}
