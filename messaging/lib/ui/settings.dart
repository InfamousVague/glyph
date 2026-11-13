/// Ghost Messaging's Settings, in Ghost Keyboard's shape (its lib/settings/settings_screen.dart; Matt, 2026-11-13:
/// "make the settings page more like ghost kbd where it's nested sections and expand on the settings available"):
/// a search field over a list of sections in groups, each a row with its icon on a chip in the section's colour, its
/// name and a line of its state, opening the section's page; a page is the kit's cards (kit/settings_kit.dart) under
/// the bar with the way back. The sections themselves are settings_panes.dart.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../effects.dart';
import '../kit/fold.dart';
import '../kit/settings_icons.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';
import 'settings_panes.dart';

/// What Settings shows that is not a choice of the person's: what Android has allowed, this phone's number, where
/// the app's update stands, who encryption is on with, the blocked numbers. Asked for as Settings opens and again
/// after anything changes it; the choices themselves are [app].
class SettingsModel extends ChangeNotifier {
  SettingsModel(this.app) {
    app.addListener(notifyListeners);
  }

  final AppState app;
  SmsStatus? status;
  String? ownNumber;
  UpdateState update = const UpdateState();
  List<E2eState> e2e = const [];

  /// A short name for this phone's encryption key; null until one is made (the first time a key is sent).
  String? myKey;
  List<Person> blocked = const [];
  int archived = 0;

  /// Ghost Keyboard is on this phone (and is the real one, by its certificate).
  bool keyboardHere = false;

  /// What can be seen of the texting app this one replaced, and of Android's store of texts.
  Arriving arriving = const Arriving();

  StreamSubscription<UpdateState>? _updates;
  StreamSubscription<int>? _changes;
  bool _gone = false;

  void start() {
    _updates = Sms.instance.updates.stream.listen((u) {
      update = u;
      _say();
    });
    _changes = Sms.instance.changes.stream.listen((_) => refresh());
    refresh();
  }

  void _say() {
    if (!_gone) notifyListeners();
  }

  /// Each asked for on its own: one that Android refuses leaves the rest.
  Future<void> refresh() async {
    Future<void> ask(Future<void> Function() what) async {
      try {
        await what();
      } catch (_) {}
    }

    await Future.wait([
      ask(() async => status = await Sms.instance.status()),
      ask(() async => ownNumber = await Sms.instance.ownNumber()),
      ask(() async => update = await Sms.instance.update()),
      ask(() async => e2e = await Sms.instance.e2eList()),
      ask(() async => myKey = await Sms.instance.e2eMine()),
      ask(() async => blocked = await Sms.instance.blockedNumbers()),
      ask(() async => keyboardHere = await Sms.instance.keyboardHere()),
      ask(() async => arriving = await Sms.instance.arriving()),
      ask(() async => archived = await Sms.instance.archivedCount()),
    ]);
    _say();
  }

  @override
  void dispose() {
    _gone = true;
    app.removeListener(notifyListeners);
    _updates?.cancel();
    _changes?.cancel();
    super.dispose();
  }
}

/// One section: a row on the list and the page it opens.
@immutable
class SettingsSection {
  const SettingsSection({required this.id, required this.label, required this.icon, required this.hue, required this.group, required this.page, this.summary, this.screen});

  final String id;
  final String label;
  final Widget icon;

  /// Its colour, by the names settings.css keeps (kit/settings_css.dart).
  final String hue;

  /// Rows with the same group share one card.
  final String group;

  /// The row's second line, read live.
  final String Function(SettingsModel model)? summary;

  /// Its page's cards.
  final List<Widget> Function(BuildContext context, SettingsModel model) page;

  /// A screen of its own in place of a page of cards: Archived, the chat background.
  final Widget Function(BuildContext context, SettingsModel model)? screen;
}

/// A section's page can play a message effect over itself (Effects): asked for from a row on it.
class EffectsHost extends InheritedWidget {
  const EffectsHost({super.key, required this.play, required super.child});
  final void Function(ScreenEffect effect) play;

  static EffectsHost? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<EffectsHost>();

  @override
  bool updateShouldNotify(EffectsHost old) => false;
}

