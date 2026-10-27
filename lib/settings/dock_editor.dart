import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart' show Lucide, LucideIcon;
import '../book/row_drag.dart';
import '../claude/claude_mark.dart';
import '../core/preferences.dart';
import '../home/home_icons.dart';
import '../sheet/css.dart' show lucide;
import '../shell/page_dock.dart';
import 'kit/settings_kit.dart';
import 'kit/settings_type.dart';
import 'settings_search.dart';

/// What Settings' search finds of the dock on Appearance: the one card, by the name it draws, in either mode.
const SettingsFindable dockFindable = SettingsFindable('Dock', 'buttons order reorder rearrange hide show claude search market settings microphone mic speak talk fold wide phone');

/// One of the app's buttons as the editor lists it: its name, what it is, and its mark.
typedef _Button = ({String label, String hint, LucideIcon? icon, HomeGlyph? glyph});

const Map<String, _Button> _buttons = {
  'claude': (label: 'Ask Claude', hint: 'Where the Claude plugin is on.', icon: null, glyph: null),
  'talk': (label: 'Talk to Claude', hint: 'While it is on the dock, Speak is not: one microphone.', icon: null, glyph: HomeGlyph.mic),
  'search': (label: 'Search', hint: 'Notes and commands.', icon: null, glyph: HomeGlyph.magnifier),
  'add': (label: 'Write a note', hint: 'The +.', icon: null, glyph: HomeGlyph.plus),
  'speak': (label: 'Speak', hint: 'A voice note.', icon: null, glyph: HomeGlyph.mic),
  'market': (label: 'Market', hint: 'Plugins, themes and fonts.', icon: Lucide.store, glyph: null),
  'settings': (label: 'Settings', hint: 'Always on the dock: it is the way back here.', icon: Lucide.settings, glyph: null),
};

/// The buttons simple mode's docks have (docs/DOCK.md, "Simple mode"): Claude, Talk and the Market are advanced, so
/// the editor in Simple lists only what Simple draws. What the others were set to is kept for Advanced.
const Set<String> _simpleButtons = {'search', 'add', 'speak', 'settings'};

/// The dock editor (Matt, 2026-10-27: "build the dock editor"; docs/ideas/CUSTOMIZATION_AND_SOUNDS.md idea 9):
/// Appearance's Dock card. The app's buttons as a list, dragged into order by their grips, each with a switch to show
/// or hide it, beside the dock drawn as it will be; and Reset to default. Settings has no switch: on a phone the
/// dock's cog is the way into Settings that is always in reach, so it is never hidden (lib/core/dock_layout.dart
/// `dockKeptIds`), and the row says so.
///
/// The phone and a wide window (the Fold opened, a tablet, a desktop) can each have their own dock: "Its own dock
/// when wide" copies the phone's to start from, and Phone or Wide chooses which is being edited. In Simple (GHST-103)
/// the list is Simple's four buttons and that choice is behind More, opened in place, as Recording's rest is.
///
/// Every change is the preferences' at once (`Preferences.dock`), so the app's own dock behind Settings, and the
/// picture here, change as the switch is touched.
class DockEditor extends StatefulWidget {
  const DockEditor({super.key, this.store});

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;

  @override
  State<DockEditor> createState() => _DockEditorState();
}

class _DockEditorState extends State<DockEditor> {
  /// Whether the wide window's dock is the one being edited, where it has its own.
  bool _editingWide = false;

  /// Simple's More, opened.
  bool _more = false;

  late final RowDrag _drag = RowDrag((from, to) => _move(from, to));

  PreferencesStore get _store => widget.store ?? preferences;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  bool get _wide => _editingWide && _store.value.dock.wide != null;

  DockLayout get _layout {
    final dock = _store.value.dock;
    return _wide ? dock.wide! : dock.phone;
  }

  void _set(DockLayout layout) {
    final wide = _wide;
    _store.update((now) => now.copyWith(dock: wide ? now.dock.withWide(layout) : now.dock.withPhone(layout)));
  }

  /// The buttons the list shows, head to foot.
  List<String> get _listed {
    final simple = _store.value.simple;
    return [for (final id in _layout.resolved) if (!simple || _simpleButtons.contains(id)) id];
  }

