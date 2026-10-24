import 'dart:math' as math;
import 'dart:ui' show ImageFilter, SemanticsRole;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/blur_edge.dart';
import '../core/back.dart';
import '../perf/frame_log.dart';
import '../shell/desktop/mac_drag_strip.dart';
import '../shell/desktop/mac_lights.dart' show titlebarOverlay;
import '../shell/page_dock.dart';
import '../shell/wide_screen.dart' show mousePointer, splitFits;
import 'kit/settings_icons.dart';
import 'kit/settings_kit.dart';
import 'kit/settings_type.dart';
import 'section_steps.dart';
import 'settings_search.dart';
import '../app/plain.dart';

/// One section of a settings screen (`SettingsSection`, SettingsScreen.tsx): a row on the list, or a sub-page off
/// it, and the page it opens.
class SettingsSection implements SearchableSection, SectionPlace {
  const SettingsSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.content,
    this.summary,
    required this.group,
    this.hue,
    this.words,
    this.settings = const [],
    this.listed = true,
    this.parent,
    this.searched = true,
  });

  @override
  final String id;
  @override
  final String label;

  /// Its glyph, drawn in the section's colour on its chip.
  final Widget icon;

  /// Its page: usually a [PaneBody] of the kit's cards.
  final WidgetBuilder content;

  /// The row's second line: the section's state, read live.
  @override
  final String? summary;

  /// Rows with the same group share one card.
  @override
  final int group;

  /// Its colour, when it brings its own (a plugin's page says it); otherwise the one kept for its id, or grey.
  final String? hue;

  /// Other words the search finds the section by.
  @override
  final String? words;

  /// The settings on its page, by the names the page gives them, for the search to find and open onto.
  @override
  final List<SettingsFindable> settings;

  /// False keeps it off the list: a sub-page, opened from a row on its parent's page, or found by the search.
  @override
  final bool listed;

  /// The section a sub-page steps back to, and whose row is current in the split view while it shows.
  @override
  final String? parent;

  /// False keeps it out of the search's results; it still opens from a row or a link.
  @override
  final bool searched;
}

/// Where to land (`SettingsTarget` with its nonce): a section, and a setting on its page to bring into view and
/// light, by its row's or card's name. A new [nonce] asks again.
@immutable
class SettingsTarget {
  const SettingsTarget(this.id, {this.setting, required this.nonce});

  final String id;
  final String? setting;
  final int nonce;
}

/// Each section's colour (`HUES`): its row's chip in the list, and the icons on its own page. Names, not values:
/// settings.css draws each (../settings_css.dart), a shade deeper on the light page than on the dark.
const Map<String, String> _hues = {
  'account': 'blue',
  // Account's sub-page keeps its blue; Notifications wears the coral that was kept free until it.
  'organizations': 'blue',
  'notifications': 'coral',
  // Every row in a colour of its own (Matt, 2026-10-24: "make sure all settings sections icons have a color"): none
  // in grey or graphite.
  'meetings': 'orange',
  'workspaces': 'indigo',
  'daily': 'indigo',
  'library': 'cyan',
  'backup': 'lime',
  'export': 'rose',
  'import': 'rose',
  'ai': 'magenta',
  'theme': 'purple',
  'recording': 'red',
  'plugins': 'green',
  'about': 'yellow',
  'developer': 'brown',
  'test-results': 'mint',
  // The sub-pages About opens keep the cheat sheet's yellow; a plugin's brings its own.
  'cheatsheet': 'yellow',
  'examples': 'yellow',
  'spec': 'yellow',
};

/// The colours a section is drawn in where nothing names one: a section added later, or a plugin's page that brings
/// none, takes one of these by its id, never grey.
const List<String> _spareHues = ['blue', 'purple', 'red', 'coral', 'green', 'yellow', 'mint', 'amber', 'indigo', 'orange', 'cyan', 'lime', 'rose', 'magenta'];

String _spareHue(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return _spareHues[hash % _spareHues.length];
}

/// A section's colour (`hueOf`): its own, or its id's, or one picked by its id for a section added later without one.
String settingsHueOf(SettingsSection section) => section.hue ?? _hues[section.id] ?? _spareHue(section.id);

/// Whether Settings is a split view in this window: exactly the sidebar's line (core/useWideScreen.ts `useSidebar`,
/// lib/shell/wide_screen.dart), so the app changes shape once.
bool settingsSplitFits(BuildContext context) => splitFits(MediaQuery.sizeOf(context), mouse: mousePointer);

/// Marks its child as something that moves sideways itself, so a drag begun on it is not Settings' swipe
/// (`data-noswipe`, core/swipe.ts). A text field and a group of radios (the kit's segmented control and density
/// picker, the choice cards) are left alone without it.
class SettingsNoSwipe extends StatelessWidget {
  const SettingsNoSwipe({super.key, this.swipes = false, required this.child});

  /// True says the opposite: a group of radios that does not move, and swipes as the page under it does (the
  /// accent's dots, which the page drew as buttons).
  final bool swipes;
  final Widget child;

