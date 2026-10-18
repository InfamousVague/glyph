/// What is in the app and not yet for everyone: switches of this device's own, under Settings > Developer > Work in
/// progress. After `core/wip.ts` on Ghost.md's unmerged branch `voice/assistant-flag` (its docs/DESIGN.md §146).
///
/// **The voice assistant** is the one there is: the phone's digital assistant with the side key, and the launcher's
/// "Record note". Off on every device, the owner's included, who switches it on himself (Matt, 2026-10-11: "off by
/// default behind a developer flag"). A device flag, never a preference, which would travel to the account's other
/// devices; a reset keeps it, as it keeps developer mode (lib/core/reset.dart `spared`).
///
/// What differs from that branch: there the page could only decline a key it was still sent, because a manifest
/// cannot be changed from a page. Here the phone's half really switches (android/…/AssistantSwitch.kt): off, the app
/// is not in Android's list of assistants and has no shortcut at all. And the branch's switch also silenced the
/// spoken commands in the recorder ("Hey Ghost", "add a note to …"); this one does not touch them: they are as they
/// are on Ghost.md's `main`.
///
/// The phone holds the truth (it is asked at every start what is enabled, lib/root/voice_wiring.dart); the flag
/// here is what the switch draws, and [switchVoiceAssistant] sets both.
///
/// **Back as a setting** (Matt, 2026-10-17: "add the setting back in to be able to bind ghost as the agent on the
/// phone"). The same switch stands on the Claude plugin's page too, as Phone assistant (lib/plugins/claude/
/// claude_in_app.dart), where a person finds it (Settings' search finds "assistant"), with the way to Android's
/// Default digital assistant app screen ([openAssistantChooser]): the app cannot make itself the assistant, a person
/// picks it there. It is one flag: the Developer row and the plugin's draw and set the same one. And the assistant
/// now talks to Claude (lib/claude/claude_voice.dart) where Claude can answer, its plugin on and a key kept; else it
/// records as it did (lib/root/capture_route.dart `assist`). Off by default still, on every device.
library;

import 'dart:async';

import '../capture/meeting_host.dart';
import 'preferences.dart';

/// The key the branch keeps it under.
const String wipAssistantKey = 'glyph-wip-assistant';

/// Whether this device's voice assistant switch is on.
final DeviceFlag wipAssistant = DeviceFlag(wipAssistantKey);

/// The switch's hint: what it turns on, and what works either way.
const String wipAssistantHint = 'The side key as the phone’s assistant, and Record note on the app’s icon. Off, nothing outside Ghost.md starts a recording. '
    'Recording, voice memos and meetings work either way. Open Ghost.md again after switching it. The same switch is Phone assistant on Settings › Plugins › Claude.';

/// Switches it: the flag, and the phone's half. [phone] is the phone's own unless a test gives another; a phone
/// that will not answer leaves the flag as it was.
Future<void> switchVoiceAssistant(bool on, {Future<bool> Function(bool on)? phone}) async {
  try {
    await (phone ?? _onPhone)(on);
    wipAssistant.set(on);
  } catch (_) {
    // No phone under it (a Mac, a test): nothing to switch.
  }
}

/// Opens Android's screen for choosing the digital assistant app (MeetingBridge.kt `openAssistantSettings`: Assist &
/// voice input where the phone has it, else Default apps), answering whether one opened. False off a phone.
Future<bool> openAssistantChooser() async {
  try {
    return await DeviceMeetingHost.channel.invokeMethod<bool>('openAssistantSettings') ?? false;
  } catch (_) {
    return false;
  }
}

/// Whether Ghost.md is the phone's digital assistant app now (MeetingBridge.kt `isAssistant`). False off a phone.
Future<bool> isPhoneAssistant() async {
  try {
    return await DeviceMeetingHost.channel.invokeMethod<bool>('isAssistant') ?? false;
  } catch (_) {
    return false;
  }
}

/// The phone's half, on the meeting bridge's channel (MeetingBridge.kt `setAssistantSwitch`): whether the assistant
/// is there afterwards.
Future<bool> _onPhone(bool on) async => await DeviceMeetingHost.channel.invokeMethod<bool>('setAssistantSwitch', {'on': on}) ?? false;
