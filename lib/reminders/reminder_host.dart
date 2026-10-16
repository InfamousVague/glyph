/// The phone's half of reminders, over the channel `ghost_md/reminders` (android/…/ghost_md/reminders/Reminders.kt):
/// the alarms it holds, what Android lets them be, the clock a time is picked on, and the Done it hands back while
/// the app runs.
///
/// - `set {json}`: the whole plan (reminder_plan.dart `planJson`), which the phone keeps, arms, and arms again after a
///   restart or an update; whatever it held that the plan no longer has is let go.
/// - `state` -> `{notify, exact}`: whether Android shows the app's notifications, and whether it lets an alarm ring
///   on its minute (Android 12+ asks the person for that; without it a reminder may be some minutes late).
/// - `allowExact`: Android's own page where the person allows alarms and reminders for the app.
/// - `pickTime {hour, minute}` -> `HH:MM` or null: the phone's own clock.
/// - `tick {note, line, words}`, said TO the app: Done pressed on a notification, or a to-do ticked on the home
///   screen, while the app runs; the app writes it through its library and answers true.
///
/// Where there is no phone half (a desktop, an iPhone, a test without one) every ask answers null or false, and
/// reminders are offered nowhere.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// The phone's reminders, where this run has them: Settings › Notifications draws its Reminders group, and a line's
/// menu its Remind me, only while this is set (lib/root/phone_extras.dart, on Android over the real library).
final ValueNotifier<ReminderHost?> phoneReminders = ValueNotifier<ReminderHost?>(null);

/// What Android lets reminders do now.
typedef ReminderAbility = ({bool notify, bool exact});

/// Done from outside the app's window: the note, the item's line and its words (tick_item.dart says how it is found).
typedef OutsideTick = Future<bool> Function(String noteId, int line, String words);

/// The phone, asked about reminders.
abstract interface class ReminderHost {
  /// Hands the phone the whole plan. False where it could not be handed.
  Future<bool> set(String json);

  /// What Android lets them do; null where there is no phone half.
  Future<ReminderAbility?> state();

  /// Android's page for alarms and reminders.
  Future<bool> allowExact();

  /// The phone's clock, from [hour] and [minute]; the time picked, or null.
  Future<({int hour, int minute})?> pickTime(int hour, int minute);

  /// Who writes a Done the phone hands over while the app runs.
  set onTick(OutsideTick? tick);
}

/// The channel the phone answers on.
const MethodChannel remindersChannel = MethodChannel('ghost_md/reminders');

/// The phone's own half, on Android; nothing anywhere else.
class PhoneReminderHost implements ReminderHost {
  PhoneReminderHost({MethodChannel channel = remindersChannel, bool? android}) : _channel = channel, _android = android ?? defaultTargetPlatform == TargetPlatform.android {
    if (_android) _channel.setMethodCallHandler(_said);
  }

  final MethodChannel _channel;
  final bool _android;
  OutsideTick? _tick;

  @override
  set onTick(OutsideTick? tick) => _tick = tick;

  Future<Object?> _said(MethodCall call) async {
    if (call.method != 'tick') return null;
    final args = call.arguments;
    final tick = _tick;
    if (tick == null || args is! Map) return false;
    final note = args['note'], line = args['line'], words = args['words'];
    if (note is! String || line is! int) return false;
    return tick(note, line, words is String ? words : '');
  }

  Future<Object?> _ask(String method, [Map<String, Object?>? arguments]) async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> set(String json) async => await _ask('set', {'json': json}) == true;

  @override
  Future<ReminderAbility?> state() async {
    final answer = await _ask('state');
    if (answer is! Map) return null;
    return (notify: answer['notify'] == true, exact: answer['exact'] == true);
  }

  @override
  Future<bool> allowExact() async => await _ask('allowExact') == true;

  @override
  Future<({int hour, int minute})?> pickTime(int hour, int minute) async {
    final answer = await _ask('pickTime', {'hour': hour, 'minute': minute});
    if (answer is! String) return null;
    final parts = answer.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) : null, m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return (hour: h, minute: m);
  }

  /// Stops hearing the phone: for a root started over.
  void dispose() {
    if (_android) _channel.setMethodCallHandler(null);
  }
}