  @override
  Widget build(BuildContext context) => MetaData(metaData: swipes ? _SwipeMark.through : _SwipeMark.none, behavior: HitTestBehavior.translucent, child: child);
}

enum _SwipeMark { none, through }

/// Port of `SettingsScreen` (src/app/settings/SettingsScreen.tsx, with the shell's rules of settings.css): the
/// settings surface, a full-screen page over the app that opens on the list of sections and pushes into one, and on
/// a window with room for the sidebar is a split view with the sections down the left.
///
/// Put it over the app's screens and give it [open]; closed, it draws nothing. Every fresh open lands on the list.
/// The top bar reads `← Settings` over both the list and a page: on the list it leaves ([onClose]), over a page it
/// steps back, and over a sub-page it names the parent it steps back to. The page can also be left the way a person
/// came: the phone's back gesture or Escape (through the app's back stack, lib/core/back.dart, on which it puts one
/// handler while it is open), or a swipe to the right across it; a swipe to the left goes forward again, into the
/// page just left. [goTo] lands on a page, and on a setting there when one is named, scrolled to and lit as a search
/// hit is; each request is answered once, by its nonce.
///
/// What the shell needs: a `BackScope` (lib/core/back.dart) above it, which is what hears the system's back and
/// Escape; nothing else. With none above, the handler still goes on the app's own stack and waits for one.
///
/// What differs from the web original:
/// - The icons are Lucide's outlines without the web's wash (kit/settings_icons.dart).
/// - A section's `content` is a builder, and its page is laid out by [PaneBody] where React returned a fragment.
/// - The search field is an `EditableText` with the kit's handles and menu; the web's was an `<input type=search>`.
/// - A row shows the kit's focus ring inside its edge, where the page left the browser's own.
/// - [split] lets the shell say the shape itself; left out, it is the sidebar's line asked of this window.
/// - The Mac's title bar rule (`data-titlebar='overlay'`) is [SettingsScreenState._head]'s: the head starts under
///   the window's buttons, and their row drags the window (lib/shell/desktop/mac_drag_strip.dart).
/// - Given [dock], the dock every page has (lib/shell/page_dock.dart) floats at its bottom end corner with Claude
///   alone in it, its chat opened over Settings; the pages' foot leaves it room.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.open,
    required this.onClose,
    required this.sections,
    this.goTo,
    this.title = 'Settings',
    this.search = true,
    this.closeWord,
    this.split,
    this.dock,
  });

  final bool open;
  final VoidCallback onClose;
  final List<SettingsSection> sections;

  /// Asked from outside or from inside a pane: land on a section, and on a setting there when one is named.
  final SettingsTarget? goTo;

  /// The screen's name: over the list, in the head's way out, and in every word that would otherwise say "Settings".
  final String title;

  /// Whether the field that searches the sections stands over the list; off for a screen of a few sections.
  final bool search;

  /// What the head's way out says instead of the title, and where it goes: an organization opened from Settings ›
  /// Organizations reads "← Organizations", since closing it reopens Settings there.
  final String? closeWord;

  /// Whether to draw the split view; null asks the window ([settingsSplitFits]).
  final bool? split;

  /// Claude and the halo for the dock (docs/DOCK.md); no dock where it is left out.
  final PageDockSeam? dock;

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

