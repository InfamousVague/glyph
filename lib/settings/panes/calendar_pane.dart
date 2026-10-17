import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../calendar/calendar.dart';
import '../../calendar/setup.dart';
import '../../core/preferences.dart';
import '../../sync/engine.dart' show syncedWhen;
import '../account_forms.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';

/// What Settings' search finds on Calendar: what the page draws now. Google's card is drawn where its sign-in is
/// offered ([offered]) or already connected, and the to-dos' once it is connected.
List<SettingsFindable> calendarFindable(Preferences prefs, {required bool offered}) {
  final google = calendarSetupOf(prefs).google != null;
  return [
    const SettingsFindable('Calendar addresses', 'calendar ical ics webcal address secret google outlook icloud fastmail events'),
    if (offered || google) const SettingsFindable('Google Calendar', 'google calendar connect sign in events two-way'),
    if (google) const SettingsFindable('To-dos on the calendar', 'to-do todo due date event google calendar export'),
  ];
}

/// The row's reading: Google, and how many addresses.
String calendarSummary(Preferences prefs) {
  final setup = calendarSetupOf(prefs);
  final count = setup.addresses.length;
  final addresses = count == 0 ? null : (count == 1 ? '1 address' : '$count addresses');
  if (setup.google != null) return ['Google', ?addresses].join(' · ');
  return addresses ?? 'None yet';
}

/// Settings › Calendar (docs/CALENDAR.md; the port's own, 2026-10-17): the calendars whose events the app shows in
/// queries, on a calendar of to-dos and on the home page's Today. Three cards:
///
/// - **Calendar addresses**: a calendar's secret iCal address pasted in (Google's, iCloud's, Outlook's, any), read
///   when the app opens and every 30 minutes; each listed by its calendar's name with how its last read went, and
///   Remove. The address itself is a secret, so it is never shown again.
/// - **Google Calendar**, where glyph-api has Google sign-in set up (`start` does not answer 503): Connect, which
///   opens Google in the browser and is collected when the person comes back; then the account's calendars, each a
///   switch, and Disconnect.
/// - **To-dos on the calendar**, once Google is connected: the switch, off until turned on, and which calendar.
///
/// Then the last read and what went wrong, with Read now. Everything chosen is kept with the account's settings, so
/// it follows the account; nothing is read with Local only on, which the page says.
class CalendarPane extends StatefulWidget {
  const CalendarPane({super.key, this.calendar, this.prefs});

  /// The calendars it shows and changes; the app's own when left out.
  final CalendarService? calendar;

  /// The preferences, for Local only; the service's own when left out.
  final PreferencesStore? prefs;

  static Widget hosted(BuildContext context) => const CalendarPane();

  @override
  State<CalendarPane> createState() => _CalendarPaneState();
}

class _CalendarPaneState extends State<CalendarPane> {
  CalendarService get _calendar => widget.calendar ?? calendar;
  PreferencesStore get _prefs => widget.prefs ?? _calendar.prefs;