  /// The row at [from] put where the row at [to] stood: in the whole order, so a button the list does not show
  /// (Claude, in Simple) keeps its place among the rest.
  void _move(int from, int to) {
    final listed = _listed;
    if (from == to || from < 0 || to < 0 || from >= listed.length || to >= listed.length) return;
    final layout = _layout;
    _set(layout.moved(listed[from], layout.resolved.indexOf(listed[to])));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final t = context.tokens;
        final prefs = _store.value;
        final simple = prefs.simple;
        final dock = prefs.dock;
        final layout = _layout;
        final listed = _listed;
        final wideOwn = dock.wide != null;
        final more = !simple || _more;

        final rows = <Widget>[
          if (more)
            SettingRow(
              key: const ValueKey('dock-wide-own'),
              label: 'Its own dock when wide',
              hint: const Text('The Fold opened, a tablet or a desktop window can have a different dock from the phone.'),
              control: GlacierSwitch(
                ariaLabel: 'Its own dock when wide',
                checked: wideOwn,
                onCheckedChange: (on) {
                  // On, the wide dock starts as the phone's and is the one edited; off, a wide window draws the
                  // phone's.
                  setState(() => _editingWide = on);
                  _store.update((now) => now.copyWith(dock: now.dock.withWide(on ? now.dock.phone : null)));
                },
              ),
            ),
          if (more && wideOwn)
            SettingRow(
              label: 'Editing',
              layout: SettingRowLayout.stacked,
              control: GlacierSegmentedControl(
                key: const ValueKey('dock-editing'),
                ariaLabel: 'Which dock is being edited',
                fullWidth: true,
                size: GlacierSegmentedSize.sm,
                options: const [GlacierSegmentedOption(value: 'phone', label: Text('Phone')), GlacierSegmentedOption(value: 'wide', label: Text('Wide'))],
                value: _wide ? 'wide' : 'phone',
                onValueChange: (value) => setState(() => _editingWide = value == 'wide'),
              ),
            ),
          SettingRowBox(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, id) in listed.indexed) DragRow(key: ValueKey('dock-edit:$id'), drag: _drag, index: i, radius: t.radius('sm'), child: _row(t, i, id, listed, layout)),
                    ],
                  ),
                ),
                SizedBox(width: t.space(3)),
                // The dock as it will be drawn: a picture, so nothing in it presses or is read twice.
                ExcludeSemantics(child: IgnorePointer(child: _DockPicture(layout: layout, simple: simple))),
              ],
            ),
          ),
          SettingRow(
            key: const ValueKey('dock-reset'),
            label: 'Reset to default',
            hint: Text(_wide ? 'The wide dock as it came: every button, in its first order.' : 'Every button, in the order the dock came in.'),
            control: RowAction(onPress: () => _set(DockLayout.defaults), disabled: layout.isDefault, child: const Text('Reset')),
          ),
          if (!more)
            SettingRow(
              key: const ValueKey('dock-more'),
              label: 'More',
              hint: const Text('A different dock on the Fold opened, a tablet or a desktop.'),
              control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
            ),
        ];
        return PaneSection(
          title: 'Dock',
          description: const Text('The round buttons in the corner of every page. Drag to change their order; switch off the ones you do not use.'),
          children: rows,
        );
      },
    );
  }

  /// One button: its grip, its mark, its name over what it is, and its switch.
  Widget _row(Tokens t, int i, String id, List<String> listed, DockLayout layout, {bool ghost = false}) {
    final button = _buttons[id]!;
    final kept = dockKeptIds.contains(id);
    final shown = layout.shows(id);
    final em = t.fontSize('md');
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(button.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, em, weight: 'medium', color: shown ? null : t.color('app-ink-3'))),
        Text(button.hint, style: pageText(t, t.fontSize('xs'), height: t.len('glacier-leading-sm'), color: t.color('app-ink-3'))),
      ],
    );
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: t.space(1)),
      child: Row(
        spacing: t.space(2),
        children: [
          SizedBox(
            width: 1.4 * em,
            child: ghost
                ? SizedBox(height: 2 * em, child: Center(child: lucide(Lucide.gripVertical, size: 16, color: t.color('glacier-text-subtle'))))
                : RowGrip(
                    key: ValueKey('dock-grip:$id'),
                    drag: _drag,
                    index: i,
                    count: listed.length,
                    em: em,
                    radius: BorderRadius.circular(t.radius('sm')),
                    ghost: (context) => ColoredBox(color: t.color('app-paper-2'), child: _row(t, i, id, listed, layout, ghost: true)),
                  ),
          ),
          ExcludeSemantics(child: Opacity(opacity: shown ? 1 : 0.45, child: _Mark(id: id, size: 1.75 * em))),
          Expanded(child: words),
          if (!ghost)
            GlacierSwitch(
              key: ValueKey('dock-show:$id'),
              ariaLabel: kept ? '${button.label}, always on the dock' : 'Show ${button.label} on the dock',
              checked: shown,
              disabled: kept,
              onCheckedChange: kept ? null : (on) => _set(layout.showing(id, on)),
            ),
        ],
      ),
    );
    if (ghost) return row;
    // The grip says nothing to a screen reader (lib/book/row_drag.dart); moving is said as the row's own actions.
    final last = listed.length - 1;
    return Semantics(
      customSemanticsActions: {
        if (i > 0) CustomSemanticsAction(label: 'Move ${button.label} up'): () => _move(i, i - 1),
        if (i < last) CustomSemanticsAction(label: 'Move ${button.label} down'): () => _move(i, i + 1),
      },
      child: row,
    );
  }
}

