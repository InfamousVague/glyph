/// The home page's search, and its filters beside it. A port of `src/app/home/HomeFilters.tsx` and its part of
/// HomeLayouts.module.css (docs/DESIGN.md §148).
///
/// The search has one button at its end, and the choices open from it in a panel: what to show, with how many of
/// each, and which workspace, with a new one and the chosen one's name and colour to change. Each is a radio, so a
/// person picks both in one opening; a tap outside, Escape, the phone's back, or the keyboard leaving it closes it.
/// What is chosen is never hidden: the button is inked while anything is, and under the search a chip names each
/// choice, its cross taking it off. With everything shown, nothing stands under the search.
///
/// What differs:
/// - The workspaces are a [WorkspaceStore] handed in (the web's is one module-wide store).
/// - The field is the page's own `<input>` on the web, with the browser's caret, selection and menu; here it is an
///   `EditableText` with the kit's handles and menu, since Flutter brings none without Material.
/// - The room the panel may take is measured as it opens, as on the web, from the button's place in the window.
/// - A chip's cross hands the keyboard to the next chip or to the button on the web by finding it in the page; here
///   the focus goes to the filters' button.
library;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/search_query.dart' show parseSearch;
import '../core/workspaces.dart';
import 'home_icons.dart';
import 'home_layout.dart';
import 'home_text.dart';
import 'marks.dart';
import 'search_hints.dart';

/// The search field and the filters' button with its panel and chips (`src/app/home/HomeFilters.tsx`). The
/// workspaces are a [WorkspaceStore] handed in, and the field is an `EditableText` with the kit's handles where the
/// web's is the page's own `<input>`.
class HomeFilters extends StatefulWidget {
  const HomeFilters({
    super.key,
    required this.query,
    required this.onQuery,
    required this.filter,
    required this.onFilter,
    required this.counts,
    required this.workspaces,
    required this.onManage,
    this.onNewOrganization,
    this.onOrganization,
    this.onSearching,
    this.onSaveSearch,
    this.simple = false,
    this.searchField = true,
    this.filtersButton = true,
  });

  final String query;
  final ValueChanged<String> onQuery;

  /// The search field has taken the keyboard: whoever searches may make ready for the first letter
  /// (lib/core/search_ahead.dart).
  final VoidCallback? onSearching;
  final HomeFilter filter;
  final ValueChanged<HomeFilter> onFilter;

  /// How many of each filter's notes, the archive left out and the search not applied (`homeCounts`).
  final Map<HomeFilter, int> counts;
  final WorkspaceStore workspaces;

  /// A workspace to rename, colour or remove; null for a new one (`onManage(which | 'new')`).
  final ValueChanged<Workspace?> onManage;

  /// A new organization, beside New workspace; absent signed out.
  final VoidCallback? onNewOrganization;

  /// An organization's own screen, for "Edit" on its workspace.
  final ValueChanged<String>? onOrganization;

  /// Keeps what is typed as a smart notebook (lib/core/smart_notebooks.dart); left out, the row under the search
  /// offers no Save.
  final VoidCallback? onSaveSearch;

  /// Simple mode (GHST-103; Matt, 2026-10-17: "fancy features hidden behind more"): the panel is the Show radios
  /// alone, with no Workspace radios and no New workspace, New organization or Edit under them, and the search
  /// offers no operator chips and no Save as a smart notebook. Plain words still search as they always have, and an
  /// operator typed by hand is still read and still said back as a chip.
  final bool simple;

  /// Whether the search field is drawn. Not while the header toolbar's Grouped command draws the bar, whose title pill
  /// is the search (lib/shell/header/grouped_command_row.dart; Matt, 2026-10-28: "remove the search bar from the home
  /// page since it's redundant"): the filters' button alone then, at the row's end, where it always stood.
  final bool searchField;

