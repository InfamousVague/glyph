import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/location.dart' show LocateFailure, whyLocateFailed;
import '../../core/place_tags.dart';
import '../../core/preferences.dart';
import '../../mail/ui/mail_card.dart';
import '../../sync/engine.dart' show syncSummary, syncedWhen, unsentLine;
import '../../sync/notes.dart' show longestSyncedSaid, stayedHere;
import '../account_forms.dart';
import '../colour_card.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../privacy_card.dart';
import '../published_sites.dart';
import '../settings_search.dart';
import '../settings_sections.dart' show SettingsNotPortedCard, settingsSections;
import '../shared_links.dart';
import 'ghostex_cards.dart';
import 'pane_parts.dart';
import 'settings_host.dart';
import '../../core/iphone_app.dart' show recordsVoice;

export '../privacy_card.dart' show PrivacyCard, privacyUrl;

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

/// What Settings' search finds on Account (`findable(signedIn, true)`, src/app/settings/AccountPane.findable.ts), by
/// the names the page draws: signed in the page is the account's, signed out it is the ways in, and the Privacy and
/// Location cards are on it either way. [ported] false is a build with no account to hand the page: its signed-in
/// page is the card that says so, and nothing of the account's own is listed.
List<SettingsFindable> accountFindable({required bool signedIn, bool ported = false, bool shared = false}) => signedIn
    ? (ported
        ? [
            const SettingsFindable('Sync now', 'devices'),
            // An iPhone records nothing, so it has no such switch (the row below).
            if (recordsVoice) const SettingsFindable('Sync meeting recordings', 'audio meeting meetings tapes'),
            const SettingsFindable('Live typing', 'realtime collaborate claude'),
            const SettingsFindable('Password and recovery codes', 'change'),
            const SettingsFindable('Sign out', 'log out logout'),
            // The page lists it always; here only while the card is drawn, so a hit always has somewhere to land.
            if (shared) const SettingsFindable('Shared links', 'share publish read'),
            ...privacyFindable,
            ...locationFindable,
            ghostexExportFindable,
            const SettingsFindable('Delete account', 'remove close erase data'),
          ]
        : const [])
    : const [
        SettingsFindable('I have an account', 'sign in login'),
        SettingsFindable('Create an account', 'sign up register'),
        SettingsFindable('Lost the password', 'forgot recovery code reset'),
        ...privacyFindable,
        ...locationFindable,
        ghostexExportFindable,
      ];

/// Account's row in the list (SettingsSheet.tsx: `syncSummary` with " · Local only" while that holds the sync off).
/// Without [services] it is the signed-out line.
String accountSummary(Preferences prefs, [AccountServices? services]) =>
    '${services == null ? 'Not signed in' : syncSummary(services.session?.handle, services.status, now: services.now())}${prefs.localOnly ? ' · Local only' : ''}';

/// Port of `AccountPane` (src/app/settings/AccountPane.tsx): a Ghost.md account keeps notes, their recordings and
/// pictures, and settings the same on every device. Everything is sealed on the device before it is sent, so the
/// page says so plainly, and says the one consequence that follows: a password and every recovery code lost is an
/// account nobody can open.
///
/// **Signed out** (`SignedOut`): the ghost, the way in (sign in, make an account, or recover one, with a new
/// account's recovery codes shown once), the three rows that change which, what a lost password means, and then
/// what leaves the phone: the Privacy card ([PrivacyCard]) and the Location card ([LocationCard]).
///
/// **Signed in**: the hero (the handle, "End-to-end encrypted", where the sync stands), what the last sync kept
/// twice or could not send, the Sync card (Sync now, Sync meeting recordings, Live typing, Password and recovery
/// codes, Sign out), then Your colour ([ColourCard]), Shared links ([SharedLinks]), Privacy, Location, and Delete
/// account. Password and recovery codes, and Delete account, each put a form where the Sync card was and take the
/// cards after it off the page until it is done or cancelled.
///
/// While Local only holds the sync off, a callout says so, signed in or out, and its "Local only" is a word that
/// brings the card into view: a plain word while a form has the card off the page.
///
/// What differs from the web original:
/// - The account is the [AccountServices] the page is handed ([services], or the [AccountScope] over Settings),
///   where the page reached for its modules. **Without one the page is as it was before there was an account**:
///   signed out, with the button running [SettingsFeatures.onWayIn] (or unpressable without it), and
///   [SettingsFeatures.signedIn] drawing the card that says the signed-in page waits.
/// - How many recordings stayed on this phone is counted from [AccountServices.listNotes], and is none without it.
/// - Live typing's switch writes [AccountServices.liveTyping], which the app's account keeps as this device's own
///   flag (the page's `glyph-live`; lib/root/account_wiring.dart): a note opened after it is on is live.
/// - The form's fields are the kit's `GlacierInput`; a password manager is not told which is which
///   (`autocomplete`) beyond what the kit passes on.
/// - There is no list of this account's devices: the web's page has none either.
class AccountPane extends StatefulWidget {
  const AccountPane({super.key, this.store, this.features = const SettingsFeatures(), this.services, this.onOpenPrivacy, this.onOpenLink});

