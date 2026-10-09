/// A day picked from the phone's own calendar: the [DayPicker] over the channel `ghost_md/day` (Kotlin's `DayPick`,
/// Android's date dialog). What a hidden `<input type="date">` opened from the press was to `pickDay` in
/// `src/app/editor/fieldMenu.ts`.
///
/// What differs: the page's input sat at the place of the press so the dialog had somewhere to open from; Android's
/// dialog is the window's own, so where the press was is not told to it. A run with no phone half (a desktop, a
/// test) picks nothing.
library;

import 'package:flutter/services.dart';

/// The channel the phone's calendar answers on.
const MethodChannel dayChannel = MethodChannel('ghost_md/day');

final RegExp _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Opens the phone's calendar on [current] (`YYYY-MM-DD`; today where there is none) and answers the day chosen, or
/// null when it was left without one: lib/editor/items/field_menu.dart's `DayPicker`.
Future<String?> phoneDayPicker(Offset at, String? current, {MethodChannel channel = dayChannel}) async {
  try {
    final picked = await channel.invokeMethod<String>('pick', <String, Object?>{if (current != null && _day.hasMatch(current)) 'current': current});
    return picked != null && _day.hasMatch(picked) ? picked : null;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