  /// Whether the filters' button is drawn here. Not where Grouped command draws the bar, which holds the button beside
  /// its title pill (Matt, 2026-10-29: "also remove this filter button on the home page, when on the homepage add it
  /// next to the command search bar in the top bar"): the same [HomeFiltersButton], handed to the bar by the home page
  /// (lib/shell/top_bar_tools.dart `TopBarFill.filters`). The chips of what is chosen stay here, under it.
  final bool filtersButton;

  @override
  State<HomeFilters> createState() => HomeFiltersState();
}

/// How a [HomeFiltersButton] is drawn: for the press's state, whether its panel is [open], and whether a filter is
/// [on] (a Show other than All, or a workspace chosen). The home page's own round button unless one is given: the
/// header toolbar draws it in the bar's own look.
typedef HomeFiltersFace = Widget Function(BuildContext context, PressState state, {required bool open, required bool on});

/// The filters' button and its panel - Show, with each one's count and a tick by the chosen one, and Workspace, with
/// New workspace, New organization and Edit (`HomeFilters.tsx` `.filters`, `.panel`) - on its own, so it can be drawn
/// in the home page's row or in the top bar (Grouped command), one widget with one panel either way: what it shows
/// and what it changes are the page's, handed in.
class HomeFiltersButton extends StatefulWidget {
  const HomeFiltersButton({
    super.key,
    required this.filter,
    required this.onFilter,
    required this.counts,
    required this.workspaces,
    required this.onManage,
    this.onNewOrganization,
    this.onOrganization,
    this.simple = false,
    this.focusNode,
    this.face,
    this.placement = Placement.bottomEnd,
  });

  final HomeFilter filter;
  final ValueChanged<HomeFilter> onFilter;
  final Map<HomeFilter, int> counts;
  final WorkspaceStore workspaces;
  final ValueChanged<Workspace?> onManage;
  final VoidCallback? onNewOrganization;
  final ValueChanged<String>? onOrganization;
  final bool simple;

  /// The button's focus, which the page's chips and the workspace sheet hand the keyboard back to; its own if none.
  final FocusNode? focusNode;
  final HomeFiltersFace? face;
  final Placement placement;

  @override
  State<HomeFiltersButton> createState() => _HomeFiltersButtonState();
}

class _HomeFiltersButtonState extends State<HomeFiltersButton> {
  final GlobalKey _buttonKey = GlobalKey(debugLabel: 'Home filters button');
  FocusNode? _own;
  bool _open = false;

  /// How tall the panel may be: the room under the button, measured as it opens.
  double? _room;