/// The state of a [SettingsScreen]. Public for [back] and [forward], which a shell with gestures of its own may call.
class SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  String? _activeId;

  /// Which way the pane came in: pushed from the right going deeper, from the left coming back.
  bool _out = false;

  /// The pane a back step just left, for a forward swipe to return to.
  String? _left;
  String _query = '';
  SettingsTarget? _target;
  int? _answered;
  int? _shownTarget;
  int _targetTries = 0;
  bool _split = false;

  final TextEditingController _field = TextEditingController();
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'settings search');
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'settings');
  final List<FocusNode> _resultNodes = [];
  final SettingsFinder _finder = SettingsFinder();
  final ScrollController _paneScroll = ScrollController();
  final ScrollController _listScroll = ScrollController();
  late final AnimationController _enter = AnimationController(vsync: this);

  ({Offset at, Duration time, int pointer})? _swipe;

  /// The page showing, or null over the list.
  String? get activeId => _activeId;

  SettingsSection? get _active => _sectionOf(_activeId);

  SettingsSection? _sectionOf(String? id) {
    if (id == null) return null;
    for (final section in widget.sections) {
      if (section.id == id) return section;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _field.addListener(_onField);
    _fieldFocus.addListener(_onFocus);
    HardwareKeyboard.instance.addHandler(_onKey);
    if (widget.open) _answer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = context.tokens;
    _enter.duration = t.duration('glacier-duration-normal');
    if (widget.open && _enter.status == AnimationStatus.dismissed) _arrive();
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open && !widget.open) {
      _activeId = null;
      _left = null;
      _target = null;
      _query = '';
      _field.clear();
      _enter.value = 0;
    }
    if (!oldWidget.open && widget.open) _arrive();
    if (widget.open) _answer();
    // A section that left the list (developer mode switched off inside it) drops back to the list rather than onto
    // a pane that no longer exists.
    if (_activeId != null && _active == null) _activeId = null;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _field.dispose();
    _fieldFocus.dispose();
    _scope.dispose();
    for (final node in _resultNodes) {
      node.dispose();
    }
    _paneScroll.dispose();
    _listScroll.dispose();
    _enter.dispose();
    super.dispose();
  }

  /// `animation: settingsEnter var(--glacier-duration-normal) var(--glacier-ease-out)`.
  void _arrive() {
    if (context.tokens.reducedMotion) {
      _enter.value = 1;
    } else {
      _enter.forward(from: 0);
    }
  }

  /// Each request once, by its nonce. The sheet keeps its last one while the page is closed, and answering it again
  /// on the next open would land on the last page a link opened rather than on the list.
  void _answer() {
    final goTo = widget.goTo;
    if (goTo == null || _answered == goTo.nonce) return;
    _answered = goTo.nonce;
    _out = false;
    _left = null;
    _activeId = goTo.id;
    // A setting named with it is looked for on the page as a search hit is.
    _target = goTo.setting == null ? null : goTo;
    _lookSoon();
  }

  void _onField() {
    if (_field.text == _query) return;
    setState(() => _query = _field.text);
  }

  void _onFocus() => setState(() {});

  void _enterSection(String id) {
    setState(() {
      _out = false;
      _left = null;
      _activeId = id;
    });
  }

  /// Steps back: out of a sub-page to its parent, out of a page to the list, and from the list out of Settings. In
  /// the split view there is no list page to step back to: a sub-page steps to its parent, anything else leaves.
  void back() {
    final step = stepBack(widget.sections, _activeId);
    if (step is BackCloses || (_split && step is BackTo && step.id == null)) {
      widget.onClose();
      return;
    }
    setState(() {
      _out = true;
      _left = _activeId;
      _activeId = (step as BackTo).id;
    });
  }

  /// Goes back into the page a back step just left, from where back landed.
  void forward() {
    final to = stepForward(widget.sections, _activeId, _left);
    if (to == null) return;
    setState(() {
      _out = false;
      _left = null;
      _activeId = to;
    });
  }

  /// A result: its section's page, and when it was a setting inside it, that setting brought into view there.
  void _openHit(SettingsHit<SettingsSection> hit) {
    _enterSection(hit.section.id);
    _target = hit.setting == null ? null : SettingsTarget(hit.section.id, setting: hit.setting, nonce: DateTime.now().microsecondsSinceEpoch);
    _lookSoon();
  }

  void _lookSoon() {
    _targetTries = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _look());
  }

  /// The setting a result named, found on its page once the page is drawn: scrolled to and lit for a moment. A page
  /// can draw a frame or two late, so it is looked for over a few frames. Once, for each result opened: coming back
  /// to the same page later from the list is only opening it.
  void _look() {
    final target = _target;
    if (!mounted || !widget.open || target == null || target.setting == null) return;
    final shown = _split ? (_active ?? listedOf(widget.sections).firstOrNull) : _active;
    if (shown?.id != target.id || _shownTarget == target.nonce) return;
    final found = _finder.find(target.setting!);
    if (found == null) {
      if (++_targetTries < 12) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _look());
        WidgetsBinding.instance.scheduleFrame();
      }
      return;
    }
    _shownTarget = target.nonce;
    // Lit first: the light carries the margin a card brought in by its top keeps from the page's edge.
    found.light();
    revealSetting(found);
  }

  /// ⌘F or Ctrl+F while Settings is open goes to its field rather than to a find in the note underneath.
  bool _onKey(KeyEvent event) {
    if (!widget.open || !widget.search || event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyF) return false;
    final keys = HardwareKeyboard.instance;
    if (!keys.isMetaPressed && !keys.isControlPressed) return false;
    // In the split view the field is always there; on a phone only over the list.
    if (!_split && _activeId != null) return false;
    _fieldFocus.requestFocus();
    _field.selection = TextSelection(baseOffset: 0, extentOffset: _field.text.length);
    return true;
  }

  // --- the swipe (core/swipe.ts) -----------------------------------------------------------------------------------

  static const double _swipeDistance = 64;
  static const Duration _swipeWithin = Duration(milliseconds: 1500);

  /// A drag that began on something that moves sideways itself: text being edited, a group of radios, anything
  /// marked [SettingsNoSwipe].
  bool _ownsTheDrag(PointerDownEvent event) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    var radios = false;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderEditable) return true;
      if (target is RenderMetaData && target.metaData == _SwipeMark.none) return true;
      if (target is RenderMetaData && target.metaData == _SwipeMark.through) return false;
      if (target is RenderSemanticsAnnotations && target.properties.role == SemanticsRole.radioGroup) radios = true;
    }
    return radios;
  }

  void _swipeDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton || _ownsTheDrag(event)) return;
    _swipe = (at: event.position, time: event.timeStamp, pointer: event.pointer);
  }

  void _swipeUp(PointerUpEvent event) {
    final start = _swipe;
    if (start == null || event.pointer != start.pointer) return;
    _swipe = null;
    final d = event.position - start.at;
    final took = event.timeStamp - start.time;
    if (took > _swipeWithin || d.dx.abs() < _swipeDistance || d.dx.abs() < d.dy.abs() * 2) return;
    if (d.dx > 0) {
      // Android offers the same thumb-swipe as its own back gesture a moment later: one swipe, one step.
      BackScope.of(context).markSteppedBack();
      back();
    } else {
      forward();
    }
  }

  // --- the parts ---------------------------------------------------------------------------------------------------

  /// 1rem at the page's own size, `line-height: normal`, in the page's ink: what `.settingsScreen` hands down.
  TextStyle _body(Tokens t) => pageText(t, t.lenOf('1rem'));

  /// The way out or back in the head: the arrow, a space and a word, as one button.
  Widget _headWord(Tokens t, {required String word, required VoidCallback onPressed, String? says}) {
    final size = t.len('app-action');
    return DefaultTextStyle(
      style: pageText(t, size),
      child: SettingsWord(
        key: const ValueKey('settings-head-word'),
        onPressed: onPressed,
        color: t.color('glacier-text'),
        semanticLabel: says,
        // The word's line the page's own (`line-height: normal`: 81 device pixels for its 25.6px on the Fold, the
        // baseline 64 under its top), where the engine's whole pixel stood the word two device pixels low.
        child: ExactLines.of(
          Text.rich(
            TextSpan(children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                // `inline-size: 1em; block-size: 1em; vertical-align: -0.12em`
                child: _SitsBelowBaseline(by: size * 0.12, child: ExcludeSemantics(child: SettingsIcon(SettingsGlyph.arrowLeft, size: size, strokeWidth: 2.4))),
              ),
              TextSpan(text: ' $word'),
            ]),
            maxLines: 1,
            softWrap: false,
            style: pageText(t, size, weight: 'medium', color: t.color('glacier-text')),
          ),
          normal: true,
          dpr: t.css.lineDpr,
        ),
      ),
    );
  }

  /// `.settingsScreen__head`: one row, the word at its start.
  Widget _head(Tokens t, Widget word) {
    // On the Mac its first row met the window's three buttons, which sit where the tab bar's controls begin: there
    // it starts below their row (`:root[data-titlebar='overlay'] .settingsScreen__head`), and that row drags the
    // window, as the tab bar does.
    final overlay = titlebarOverlay(t);
    final head = Padding(
      padding: EdgeInsets.only(
        left: t.len('app-gutter-start'),
        right: t.len('app-gutter-end'),
        // Settings is drawn over everything, the app's tab bar included, so it clears the notch alone.
        top: overlay ? t.lenOf('calc(2.25rem + var(--glacier-space-1))') : t.lenOf('calc(var(--app-inset-top) + var(--glacier-space-1))'),
        bottom: t.space(1),
      ),
      child: Align(alignment: AlignmentDirectional.centerStart, child: word),
    );
    if (!overlay) return head;
    return Stack(children: [Positioned(left: 0, right: 0, top: 0, height: t.lenOf('2.25rem'), child: const MacDragStrip()), head]);
  }

  String get _searchWord => widget.title == 'Settings' ? 'Search settings' : 'Search ${widget.title}';

  /// The field at the top of the list. Enter opens the first result, the down arrow steps into them, and Escape
  /// empties the field before it is asked to close anything.
  Widget _find(Tokens t, List<SettingsHit<SettingsSection>> hits, {required EdgeInsets padding}) {
    final focused = _fieldFocus.hasFocus;
    final size = t.fontSize('md');
    return Padding(
      padding: padding,
      child: _FindField(
        controller: _field,
        focusNode: _fieldFocus,
        placeholder: _searchWord,
        height: t.len('settings-find-pill'),
        focused: focused,
        style: pageText(t, size),
        onKey: (event) {
          if (event is KeyUpEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.escape && _query.isNotEmpty) {
            _field.clear();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.enter && hits.isNotEmpty) {
            _openHit(hits.first);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && hits.isNotEmpty && _resultNodes.isNotEmpty) {
            _resultNodes.first.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        onSubmitted: () {
          if (hits.isNotEmpty) _openHit(hits.first);
        },
        onClear: () {
          _field.clear();
          _fieldFocus.requestFocus();
        },
      ),
    );
  }

  /// The sections, clustered into cards: the list page on a phone, the left column of the split view.
  List<Widget> _list(Tokens t, String? current) {
    var row = 0;
    return [
      for (final cluster in clustersOf(widget.sections))
        _Group(
          key: ValueKey('cluster ${cluster.first.id}'),
          rows: [
            for (final section in cluster)
              _SectionRow(
                key: ValueKey('row ${section.id}'),
                section: section,
                label: section.label,
                summary: section.summary,
                current: section.id == current,
                index: row++,
                split: _split,
                onPress: () => _enterSection(section.id),
              ),
          ],
        ),
    ];
  }

  void _syncResultNodes(int count) {
    while (_resultNodes.length > count) {
      _resultNodes.removeLast().dispose();
    }
    while (_resultNodes.length < count) {
      _resultNodes.add(FocusNode(debugLabel: 'settings result ${_resultNodes.length}'));
    }
  }

  /// What the field found, in place of the sections: one card of rows, a section by its own name and state, a
  /// setting by its name with its section's name under it, each in its section's colour. The arrows move between
  /// them, and Escape goes back to the field.
  List<Widget> _found(Tokens t, List<SettingsHit<SettingsSection>> hits, String? current) {
    _syncResultNodes(hits.length);
    if (hits.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.only(top: t.space(2), left: t.space(2), right: t.space(2)),
          child: Semantics(
            liveRegion: true,
            child: Text('Nothing in ${widget.title} matches “${_query.trim()}”.', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
          ),
        ),
      ];
    }
    return [
      Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyUpEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          final at = _resultNodes.indexWhere((n) => n.hasFocus);
          if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
            final next = at + (key == LogicalKeyboardKey.arrowDown ? 1 : -1);
            if (next < 0) {
              _fieldFocus.requestFocus();
            } else {
              _resultNodes[next.clamp(0, _resultNodes.length - 1)].requestFocus();
            }
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape) {
            _fieldFocus.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _Group(
          key: const ValueKey('settings-results'),
          rows: [
            for (var i = 0; i < hits.length; i++)
              // A setting says its section's name under it, so "smoke" says which of two pages each smoke is on.
              _SectionRow(
                key: ValueKey('hit ${hits[i].section.id}/${hits[i].setting ?? ''}'),
                section: hits[i].section,
                label: hits[i].setting ?? hits[i].section.label,
                summary: hits[i].setting != null ? hits[i].section.label : hits[i].section.summary,
                current: hits[i].setting == null && hits[i].section.id == current,
                index: i < 6 ? i : 6,
                split: _split,
                focusNode: _resultNodes[i],
                onPress: () => _openHit(hits[i]),
              ),
          ],
        ),
      ),
    ];
  }

  /// `.settingsScreen__list` and `.settingsScreen__pane`: the scrolling body, a column with `--glacier-space-4`
  /// between its children, ending in air.
  Widget _scroller(Tokens t, {required ScrollController controller, required EdgeInsets padding, required List<Widget> children, Key? key}) {
    final gap = t.space(4);
    return SingleChildScrollView(
      key: key,
      controller: controller,
      // `overscroll-behavior: contain`: the page under it never moves.
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
        ],
      ),
    );
  }

  /// A section's page: its name as the page's word, then what it holds, in its colour.
  Widget _pane(Tokens t, SettingsSection shown, {required EdgeInsets padding}) {
    final titleSize = t.len('app-title');
    return _Arrive(
      // A pane drilled into slides in from the right; coming back, from the left.
      key: ValueKey('pane ${shown.id} ${_out ? 'out' : 'in'}'),
      fromLeft: _out,
      child: GlacierScope(
        attrs: {'hue': settingsHueOf(shown)},
        child: SettingsPaneScope(
          finder: _finder,
          // A setting on this page still to be found and lit: the page is built whole, so it is there to find.
          whole: _target?.setting != null && _target!.id == shown.id && _shownTarget != _target!.nonce,
          child: Builder(
            // `useWispEdge(scroller, …)`, as the list: no header over the page, so it fades at its own top.
            builder: (context) => BlurEdge(child: SingleChildScrollView(
              key: ValueKey('scroll ${shown.id}'),
              controller: _paneScroll,
              padding: padding,
              // A layer of its own: the page is one box in its scroller, and without one every row and every example
              // of it was drawn again at each frame of a scroll (the cheat sheet flung on the Fold: 4.3 ms of a
              // frame's 8.3 to draw what had only moved, 415 of 561 frames late).
              child: RepaintBoundary(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // `.settingsScreen__display`: a title rather than a display word, so the rows start near the top.
                  Padding(
                    padding: EdgeInsets.only(bottom: t.space(3) + t.space(4)),
                    child: Semantics(
                      header: true,
                      // Its words where the page has them on its line of 1.15: on a phone, a whole number of device
                      // pixels over the line's top (they stood two device pixels low on the Fold).
                      child: ExactLines.of(
                        Text(
                          shown.label,
                          key: const ValueKey('settings-display'),
                          style: pageText(t, titleSize, weight: 'bold', height: 1.15, tracking: t.len('app-tracking-title', em: titleSize)),
                        ),
                        dpr: t.css.lineDpr,
                      ),
                    ),
                  ),
                  shown.content(context),
                ],
              )),
            )),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final root = context.tokens;
    _split = widget.split ?? settingsSplitFits(context);
    final split = _split;
    return GlacierScope(
      classes: const {'settingsScreen'},
      attrs: {if (split) 'layout': 'split'},
      child: Builder(builder: (context) => _screen(context, root)),
    );
  }

  Widget _screen(BuildContext context, Tokens root) {
    if (ghostPerf) Perf.count('settings.screen');
    final t = context.tokens;
    final split = _split;
    final sections = widget.sections;
    final active = _active;
    final title = widget.title;
    final searchable = widget.search;
    final hits = searchSettings(sections, _query);
    final looking = searchable && _query.trim().isNotEmpty;
    final dock = widget.dock;
    // And at least the room the dock stands in, Claude alone, so a page's last rows scroll clear of it.
    final bottom = math.max(t.lenOf('calc(var(--app-safe-bottom) + var(--glacier-space-16))'), dock == null ? 0.0 : t.len('app-safe-bottom') + pageDockRoom(t, dock.claude != null ? 1 : 0));
    final gutter = EdgeInsets.only(left: t.len('app-gutter-start'), right: t.len('app-gutter-end'));

    // The way out, over the list and over the split view: the screen's name with the arrow, leaving for the notes,
    // which is what it is told to say aloud. Given a `closeWord` it names where it goes instead, and says no more.
    Widget wayOut() => _headWord(t, word: widget.closeWord ?? title, onPressed: widget.onClose, says: widget.closeWord == null ? 'Back to your notes' : null);

    final List<Widget> body;
    if (split) {
      final shown = active ?? listedOf(sections).firstOrNull;
      final current = currentRow(sections, shown);
      // Over a sub-page the head names its parent and steps there, as back and Escape do; anywhere else it leaves.
      final sub = shown != null && current != shown.id;
      final side = t.len('settings-side');
      final hairline = t.len('glacier-hairline');
      final columnPad = EdgeInsets.only(left: t.lenOf('calc(var(--app-safe-left) + var(--glacier-space-4))'), right: t.space(4));
      // The sections start under the field, which is laid over them in the header's glass.
      final columnTop = searchable ? t.lenOf('calc(var(--glacier-space-1) + var(--settings-find-pill) + var(--glacier-space-3))') : 0.0;
      body = [
        _head(t, sub ? _headWord(t, word: backWord(sections, shown, title), onPressed: back) : wayOut()),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The left column: the search field, fixed, over the sections, which scroll under it.
              Container(
                width: side,
                decoration: BoxDecoration(border: BorderDirectional(end: BorderSide(color: t.color('glacier-border-subtle'), width: hairline))),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Semantics(
                        container: true,
                        label: looking ? '$title found' : '$title sections',
                        // `useWispEdge(column, …, findBar, { band: 'column' })`: the sections go soft under the field.
                        child: BlurEdge(
                          under: columnTop,
                          child: _scroller(
                          t,
                          key: const ValueKey('settings-list'),
                          controller: _listScroll,
                          padding: columnPad.copyWith(top: columnTop, bottom: bottom),
                          children: looking ? _found(t, hits, current) : _list(t, current),
                        )),
                      ),
                    ),
                    if (searchable)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ClipRect(
                          child: BackdropFilter(enabled: !ghostPlain, 
                            // `backdrop-filter: var(--app-glass-blur)`: blur(18px) saturate(1.1), the blur alone here.
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: ColoredBox(
                              color: t.colorOf(ghostPlain ? 'color-mix(in srgb, var(--glacier-bg) 94%, transparent)' : 'color-mix(in srgb, var(--glacier-bg) var(--app-glass-mix), transparent)'),
                              child: _find(t, hits, padding: columnPad.copyWith(top: t.space(1), bottom: t.space(3))),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (shown != null)
                Expanded(
                  // The page takes the pane's whole width, in the app's gutter.
                  child: _pane(t, shown, padding: EdgeInsets.only(left: t.len('app-gutter'), right: t.len('app-gutter-end'), bottom: bottom)),
                ),
            ],
          ),
        ),
      ];
    } else if (active != null) {
      body = [
        // The way back names where it goes: "Settings" over a pane, its parent's name over a sub-page.
        _head(t, _headWord(t, word: backWord(sections, active, title), onPressed: back)),
        Expanded(child: _pane(t, active, padding: gutter.copyWith(bottom: bottom))),
      ];
    } else {
      final list = Semantics(
        container: true,
        label: looking ? '$title found' : '$title sections',
        // `useWispEdge(scroller, …)` with no header: the list fades over its first `--app-safe-top + 8px` once scrolled,
        // and is soft for a band below that (art/blur_edge.dart).
        child: BlurEdge(
          child: _scroller(
            t,
            key: const ValueKey('settings-list'),
            controller: _listScroll,
            padding: gutter.copyWith(bottom: bottom),
            children: looking ? _found(t, hits, null) : _list(t, null),
          ),
        ),
      );
      body = [
        _head(t, wayOut()),
        if (searchable) _find(t, hits, padding: gutter.copyWith(top: t.space(1), bottom: t.space(3))),
        // The list ends in air: a left swipe still goes back into the page just left, without a line saying so.
        Expanded(child: _Arrive(key: ValueKey('list $_out'), fromLeft: true, moves: _out, child: list)),
      ];
    }

    final Widget screen = Listener(
      onPointerDown: _swipeDown,
      onPointerUp: _swipeUp,
      onPointerCancel: (_) => _swipe = null,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: t.color('sheet-ground'),
        child: DefaultTextStyle(
          style: _body(t),
          // The page ends where the keyboard begins, as the web page's window does when the keyboard comes up, so
          // what the search finds can be scrolled clear of it.
          child: () {
            final Widget page = Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
            );
            // Claude alone: the chat it opens comes up over Settings.
            return dock == null ? page : PageDockFrame(seam: dock, actions: const <DockAction>[], label: '${widget.title} actions', child: page);
          }(),
        ),
      ),
    );

    return OnBack(
      onBack: back,
      child: AnimatedBuilder(
        animation: _enter,
        builder: (context, child) {
          final v = t.curve('glacier-ease-out').transform(_enter.value.clamp(0.0, 1.0));
          // `from { opacity: 0; transform: translateY(12px) }`. The same wrappers at rest, so nothing under them is
          // made again when the arrival ends.
          return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child));
        },
        // `role="dialog" aria-modal="true" aria-label={title}`: named, and what is under it is not read.
        child: BlockSemantics(
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: title,
            child: FocusScope(node: _scope, child: FocusTraversalGroup(child: screen)),
          ),
        ),
      ),
    );
  }
}