  /// The preferences to read and write; the services' when there are some, else the app's own.
  final PreferencesStore? store;
  final SettingsFeatures features;

  /// The account; null draws the page as it was before there was one.
  final AccountServices? services;

  /// Brings the Privacy card into view (`onOpen({ id: 'account', setting: 'Privacy' })`).
  final VoidCallback? onOpenPrivacy;
  final void Function(String url)? onOpenLink;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return AccountPane(
      features: host?.features ?? const SettingsFeatures(),
      services: AccountScope.maybeOf(context),
      onOpenPrivacy: host == null ? null : () => host.go('account', setting: 'Privacy'),
      onOpenLink: host?.onOpenLink,
    );
  }

  @override
  State<AccountPane> createState() => _AccountPaneState();
}

/// The way-in form's state and its submit, for the long form (`SignedOut`) and the card ([SignInFlow]) alike
/// (`useWayIn`).
class WayIn extends ChangeNotifier {
  WayIn({required this.submitWith, this.onCodes, this.onIn});

  /// Runs the way in: [AccountServices.wayIn], or a page's own. Null leaves the button unpressable.
  final SettingsWayIn? Function() submitWith;
  final ValueChanged<List<String>>? onCodes;
  final VoidCallback? onIn;

  /// `in`, `up` or `recover` (`Mode`).
  String mode = 'in';
  String handle = '', password = '', code = '';
  bool busy = false;
  String? problem;
  bool _gone = false;

  void _tell() {
    if (!_gone) notifyListeners();
  }

  void setMode(String next) {
    mode = next;
    problem = null;
    _tell();
  }

  void set({String? handle, String? password, String? code}) {
    this.handle = handle ?? this.handle;
    this.password = password ?? this.password;
    this.code = code ?? this.code;
    _tell();
  }

  bool get ready => !busy && handle.isNotEmpty && password.isNotEmpty && (mode != 'recover' || code.isNotEmpty) && submitWith() != null;

  String get verb => mode == 'up' ? 'Create account' : (mode == 'recover' ? 'Recover and set password' : 'Sign in');

  Future<void> submit() async {
    final wayIn = submitWith();
    if (wayIn == null || !ready) return;
    busy = true;
    problem = null;
    _tell();
    try {
      final codes = await wayIn(mode: mode, handle: handle, password: password, code: mode == 'recover' ? code : null);
      if (codes != null) {
        onCodes?.call(codes);
      } else {
        onIn?.call();
      }
    } catch (failure) {
      problem = failureText(failure);
    }
    busy = false;
    _tell();
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }
}

