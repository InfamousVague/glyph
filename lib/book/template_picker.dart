/// What a journal's entries start with, and whether they keep where they were written (../glyph docs/DESIGN.md
/// §142): the one page for both, in the New notebook sheet with Journal chosen and on a notebook's More sheet. A
/// port of `src/app/book/TemplatePicker.tsx`, `TemplatePicker.module.css` and `book/entryPlace.ts`.
///
/// Five choices, the presets and your own (journal.dart). Your own opens a box to write it in, in the note's own
/// face, with the placeholders under it to tap in at the caret, and the one rule a format has (lib/core/template.dart:
/// words go in square brackets). Under the choice, the page an entry would start as now, filled with this minute
/// and drawn by the note's own renderer, read-only, in the view a new note opens in (Settings' Show), so the page
/// shown is the page opened. On the Fold opened out the preview sits beside the choice.
///
/// "With where you are" is the journal's choice, and travels in its file. What protects a device stays that
/// device's: Local only, a device that cannot say where it is, a refusal kept, and the system's prompt only ever
/// from a press. So turning it on asks here, and the hint says why it cannot keep a place on this device when it
/// cannot.
///
/// What differs:
/// - **The device's side of a place is handed in** ([EntryPlaceDevice]): whether a fix can be asked for, a refusal
///   that stands, where to allow it again and the ask a press makes, where the page asked `core/location.ts`. Left
///   out, the device can, nothing was refused and nothing is asked, which is this port until the phone's location
///   is wired (README, "Nothing can be added that needs the phone").
/// - **The view and the two preferences the hint reads** come from lib/core/preferences.dart's store unless given
///   ([TemplatePicker.display], [TemplatePicker.asksName]).
/// - `position: sticky` on the wide layout's preview is not carried: the sheet scrolls as one.
/// - `resize: vertical` on the box is a pointer's handle; the box grows with what is written, as `field-sizing:
///   content` grows it.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/item_syntax.dart' show jsTrim;
import '../core/location.dart' show LocateFailure;
import '../core/preferences.dart' show preferences;
import '../core/template.dart' show fillTemplate;
import '../editor/looks/look.dart';
import '../editor/state/state.dart';
import '../editor/view/base.dart';
import '../editor/view/column.dart';
import '../editor/view/editor_view.dart';
import '../editor/view/view_mode.dart';
import '../sheet/css.dart';
import '../sheet/flow.dart';
import '../sheet/kit.dart';
import 'book_view.dart' show BookField;
import 'journal.dart';

/// Why entries made here keep no place, where the device itself cannot say (`CANNOT`).
const Map<LocateFailure, String> _cannot = <LocateFailure, String>{
  LocateFailure.localOnly: 'Local only is on, so entries made here keep no place.',
  LocateFailure.mac: 'This Mac can’t say where it is. Entries made on the phone keep theirs.',
  LocateFailure.unavailable: 'Update Ghost.md to keep where entries were written.',
  LocateFailure.none: 'This browser can’t say where you are.',
};

/// Where location is allowed again after a refusal, as a sentence's start (`allowLocationWhere()`): the phone's
/// settings, where Ghost.md is an app.
const String allowLocationOnPhone = 'Allow location for Ghost.md in the phone’s settings';

/// What a journal's "With where you are" says under its switch (`entryPlaceHint`): what keeping a place means on
/// this device, or why entries made here keep none. A fixed sentence for each state, never a name pasted into a
/// frame. [cannot] is why a fix cannot be asked for here at all, or null where it can.
String entryPlaceHint({LocateFailure? cannot, LocateFailure? refused, required bool asksName, String allowWhere = allowLocationOnPhone}) {
  final why = cannot == null ? null : _cannot[cannot];
  if (why != null) return why;
  if (refused == LocateFailure.refused || refused == LocateFailure.blocked) return 'Ghost.md wasn’t allowed to know where you are. $allowWhere, then turn this on again.';
  return asksName ? 'Each entry keeps where you are. Its name is asked of OpenStreetMap once.' : 'Each entry keeps where you are.';
}

/// This device's side of keeping a place (`canLocate`, `autoTagRefusal`, `allowLocationWhere`, `askFromPress` of
/// core/location.ts), handed to the picker.
@immutable
class EntryPlaceDevice {
  const EntryPlaceDevice({this.cannot, this.refused, this.allowWhere = allowLocationOnPhone, this.ask});

