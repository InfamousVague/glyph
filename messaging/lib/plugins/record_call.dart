/// Record call: a call recorded to one MP4, its first track everyone together and then a track of each voice, named
/// for them (Matt, 2026-11-19: "I'd like to have a "record call" plugin where it records the call to an MP4 with
/// multiple named audio tracks"). The work is lib/voice/recorder.dart's; this puts it in a call's menu.
///
/// A plugin a whole circle can hold: in a circle's spaces it is there when the circle's owner or an admin has turned
/// it on (Circle settings › Plugins), for everyone in the circle; elsewhere when it is added here. Whatever is on,
/// everyone in a call being recorded is told and asked (lib/ui/recording_ui.dart), and only voices whose own device
/// said yes are in it.
library;

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../ui/recording_ui.dart';
import '../voice/recorder.dart';
import 'plugin.dart';

class RecordCallPlugin extends GhostPlugin {
  const RecordCallPlugin();

  @override
  String get id => 'recordcall';

  @override
  String get name => 'Record call';

  @override
  String get description => 'Record a call to one file with a track for each voice, named. Only people who say yes are in it.';

  @override
  LucideIcon get icon => Lucide.circleDot;

  @override
  bool get onByDefault => false;

  @override
  String get hue => 'coral';

  @override
  PluginShelf get shelf => PluginShelf.tools;

  @override
  String get tagline => 'A track for each voice, named, in one MP4.';

  @override
  String get pitch => 'Record a call to one MP4: everyone together, then each voice on its own named track.';

  @override
  List<String> get adds => const [
        'Record this call in a call\'s menu',
        'A red line over the call for everyone while it records',
        'Each person asked first; only those who say yes are in it',
        'Recordings kept on this device, to play, share or send to the space',
      ];

  @override
  List<PluginReach> get reaches => const [
        PluginReach(Lucide.mic, 'The voices in a call, on this device', 'Only of people whose own app said yes, and yours while you record.'),
        PluginReach(Lucide.hardDrive, 'Recordings kept on this device', 'Nothing is uploaded unless you send it to a space.'),
      ];

  @override
  Set<PluginScope> get scopes => const {PluginScope.device, PluginScope.circle};

  @override
  List<SlotFill> get slots => [
        Slots.callControls.fill((place, prefs) {
          if (!CallRecorder.supported) return const [];
          final rec = CallRecorder.instance;
          return [
            if (rec.recording == null && !rec.finishing)
              PluginAction(
                label: 'Record this call',
                icon: Lucide.circleDot,
                run: (host) async {
                  final why = await rec.start();
                  host.say(why ?? 'Recording. Everyone is asked whether their voice may be in it.');
                },
              )
            else if (rec.recording != null)
              PluginAction(
                label: 'Stop recording',
                icon: Lucide.circleStop,
                danger: true,
                run: (host) async {
                  final r = await rec.stop();
                  host.say(r == null ? 'The recording couldn\'t be saved' : 'Recording saved in Recordings');
                },
              ),
            PluginAction(label: 'Recordings', icon: Lucide.audioLines, run: (host) => host.present((_) => const RecordingsScreen())),
          ];
        }),
      ];

  @override
  PluginSettingsPage? get settingsPage => null;
}