  FocusNode get _button => widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'Home filters'));

  @override
  void initState() {
    super.initState();
    widget.workspaces.addListener(_redraw);
  }

  @override
  void didUpdateWidget(HomeFiltersButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaces != widget.workspaces) {
      oldWidget.workspaces.removeListener(_redraw);
      widget.workspaces.addListener(_redraw);
    }
  }

  @override
  void dispose() {
    widget.workspaces.removeListener(_redraw);
    _own?.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _openPanel(bool next) {
    if (next) {
      final box = _buttonKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final below = box.localToGlobal(Offset(0, box.size.height)).dy;
        final room = MediaQuery.sizeOf(context).height - below - 44;
        _room = room < 160 ? 160 : room;
      }
    }
    setState(() => _open = next);
  }

  void _manage(Workspace? which) {
    setState(() => _open = false);
    widget.onManage(which);
  }

  /// "Edit" on an organization's workspace is the organization's screen; its name and colour are the organization's.
  void _edit(Workspace workspace) {
    final org = workspace.org;
    if (org != null && widget.onOrganization != null) {
      setState(() => _open = false);
      widget.onOrganization!(org);
    } else {
      _manage(workspace);
    }
  }

  /// The home page's own round button.
  Widget _homeFace(BuildContext context, PressState state, {required bool open, required bool on}) {
    final t = context.tokens;
    final lit = state.hovered || open;
    final ink = on ? t.color('app-paper') : (lit ? t.color('app-ink') : t.color('app-ink-2'));
    return GlacierFocusRing(
      visible: state.focused,
      child: Container(
        width: t.space(10),
        height: t.space(10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? t.color('app-ink') : t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)'),
          border: Border.all(color: on ? t.color('app-ink') : (lit ? t.color('glacier-border-strong') : t.color('app-rule')), width: t.len('glacier-hairline')),
        ),
        child: HomeIcon(HomeGlyph.filters, size: 16, strokeWidth: 2.2, color: ink),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final current = widget.workspaces.value.current;
    final shown = homeFilters.firstWhere((each) => each.id == widget.filter);
    final chosen = [if (widget.filter != HomeFilter.all) shown.label, if (current != null) current.name].join(', ');
    final face = widget.face ?? _homeFace;
    return GlacierPopover(
      open: _open,
      onOpenChange: _openPanel,
      placement: widget.placement,
      ariaLabel: 'Filters',
      // `.panel { min-inline-size: min(17rem, calc(100vw - 2rem)) }`.
      minWidth: t.lenOf('min(17rem, calc(100vw - 2rem))'),
      trigger: (context, trigger) => GlacierPressable(
        key: _buttonKey,
        focusNode: _button,
        onPressed: trigger.toggle,
        semanticLabel: chosen.isEmpty ? 'Filters' : 'Filters: $chosen',
        builder: (context, state) => face(context, state, open: trigger.isOpen, on: chosen.isNotEmpty),
      ),
      child: _PanelBody(
        room: _room,
        filter: widget.filter,
        onFilter: widget.onFilter,
        counts: widget.counts,
        store: widget.workspaces,
        simple: widget.simple,
        onNew: () => _manage(null),
        onNewOrganization: widget.onNewOrganization == null
            ? null
            : () {
                setState(() => _open = false);
                widget.onNewOrganization!();
              },
        onEdit: _edit,
        onLeave: () => setState(() => _open = false),
        trigger: _button,
      ),
    );
  }
}