  /// Why a fix cannot be asked for here at all; null where it can.
  final LocateFailure? Function()? cannot;

  /// A refusal that still stands.
  final LocateFailure? Function()? refused;
  final String allowWhere;

  /// The system's prompt, from the press that turned the switch on; answers why it failed, or null.
  final Future<LocateFailure?> Function()? ask;
}

/// The placeholders a tap puts in at the caret (`CHIPS`).
const List<String> templateChips = <String>['{{date}}', '{{time}}', '{{weekday}}', '{{title}}', '{{journal}}'];

/// What a journal's entries start with, and whether they keep where they were written (`TemplatePicker`). Put it
/// among a [Sheet]'s children: it is a block of the sheet's flow.
class TemplatePicker extends StatefulWidget {
  const TemplatePicker({super.key, required this.template, required this.onTemplate, required this.place, required this.onPlace, required this.name, this.note, this.device = const EntryPlaceDevice(), this.display, this.asksName, this.clock});

  final String template;
  final ValueChanged<String> onTemplate;
  final bool place;
  final ValueChanged<bool> onPlace;

  /// The journal's name, for `{{journal}}` in the preview.
  final String name;

  /// A line under the choice: on a journal's own page, that a change is for entries from then on.
  final String? note;
  final EntryPlaceDevice device;

  /// The view a new note opens in (Settings' Show); the preference where it is left out.
  final NoteView? display;

  /// Whether a place's name is asked for (`placeNames` and not `localOnly`); the preferences where it is left out.
  final bool? asksName;

  /// The minute the preview is filled for; this one where it is left out.
  final DateTime Function()? clock;

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  /// Which choice is ticked: your own stays your own while its words happen to be a preset's.
  late String _choice = presetOf(widget.template);
  late final TextEditingController _box = TextEditingController(text: widget.template);
  final FocusNode _boxFocus = FocusNode(debugLabel: 'Your own template');
  LocateFailure? _refusedHere;

  @override
  void didUpdateWidget(TemplatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Controlled: the template is the parent's.
    if (widget.template != _box.text) _box.value = TextEditingValue(text: widget.template, selection: TextSelection.collapsed(offset: widget.template.length));
  }

  @override
  void dispose() {
    _box.dispose();
    _boxFocus.dispose();
    super.dispose();
  }

  void _pick(String id) {
    setState(() => _choice = id);
    if (id != ownTemplate.id) widget.onTemplate(entryPresets.firstWhere((preset) => preset.id == id).text);
  }

