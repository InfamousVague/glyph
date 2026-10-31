/// The Calendar plugin, built in and off until switched on: the calendars whose events the app shows (docs/CALENDAR.md),
/// an iCal address or Google Calendar, and the to-dos with a due date put on Google's. Matt, 2026-10-17: "Ask Claude
/// and other integrations should be shipped as plugins".
///
/// The calendars themselves are lib/calendar/ (the service, its reads and its keeping), started by the app's root
/// with this plugin's switch ([calendarOn]): off, nothing is read, nothing goes to Google's, and no query, calendar of
/// to-dos or Today shows an event. What was read, and the calendars chosen (kept with the account's settings), stay
/// as they were, so switching it on again shows them at once and reads them soon after. Its page is the one that was
/// Settings › Calendar ([CalendarPane]), with Google Calendar's setup at its head (calendar_setup.dart).
///
/// A device that had a calendar before this was a plugin finds it on: the root adopts it once ([calendarInUse],
/// lib/plugins/registry.dart `Registry.adopt`), and from then on it is the switch's.
library;

import '../../calendar/calendar.dart' show CalendarService, calendar;
import '../../core/preferences.dart' show preferences;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../registry.dart' show pluginOn;
import '../types.dart';
import 'calendar_pane.dart';
import 'calendar_setup.dart';

export 'calendar_pane.dart' show CalendarPane, calendarFindable, calendarSummary;
export 'calendar_setup.dart';

const PluginManifest calendarManifest = PluginManifest(
  id: 'calendar',
  name: 'Calendar',
  description: 'Shows your calendars’ events in queries and on the home page’s Today, from an iCal address or Google Calendar, and can put dated to-dos on Google’s.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.calendar,
  tagline: 'Your events in queries and on Today',
  adds: [
    'Your calendars’ events in queries and on the home page’s Today',
    'An iCal address, or Google Calendar once you connect it',
    'Dated to-dos on a Google calendar, where you switch that on',
  ],
  // Off until switched on: it reads calendars from outside the phone, and only those the person adds.
  standard: false,
  permissions: [
    PluginPermission(Permission.network, 'Reads the calendar addresses you add, wherever they are, and Google Calendar once you connect it, its sign-in through ghostmarkdown.com. The addresses are kept with your account’s settings.'),
    PluginPermission(Permission.notes, 'Reads your to-dos with a due date to put them on a Google calendar, only where you switch that on. Nothing in a note changes.'),
  ],
  // What it keeps on this device of what it read (lib/calendar/store.dart); the calendars chosen are the account's.
  storage: ['glyph-calendar-events', 'glyph-calendar-status', 'glyph-google-token', 'glyph-google-calendars', 'glyph-google-signin'],
);

/// Whether the calendars are read and shown: the plugin's switch, asked as the service works.
bool calendarOn() => pluginOn(calendarManifest);

/// Whether this device was using the calendars before they were a plugin: an address added, or Google connected
/// ([CalendarService.hasCalendars], an address whose secret is still on its way counted).
bool calendarInUse([CalendarService? service]) => (service ?? calendar).hasCalendars;

/// The page, and what the search finds on it as it stands now: Google's card is drawn only where its sign-in is
/// offered or connected, so the list is read afresh each time it is asked for.
class _CalendarSettings extends PluginSettings {
  _CalendarSettings() : super(pane: (context) => const CalendarPane(), summary: () => calendarSummary(preferences.value), hue: 'cyan');

  @override
  List<SettingsFindable> get settings => calendarFindable(preferences.value, offered: calendar.offered == true);
}

final GlyphPlugin calendarPlugin = GlyphPlugin(manifest: calendarManifest, icon: 'calendar-days', settings: _CalendarSettings(), setup: calendarSetup);