/// [HomeFilters]' state, public for [focusButton]: the workspace sheet hands the keyboard back to the filters'
/// button as it closes (HomeScreen.tsx's `WorkspaceSheet onClose`).
class HomeFiltersState extends State<HomeFilters> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _field = FocusNode(debugLabel: 'Home search');
  final FocusNode _button = FocusNode(debugLabel: 'Home filters');

  /// The button kept across the row moving into a column under it as a filter is chosen, so its panel stays open for
  /// another choice: the panel's open state is the button's own.
  final GlobalKey _filtersKey = GlobalKey(debugLabel: 'Home filters');

  @override
  void initState() {
    super.initState();
    _controller.text = widget.query;
    _field.addListener(_redraw);
    _field.addListener(_searching);
    widget.workspaces.addListener(_redraw);
  }

  void _searching() {
    if (_field.hasFocus) widget.onSearching?.call();
  }

  @override
  void didUpdateWidget(HomeFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaces != widget.workspaces) {
      oldWidget.workspaces.removeListener(_redraw);
      widget.workspaces.addListener(_redraw);
    }
    // The text is the page's: whatever it hands down is what shows.
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(text: widget.query, selection: TextSelection.collapsed(offset: widget.query.length));
    }
  }

  @override
  void dispose() {
    widget.workspaces.removeListener(_redraw);
    _field.removeListener(_redraw);
    _field.removeListener(_searching);
    _controller.dispose();
    _field.dispose();
    _button.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  /// Puts the keyboard on the filters' button: where the workspace sheet hands it back as it closes. Nowhere while
  /// the button is the bar's ([HomeFilters.filtersButton]).
  void focusButton() {
    if (_button.context != null) _button.requestFocus();
  }

  /// A chip's cross: the filter comes off, and the keyboard goes to the button.
  void _takeOff(VoidCallback clear) {
    clear();
    focusButton();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final spaces = widget.workspaces.value;
    final current = spaces.current;
    final shown = homeFilters.firstWhere((each) => each.id == widget.filter);
    final chosen = [if (widget.filter != HomeFilter.all) shown.label, if (current != null) current.name].join(', ');
    final sm = t.fontSize('sm');

    final Widget? row = !widget.searchField && !widget.filtersButton
        ? null
        : Row(
            children: [
              if (widget.searchField) ...[
                Expanded(child: _SearchField(controller: _controller, focusNode: _field, onQuery: widget.onQuery)),
                if (widget.filtersButton) SizedBox(width: t.space(2)),
              ] else
                const Spacer(),
              if (widget.filtersButton)
                HomeFiltersButton(
                  key: _filtersKey,
                  filter: widget.filter,
                  onFilter: widget.onFilter,
                  counts: widget.counts,
                  workspaces: widget.workspaces,
                  onManage: widget.onManage,
                  onNewOrganization: widget.onNewOrganization,
                  onOrganization: widget.onOrganization,
                  simple: widget.simple,
                  focusNode: _button,
                ),
            ],
          );
    // The operators a search reads, offered while the field is empty and has the keyboard, and what it understood
    // of what is typed (lib/home/search_hints.dart): the port's own.
    // Simple mode offers no operators and no Save: the row is there only to say back what was typed.
    final typed = widget.query.trim().isNotEmpty;
    final onSave = widget.simple ? null : widget.onSaveSearch;
    final hinted = typed ? (parseSearch(widget.query).parts.isNotEmpty || onSave != null) : _field.hasFocus && !widget.simple;
    final hints = hinted
        ? SearchHints(
            query: widget.query,
            focused: _field.hasFocus,
            onQuery: (next) {
              widget.onQuery(next);
              _field.requestFocus();
            },
            onSave: onSave,
          )
        : null;
    if (chosen.isEmpty && hints == null) return row ?? const SizedBox.shrink();

    // What is chosen, under the search: a chip for each, its cross taking it off.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ?row,
        if (hints != null) ...[if (row != null) SizedBox(height: t.space(3)), hints],
        if (chosen.isNotEmpty) ...[
        if (row != null || hints != null) SizedBox(height: t.space(3)),
        Semantics(
          container: true,
          label: 'Filters on',
          explicitChildNodes: true,
          child: Wrap(
            spacing: t.space(2),
            runSpacing: t.space(2),
            children: [
              if (widget.filter != HomeFilter.all)
                _Chip(
                  label: '${shown.label}: show everything',
                  onPressed: () => _takeOff(() => widget.onFilter(HomeFilter.all)),
                  children: [
                    if (widget.filter == HomeFilter.pinned) ...[HomeIcon(HomeGlyph.pin, size: 1.05 * sm, color: t.color('app-ink-2')), SizedBox(width: 0.4 * sm)],
                    Text(shown.label),
                  ],
                ),
              if (current != null)
                GlacierScope(
                  attrs: {'hue': current.hue ?? 'ink'},
                  child: Builder(
                    builder: (context) => _Chip(
                      label: '${workspacePathName(spaces.list, current.id)}: every workspace',
                      onPressed: () => _takeOff(() => widget.workspaces.chooseWorkspace(null)),
                      children: [
                        const _HueDot(),
                        SizedBox(width: 0.4 * sm),
                        if (orgOfWorkspace(spaces.list, current.id) != null) OrgMark(em: sm, color: t.color('app-ink')),
                        // A folder says where it is: "HelloTrade › Designs", not "Designs" as if it were an organization.
                        Text(workspacePathName(spaces.list, current.id)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        ],
      ],
    );
  }
}

/// `.search`: a pill of the faint ink wash, the page's first thing and its main tool; and `.field`, the input in it.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.focusNode, required this.onQuery});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onQuery;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> implements TextSelectionGestureDetectorBuilderDelegate {
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _handles = false;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_redraw);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final focused = widget.focusNode.hasFocus;
    final sm = t.fontSize('sm');
    final style = pageText(t, sm, color: t.color('app-ink'));
    const words = 'Search notebooks and notes';
    final empty = widget.controller.text.isEmpty;

    final editable = EditableText(
      key: editableTextKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: style,
      cursorColor: t.color('app-ink'),
      cursorWidth: 1,
      backgroundCursorColor: t.color('app-ink-3'),
      selectionColor: focused ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      showSelectionHandles: _handles,
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      // The page's `<input type="search">` gets the keyboard's row of suggestions on the phone, whatever its
      // `autocorrect="off"` says; without them Gboard swaps that row for one of digits.
      enableSuggestions: true,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      textCapitalization: TextCapitalization.none,
      onChanged: widget.onQuery,
      onSelectionChanged: (selection, cause) {
        // Handles are a finger's: none for a selection the keyboard or the program made.
        final show = !empty && (cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.doubleTap || cause == SelectionChangedCause.drag || cause == SelectionChangedCause.tap) && _gestures.shouldShowSelectionHandles;
        if (show != _handles) setState(() => _handles = show);
      },
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
    );

    return TextFieldTapRegion(
      child: Semantics(
        label: words,
        textField: true,
        onTap: () => editableTextKey.currentState?.requestKeyboard(),
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(10)),
          padding: EdgeInsetsDirectional.only(start: t.space(3), end: t.space(1)),
          decoration: BoxDecoration(
            color: t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)'),
            border: Border.all(color: focused ? t.color('glacier-border-strong') : t.color('app-rule'), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: Row(
            children: [
              HomeIcon(HomeGlyph.search, size: 15, strokeWidth: 2.2, color: focused ? t.color('app-ink-2') : t.color('app-ink-3')),
              SizedBox(width: t.space(2)),
              Expanded(
                child: _gestures.buildGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.text,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: t.space(8)),
                      child: Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [
                          if (empty) ExcludeSemantics(child: Text(words, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style.copyWith(color: t.color('app-ink-3')))),
                          DefaultTextEditingShortcuts(child: editable),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!empty) ...[
                SizedBox(width: t.space(2)),
                GlacierPressable(
                  onPressed: () {
                    widget.controller.clear();
                    widget.onQuery('');
                    widget.focusNode.requestFocus();
                  },
                  semanticLabel: 'Clear the search',
                  builder: (context, state) => GlacierFocusRing(
                    visible: state.focused,
                    child: Container(
                      width: t.space(6),
                      height: t.space(6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)')),
                      child: HomeIcon(HomeGlyph.cross, size: 14, strokeWidth: 2.4, color: t.color('app-ink-2')),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.chip`: what is chosen, said under the search, its cross taking it off. Tinted with the workspace's colour where
/// it stands inside one (`--app-space`), and the ink otherwise.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onPressed, required this.children});

  final String label;
  final VoidCallback onPressed;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(8)),
          padding: EdgeInsetsDirectional.only(start: t.space(3), end: t.space(2)),
          decoration: BoxDecoration(
            color: t.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink)) 10%, transparent)'),
            border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink)) 55%, transparent)'), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: ExcludeSemantics(
            child: DefaultTextStyle.merge(
              style: pageText(t, sm, weight: 'medium', color: t.color('app-ink')),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [...children, SizedBox(width: 0.4 * sm), HomeIcon(HomeGlyph.cross, size: 13, strokeWidth: 2.4, color: t.color('app-ink'))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.hueDot`: a workspace's colour as a dot (ink.css `[data-hue]` gives `--app-space` to whatever stands in a
/// [GlacierScope] with the hue), in the third ink where it has none.
class _HueDot extends StatelessWidget {
  const _HueDot({this.em});

  /// The font size it is measured in; the medium step, a choice's own, where it is left out.
  final double? em;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = em ?? t.fontSize('sm');
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 0.15 * size),
      child: Container(width: 0.7 * size, height: 0.7 * size, decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('var(--app-space, var(--app-ink-3))'))),
    );
  }
}

/// The panel's contents, which it scrolls when they are taller than the room under the button. It opens on the
/// chosen Show, where the arrow keys work at once; the keyboard leaving it for the page closes it.
class _PanelBody extends StatefulWidget {
  const _PanelBody({
    required this.room,
    required this.filter,
    required this.onFilter,
    required this.counts,
    required this.store,
    required this.onNew,
    required this.onNewOrganization,
    required this.onEdit,
    required this.onLeave,
    required this.trigger,
    this.simple = false,
  });

  final double? room;
  final HomeFilter filter;
  final ValueChanged<HomeFilter> onFilter;
  final Map<HomeFilter, int> counts;
  final WorkspaceStore store;

  /// Simple mode: the Show radios alone ([HomeFilters.simple]).
  final bool simple;
  final VoidCallback onNew;
  final VoidCallback? onNewOrganization;
  final ValueChanged<Workspace> onEdit;
  final VoidCallback onLeave;
  final FocusNode trigger;

  @override
  State<_PanelBody> createState() => _PanelBodyState();
}

class _PanelBodyState extends State<_PanelBody> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'Home filters panel');
  late final List<FocusNode> _show = [for (final each in homeFilters) FocusNode(debugLabel: 'Show ${each.label}')];
  final Map<String, FocusNode> _place = {};
  bool _focusedOnce = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_redraw);
    _scope.addListener(_left);
    // The panel takes the focus as it opens; a moment later it goes to the chosen Show.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _show[homeFilters.indexWhere((each) => each.id == widget.filter)].requestFocus();
      _focusedOnce = true;
    });
  }

  @override
  void dispose() {
    widget.store.removeListener(_redraw);
    _scope.removeListener(_left);
    _scope.dispose();
    for (final node in [..._show, ..._place.values]) {
      node.dispose();
    }
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  /// The keyboard has left the panel for the page: it closes. Leaving for nowhere, or for the button, leaves it open.
  void _left() {
    if (!_focusedOnce || _scope.hasFocus) return;
    final to = FocusManager.instance.primaryFocus;
    if (to == null || to == widget.trigger || to.context == null) return;
    // The panel's own root (the popover's) holding the focus is still the panel.
    if (to.descendants.contains(_scope) || to.ancestors.contains(widget.trigger)) return;
    widget.onLeave();
  }

  FocusNode _placeNode(String key) => _place.putIfAbsent(key, () => FocusNode(debugLabel: 'Workspace $key'));

  /// The arrow keys in a radiogroup: the next or the previous choice, round the ends, chosen as it is reached.
  KeyEventResult _step(KeyEvent event, int at, int count, void Function(int to) choose) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final by = key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight ? 1 : (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft ? -1 : 0);
    if (by == 0) return KeyEventResult.ignored;
    choose((at + by + count) % count);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final spaces = widget.store.value;
    final current = spaces.current;
    final md = t.fontSize('md');
    // A workspace's radios: every workspace, then each by name, an organization's with its mark, and each folder
    // under its parent, named with its parents before it (Matt, 2026-10-20: "when filtering, instead of showing
    // folders as orgs show them as Org -> Folder").
    final places = <Workspace?>[null, ..._parentsFirst(spaces.list)];

    Widget heading(String words, {bool first = false}) => Padding(
          padding: EdgeInsetsDirectional.fromSTEB(t.space(2), first ? t.space(1) : t.space(2), t.space(2), t.space(1)),
          child: Semantics(
            header: true,
            // The page's line (`line-height: normal`, 13.5px for these 11.16px words), not a whole pixel more: the
            // panel's two headings put its foot 2.6 device pixels low beside the page's.
            child: ExactLines.of(
              Text(words.toUpperCase(), style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'), tracking: 0.04 * t.fontSize('xs'))),
              normal: true,
              dpr: t.css.lineDpr,
            ),
          ),
        );

    final children = <Widget>[
      heading('Show', first: true),
      Semantics(
        container: true,
        label: 'Show',
        role: SemanticsRole.radioGroup,
        explicitChildNodes: true,
        child: _Gapped(
          children: [
            for (final (at, each) in homeFilters.indexed)
              _Choice(
                focusNode: _show[at],
                checked: widget.filter == each.id,
                label: each.label,
                count: widget.counts[each.id] ?? 0,
                onPressed: () => widget.onFilter(each.id),
                onKey: (event) => _step(event, at, homeFilters.length, (to) {
                  widget.onFilter(homeFilters[to].id);
                  _show[to].requestFocus();
                }),
                mark: HomeIcon(
                  switch (each.id) { HomeFilter.all => HomeGlyph.grid, HomeFilter.books => HomeGlyph.notebook, HomeFilter.notes => HomeGlyph.note, HomeFilter.pinned => HomeGlyph.pin },
                  size: md,
                  // `<FileText size="1em" strokeWidth={2.2} />`, the one of the four that is the kit's.
                  strokeWidth: 2.2,
                  color: t.color('app-ink-2'),
                ),
              ),
          ],
        ),
      ),
      // Simple mode's panel ends with Show: no workspaces to choose, none to make, nothing to edit.
      if (!widget.simple) ...[
        heading('Workspace'),
        if (spaces.list.isNotEmpty)
          Semantics(
            container: true,
            label: 'Workspace',
            role: SemanticsRole.radioGroup,
            explicitChildNodes: true,
            child: _Gapped(
              children: [
                for (final (at, place) in places.indexed)
                  GlacierScope(
                    attrs: place == null ? const {} : {'hue': place.hue ?? 'ink'},
                    child: _Choice(
                      focusNode: _placeNode(place?.id ?? ''),
                      checked: current?.id == place?.id,
                      label: place == null ? 'Every workspace' : workspacePathName(spaces.list, place.id),
                      onPressed: () => widget.store.chooseWorkspace(place?.id),
                      onKey: (event) => _step(event, at, places.length, (to) {
                        widget.store.chooseWorkspace(places[to]?.id);
                        _placeNode(places[to]?.id ?? '').requestFocus();
                      }),
                      mark: place == null ? HomeIcon(HomeGlyph.workspace, size: md, color: t.color('app-ink-2')) : _HueDot(em: md),
                      org: place != null && orgOfWorkspace(spaces.list, place.id) != null,
                    ),
                  ),
              ],
            ),
          )
        else
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(t.space(2), 0, t.space(2), t.space(1)),
            child: Text(
              'Notes filed in a workspace show together. A note made while one is chosen goes there.',
              style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
            ),
          ),
        Container(
          margin: EdgeInsets.only(top: t.space(1)),
          padding: EdgeInsets.only(top: t.space(1)),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('app-rule'), width: t.len('glacier-hairline')))),
          child: _Gapped(
            children: [
              _PanelAction(label: 'New workspace', onPressed: widget.onNew, mark: HomeIcon(HomeGlyph.plus, size: md, color: t.color('app-ink-2'))),
              if (widget.onNewOrganization != null)
                _PanelAction(label: 'New organization', onPressed: widget.onNewOrganization!, mark: HomeIcon(HomeGlyph.organization, size: md, strokeWidth: 2.2, color: t.color('app-ink-2'))),
              if (current != null)
                GlacierScope(
                  attrs: {'hue': current.hue ?? 'ink'},
                  child: _PanelAction(label: 'Edit ${current.name}', onPressed: () => widget.onEdit(current), mark: _HueDot(em: md)),
                ),
            ],
          ),
        ),
      ],
    ];

    return FocusScope(
      node: _scope,
      // As wide as its longest choice wants, and no narrower than the panel's own least: a panel on the page shrinks
      // to what is in it.
      child: IntrinsicWidth(
        child: ConstrainedBox(
          // Its body scrolls when it is taller than the room under the button; `70dvh` until that is measured.
          constraints: BoxConstraints(maxHeight: widget.room ?? t.lenOf('70vh')),
          child: SingleChildScrollView(
            child: _Gapped(children: children),
          ),
        ),
      ),
    );
  }
}

