/// The templates on a new note's blank page (docs/DESIGN.md §144), under its names. A port of
/// `src/app/notes/TemplateCards.tsx` with TemplateCards.module.css. Matt, when he chose where: "cards on the blank
/// page".
///
/// A card for each template (lib/notes/note_templates.dart), one to a row on a phone and as many as fit 15rem from
/// 600px, each the top of the note it makes drawn small, then its name and its sentence. A card's tap turns the
/// blank note into that template. Every card's picture is the same height, so a row's names sit on one line.
///
/// **A card is a button**, named by the template and described by its sentence; what is drawn in it says nothing and
/// takes no press. **One map**: A map at the top draws its header above its words, and is the only card with a map.
/// It is not drawn where the device can never say where it is, and is dimmed with its reason under Local only or a
/// refusal that still stands, where a press only buzzes. **A day** whose name today is taken says so, and draws the
/// `(2)` it will write.
///
/// Once there is a Templates notebook (lib/notes/own_templates.dart), the cards are its pages, in its order; the last
/// card, Your templates, makes that notebook the first time and opens it.
///
/// What differs:
/// - **This is not held to the page by measurement.** The cards are drawn on a new note's blank page, which is the
///   editor's (stage 4); the rules below are the stylesheet's, read and translated, and no rectangle of them was
///   measured on the running page.
/// - **The note's top is `MarkdownView` with `whole`** (the page's `NotePeek` with `whole`, `look`, `openHeading`,
///   `eager`): the note's own ink and heading proportions at the card's scale. A heading left open says `A name` in
///   the heading's own ink, not the hint's faint one.
/// - **A map at the top's header** (`editor/MapCard.tsx` `MapPicture`) is not ported: [TemplateCards.mapHeader]
///   builds it, and without one the card draws its words alone. Whether the device can say where it is, Local only,
///   and a refusal that stands are handed in ([TemplateCards.canLocate], [TemplateCards.localOnly],
///   [TemplateCards.refused]), where the page asked `core/location.ts` and the preferences; [TemplateCards.canLocate]
///   is false until something can, which leaves the map's card out, as on the Mac.
/// - "A press that keeps the editor's focus" is the page's (`preventDefault` on the press): a Flutter press takes no
///   focus from a field unless it asks for it, and these do not ([GlacierPressable.canRequestFocus] false).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/preferences.dart';
import '../home/home_parts.dart';
import '../home/home_text.dart';
import '../editor/markdown_view.dart';
import 'note_templates.dart';
import 'own_templates.dart';

/// The template cards (`src/app/notes/TemplateCards.tsx`). The picture is lib/home's hand-drawn peek, the map's
/// header is a seam, and what the device can do is handed in; see the library doc. Not measured against the page.
class TemplateCards extends StatelessWidget {
  const TemplateCards({
    super.key,
    required this.at,
    required this.taken,
    required this.onChoose,
    this.templates,
    this.onYours,
    this.canLocate = false,
    this.localOnly = false,
    this.refused,
    this.mapHeader,
    this.windowWidth,
    this.simple,
  });

  /// The minute the notes would be made in.
  final DateTime at;

  /// Every note's title key, archived and in the Trash too.
  final Set<String> taken;
  final ValueChanged<NoteTemplate> onChoose;

  /// Your own, the pages of your Templates notebook; absent, the eight built in.
  final List<NoteTemplate>? templates;

  /// Your templates: the notebook they are kept in, made the first time. Absent, no such card.
  final VoidCallback? onYours;

  /// Whether this device can ever say where it is (`locateHere().ok`); where it cannot, no map's card.
  final bool canLocate;

  /// Local only is on (the preference): a note made here keeps no place, and the map's card is dimmed.
  final bool localOnly;

  /// A refusal of location that still stands, as where to allow it (`allowLocationWhere()`: "Allow location for this
  /// site in the browser’s settings"); null where there is none.
  final String? refused;

  /// A map at the top's header, a picture (`MapPicture size="header" pin`); absent, the card draws its words alone.
  final WidgetBuilder? mapHeader;

  /// The window's width, as the stylesheet's media query asks it; the screen's where left out.
  final double? windowWidth;

  /// Simple mode (GHST-103): no cards, the blank page is its placeholder and its names. Matt: "a much more
  /// approachable UI with fancy features hidden behind more", and a blank page with eight cards on it is not that.
  /// Null asks the preferences, since the screen that draws the cards is another piece's.
  final bool? simple;

  @override
  Widget build(BuildContext context) {
    final simple = this.simple;
    if (simple != null) return simple ? const SizedBox.shrink() : _cards(context);
    return ValueListenableBuilder<Preferences>(valueListenable: preferences, builder: (context, prefs, _) => prefs.simple ? const SizedBox.shrink() : _cards(context));
  }