  /// A placeholder put in at the caret, the caret after it and the box focused.
  void _insert(String chip) {
    final text = _box.text;
    final selection = _box.selection;
    final from = selection.isValid ? selection.start : text.length;
    final to = selection.isValid ? selection.end : text.length;
    final next = '${text.substring(0, from)}$chip${text.substring(to)}';
    _box.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: from + chip.length));
    _boxFocus.requestFocus();
    widget.onTemplate(next);
  }

  void _flipPlace(bool on) {
    widget.onPlace(on);
    setState(() => _refusedHere = null);
    // The prompt from this press, where it has never been answered: the first entry is not the first ask.
    final ask = widget.device.ask;
    if (on && ask != null) {
      ask().then((why) {
        if (mounted) setState(() => _refusedHere = why == LocateFailure.refused || why == LocateFailure.blocked ? why : null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final prefs = preferences.value;
    final display = widget.display ?? (prefs.noteView == 'formatted' ? NoteView.formatted : NoteView.mixed);
    final now = widget.clock?.call() ?? DateTime.now();
    final name = jsTrim(widget.name);
    final filled = fillTemplate(widget.template, at: now, title: entryTitle(now), journal: name.isEmpty ? 'Journal' : name);
    final hint = entryPlaceHint(
      cannot: widget.device.cannot?.call(),
      refused: _refusedHere ?? widget.device.refused?.call(),
      asksName: widget.asksName ?? (prefs.placeNames && !prefs.localOnly),
      allowWhere: widget.device.allowWhere,
    );
    final sm = t.fontSize('sm');
    final md = t.fontSize('md');
    final subtle = t.color('glacier-text-subtle');
    final ink = t.color('glacier-text');
    final strong = t.color('glacier-border-strong');
    final appLine = snapBorder(context, t.len('app-line'));
    final noteFace = LookEnv.page(t).noteFamilies;
    TextStyle inNoteFace(TextStyle style) => style.copyWith(fontFamily: noteFace.first, fontFamilyFallback: noteFace.skip(1).toList());

    final choice = CssFlow(
      key: const ValueKey('template-choice'),
      children: [
        const SheetHeading('Each entry starts with'),
        SheetGroup(
          children: [
            for (final preset in entryPresets) SheetRow(key: ValueKey('template:${preset.id}'), label: preset.name, chosen: _choice == preset.id, onPress: () => _pick(preset.id)),
            SheetRow(key: ValueKey('template:${ownTemplate.id}'), label: ownTemplate.name, chosen: _choice == ownTemplate.id, onPress: () => _pick(ownTemplate.id)),
          ],
        ),
        if (widget.note != null)
          CssFlow.block(
            // `.note { margin-block: calc(-1 * var(--glacier-space-1)) var(--glacier-space-3);
            // padding-inline: var(--glacier-space-1) }`: a negative margin, taken here from the card's above.
            margin: EdgeInsets.only(bottom: t.space(3)),
            padding: EdgeInsets.symmetric(horizontal: t.space(1)),
            child: Transform.translate(offset: Offset(0, -t.space(1)), child: Text(widget.note!, style: pageText(t, sm, color: subtle))),
          ),
        if (_choice == ownTemplate.id)
          CssFlow.block(
            key: const ValueKey('template-own'),
            // `.own { display: grid; gap: var(--glacier-space-2); margin-block-end: var(--glacier-space-3) }`
            margin: EdgeInsets.only(bottom: t.space(3)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: t.space(2),
              children: [
                // Your own template, in the note's face: four lines to start, growing with what is written.
                BookField(
                  key: const ValueKey('template-box'),
                  label: 'Your own template',
                  controller: _box,
                  focusNode: _boxFocus,
                  placeholder: '# {{date}}',
                  lines: null,
                  spellCheck: false,
                  // `min-block-size: 6.5lh`
                  minHeight: 6.5 * t.len('glacier-leading-md') * md,
                  style: inNoteFace(t.textAt(md, color: ink, height: t.len('glacier-leading-md'))),
                  // `padding: var(--glacier-space-3) var(--glacier-space-4)`, inside `border: var(--app-line) solid strong`.
                  padding: EdgeInsets.symmetric(vertical: t.space(3) + appLine, horizontal: t.space(4) + appLine),
                  decoration: (focused) => BoxDecoration(
                    color: t.color('glacier-bg'),
                    borderRadius: BorderRadius.circular(t.radius('lg')),
                    // `.box:focus { border-color: var(--glacier-text) }`
                    border: Border.all(color: focused ? ink : strong, width: appLine),
                  ),
                  onChange: widget.onTemplate,
                ),
                Semantics(
                  container: true,
                  label: 'Placeholders',
                  // `.chips { display: flex; flex-wrap: wrap; gap: var(--glacier-space-2) }`
                  child: Wrap(
                    spacing: t.space(2),
                    runSpacing: t.space(2),
                    children: [
                      for (final chip in templateChips)
                        GlacierPressable(
                          key: ValueKey('template-chip:$chip'),
                          semanticLabel: chip,
                          excludeSemantics: true,
                          onPressed: () => _insert(chip),
                          builder: (context, state) => Container(
                            // `.chip { min-block-size: 2rem; padding: 0 var(--glacier-space-3); border: var(--app-line)
                            // solid strong; border-radius: full }`, and `:active { background: var(--app-wash) }`.
                            constraints: BoxConstraints(minHeight: t.lenOf('2rem')),
                            padding: EdgeInsets.symmetric(horizontal: t.space(3)),
                            decoration: BoxDecoration(border: Border.all(color: strong, width: appLine), borderRadius: BorderRadius.circular(999), color: state.pressed ? t.color('app-wash') : null),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [Text(chip, style: inNoteFace(pageText(t, sm, color: ink)))]),
                          ),
                        ),
                    ],
                  ),
                ),
                Text('Words inside a format go in square brackets, as in {{date:D MMMM [at] HH:mm}}.', style: pageText(t, sm, color: subtle)),
              ],
            ),
          ),
      ],
    );

    final preview = Semantics(
      container: true,
      label: 'How a new entry starts',
      child: Container(
        key: const ValueKey('template-preview'),
        // `.preview { display: grid; gap: var(--glacier-space-2); padding: var(--glacier-space-4);
        // border-radius: var(--glacier-radius-lg); background: var(--glacier-bg) }`
        padding: EdgeInsets.all(t.space(4)),
        decoration: BoxDecoration(color: t.color('glacier-bg'), borderRadius: BorderRadius.circular(t.radius('lg'))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(2),
          children: [
            if (widget.place) Text('Where you are, with the map, at the top.', style: pageText(t, sm, color: subtle)),
            if (jsTrim(filled).isNotEmpty) EntryPreviewPage(key: const ValueKey('template-page'), words: filled, display: display) else Text('An empty page.', style: pageText(t, sm, color: subtle)),
          ],
        ),
      ),
    );

    final place = SheetGroup(
      key: const ValueKey('template-place'),
      children: [
        // `.switchRow`: a row of the sheet with its switch at the end. The switch is the press, not the row.
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: t.space(12)),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: t.space(3), horizontal: t.space(4)),
            child: IconTheme(
              data: IconThemeData(color: ink, size: md),
              child: Row(
                spacing: t.space(3),
                children: [
                  const SheetIcon(icon: DrawnIconView(AppIcons.locate, size: 18)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: [
                        Text('With where you are', style: pageText(t, md, weight: 'medium', color: ink)),
                        Text(hint, key: const ValueKey('template-place-hint'), style: pageText(t, sm, color: subtle)),
                      ],
                    ),
                  ),
                  Semantics(label: 'With where you are', child: GlacierSwitch(key: const ValueKey('template-place-switch'), checked: widget.place, onCheckedChange: _flipPlace)),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    // `.preview { margin-block: var(--glacier-space-2) var(--glacier-space-3) }`
    Widget previewBlock() => CssFlow.block(margin: EdgeInsets.only(top: t.space(2), bottom: t.space(3)), child: preview);

    return LayoutBuilder(
      builder: (context, box) {
        // `@container journal-template (min-width: 44rem)`: the preview beside the choice.
        if (box.maxWidth >= t.lenOf('44rem')) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: t.space(5),
            children: [
              Expanded(child: CssFlow(children: [choice, place])),
              Expanded(child: CssFlow(children: [previewBlock()])),
            ],
          );
        }
        return CssFlow(children: [choice, previewBlock(), place]);
      },
    );
  }
}

/// The page as a note draws it, in the note's own face, in a room with no ground, gutter or caret of its own, and
/// small (`.page`): the note's reading size and its headings' sizes brought down to the sheet's, so an entry's date
/// heading is a preview and not a poster.
class EntryPreviewPage extends StatefulWidget {
  const EntryPreviewPage({super.key, required this.words, required this.display});

  final String words;
  final NoteView display;

  @override
  State<EntryPreviewPage> createState() => _EntryPreviewPageState();
}

class _EntryPreviewPageState extends State<EntryPreviewPage> {
  late EditorView _view = _make();

  EditorView _make() => EditorView(
        wholeDocument: true,
        state: EditorState.create(doc: widget.words, extensions: noteExtensions(display: widget.display, readOnly: true)),
      );

  @override
  void didUpdateWidget(EntryPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.words != widget.words || oldWidget.display != widget.display) {
      _view.destroy();
      _view = _make();
    }
  }

  @override
  void dispose() {
    _view.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final env = LookEnv(
      t: t,
      // `--app-body: sm; --app-h1: lg; --app-h2, --app-h3: md; --app-h4 to --app-h6: sm; --app-gutter: 0px`
      body: t.fontSize('sm'),
      headings: <double>[t.fontSize('lg'), t.fontSize('md'), t.fontSize('md'), t.fontSize('sm'), t.fontSize('sm'), t.fontSize('sm')],
      gutter: 0,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      dark: t.isDark,
      tabSize: _view.state.tabSize,
      contentTop: 0,
      contentBottom: 0,
    );
    return ExcludeSemantics(child: IgnorePointer(child: EditorColumn(view: _view, env: env)));
  }
}