/// The way-in form (`WayInForm`): the handle, a recovery code when recovering, the password, what went wrong, and
/// the word that submits. [bare] is the form in the sign-in card, unpadded and with its word across the card.
class WayInForm extends StatelessWidget {
  const WayInForm({super.key, required this.form, this.bare = false});
  final WayIn form;
  final bool bare;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: form,
        builder: (context, _) {
          final recover = form.mode == 'recover';
          final problem = form.problem;
          return SettingsForm(
            bare: bare,
            children: [
              GlacierInput(
                ariaLabel: 'Handle',
                placeholder: 'Handle',
                autoCapitalize: TextCapitalization.none,
                spellCheck: false,
                autoCorrect: false,
                value: form.handle,
                onChange: (text) => form.set(handle: text),
              ),
              if (recover)
                GlacierInput(
                  ariaLabel: 'Recovery code',
                  placeholder: 'Recovery code',
                  autoCapitalize: TextCapitalization.characters,
                  spellCheck: false,
                  autoCorrect: false,
                  value: form.code,
                  onChange: (text) => form.set(code: text),
                ),
              GlacierInput(
                ariaLabel: recover ? 'New password' : 'Password',
                placeholder: recover ? 'New password' : 'Password',
                type: GlacierInputType.password,
                value: form.password,
                onChange: (text) => form.set(password: text),
                onSubmitted: (_) => unawaited(form.submit()),
              ),
              if (problem != null) FormProblem(problem),
              FormSubmit(wordKey: const ValueKey('account-submit'), form.busy ? 'One moment…' : form.verb, stretch: bare, onPressed: form.ready ? () => unawaited(form.submit()) : null),
            ],
          );
        },
      );
}

/// The callout while Local only holds the sync off; its words bring the Privacy card into view, where there is one
/// (`LocalOnlyCallout`).
class LocalOnlyCallout extends StatelessWidget {
  const LocalOnlyCallout({super.key, this.onOpen});
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => SettingsCallout(
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Local only', onPress: onOpen)),
              const TextSpan(text: ' is on, so nothing syncs until it is off.'),
            ],
          ),
        ),
      );
}

class _AccountPaneState extends State<AccountPane> {
  late final WayIn _form = WayIn(submitWith: () => widget.services?.wayIn ?? widget.features.onWayIn, onCodes: (codes) => setState(() => _codes = codes));
  List<String>? _codes;
  bool _editing = false;
  bool _deleting = false;

  /// Said on the signed-out page that follows a deletion, so it is clear the account went and the notes didn't.
  bool _deleted = false;

  /// How many recordings stayed on this phone, counted as the page opens and whenever the two rules change.
  int _stayed = 0;
  Object? _stayedFor;
  SharedLinksModel? _shared;

  PreferencesStore get _store => widget.store ?? widget.services?.prefs ?? preferences;

  @override
  void initState() {
    super.initState();
    final services = widget.services;
    if (services != null) _shared = SharedLinksModel(services)..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _shared?.removeListener(_changed);
    _shared?.dispose();
    _form.dispose();
    super.dispose();
  }