/// `display: grid; gap: 2px`: its children one under another, two pixels apart.
class _Gapped extends StatelessWidget {
  const _Gapped({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (at, child) in children.indexed) ...[if (at > 0) const SizedBox(height: 2), child],
        ],
      );
}

/// `.choice`: its mark, its word, its count, and a tick while it is the one chosen.
class _Choice extends StatelessWidget {
  const _Choice({required this.focusNode, required this.checked, required this.label, this.count, required this.onPressed, required this.onKey, required this.mark, this.org = false});

  final FocusNode focusNode;
  final bool checked;
  final String label;
  final int? count;
  final VoidCallback onPressed;
  final KeyEventResult Function(KeyEvent event) onKey;
  final Widget mark;
  final bool org;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: checked,
      label: count == null ? label : '$label, $count',
      onTap: onPressed,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: (node, event) => onKey(event),
        child: GlacierPressable(
          focusNode: focusNode,
          // A press takes the keyboard to the choice, as a click on a button does on the page.
          onPressed: () {
            focusNode.requestFocus();
            onPressed();
          },
          haptic: HapticKind.selection,
          excludeSemantics: true,
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('md'),
            child: Container(
              constraints: BoxConstraints(minHeight: t.space(10)),
              padding: EdgeInsets.symmetric(horizontal: t.space(2)),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.radius('md')),
                color: checked
                    ? t.colorOf('color-mix(in oklch, var(--app-ink) 9%, transparent)')
                    : (state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null),
              ),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    mark,
                    SizedBox(width: t.space(3)),
                    if (org) OrgMark(em: md, color: t.color('app-ink')),
                    Expanded(
                      child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, md, weight: checked ? 'semibold' : 'regular', color: t.color('app-ink'))),
                    ),
                    if (count != null) ...[SizedBox(width: t.space(3)), Text('$count', style: tabular(pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))))],
                    SizedBox(width: t.space(3)),
                    // `visibility: hidden` until it is the one chosen: the tick keeps its room either way.
                    Visibility(visible: checked, maintainSize: true, maintainAnimation: true, maintainState: true, child: HomeIcon(HomeGlyph.check, size: 16, strokeWidth: 2.4, color: t.color('app-ink'))),
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

/// `.panelAction`: a choice's shape for something done rather than chosen, in the second ink.
class _PanelAction extends StatelessWidget {
  const _PanelAction({required this.label, required this.onPressed, required this.mark});

  final String label;
  final VoidCallback onPressed;
  final Widget mark;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('md'),
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(10)),
          padding: EdgeInsets.symmetric(horizontal: t.space(2)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius('md')),
            color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null,
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                mark,
                SizedBox(width: t.space(3)),
                Expanded(child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2')))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [list] with every folder straight after its parent, to any depth, the top ones in [list]'s order: a workspace
/// whose parent is not in [list] counts as a top one.
List<Workspace> _parentsFirst(List<Workspace> list) {
  final ids = {for (final w in list) w.id};
  final out = <Workspace>[];
  void add(Workspace w) {
    if (out.contains(w)) return;
    out.add(w);
    for (final child in list) {
      if (child.parent == w.id) add(child);
    }
  }

  for (final w in list) {
    if (w.parent == null || !ids.contains(w.parent)) add(w);
  }
  // Anything a loop of parents kept out, at the end rather than lost.
  for (final w in list) {
    if (!out.contains(w)) out.add(w);
  }
  return out;
}