  String _typed = '';
  String? _addProblem;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    unawaited(_calendar.checkOffered());
  }

  Future<void> _add() async {
    if (_adding) return;
    setState(() {
      _adding = true;
      _addProblem = null;
    });
    final problem = await _calendar.addAddress(_typed);
    if (!mounted) return;
    setState(() {
      _adding = false;
      _addProblem = problem;
      if (problem == null) _typed = '';
    });
  }

  String _statusLine(String source, {required bool local}) {
    if (local) return 'Not read while Local only is on.';
    final status = _calendar.statusOf(source);
    if (status == null) return 'Not read yet.';
    return status.problem ?? 'Read ${syncedWhen(status.at)}.';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_calendar, _prefs]),
      builder: (context, _) {
        final service = _calendar;
        final setup = service.setup;
        final local = _prefs.value.localOnly;
        final google = setup.google;
        final offered = service.offered == true || google != null;
        final calendars = service.googleCalendars;
        final read = service.lastRead;
        final target = google == null ? null : service.todoCalendarOf(google);
        final writable = [for (final each in calendars) if (each.writable) each];
        return PaneBody(
          children: [
            if (local) const SettingsCallout(child: Text('Local only is on: no calendar is read until it is off (Settings › Account).')),
            PaneSection(
              title: 'Calendar addresses',
              description: const Text(
                'Paste a calendar’s secret address in iCal format: in Google Calendar it is under the calendar’s settings, Integrate calendar. iCloud, Outlook and Fastmail give one too. Read when the app opens and every 30 minutes.',
              ),
              children: [
                for (final address in setup.addresses)
                  SettingRow(
                    key: ValueKey('calendar-address-${address.id}'),
                    icon: const AppIcon(Lucide.calendarDays, size: 16),
                    label: address.label,
                    hint: Text(_statusLine('ical:${address.id}', local: local)),
                    control: RowAction(onPress: () => service.removeAddress(address.id), child: const Text('Remove')),
                  ),
                SettingsForm(
                  children: [
                    GlacierInput(
                      ariaLabel: 'Calendar address',
                      placeholder: 'https:// or webcal://',
                      type: GlacierInputType.url,
                      autoCorrect: false,
                      spellCheck: false,
                      value: _typed,
                      onChange: (text) => setState(() => _typed = text),
                      onSubmitted: (_) => unawaited(_add()),
                    ),
                    if (_addProblem != null) FormProblem(_addProblem!),
                    FormSubmit(wordKey: const ValueKey('calendar-add'), _adding ? 'Adding…' : 'Add', onPressed: !_adding && _typed.trim().isNotEmpty ? () => unawaited(_add()) : null),
                  ],
                ),
              ],
            ),
            if (offered)
              PaneSection(
                title: 'Google Calendar',
                description: const Text('Signed in, Ghost.md reads the calendars you tick, every 15 minutes, and can put your to-dos on one. Signing in goes through ghostmarkdown.com; your notes never do.'),
                children: [
                  if (google == null)
                    SettingRow(
                      label: service.connecting ? 'Finish signing in on Google' : 'Connect Google Calendar',
                      hint: Text(service.problem ?? (service.connecting ? 'Allow Ghost.md, then come back here.' : 'Google opens in your browser and asks what Ghost.md may see.')),
                      control: RowAction(onPress: () => unawaited(service.connectGoogle()), child: Text(service.connecting ? 'Open again' : 'Connect')),
                    )
                  else ...[
                    SettingRow(
                      label: 'Connected',
                      hint: Text(_statusLine(googleSource, local: local)),
                      control: RowAction(onPress: service.disconnectGoogle, child: const Text('Disconnect')),
                    ),
                    if (calendars.isEmpty)
                      const SettingRow(label: 'Looking for your calendars…')
                    else
                      for (final each in calendars)
                        SettingRow(
                          key: ValueKey('google-calendar-${each.id}'),
                          label: each.name,
                          hint: each.primary ? const Text('Your own calendar') : null,
                          control: GlacierSwitch(ariaLabel: 'Show ${each.name}', checked: google.ticked.contains(each.id), onCheckedChange: (on) => service.tick(each.id, on)),
                        ),
                  ],
                ],
              ),
            if (google != null)
              PaneSection(
                title: 'To-dos on the calendar',
                description: const Text('Every open to-do with a due date becomes an all-day event, linked back to its note. A new date moves it; ticked or removed, it goes. Events Ghost.md did not make are never changed.'),
                children: [
                  SettingRow(
                    label: 'To-dos on the calendar',
                    control: GlacierSwitch(ariaLabel: 'To-dos on the calendar', checked: google.todos, onCheckedChange: service.setTodos),
                  ),
                  if (google.todos)
                    for (final each in writable)
                      SettingRow(
                        key: ValueKey('todo-calendar-${each.id}'),
                        label: each.name,
                        hint: each.primary ? const Text('Your own calendar') : null,
                        control: Pick(checked: target == each.id, label: 'Put to-dos on ${each.name}', onPress: () => service.setTodoCalendar(each.id)),
                      ),
                ],
              ),
            if (!setup.isEmpty)
              PaneSection(
                children: [
                  SettingRow(
                    icon: const AppIcon(Lucide.refreshCw, size: 20),
                    label: 'Read now',
                    hint: Text(local ? 'Not while Local only is on.' : (read.problem ?? (read.at == null ? 'Not read yet.' : 'Last read ${syncedWhen(read.at!)}.'))),
                    onPress: () => unawaited(service.syncNow()),
                    disabled: local || service.busy,
                  ),
                ],
              ),
            const SettingsFootnote(
              child: Text('The events are kept on this device and shown in queries (from: events), on a calendar of to-dos and on Today. The addresses are secrets: they travel sealed with your settings and are sent nowhere but to read them.'),
            ),
          ],
        );
      },
    );
  }
}
