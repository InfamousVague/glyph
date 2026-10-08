import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../settings_search.dart';
import '../settings_sections.dart' show SettingsNotPortedCard, settingsSections;
import 'pane_parts.dart';
import 'settings_host.dart';

/// The Privacy card's names (AccountPane.findable.ts `privacy`, for the app, where a model runs).
const List<SettingsFindable> privacyFindable = [
  SettingsFindable('Privacy', 'what leaves the phone'),
  SettingsFindable('Local only', 'offline privacy network internet nothing leaves the phone'),
  SettingsFindable('Link previews', 'links url cards'),
  SettingsFindable('Look up blanks online', 'fill blank weather rates wikipedia web live internet'),
  SettingsFindable('Privacy policy', 'data privacy personal information policy'),
];

/// The Location card's names (AccountPane.findable.ts `LOCATION`).
const List<SettingsFindable> locationFindable = [
  SettingsFindable('Location', 'map place where geotag gps'),
  SettingsFindable('Map on a tagged note', 'openstreetmap tiles'),
  SettingsFindable('Place names', 'nominatim address geocode'),
  SettingsFindable('Tag new notes with my location', 'automatic gps position geotag place where front matter'),
];

/// What Settings' search finds on Account signed out (`findable(false, true)`, src/app/settings/AccountPane.findable.ts):
/// the ways in, then the Privacy and Location cards. Signed in, the account's own page is not ported, and nothing of
/// it is listed.
List<SettingsFindable> accountFindable({required bool signedIn}) => signedIn
    ? const []
    : const [
        SettingsFindable('I have an account', 'sign in login'),
        SettingsFindable('Create an account', 'sign up register'),
        SettingsFindable('Lost the password', 'forgot recovery code reset'),
        ...privacyFindable,
        ...locationFindable,
      ];

/// Account's row in the list, signed out (core/sync/engine.ts `syncSummary` with no handle): Local only holds the
/// sync off, so the line says it is on.
String accountSummary(Preferences prefs) => 'Not signed in${prefs.localOnly ? ' · Local only' : ''}';

/// The privacy policy (landing/privacy.html), on the download site (`PRIVACY_URL`).
const String privacyUrl = 'https://ghostmarkdown.com/privacy.html';

/// Port of `AccountPane` (src/app/settings/AccountPane.tsx) **signed out** (`SignedOut`): the ghost, the way in (sign
/// in, make an account, or recover one, with a new account's recovery codes shown once), the three rows that change
/// which, what a lost password means, and then what leaves the phone: the Privacy card ([PrivacyCard]) and the
/// Location card ([LocationCard]). While Local only holds the sync off, a callout says so, and its "Local only" is a
/// word that brings the card into view.
///
/// What differs from the web original:
/// - **There is no account yet** (stage 7). The form is the page's, and its button runs
///   [SettingsFeatures.onWayIn]; until that is given the button cannot be pressed whatever is typed. The page's
///   early checks of a handle and a password (`handleProblem`, `passwordProblem`) are the account's to port, so
///   they are the callback's to make, and what it throws is said under the fields.
/// - **Signed in** ([SettingsFeatures.signedIn]) the account's own page (the hero, Sync, the password, the colour,
///   shared links, Delete account) is not ported: it draws the card that says so, then Privacy and Location, which
///   are on the page either way.
/// - The form's fields are the kit's `GlacierInput`; a password manager is not told which is which
///   (`autocomplete`) beyond what the kit passes on.
class AccountPane extends StatefulWidget {
  const AccountPane({super.key, this.store, this.features = const SettingsFeatures(), this.onOpenPrivacy, this.onOpenLink});

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;
  final SettingsFeatures features;

  /// Brings the Privacy card into view (`onOpen({ id: 'account', setting: 'Privacy' })`).
  final VoidCallback? onOpenPrivacy;
  final void Function(String url)? onOpenLink;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return AccountPane(
      features: host?.features ?? const SettingsFeatures(),
      onOpenPrivacy: host == null ? null : () => host.go('account', setting: 'Privacy'),
      onOpenLink: host?.onOpenLink,
    );
  }

  @override
  State<AccountPane> createState() => _AccountPaneState();
}