  void _countStayed(Preferences prefs) {
    final list = widget.services?.listNotes;
    final rules = (prefs.meetings, prefs.syncMeetingRecordings);
    if (list == null || rules == _stayedFor) return;
    _stayedFor = rules;
    unawaited(() async {
      try {
        final count = stayedHere(await list(), meetings: prefs.meetings, syncMeetingRecordings: prefs.syncMeetingRecordings);
        if (mounted && rules == _stayedFor) setState(() => _stayed = count);
      } catch (_) {
        // The footer says nothing of them.
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final features = widget.features;
    final services = widget.services;
    final codes = _codes;
    // A new or recovered account's codes, shown this once (`Codes`).
    if (codes != null) return PaneBody(children: [RecoveryCodes(codes: codes, onDone: () => setState(() => _codes = null))]);

    return AccountBuilder(
      services: services,
      builder: (context) => ValueListenableBuilder<Preferences>(
        valueListenable: store,
        builder: (context, prefs, _) {
          final privacy = PrivacyCard(store: store, onOpenLink: widget.onOpenLink);
          final location = LocationCard(store: store, onLocate: features.onLocate, cannot: features.cannotLocate, places: features.places);
          if (services == null && features.signedIn) {
            return PaneBody(children: [SettingsNotPortedCard(spec: settingsSections.firstWhere((spec) => spec.id == 'account')), privacy, ...location.parts(prefs), GhostexExportCard(ghostex: features.ghostex)]);
          }
          if (services == null || !services.signedIn) return _signedOut(prefs, privacy, location);
          _countStayed(prefs);
          return _signedIn(services, store, prefs, privacy, location);
        },
      ),
    );
  }

  Widget _signedOut(Preferences prefs, Widget privacy, LocationCard location) => ListenableBuilder(
        listenable: _form,
        builder: (context, _) {
          final mode = _form.mode;
          return PaneBody(
            children: [
              if (_deleted) const SettingsCallout(child: Text('Your account is deleted. The notes on this device are still here.')),
              if (prefs.localOnly) LocalOnlyCallout(onOpen: widget.onOpenPrivacy),
              const Ghost(scene: GhostScene.signedOut, align: GhostAlign.center),
              PaneSection(
                title: mode == 'up' ? 'New account' : (mode == 'recover' ? 'Recover' : 'Sign in'),
                // An iPhone records nothing ([recordsVoice]): its sentences leave recordings and the model out.
                description: Text('Keep your ${recordsVoice ? 'notes, recordings and settings' : 'notes and settings'} the same on your phone and computer. They are encrypted on the device first. The service stores only what it cannot read.'),
                children: [WayInForm(form: _form)],
              ),
              PaneSection(
                children: [
                  if (mode != 'in') SettingRow(label: 'I have an account', onPress: () => _form.setMode('in')),
                  if (mode != 'up') SettingRow(label: 'Create an account', onPress: () => _form.setMode('up')),
                  if (mode != 'recover') SettingRow(label: 'Lost the password', hint: const Text('Use one of your recovery codes.'), onPress: () => _form.setMode('recover')),
                ],
              ),
              const SettingsFootnote(
                child: Text("Your password never leaves this device, and nobody can reset it for you. Without it or a recovery code, the notes in an account can't be opened by anyone. Notes on this device stay here either way."),
              ),
              privacy,
              ...location.parts(prefs),
              GhostexExportCard(ghostex: widget.features.ghostex),
            ],
          );
        },
      );

  Widget _signedIn(AccountServices services, PreferencesStore store, Preferences prefs, Widget privacy, LocationCard location) {
    final status = services.status;
    final lastAt = status.lastAt;
    final statusText = status.phase == 'syncing'
        ? 'Syncing'
        : status.phase == 'error'
            ? (status.message ?? 'Not synced')
            : lastAt != null && lastAt != 0
                ? 'Synced ${syncedWhen(lastAt, now: services.now())}'
                : services.unlocked
                    ? 'Waiting to sync'
                    : 'Sign in again to sync';
    final form = _editing || _deleting;
    final shared = _shared;
    final stayed = _stayed;
    // The account's published sites and its mail address are the service's to say (docs/SITES.md, docs/MAIL.md).
    services.sites?.readSoon();
    services.mailIn?.readSoon();
    services.meetIn?.readSoon();
    final sites = services.sites, mail = services.mailIn;
    return PaneBody(
      children: [
        PaneSection(
          children: [
            PaneHero(
              glyph: const AppIcon(Lucide.shieldCheck, size: 22),
              title: services.session!.handle,
              meta: const Text('End-to-end encrypted'),
              status: PaneHeroStatus(statusText, pulse: status.phase == 'syncing'),
            ),
          ],
        ),
        if (status.conflicts != 0)
          SettingsCallout(child: Text('${status.conflicts == 1 ? 'A note was' : '${status.conflicts} notes were'} changed on two devices at once. Both versions are kept as separate notes.')),
        if (status.unsent != 0) SettingsCallout(child: Text('${unsentLine(status.unsent)}. ${status.unsentReason ?? 'They are sent again next time.'}')),
        // The password and delete forms take the Privacy card off the page: the word has nowhere to go while one is open.
        if (prefs.localOnly) LocalOnlyCallout(onOpen: form ? null : widget.onOpenPrivacy),
        if (_deleting)
          DeleteAccountForm(
            services: services,
            onDeleted: () => setState(() {
              _deleting = false;
              _deleted = true;
            }),
            onDone: () => setState(() => _deleting = false),
          )
        else if (_editing)
          PasswordForm(
            services: services,
            onCodes: (next) => setState(() {
              _editing = false;
              _codes = next;
            }),
            onDone: () => setState(() => _editing = false),
          )
        else
          PaneSection(
            title: 'Sync',
            footer: Text(
              '${recordsVoice ? 'Notes, their recordings and pictures, and your settings. The model you downloaded and Developer settings stay on each device.' : 'Notes, their pictures, and your settings. Developer settings stay on each device.'}${stayed != 0 ? ' ${stayed == 1 ? '1 recording' : '$stayed recordings'} stayed on this phone: ${prefs.syncMeetingRecordings ? 'longer than the account takes, over $longestSyncedSaid.' : 'meetings, while their recordings stay, and any over $longestSyncedSaid.'}' : ''}',
            ),
            children: [
              SettingRow(icon: const AppIcon(Lucide.refreshCw, size: 20), label: 'Sync now', onPress: () => unawaited(services.syncNow()), disabled: status.phase == 'syncing'),
              if (recordsVoice) SettingRow(
                label: 'Sync meeting recordings',
                hint: const Text("On, a meeting's audio goes to your other devices, and with a team's note to everyone in the team. A meeting is other people's voices: off, the words sync and the audio stays on the device it was made on."),
                control: GlacierSwitch(
                  ariaLabel: 'Sync meeting recordings',
                  checked: prefs.syncMeetingRecordings,
                  onCheckedChange: (on) => store.update((now) => now.copyWith(syncMeetingRecordings: on, syncMeetingRecordingsChosen: true)),
                ),
              ),
              // Live sync (docs/LIVE.md), on unless turned off here (docs/CLAUDE_LIVE.md).
              SettingRow(
                label: 'Live typing',
                hint: const Text('A note open on two of your devices, or one Claude is writing in, shows the words as they are typed, end to end encrypted like everything else. Starts with the next note you open.'),
                control: GlacierSwitch(ariaLabel: 'Live typing', checked: services.liveTyping.value, onCheckedChange: (on) => services.liveTyping.value = on),
              ),
              SettingRow(icon: const AppIcon(Lucide.keyRound, size: 20), label: 'Password and recovery codes', onPress: () => setState(() => _editing = true)),
              SettingRow(icon: const AppIcon(Lucide.logOut, size: 20), label: 'Sign out', hint: const Text('Your notes stay on this device.'), onPress: () => unawaited(services.signOut())),
            ],
          ),
        if (!form) ...[
          ColourCard(services: services),
          if (shared != null && shared.any) SharedLinks(services: services, model: shared),
          if (sites != null && publishedSitesShown(sites)) PublishedSites(services: services),
          if (mail != null && mailCardShown(mail)) MailCard(services: services),
          privacy,
          ...location.parts(prefs),
          GhostexExportCard(ghostex: widget.features.ghostex),
          PaneSection(
            children: [
              SettingRow(
                icon: const AppIcon(Lucide.trash2, size: 20),
                label: 'Delete account',
                hint: const Text('Your account and everything synced to it. The notes on this device stay.'),
                onPress: () => setState(() => _deleting = true),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The password changed, or a new sheet of recovery codes made, each needing the current password
/// (AccountPane.tsx `PasswordForm`).
class PasswordForm extends StatefulWidget {
  const PasswordForm({super.key, required this.services, required this.onCodes, required this.onDone});
  final AccountServices services;
  final ValueChanged<List<String>> onCodes;
  final VoidCallback onDone;

  @override
  State<PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<PasswordForm> {
  /// `password` or `codes`.
  String _what = 'password';
  String _current = '', _next = '';
  bool _busy = false;
  String? _problem;

  bool get _ready => !_busy && _current.isNotEmpty && (_what != 'password' || _next.isNotEmpty);

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      if (_what == 'password') {
        await widget.services.account.changePassword(_current, _next);
        if (mounted) widget.onDone();
        return;
      }
      final made = await widget.services.account.newRecoveryCodes(_current);
      if (mounted) widget.onCodes(made.codes);
      return;
    } catch (failure) {
      if (mounted) setState(() => _problem = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final password = _what == 'password';
    final problem = _problem;
    return PaneSection(
      title: password ? 'Change password' : 'New recovery codes',
      footer: Align(alignment: AlignmentDirectional.centerStart, child: RowAction(onPress: widget.onDone, child: const Text('Cancel'))),
      children: [
        SettingsForm(
          children: [
            GlacierInput(ariaLabel: 'Current password', placeholder: 'Current password', type: GlacierInputType.password, value: _current, onChange: (text) => setState(() => _current = text), onSubmitted: (_) => unawaited(_submit())),
            if (password)
              GlacierInput(ariaLabel: 'New password', placeholder: 'New password', type: GlacierInputType.password, value: _next, onChange: (text) => setState(() => _next = text), onSubmitted: (_) => unawaited(_submit())),
            if (problem != null) FormProblem(problem),
            FormSubmit(_busy ? 'One moment…' : (password ? 'Change password' : 'Make new codes'), onPressed: _ready ? () => unawaited(_submit()) : null),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DefaultTextStyle(
                style: pageText(t, t.lenOf('1rem')),
                child: SettingsWord(
                  onPressed: () => setState(() {
                    _what = password ? 'codes' : 'password';
                    _problem = null;
                  }),
                  child: Text(password ? 'Make new recovery codes instead' : 'Change the password instead'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Deleting the account (AccountPane.tsx `DeleteAccountForm`; App Store 5.1.1(v) and Google Play both ask for it in
/// the app): what goes and what stays said first, then the password asked for, as a phone left unlocked shouldn't
/// be able to lose its owner's account. Everything the account keeps on the service goes at once and for good; the
/// notes on this device stay.
class DeleteAccountForm extends StatefulWidget {
  const DeleteAccountForm({super.key, required this.services, required this.onDeleted, required this.onDone});
  final AccountServices services;
  final VoidCallback onDeleted;
  final VoidCallback onDone;

  @override
  State<DeleteAccountForm> createState() => _DeleteAccountFormState();
}

class _DeleteAccountFormState extends State<DeleteAccountForm> {
  String _password = '';
  bool _busy = false;
  String? _problem;

  Future<void> _submit() async {
    if (_busy || _password.isEmpty) return;
    // Read before the wait: the page under this form is the signed-out one by the time the account is gone.
    final deleted = widget.onDeleted;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.services.deleteAccount(_password);
      deleted();
    } catch (failure) {
      if (mounted) {
        setState(() {
          _problem = accountFailureText(failure);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return PaneSection(
      title: 'Delete account',
      description: const Text(
        "This deletes your account and everything it keeps on the sync service, for good: your synced notes, their recordings and pictures, your settings, and every link you've shared, which will stop opening. Your other devices are signed out. The notes on this device stay here.",
      ),
      footer: Align(alignment: AlignmentDirectional.centerStart, child: RowAction(onPress: widget.onDone, child: const Text('Cancel'))),
      children: [
        SettingsForm(
          children: [
            GlacierInput(ariaLabel: 'Password', placeholder: 'Password', type: GlacierInputType.password, value: _password, onChange: (text) => setState(() => _password = text), onSubmitted: (_) => unawaited(_submit())),
            if (problem != null) FormProblem(problem),
            FormSubmit(wordKey: const ValueKey('delete-account-submit'), _busy ? 'Deleting…' : 'Delete my account', onPressed: _busy || _password.isEmpty ? null : () => unawaited(_submit())),
          ],
        ),
      ],
    );
  }
}

/// Port of `SignInFlow` (AccountPane.tsx): the way in on its own, as one plain card - sign in or make an account,
/// and keep a new account's recovery codes, or recover one. The first screen on open draws it
/// (lib/shell/account_gate.dart), told by [onIn] once the person is in: straight after a sign-in, and after the
/// codes are put away for a new or recovered account, so the codes are never skipped.
///
/// What differs from the web original: the flows are [AccountServices.wayIn], or [onWayIn] where a page has its
/// own; with neither, the card is drawn and its button cannot be pressed.
class SignInFlow extends StatefulWidget {
  const SignInFlow({super.key, this.services, this.onWayIn, required this.onIn});
  final AccountServices? services;
  final SettingsWayIn? onWayIn;
  final VoidCallback onIn;

  @override
  State<SignInFlow> createState() => _SignInFlowState();
}

class _SignInFlowState extends State<SignInFlow> {
  late final WayIn _form = WayIn(submitWith: () => widget.services?.wayIn ?? widget.onWayIn, onCodes: (codes) => setState(() => _codes = codes), onIn: () => widget.onIn());
  List<String>? _codes;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final codes = _codes;
    Widget card(String label, List<Widget> children) => Semantics(
          container: true,
          label: label,
          child: Container(
            key: const ValueKey('sign-in-card'),
            // `.setk-signIn`
            padding: EdgeInsets.fromLTRB(t.space(5), t.space(6), t.space(5), t.space(4)),
            decoration: BoxDecoration(color: t.color('app-paper'), borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: t.color('app-rule'))),
            child: DefaultTextStyle(
              style: pageText(t, t.lenOf('1rem'), color: t.color('glacier-text')),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) SizedBox(height: t.space(3)),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        );
    if (codes != null) return card('Recovery codes', [RecoveryCodes(codes: codes, onDone: widget.onIn)]);
    return ListenableBuilder(
      listenable: _form,
      builder: (context, _) {
        final mode = _form.mode;
        final recover = mode == 'recover';
        final sm = t.fontSize('sm');
        return card(mode == 'up' ? 'Create an account' : (recover ? 'Recover an account' : 'Sign in'), [
          Semantics(
            header: true,
            child: Text(mode == 'up' ? 'Create an account' : (recover ? 'Recover an account' : 'Sign in to Ghost.md'), style: pageText(t, t.fontSize('xl'), weight: 'semibold', color: t.color('glacier-text'))),
          ),
          Text(recover ? 'A recovery code and a new password open it again.' : 'Your notes, the same on every device, encrypted before they leave this one.', style: pageText(t, sm, color: t.color('glacier-text-subtle'))),
          if (!recover)
            GlacierSegmentedControl(
              ariaLabel: 'Sign in or sign up',
              fullWidth: true,
              size: GlacierSegmentedSize.sm,
              options: const [GlacierSegmentedOption(value: 'in', label: Text('Sign in')), GlacierSegmentedOption(value: 'up', label: Text('Sign up'))],
              value: mode,
              onValueChange: _form.setMode,
            ),
          WayInForm(form: _form, bare: true),
          Align(
            child: DefaultTextStyle(
              style: pageText(t, sm),
              child: SettingsWord(
                key: const ValueKey('sign-in-other'),
                color: t.color('glacier-text-subtle'),
                onPressed: () => _form.setMode(recover ? 'in' : 'recover'),
                child: Text(recover ? 'Back to sign in' : 'Lost the password?'),
              ),
            ),
          ),
        ]);
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

/// What the Location card says under itself once an ask was refused, here or by a new note's own
/// (lib/core/place_tags.dart `autoTagRefusal`): why new notes are not tagged, where to allow it, and the way there.
class _LocationRefused extends StatelessWidget {
  const _LocationRefused({required this.places});
  final PlaceTags places;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: places.refusals,
        builder: (context, _, _) {
          final refused = places.autoTagRefusal();
          if (refused == null) return const SizedBox.shrink();
          final blocked = refused == LocateFailure.blocked;
          return Padding(
            // The gap a page puts between its parts (`PaneBody`).
            padding: EdgeInsets.only(top: context.tokens.space(4)),
            child: SettingsFootnote(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: context.tokens.space(1),
              children: [
                Text('${blocked ? 'Location is off for Ghost.md, so new notes are not tagged. ' : 'Ghost.md wasn’t allowed to know where you are, so new notes are not tagged. '}${places.allowLocationWhere()} and they will be.'),
                if (blocked && places.locations.onPhone) RowAction(onPress: () => unawaited(places.locations.openSettings()), child: const Text('Open settings')),
              ],
            ),
            ),
          );
        },
      );
}

/// Port of `LocationCard` (src/app/settings/LocationCard.tsx): where a note was written, and the three network things
/// it can mean. The map at the top of a tagged note, the place's name, and every new note starting with where the
/// device was: each is its own switch (`mapTiles`, `placeNames`, `tagNewNotes`), and Local only turns all of them
/// off.
///
/// It is more than one child of the page (the card, and a footnote while Local only is on), so a page lays out its
/// [parts]; on its own it is the card.
///
/// Turning tagging on asks for a fix once, here, so the permission prompt happens in Settings and never over the
/// recorder. A refusal leaves the switch on: notes are simply not tagged until location is allowed, and the footnote
/// and each note's More sheet say so.
///
/// What differs from the web original: what finds where the device is comes in as [places]
/// (lib/core/place_tags.dart). Without it, as in a build with no phone half, switching tagging on writes the
/// preference and asks [onLocate], and [cannot] is why this device cannot tag, said under the row; a refusal is said
/// by a footnote that listens to [places] where the page kept it in the card's own state.
class LocationCard extends StatelessWidget {
  const LocationCard({super.key, this.store, this.onLocate, this.cannot, this.places});
  final PreferencesStore? store;
  final VoidCallback? onLocate;
  final String? cannot;
  final PlaceTags? places;

  /// The card and what follows it, as children of a page.
  List<Widget> parts(Preferences prefs) => [
        // The refusal's line brings its own gap and stands in the card's own place in the page: as a child of the
        // page with nothing to say it was an empty box with the page's gap over it, and the page ended 18px lower
        // than the web's (seen beside it on a phone).
        if (places != null && prefs.tagNewNotes && !prefs.localOnly)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [this, _LocationRefused(places: places!)])
        else
          this,
        if (prefs.localOnly) const SettingsFootnote(child: Text('A tagged note shows where it was written and a pin while Local only is on, and no new location is taken.')),
      ];

  /// Why tagging cannot happen here, under its switch (`CANNOT`).
  static const Map<LocateFailure, String> _cannot = <LocateFailure, String>{
    LocateFailure.localOnly: 'Local only is on.',
    LocateFailure.mac: 'This Mac can’t say where it is yet.',
    LocateFailure.ios: 'Ghost.md can’t find where you are on this device yet.',
    LocateFailure.none: 'This browser can’t say where you are.',
    LocateFailure.unavailable: 'Update Ghost.md to tag notes.',
  };

  /// The ask, once, here: a fix now means the next new note's comes without a dialog (`flipTagging`).
  void _locate() {
    final places = this.places;
    if (places == null) return onLocate?.call();
    places.locations.locate().then<void>((_) => places.forgetRefusal(), onError: (Object failure) {
      // Asked once: refused, the switch stays on and new notes are simply not tagged, nor asked for again.
      places.rememberRefusal(whyLocateFailed(failure));
    });
  }

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
              hint: Text('Every note you make here starts with where you were${recordsVoice ? ', typed or spoken' : ''}. Off, you add a location by hand from More on a note. This switch stays on this device.'),
              control: GlacierSwitch(
                ariaLabel: 'Tag new notes with my location',
                checked: prefs.tagNewNotes,
                onCheckedChange: (on) {
                  store.update((now) => now.copyWith(tagNewNotes: on));
                  if (on) _locate();
                },
              ),
              disabledReason: localOnly ?? cannot ?? _cannot[places?.locations.cannotLocate],
            ),
          ],
        );
      },
    );
  }
}
