/// The sound and the touch at the end of a long job (docs/ACTIVITY.md, Sound; Matt, 2026-10-29: "A soft chime and a
/// light tap when a job the person started and that ran over ~30 s finishes; nothing for sync or small jobs; off with
/// the app's sounds setting").
///
/// The record decides which job it is (lib/core/background_jobs.dart `Activity.onChime`: one the person started, that
/// ran [Activity.longJob] or more, never a sync, never one ended quietly or stopped); this plays it: the pack's
/// `job-done` (lib/sounds/sound_pack.dart `SoundEvent.jobDone`), and a light tap where the device has a motor and
/// its haptics are on. Both are off with Settings › Sounds' interface sounds, and the chime with its own switch.
library;

import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../core/background_jobs.dart';
import '../core/preferences.dart';
import '../sounds/sound_pack.dart';
import '../sounds/sounds.dart';

/// Wires [record]'s chime (the app's [activity] unless given): [play] and [tap] are the sound's and the motor's, the
/// app's own unless a test says.
void startActivityChime({Activity? record, void Function(SoundEvent event)? play, void Function()? tap, PreferencesStore? prefs}) {
  (record ?? activity).onChime = (job) {
    final now = (prefs ?? preferences).value;
    if (!now.interfaceSounds) return;
    (play ?? sounds.play)(SoundEvent.jobDone);
    // The motor is the kit's, on where the device's haptics are (lib/app/ghost_app.dart `HapticsProvider`).
    (tap ?? () => fireMotor(HapticKind.light))();
  };
}