  Widget _cards(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(3);
    final cards = [
      for (final template in templates ?? builtIns)
        if (template.look != Look.map || canLocate) template,
    ];
    final String? mapWhy = localOnly ? 'Local only is on, so a note made here keeps no place.' : (refused != null ? '$refused for a note to keep its place.' : null);
    final yours = onYours;
    final window = windowWidth ?? MediaQuery.sizeOf(context).width;
    return Semantics(
      container: true,
      label: 'Start from a template',
      child: Padding(
        // `padding-block-start: var(--glacier-space-5)`
        padding: EdgeInsets.only(top: t.space(5)),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            // `max-inline-size: 56rem`
            constraints: BoxConstraints(maxWidth: t.lenOf('56rem')),
            child: LayoutBuilder(
              builder: (context, box) {
                // `grid-template-columns: minmax(0, 1fr)`; from 600px, `repeat(auto-fill, minmax(15rem, 1fr))`.
                final least = t.lenOf('15rem');
                final columns = window < 600 ? 1 : math.max(1, ((box.maxWidth + gap) / (least + gap)).floor());
                Widget card(NoteTemplate template) => _Card(key: ValueKey('template-${template.id}'), template: template, at: at, taken: taken, dimmed: template.look == Look.map ? mapWhy : null, mapHeader: mapHeader, onChoose: onChoose);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: gap,
                  children: [
                    if (columns == 1)
                      for (final template in cards) card(template)
                    else
                      for (var row = 0; row * columns < cards.length; row += 1)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: gap,
                            children: [
                              for (var column = 0; column < columns; column += 1) Expanded(child: row * columns + column < cards.length ? card(cards[row * columns + column]) : const SizedBox.shrink()),
                            ],
                          ),
                        ),
                    // Your templates: its words alone, across the whole row under the cards (`grid-column: 1 / -1`).
                    if (yours != null)
                      GlacierPressable(
                        key: const ValueKey('template-yours'),
                        onPressed: yours,
                        canRequestFocus: false,
                        builder: (context, state) => _box(t, state, clear: true, children: [_name(t, 'Your templates', state), _sentence(t, yourTemplatesSentence)]),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// `.name`: md, 1.25 to the line, semibold; muted while its card is pressed (`.card:active .name`).
Widget _name(Tokens t, String words, PressState state) {
  final md = t.fontSize('md');
  return CssLines(lineHeight: 1.25 * md, child: Text(words, style: pageText(t, md, weight: 'semibold', height: 1.25, color: state.pressed ? t.color('glacier-text-muted') : t.color('glacier-text'))));
}

/// `.sentence`: sm, the kit's leading for it, in the third ink.
Widget _sentence(Tokens t, String words) {
  final sm = t.fontSize('sm');
  return CssLines(lineHeight: t.len('glacier-leading-sm') * sm, child: Text(words, style: pageText(t, sm, color: t.color('app-ink-3'), height: t.len('glacier-leading-sm'))));
}

/// `.card`: a home card's box: a hairline, the ink at 3% for its ground (6% under a pointer; none for `.yours`).
Widget _box(Tokens t, PressState state, {bool clear = false, required List<Widget> children}) => GlacierFocusRing(
      visible: state.focused,
      radius: t.radius('lg'),
      child: Container(
        // `padding: var(--glacier-space-3)`
        padding: EdgeInsets.all(t.space(3)),
        decoration: BoxDecoration(
          color: clear ? null : t.colorOf('color-mix(in oklch, var(--app-ink) ${state.hovered ? 6 : 3}%, transparent)'),
          border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
          borderRadius: BorderRadius.circular(t.radius('lg')),
        ),
        // `display: flex; flex-direction: column; gap: var(--glacier-space-1); text-align: start`
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: t.space(1), children: children),
      ),
    );

/// A heading with no words yet, the note's first line: `# `.
final RegExp _openHeading = RegExp(r'^(#{1,6} +)$', multiLine: true);

class _Card extends StatelessWidget {
  const _Card({super.key, required this.template, required this.at, required this.taken, required this.dimmed, required this.mapHeader, required this.onChoose});

  final NoteTemplate template;
  final DateTime at;
  final Set<String> taken;

  /// Why A map at the top cannot be pressed here, said under its name; null where it can.
  final String? dimmed;
  final WidgetBuilder? mapHeader;
  final ValueChanged<NoteTemplate> onChoose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filled = fillNoteTemplate(template, at, taken);
    final dimmed = this.dimmed;
    final sentence = dimmed ?? (template.kind == TemplateId.day && filled.renamed ? dayTakenSentence : template.sentence);
    final header = template.look == Look.map ? mapHeader : null;
    // What the card draws: A map at the top's header and the note's first lines, a picture with nothing to press in
    // it. `.drawn { block-size: var(--picture); margin-block-end: var(--glacier-space-2); overflow: hidden }`, with
    // `--picture: 7rem`.
    final drawn = ExcludeSemantics(
      child: IgnorePointer(
        child: Padding(
          padding: EdgeInsets.only(bottom: t.space(2)),
          child: SizedBox(
            height: t.lenOf('7rem'),
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                // `display: flex; flex-direction: column; gap: var(--glacier-space-2)`
                spacing: t.space(2),
                children: [
                  if (header != null) header(context),
                  // `<NotePeek … whole look openHeading />` under `.card .drawn > .words { flex: 1 1 0 }`: the top of
                  // the note it makes in the note's own ink and heading proportions, taking what the header leaves and
                  // fading at the picture's foot. A heading left open says what goes in it (editor/openHeading.ts:
                  // "A name").
                  Expanded(
                    child: MarkdownView(
                      markdown: filled.words.replaceFirstMapped(_openHeading, (found) => '${found[1]}A name'),
                      whole: true,
                      look: template.look?.name,
                      fill: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    List<Widget> words(PressState state) => [
          dimmed != null ? Opacity(opacity: 0.45, child: drawn) : drawn,
          dimmed != null ? Opacity(opacity: 0.45, child: _name(t, template.name, state)) : _name(t, template.name, state),
          _sentence(t, sentence),
        ];
    if (dimmed != null) {
      // Not a button: nothing it could make here would keep a place. A press says so with the phone's own buzz.
      final buzz = HapticsProvider.of(context);
      return Semantics(
        container: true,
        label: template.name,
        hint: sentence,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => buzz(HapticKind.warning),
          child: ExcludeSemantics(child: _box(t, const PressState(), children: words(const PressState()))),
        ),
      );
    }
    return Semantics(
      hint: sentence,
      child: GlacierPressable(
        onPressed: () => onChoose(template),
        canRequestFocus: false,
        semanticLabel: template.name,
        builder: (context, state) => _box(t, state, children: words(state)),
      ),
    );
  }
}
