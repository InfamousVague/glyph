/// The Calendar plugin's setup, for Google Calendar (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the
/// voiceover onboarding for the rest of the plugins"). Four steps, in the plugin's cyan, over the service's own sign-in
/// (lib/calendar/calendar.dart), which the plugin's page uses too (calendar_pane.dart):
///
/// 1. **Your calendars in Ghost.md**: what it does, and that an iCal address works as well, on the page.
/// 2. **Connect Google Calendar**: [CalendarService.connectGoogle], which opens Google's consent page in the browser
///    through ghostmarkdown.com. Refused before anything opens where Local only is on, or where this build's service
///    has no Google sign-in ([CalendarService.checkOffered]: its `start` answers 503), with the iCal address as the
///    way instead.
/// 3. **Check it worked**: the sign-in collected ([CalendarService.collectGoogle]) if the service's own beat has not
///    collected it already, then whether the account has Google now. Said in plain words ([calendarSetupResult]):
///    still on Google's page, refused in the service's words, or connected with how many calendars.
/// 4. **Try it**: Today on the home page, `from: events` in a query, and To-dos on the calendar on the page.
///
/// Needed while the account has no calendar at all: an iCal address added on the page is as good as Google.
library;

import '../../art/lucide.g.dart';
import '../../calendar/calendar.dart' show CalendarService, calendar;
import '../onboarding/setup_flow.dart';

/// The check's answer (see the header). Never throws.
Future<SetupResult> calendarSetupResult(CalendarService service) async {
  if (service.setup.google == null) await service.collectGoogle();
  if (service.setup.google == null) {
    final problem = service.problem;
    if (problem != null) return SetupResult.failed(problem, pasteAgain: true);
    return const SetupResult.failed('Google hasn’t said yet. Allow Ghost.md on Google’s page, then check again.', pasteAgain: true);
  }
  final count = service.googleCalendars.length;
  if (count == 0) return const SetupResult.ok('Google Calendar is connected. Your calendars are listed in a moment.');
  return SetupResult.ok('Google Calendar is connected, with ${count == 1 ? '1 calendar' : '$count calendars'}. Your own is shown.');
}

/// Starts Google's sign-in, or says why it can't start here (see the header).
Future<String?> calendarConnect(CalendarService service) async {
  if (service.prefs.value.localOnly) return 'Local only is on, so no calendar is read. Turn it off in Settings › Account first.';
  if (!(service.offered ?? await service.checkOffered())) return 'Google Calendar can’t be connected from here. Paste a calendar’s iCal address on Calendar’s page instead.';
  await service.connectGoogle();
  return service.problem;
}

/// The setup (see the header). [service] is the calendars it connects; the app's own where null.
PluginSetup calendarSetup({CalendarService? service}) {
  CalendarService on() => service ?? calendar;
  return PluginSetup(
    id: 'calendar',
    name: 'Google Calendar',
    hues: const ['cyan', 'blue', 'indigo'],
    tiles: const [Lucide.calendarDays, Lucide.listChecks, Lucide.refreshCw, Lucide.link],
    // Not `setup.isEmpty`: that leaves out an address whose secret is not on this device yet, which the account has.
    ready: () => on().hasCalendars,
    watch: (listener) {
      final watched = on()..addListener(listener);
      return () => watched.removeListener(listener);
    },
    about: 'A few short steps: connect Google Calendar, and a check that it worked. An iCal address works too, below.',
    again: 'The steps from the start: connecting Google Calendar, and a check that it worked.',
    steps: [
      const SetupIntro(
        id: 'intro',
        title: 'Your calendars in Ghost.md',
        icon: Lucide.calendarDays,
        points: [
          (Lucide.calendarDays, 'Your events on the home page’s Today, and in queries'),
          (Lucide.listChecks, 'To-dos with a due date put on a Google calendar, where you switch that on'),
          (Lucide.link, 'Any calendar’s iCal address works too, pasted on Calendar’s page'),
        ],
      ),
      SetupAct(id: 'signin', title: 'Connect Google Calendar', icon: Lucide.link, label: 'Connect Google Calendar', again: 'Connect again', run: () => calendarConnect(on())),
      SetupCheck(id: 'check', title: 'Check it worked', icon: Lucide.shieldCheck, checking: 'Asking Google…', run: () => calendarSetupResult(on())),
      const SetupDone(id: 'done', title: 'Try it', icon: Lucide.wandSparkles),
    ],
  );
}