/// A button's mark, small, in a ring as the dock draws it: Claude's filled orange, Talk's orange rim, Speak's ink,
/// the rest plain.
class _Mark extends StatelessWidget {
  const _Mark({required this.id, required this.size});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final button = _buttons[id]!;
    final claude = id == 'claude';
    final talk = id == 'talk';
    final speak = id == 'speak';
    final ink = claude ? claudeIvory : (talk ? claudeOrange : (speak ? t.color('app-paper') : t.color('glacier-text')));
    final Widget mark = claude
        ? ClaudeMark(size: 0.5 * size, color: ink)
        : button.glyph != null
            ? HomeIcon(button.glyph!, size: 0.5 * size, strokeWidth: 2, color: ink)
            : lucide(button.icon!, size: 0.5 * size, color: ink);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: claude ? claudeOrange : (speak ? t.color('app-ink') : t.color('glacier-bg')),
        border: claude || speak ? null : Border.all(color: talk ? claudeOrange : t.color('glacier-border-strong'), width: t.len('app-line')),
      ),
      child: mark,
    );
  }
}

/// The dock as [layout] draws it on a page of notes: the real pill ([PageDock]) with every one of the app's buttons
/// given to it, so what it hides, and the one microphone, are the dock's own rules. In Simple, Simple's four.
class _DockPicture extends StatelessWidget {
  const _DockPicture({required this.layout, required this.simple});

  final DockLayout layout;
  final bool simple;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-ring');
    void none() {}
    return PageDock(
      key: const ValueKey('dock-picture'),
      keyPrefix: 'picture',
      label: 'The dock as it will be',
      layout: layout,
      claude: simple ? null : SizedBox.square(dimension: ring, child: _Mark(id: 'claude', size: ring)),
      talk: simple ? null : SizedBox.square(dimension: ring, child: _Mark(id: 'talk', size: ring)),
      actions: [
        DockAction(id: 'search', label: 'Search and commands', glyph: HomeGlyph.magnifier, onPressed: none),
        DockAction(id: 'add', label: 'Write a note', glyph: HomeGlyph.plus, onPressed: none),
        DockAction(id: 'speak', label: 'Speak a voice note', glyph: HomeGlyph.mic, ink: true, onPressed: none),
        if (!simple) DockAction(id: 'market', label: 'Market', icon: Lucide.store, onPressed: none),
      ],
      foot: DockAction(id: 'settings', label: 'Settings', icon: Lucide.settings, onPressed: none),
    );
  }
}