class _AccountPaneState extends State<AccountPane> {
  /// `in`, `up` or `recover` (`Mode`).
  String _mode = 'in';
  String _handle = '', _password = '', _code = '';
  bool _busy = false;
  String? _problem;
  List<String>? _codes;

  void _setMode(String next) => setState(() {
        _mode = next;
        _problem = null;
      });

  Future<void> _submit() async {
    final wayIn = widget.features.onWayIn;
    if (wayIn == null || _busy || _handle.isEmpty || _password.isEmpty || (_mode == 'recover' && _code.isEmpty)) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final codes = await wayIn(mode: _mode, handle: _handle, password: _password, code: _mode == 'recover' ? _code : null);
      if (mounted && codes != null) setState(() => _codes = codes);
    } catch (failure) {
      if (mounted) setState(() => _problem = failureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store ?? preferences;
    final features = widget.features;
    final codes = _codes;
    // A new or recovered account's codes, shown this once (`Codes`).
    if (codes != null) return PaneBody(children: [RecoveryCodes(codes: codes, onDone: () => setState(() => _codes = null))]);

    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) {
        final t = context.tokens;
        final privacy = PrivacyCard(store: store, onOpenLink: widget.onOpenLink);
        final location = LocationCard(store: store, onLocate: features.onLocate, cannot: features.cannotLocate);
        if (features.signedIn) {
          return PaneBody(children: [SettingsNotPortedCard(spec: settingsSections.firstWhere((spec) => spec.id == 'account')), privacy, ...location.parts(prefs)]);
        }
        final verb = _mode == 'up' ? 'Create account' : (_mode == 'recover' ? 'Recover and set password' : 'Sign in');
        final ready = !_busy && _handle.isNotEmpty && _password.isNotEmpty && (_mode != 'recover' || _code.isNotEmpty) && features.onWayIn != null;
        return PaneBody(
          children: [
            if (prefs.localOnly)
              SettingsCallout(
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Local only', onPress: widget.onOpenPrivacy)),
                      const TextSpan(text: ' is on, so nothing syncs until it is off.'),
                    ],
                  ),
                ),
              ),
            const Ghost(scene: GhostScene.signedOut, align: GhostAlign.center),
            PaneSection(
              title: _mode == 'up' ? 'New account' : (_mode == 'recover' ? 'Recover' : 'Sign in'),
              description: const Text('Keep your notes, recordings and settings the same on your phone and computer. They are encrypted on the device first. The service stores only what it cannot read.'),
              children: [
                // `.setk-form`: the fields in a column a `--glacier-space-2` apart, in a row's padding.
                Padding(
                  padding: EdgeInsets.all(t.space(3)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlacierInput(
                        ariaLabel: 'Handle',
                        placeholder: 'Handle',
                        autoCapitalize: TextCapitalization.none,
                        spellCheck: false,
                        autoCorrect: false,
                        value: _handle,
                        onChange: (text) => setState(() => _handle = text),
                      ),
                      if (_mode == 'recover') ...[
                        SizedBox(height: t.space(2)),
                        GlacierInput(
                          ariaLabel: 'Recovery code',
                          placeholder: 'Recovery code',
                          autoCapitalize: TextCapitalization.characters,
                          spellCheck: false,
                          autoCorrect: false,
                          value: _code,
                          onChange: (text) => setState(() => _code = text),
                        ),
                      ],
                      SizedBox(height: t.space(2)),
                      GlacierInput(
                        ariaLabel: _mode == 'recover' ? 'New password' : 'Password',
                        placeholder: _mode == 'recover' ? 'New password' : 'Password',
                        type: GlacierInputType.password,
                        value: _password,
                        onChange: (text) => setState(() => _password = text),
                        onSubmitted: (_) => unawaited(_submit()),
                      ),
                      if (_problem != null) ...[
                        SizedBox(height: t.space(2)),
                        Semantics(liveRegion: true, child: Text(_problem!, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink')))),
                      ],
                      SizedBox(height: t.space(2)),
                      // `.app-word.setk-form__submit { align-self: flex-start }`
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DefaultTextStyle(
                          style: pageText(t, t.lenOf('1rem')),
                          child: SettingsWord(key: const ValueKey('account-submit'), onPressed: ready ? () => unawaited(_submit()) : null, child: Text(_busy ? 'One moment…' : verb)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            PaneSection(
              children: [
                if (_mode != 'in') SettingRow(label: 'I have an account', onPress: () => _setMode('in')),
                if (_mode != 'up') SettingRow(label: 'Create an account', onPress: () => _setMode('up')),
                if (_mode != 'recover') SettingRow(label: 'Lost the password', hint: const Text('Use one of your recovery codes.'), onPress: () => _setMode('recover')),
              ],
            ),
            const SettingsFootnote(
              child: Text("Your password never leaves this device, and nobody can reset it for you. Without it or a recovery code, the notes in an account can't be opened by anyone. Notes on this device stay here either way."),
            ),
            privacy,
            ...location.parts(prefs),
          ],
        );
      },
    );
  }
}

/// A new account's recovery codes (AccountPane.tsx `Codes`, `.setk-codes`): two columns of them, Copy all, and the
/// word that puts them away.
class RecoveryCodes extends StatelessWidget {
  const RecoveryCodes({super.key, required this.codes, required this.onDone});
  final List<String> codes;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    final style = pageText(t, md, tracking: 0.04 * md, mono: true);
    return PaneSection(
      title: 'Recovery codes',
      description: const Text('Keep these somewhere safe, away from this device. Each opens your account once if the password is lost. They are shown this once and never again.'),
      footer: Align(alignment: AlignmentDirectional.centerStart, child: RowAction(onPress: onDone, child: const Text("I've kept them"))),
      children: [
        Padding(
          padding: EdgeInsets.all(t.space(3)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < codes.length; i += 2) ...[
                if (i > 0) SizedBox(height: t.space(2)),
                Row(
                  children: [
                    Expanded(child: Text(codes[i], style: style)),
                    SizedBox(width: t.space(4)),
                    Expanded(child: i + 1 < codes.length ? Text(codes[i + 1], style: style) : const SizedBox.shrink()),
                  ],
                ),
              ],
            ],
          ),
        ),
        SettingRow(label: 'Copy all', onPress: () => unawaited(Clipboard.setData(ClipboardData(text: codes.join('\n'))))),
      ],
    );
  }
}

/// Port of `PrivacyCard` (src/app/settings/PrivacyCard.tsx): the switches that decide what leaves the device, and the
/// policy with what it comes to in two lines. Local only is the whole network switch; Link previews says whether a
/// link's card is drawn at all; Look up blanks online is greyed off under Local only, which keeps such blanks
/// waiting. Each is a stored preference (`localOnly`, `linkPreviews`, `lookUpBlanks`), live at once.
///
/// What differs from the web original: the words are the app's (the page had a second set for a browser), and the
/// policy's row opens its link through [onOpenLink], or cannot be pressed without one. Nothing reads these switches
/// yet but Settings' own rows: there is no sync, link card or fill to hold off.
class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key, this.store, this.onOpenLink});
  final PreferencesStore? store;
  final void Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? preferences;
    final open = onOpenLink;
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) => PaneSection(
        title: 'Privacy',
        footer: const Text(
          'Your notes, recordings and pictures stay on this device, and your voice is turned into text here. Signed in, they sync encrypted on the device first, so only your own devices can read them. No ads, no analytics, no tracking.',
        ),
        children: [
          SettingRow(
            label: 'Local only',
            hint: const Text('No sync, updates, downloads or link titles, and plugins that use the internet are held off. Ghost.md runs from what is on this device.'),
            control: GlacierSwitch(ariaLabel: 'Local only', checked: prefs.localOnly, onCheckedChange: (on) => store.update((now) => now.copyWith(localOnly: on))),
          ),
          SettingRow(
            label: 'Link previews',
            hint: const Text("A card under a line that is only a link. In the app, the page's title is read from that site."),
            control: GlacierSwitch(ariaLabel: 'Link previews', checked: prefs.linkPreviews, onCheckedChange: (on) => store.update((now) => now.copyWith(linkPreviews: on))),
          ),
          SettingRow(
            label: 'Look up blanks online',
            hint: const Text('On Fill, a blank that needs something live asks Open-Meteo, Frankfurter’s bank rates or Wikipedia. Only its question goes.'),
            control: GlacierSwitch(ariaLabel: 'Look up blanks online', checked: prefs.lookUpBlanks && !prefs.localOnly, onCheckedChange: (on) => store.update((now) => now.copyWith(lookUpBlanks: on))),
            disabledReason: prefs.localOnly ? 'Local only is on, so such blanks wait.' : null,
          ),
          SettingRow(
            icon: const AppIcon(Lucide.shieldCheck, size: 20),
            label: 'Privacy policy',
            hint: const Text('What stays on this device, and what an account, a shared link or a plugin sends.'),
            onPress: open == null ? () {} : () => open(privacyUrl),
            disabled: open == null,
          ),
        ],
      ),
    );
  }
}