/// Settings' home: a search field over the list of sections. While words are typed the list gives way to what they
/// find: sections and settings, each with where it is, opening there.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  SettingsModel? _model;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model ??= SettingsModel(AppState.of(context))..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _model?.dispose();
    super.dispose();
  }

  /// Back from one of Android's own pages (a permission, the default SMS app): what it allowed is asked again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _model?.refresh();
  }

  void _open(SettingsHit hit) {
    final model = _model!;
    final s = hit.section;
    push<void>(context, (context) => s.screen != null ? s.screen!(context, model) : SectionPage(section: s, model: model, seek: hit.setting));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final model = _model!;
    return GhostPage(
      title: 'Settings',
      body: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final query = _query.trim();
          final hits = query.isEmpty ? const <SettingsHit>[] : searchSettings(context, model, settingsSections, query);
          return ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              GlacierSearchField(placeholder: 'Search settings', size: GlacierFieldSize.md, onValueChange: (v) => setState(() => _query = v)),
              SizedBox(height: t.space(5)),
              if (query.isEmpty)
                SettingsList(model: model, sections: settingsSections)
              else if (hits.isEmpty)
                Padding(
                  padding: EdgeInsets.all(t.space(4)),
                  child: Text('Nothing called “$query”.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'))),
                )
              else
                _Group(rows: [
                  for (var i = 0; i < hits.length; i++)
                    _SectionRow(
                      label: hits[i].setting ?? hits[i].section.label,
                      icon: hits[i].section.icon,
                      hue: hits[i].section.hue,
                      // A setting says where it is; a section, what it is set to.
                      summary: hits[i].setting != null ? hits[i].section.label : hits[i].section.summary?.call(model),
                      index: i,
                      onPress: () => _open(hits[i]),
                    ),
                ]),
            ],
          );
        },
      ),
    );
  }
}

/// A section's page: its cards, staggered in as Ghost Keyboard's arrive. Opened from a search with [seek], the
/// setting of that name is scrolled into view and lit once the page is drawn.
class SectionPage extends StatefulWidget {
  const SectionPage({super.key, required this.section, required this.model, this.seek});

  final SettingsSection section;
  final SettingsModel model;
  final String? seek;

  @override
  State<SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<SectionPage> {
  final _finder = SettingsFinder();
  final _effects = GlobalKey<EffectLayerState>();

  @override
  void initState() {
    super.initState();
    final seek = widget.seek;
    if (seek == null) return;
    // Two frames: one to build the page whole, one for it to be laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => WidgetsBinding.instance.addPostFrameCallback((_) {
          final found = _finder.find(seek);
          if (found == null || !mounted) return;
          Scrollable.ensureVisible(found.context, alignment: 0.25, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
          found.light();
        }));
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final model = widget.model;
    return GlacierScope(
      attrs: {'hue': section.hue},
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final t = context.tokens;
          return SettingsPaneScope(
            finder: _finder,
            whole: widget.seek != null,
            seeking: widget.seek,
            child: EffectsHost(
              play: (effect) => _effects.currentState?.play(effect, text: effectLabel(effect)),
              child: GhostPage(
                title: section.label,
                body: Stack(children: [
                  Positioned.fill(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [Builder(builder: (context) => PaneBody(children: section.page(context, model)))],
                    ),
                  ),
                  Positioned.fill(child: EffectLayer(key: _effects, style: pageText(t, 26, color: t.color('app-ink')))),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One section's page by its [id], with a model of its own: the way in from outside Settings.
class SettingsSectionScreen extends StatefulWidget {
  const SettingsSectionScreen(this.id, {super.key});
  final String id;

  @override
  State<SettingsSectionScreen> createState() => _SettingsSectionScreenState();
}

class _SettingsSectionScreenState extends State<SettingsSectionScreen> {
  SettingsModel? _model;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model ??= SettingsModel(AppState.of(context))..start();
  }

  @override
  void dispose() {
    _model?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = settingsSections.firstWhere((s) => s.id == widget.id);
    return section.screen != null ? section.screen!(context, _model!) : SectionPage(section: section, model: _model!);
  }
}

/// The list of sections: Settings' home.
class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.model, required this.sections});

  final SettingsModel model;
  final List<SettingsSection> sections;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final groups = <String, List<SettingsSection>>{};
    for (final section in sections) {
      groups.putIfAbsent(section.group, () => []).add(section);
    }
    var index = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups.values) ...[
          _Group(rows: [
            for (final section in group)
              _SectionRow(
                label: section.label,
                icon: section.icon,
                hue: section.hue,
                summary: section.summary?.call(model),
                index: index++,
                onPress: () => push<void>(context, (context) => section.screen != null ? section.screen!(context, model) : SectionPage(section: section, model: model)),
              ),
          ]),
          SizedBox(height: t.space(5)),
        ],
      ],
    );
  }
}

