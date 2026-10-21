import 'dart:async';
import 'dart:convert';

import 'package:ghost_md/home_screen/home_host.dart';
import 'package:ghost_md/reminders/reminder_host.dart';

/// The phone, as reminders ask it (lib/reminders/reminder_host.dart): keeps every plan it is handed, says what
/// Android lets them do as the test sets it, and picks the time the test says.
class FakeReminders implements ReminderHost {
  final List<String> sets = [];
  bool takes = true;
  ReminderAbility ability = (notify: true, exact: true);
  ({int hour, int minute})? picks;
  int exactAsked = 0;
  final List<(int, int)> pickedFrom = [];
  OutsideTick? tick;

  /// What the last plan handed over says, as `at words`.
  List<String> get last => [for (final item in ((jsonDecode(sets.last) as Map)['items'] as List).cast<Map>()) '${item['at']} ${item['words']}'];

  @override
  Future<bool> set(String json) async {
    sets.add(json);
    return takes;
  }

  @override
  Future<ReminderAbility?> state() async => ability;

  @override
  Future<bool> allowExact() async {
    exactAsked += 1;
    return true;
  }

  @override
  Future<({int hour, int minute})?> pickTime(int hour, int minute) async {
    pickedFrom.add((hour, minute));
    return picks;
  }

  @override
  set onTick(OutsideTick? tick) => this.tick = tick;
}

/// The home screen, as the app hands it what the widgets draw (lib/home_screen/home_host.dart).
class FakeHome implements HomeScreenHost {
  final Map<HomeKind, List<String>> puts = {};

  /// The notes the phone's A note widgets show, as the phone answers `chosen`.
  List<String> shown = [];

  /// What the phone calls when a widget is set to another note.
  void Function()? heard;

  @override
  Future<bool> put(HomeKind kind, String json) async {
    puts.putIfAbsent(kind, () => []).add(json);
    return true;
  }

  @override
  Future<List<String>> chosen() async => shown;

  @override
  void listen(void Function() then) => heard = then;
}