/// Port of `LocationCard` (src/app/settings/LocationCard.tsx): where a note was written, and the three network things
/// it can mean. The map at the top of a tagged note, the place's name, and every new note starting with where the
/// device was: each is its own switch (`mapTiles`, `placeNames`, `tagNewNotes`), and Local only turns all of them
/// off.
///
/// It is more than one child of the page (the card, and a footnote while Local only is on), so a page lays out its
/// [parts]; on its own it is the card.
///
/// What differs from the web original: there is nothing that finds where the device is yet (core/location.ts).
/// Switching tagging on writes the preference and asks [onLocate] for the one fix the page asks for; what a refusal
/// then says under the card (and "Open settings") comes with that. [cannot] is why this device cannot tag, said under
/// the row as the page says "Update Ghost.md to tag notes."; it is null, and nothing is said, until something knows.
class LocationCard extends StatelessWidget {
  const LocationCard({super.key, this.store, this.onLocate, this.cannot});
  final PreferencesStore? store;
  final VoidCallback? onLocate;
  final String? cannot;

  /// The card and what follows it, as children of a page.
  List<Widget> parts(Preferences prefs) => [
        this,
        if (prefs.localOnly) const SettingsFootnote(child: Text('A tagged note shows where it was written and a pin while Local only is on, and no new location is taken.')),
      ];

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? preferences;
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) {
        final localOnly = prefs.localOnly ? 'Local only is on.' : null;
        return PaneSection(
          title: 'Location',
          description: const Text("A note can say where it was written. The place is kept in the note's own words, so it goes wherever the note does. A link you share leaves it out unless you say so on the note."),
          children: [
            SettingRow(
              label: 'Map on a tagged note',
              hint: const Text('A small map at the top of the note, and under each place you add. Opening one fetches the tiles from openstreetmap.org, which sees your IP address, as a website would.'),
              control: GlacierSwitch(ariaLabel: 'Map on a tagged note', checked: prefs.mapTiles, onCheckedChange: (on) => store.update((now) => now.copyWith(mapTiles: on))),
              disabledReason: localOnly,
            ),
            SettingRow(
              label: 'Place names',
              hint: const Text('The name of the place, asked of OpenStreetMap once when you add a location or a place, and kept in the note. Never asked again.'),
              control: GlacierSwitch(ariaLabel: 'Place names', checked: prefs.placeNames, onCheckedChange: (on) => store.update((now) => now.copyWith(placeNames: on))),
              disabledReason: localOnly,
            ),
            SettingRow(
              label: 'Tag new notes with my location',
              hint: const Text('Every note you make here starts with where you were, typed or spoken. Off, you add a location by hand from More on a note. This switch stays on this device.'),
              control: GlacierSwitch(
                ariaLabel: 'Tag new notes with my location',
                checked: prefs.tagNewNotes,
                onCheckedChange: (on) {
                  store.update((now) => now.copyWith(tagNewNotes: on));
                  // The ask, once, here: a fix now means the next new note's comes without a dialog.
                  if (on) onLocate?.call();
                },
              ),
              disabledReason: localOnly ?? cannot,
            ),
          ],
        );
      },
    );
  }
}