/// `.settingsScreen__group`: rows sharing one card, a hairline between them.
class _Group extends StatelessWidget {
  const _Group({required this.rows});
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
                i == 0 ? rows[i] : DecoratedBox(decoration: BoxDecoration(border: Border(top: BorderSide(color: rule, width: hairline))), child: Padding(padding: EdgeInsets.only(top: hairline), child: rows[i])),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.settingsScreen__row`: the section's chip in its colour, its name and a line under it, and a chevron.
class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.label, required this.icon, required this.hue, required this.summary, required this.index, required this.onPress});

  final String label;
  final Widget icon;
  final String hue;
  final String? summary;
  final int index;
  final VoidCallback onPress;

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
        semanticLabel: label,
        builder: (context, state) => ColoredBox(
          color: state.pressed ? t.color('app-paper-3') : const Color(0x00000000),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.lenOf('3.5rem')),
            child: Padding(
              padding: EdgeInsets.all(gap),
              child: Row(
                children: [
                  GlacierScope(
                    attrs: {'hue': hue},
                    child: Builder(
                      builder: (context) {
                        final hued = context.tokens;
                        return Container(
                          width: chip,
                          height: chip,
                          decoration: BoxDecoration(color: settingsHueWash(hued), borderRadius: BorderRadius.circular(t.lenOf('0.55rem'))),
                          alignment: Alignment.center,
                          child: ExcludeSemantics(child: IconTheme.merge(data: IconThemeData(color: settingsHue(hued)), child: icon)),
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
                        Text(label, style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink'))),
                        if (hasSummary) ...[
                          SizedBox(height: t.lenOf('0.1rem')),
                          Text(summary!, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: gap),
                  ExcludeSemantics(child: SettingsIcon(SettingsGlyph.chevronRight, size: 18, color: t.color('app-ink-4'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- the search -------------------------------------------------------------------------------------------------------
// Ghost Keyboard's settings_search.dart: nothing is listed by hand. The index is read off the pages themselves (each
// is a list of the kit's cards and rows, which say their own names), so a setting is found the day it is added.

final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _words(String text) => fold(text).split(_notWord).where((w) => w.isNotEmpty).toList();

/// Every word of [query] starts a word of [text].
bool settingsMatch(String query, String text) {
  final want = _words(query);
  if (want.isEmpty) return false;
  final have = _words(text);
  return want.every((w) => have.any((h) => h.startsWith(w)));
}

/// One thing found: a section, or a setting on its page.
class SettingsHit {
  const SettingsHit(this.section, {this.setting});
  final SettingsSection section;

  /// The setting found on the section's page, as the page names it; null when the section itself was found.
  final String? setting;
}

/// What a page draws that can be looked for: each card's title, each row's label with its hint. A card is found by
/// its title alone: what its footnote says is about its rows, which are found themselves.
List<(String, String)> pageEntries(List<Widget> widgets) {
  final out = <(String, String)>[];
  String textOf(Widget? w) => w is Text ? (w.data ?? '') : '';
  void walk(Widget w) {
    if (w is PaneSection) {
      if ((w.title ?? '').isNotEmpty) out.add((w.title!, ''));
      for (final c in w.children) {
        walk(c);
      }
    } else if (w is SettingRow) {
      out.add((w.label, textOf(w.hint)));
    } else if (w is PaneHero) {
      out.add((w.title, textOf(w.meta)));
    }
  }

  for (final w in widgets) {
    walk(w);
  }
  return out;
}

/// What [query] finds: sections by their names and state lines first, then settings on their pages by their names
/// and hints (with their section's name counting too, so "notifications preview" finds the switch).
List<SettingsHit> searchSettings(BuildContext context, SettingsModel model, List<SettingsSection> sections, String query, {int limit = 40}) {
  final found = <SettingsHit>[];
  final settings = <SettingsHit>[];
  final seen = <String>{};
  for (final s in sections) {
    if (settingsMatch(query, '${s.label} ${s.summary?.call(model) ?? ''}')) found.add(SettingsHit(s));
    if (s.screen != null) continue;
    for (final (label, detail) in pageEntries(s.page(context, model))) {
      if (label == s.label || !seen.add('${s.id}|$label')) continue;
      if (settingsMatch(query, '$label $detail ${s.label}')) settings.add(SettingsHit(s, setting: label));
    }
  }
  return [...found, ...settings].take(limit).toList();
}