/// A box whose baseline is [by] above its bottom edge: an inline `<svg>` with `vertical-align: -<by>`, which hangs
/// that far under the words' baseline.
class _SitsBelowBaseline extends SingleChildRenderObjectWidget {
  const _SitsBelowBaseline({required this.by, required super.child});
  final double by;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSitsBelowBaseline(by);

  @override
  void updateRenderObject(BuildContext context, _RenderSitsBelowBaseline renderObject) => renderObject.by = by;
}

class _RenderSitsBelowBaseline extends RenderProxyBox {
  _RenderSitsBelowBaseline(this._by);
  double _by;

  set by(double value) {
    if (value == _by) return;
    _by = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => size.height - _by;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => getDryLayout(constraints).height - _by;
}

/// `animation: settingsPush` or `settingsPop`, `var(--glacier-duration-normal) var(--glacier-ease-out)`: a page
/// arriving from a tenth of its width to the right, or to the left when it is come back to.
class _Arrive extends StatefulWidget {
  const _Arrive({super.key, required this.fromLeft, this.moves = true, required this.child});
  final bool fromLeft;

  /// False and it is simply there: the list on a fresh open, which only comes from the left when it is come back to.
  final bool moves;
  final Widget child;

  @override
  State<_Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<_Arrive> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final t = context.tokens;
    _controller = AnimationController(vsync: this, duration: t.duration('glacier-duration-normal'));
    if (t.reducedMotion || !widget.moves) {
      _controller!.value = 1;
    } else {
      _controller!.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = context.tokens.curve('glacier-ease-out');
    return AnimatedBuilder(
      animation: _controller!,
      child: widget.child,
      builder: (context, child) {
        final v = curve.transform(_controller!.value);
        // The same wrappers at rest as on the way, so the page keeps its state once it has arrived.
        return Opacity(
          opacity: v,
          child: FractionalTranslation(translation: Offset((widget.fromLeft ? -0.1 : 0.1) * (1 - v), 0), child: child),
        );
      },
    );
  }
}

/// `.settingsScreen__cluster` holding its `.settingsScreen__group`: consecutive rows of one group share a card, the
/// iOS-settings shape, with a hairline between one row and the next.
class _Group extends StatelessWidget {
  const _Group({super.key, required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hairline = t.len('glacier-hairline');
    final rule = t.color('app-rule');
    return GlacierScope(
      classes: const {'settingsScreen__group'},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radius('lg')),
        child: ColoredBox(
          color: t.color('app-paper-2'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows.length; i++)
                // `.settingsScreen__row + .settingsScreen__row { border-block-start }`
                i == 0 ? rows[i] : DecoratedBox(decoration: BoxDecoration(border: Border(top: BorderSide(color: rule, width: hairline))), child: Padding(padding: EdgeInsets.only(top: hairline), child: rows[i])),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.settingsScreen__row` (`SectionRow`): a row that opens a section, its chip in the section's colour, a label and a
/// line under it, and a chevron on a phone.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    super.key,
    required this.section,
    required this.label,
    this.summary,
    required this.current,
    required this.index,
    required this.split,
    required this.onPress,
    this.focusNode,
  });

  final SettingsSection section;
  final String label;
  final String? summary;
  final bool current;

  /// Its place in the rows' arrival, one after another.
  final int index;
  final bool split;
  final VoidCallback onPress;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(3);
    final chip = t.lenOf('1.85rem');
    final hasSummary = summary != null && summary!.isNotEmpty;
    return SettingsRise(
      index: index,
      child: GlacierPressable(
        onPressed: onPress,
        focusNode: focusNode,
        // `aria-current="page"`
        selected: current ? true : null,
        builder: (context, state) => GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('sm'),
          offset: -3,
          child: ColoredBox(
            // The section on show, in the left column: the row's own ground, a shade deeper.
            color: state.pressed
                ? t.color('app-paper-3')
                : current
                    ? t.colorOf('color-mix(in srgb, var(--glacier-text) 7%, transparent)')
                    : const Color(0x00000000),
            child: ConstrainedBox(
              // A row a thumb's height.
              constraints: BoxConstraints(minHeight: t.lenOf('3.5rem')),
              child: Padding(
                padding: EdgeInsets.all(gap),
                child: Row(
                  children: [
                    GlacierScope(
                      attrs: {'hue': settingsHueOf(section)},
                      child: Builder(
                        builder: (context) {
                          final hued = context.tokens;
                          return Container(
                            key: const ValueKey('settings-row-icon'),
                            width: chip,
                            height: chip,
                            decoration: BoxDecoration(color: settingsHueWash(hued), borderRadius: BorderRadius.circular(t.lenOf('0.55rem'))),
                            alignment: Alignment.center,
                            child: ExcludeSemantics(child: IconTheme.merge(data: IconThemeData(color: settingsHue(hued)), child: section.icon)),
                          );
                        },
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Each line as tall as the page's, to the fraction: twelve rows of whole-pixel lines end a dozen
                          // device pixels from where the page's do.
                          ExactLines.of(Text(label, key: const ValueKey('settings-row-label'), style: pageText(t, t.fontSize('md'), weight: 'medium')), normal: true, dpr: t.css.lineDpr),
                          if (hasSummary) ...[
                            SizedBox(height: t.lenOf('0.1rem')),
                            ExactLines.of(
                              Text(
                                summary!,
                                key: const ValueKey('settings-row-summary'),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
                              ),
                              normal: true,
                              dpr: t.css.lineDpr,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!split) ...[SizedBox(width: gap), ExcludeSemantics(child: SettingsIcon(SettingsGlyph.chevronRight, size: 18, color: t.color('app-ink-4')))],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.settingsScreen__findPill` with its field: a pill a shade off the page, the magnifier, the words, and a cross to
/// empty it once it holds any.
class _FindField extends StatefulWidget {
  const _FindField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.height,
    required this.focused,
    required this.style,
    required this.onKey,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final double height;
  final bool focused;
  final TextStyle style;
  final KeyEventResult Function(KeyEvent event) onKey;
  final VoidCallback onSubmitted;
  final VoidCallback onClear;

  @override
  State<_FindField> createState() => _FindFieldState();
}

class _FindFieldState extends State<_FindField> implements TextSelectionGestureDetectorBuilderDelegate {
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _handles = false;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final quiet = t.color('app-ink-3');
    final hasText = widget.controller.text.isNotEmpty;
    final editable = EditableText(
      key: editableTextKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: widget.style,
      cursorColor: widget.style.color ?? t.color('glacier-text'),
      cursorWidth: 1,
      backgroundCursorColor: quiet,
      selectionColor: widget.focused ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      showSelectionHandles: _handles,
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      // `inputMode="search" autoCapitalize="off" autoCorrect="off" spellCheck={false}`
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      maxLines: 1,
      onSubmitted: (_) => widget.onSubmitted(),
      onSelectionChanged: (selection, cause) {
        final show = cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.doubleTap || (cause == SelectionChangedCause.tap && hasText);
        final touch = switch (defaultTargetPlatform) { TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true, _ => false };
        if (show && touch != _handles || !show && _handles && cause == SelectionChangedCause.keyboard) setState(() => _handles = show && touch);
      },
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
    );
    final field = Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        if (!hasText) ExcludeSemantics(child: Text(widget.placeholder, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: widget.style.copyWith(color: t.color('app-ink-4')))),
        DefaultTextEditingShortcuts(
          // `aria-label`: the field is named by what it searches.
          child: Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: (node, event) => widget.onKey(event), child: Semantics(
              label: widget.placeholder,
              // A screen reader's double tap puts the caret in it and brings the keyboard up, as a touch does.
              onTap: () {
                widget.focusNode.requestFocus();
                editableTextKey.currentState?.requestKeyboard();
              },
              child: editable,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      // `role="search"`: the field and the cross that empties it, as one group.
      container: true,
      explicitChildNodes: true,
      child: Container(
        constraints: BoxConstraints(minHeight: widget.height),
        padding: EdgeInsets.symmetric(horizontal: t.space(3)),
        decoration: ShapeDecoration(
          // `:focus-within`: a shade deeper, with a line of the ink at 30% inside its edge.
          color: widget.focused ? t.color('app-paper-3') : t.color('app-paper-2'),
          shape: StadiumBorder(
            side: widget.focused
                ? BorderSide(color: t.colorOf('color-mix(in srgb, var(--glacier-text) 30%, transparent)'), width: t.len('app-line'), strokeAlign: BorderSide.strokeAlignInside)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: SettingsIcon(SettingsGlyph.search, size: 16, color: quiet)),
            SizedBox(width: t.space(2)),
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                child: _gestures.buildGestureDetector(behavior: HitTestBehavior.translucent, child: field),
              ),
            ),
            if (hasText) ...[
              SizedBox(width: t.space(2)),
              GlacierPressable(
                onPressed: widget.onClear,
                semanticLabel: 'Clear the search',
                canRequestFocus: false,
                builder: (context, state) => SettingsIcon(SettingsGlyph.x, size: 16, color: quiet),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
