/// The Lovart plugin's page in Settings: the person's Lovart keys, an access key and a secret key, checked before they
/// are kept (`POST /mode/query`, which changes nothing), Check and Forget once kept; and "Inspiration for design
/// meetings". Shaped as the Claude plugin's key card (lib/plugins/claude/claude_in_app.dart): Forget asks twice.
///
/// At its head, while the keys are missing, Set up (lovart_setup.dart, through lib/plugins/onboarding/setup_card.dart):
/// the steps from an account to keys that work; once they are kept, Run setup again.
///
/// The keys are kept in the device's secure store (manifest.dart) and follow the account sealed
/// (lib/sync/connections.dart); the page draws again when the plugin's storage or secrets change, so keys that arrive
/// from another device show as soon as they are read.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../claude/claude_settings.dart' show maskKey;
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/pane_parts.dart' show armedFor;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../github/plain_field.dart';
import '../host.dart' show onPluginStorage;
import '../onboarding/setup_card.dart';
import '../onboarding/setup_flow.dart' show PluginSetup;
import 'client.dart';
import 'lovart_mark.dart';
import 'manifest.dart';
import 'banner_run.dart' show BannerRun, bannerCandidates, bannerElsewhereWords, bannerRunEndWords, bannerRunLine, bannerRunMost, bannerTakenOff, lovartBannerJob, lovartBannerRun, runBanners, stopBannerRun;
import 'banners.dart' show bannersOn, setBanners;
import 'lovart_queue.dart';
import 'lovart_setup.dart';
import 'meetings.dart' show designMeetingsOn, setDesignMeetings;

/// What Settings' search finds on the page.
const List<SettingsFindable> lovartFindable = [
  SettingsFindable('Lovart keys', 'access key secret key ak sk lovart api credits'),
  SettingsFindable('Header images for notes', 'banner header cover image ghost dotwork automatic'),
  SettingsFindable('Queue', 'queue waiting making progress pictures header images credits'),
  SettingsFindable('Inspiration for design meetings', 'meetings design moodboard inspiration images automatic'),
];

/// What the run over the recent notes says: what it does, before one; how far it is while it runs, here or on
/// another of the account's devices; and how it ended.
/// Before a run, what Make them would cost (Matt, 2026-10-26: "Estimate about 6 credits per image for now"): "About
/// 600 credits for 100 notes", for the notes it would pick now, the ones taken off with them where [takenOff];
/// black-and-white and square ones to redo are read from their pictures as the run starts, and are on top.
String _runWords(BannerRun? run, {bool takenOff = false, bool redoOld = false}) {
  final job = lovartBannerJob;
  final count = job == null ? 0 : (bannerCandidates(job.notes()).length + (takenOff ? bannerTakenOff(job.notes()).length : 0)).clamp(0, bannerRunMost);
  final cost = count == 0 && !redoOld ? 'None of your recent notes is waiting for one now.' : '${aboutCredits(count).replaceFirst('a', 'A')} for ${count == 1 ? '1 note' : '$count notes'}${redoOld ? ', and about $lovartCreditsPerImage more for each header redone' : ''}.';
  final about = 'Banners for your $bannerRunMost most recent notes that are not tickets, meetings, mail or short, and have none yet. Three at a time, with your credits. They go on being made while you use the app. $cost';
  final elsewhere = lovartBannerJob?.elsewhere();
  if (run?.running != true && elsewhere != null) return bannerElsewhereWords(elsewhere);
  if (run == null) return about;
  if (run.running) return '${bannerRunLine(run)}. You can leave this page: they go on being made.';
  if (run.total == 0 && run.stopped != null) return run.stopped!;
  return '${bannerRunEndWords(run)}.';
}

class LovartPane extends StatefulWidget {
  const LovartPane({super.key});

  @override
  State<LovartPane> createState() => _LovartPaneState();
}

class _LovartPaneState extends State<LovartPane> {
  final TextEditingController _access = TextEditingController();
  final TextEditingController _secret = TextEditingController();
  late final VoidCallback _stop;
  bool _checking = false;
  String? _problem;
  String? _said;
  bool _armed = false;

  /// The setup the head of the page opens (lovart_setup.dart).
  late final PluginSetup _setup = lovartSetup();

  /// Make them's two choices, for the next run (Matt, 2026-10-26: "remove the header banner images on the docs as we
  /// will regenerate them"): the notes whose banner was taken off, and the black-and-white or square banners made again in
  /// colour. The page's own, never kept: each run is asked for as it is wanted.
  bool _takenOff = false;
  bool _redoOld = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _access.addListener(_redraw);
    _secret.addListener(_redraw);
    _stop = onPluginStorage(_redraw);
    unawaited(host.secrets.warm());
  }

  @override
  void dispose() {
    _stop();
    _access.dispose();
    _secret.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _keep() async {
    final access = _access.text.trim(), secret = _secret.text.trim();
    if (access.isEmpty || secret.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _problem = null;
      _said = null;
    });
    final wrong = await LovartClient(accessKey: access, secretKey: secret).check();
    if (!mounted) return;
    if (wrong != null && wrong.badKeys) {
      setState(() {
        _checking = false;
        _problem = 'Lovart refused those keys. Copy both again from AK/SK Management in Lovart.';
      });
      return;
    }
    await host.secrets.write(accessKeySecret, access);
    await host.secrets.write(secretKeySecret, secret);
    if (!mounted) return;
    _access.clear();
    _secret.clear();
    setState(() {
      _checking = false;
      // Kept even when they could not be checked (no connection): the first image says if they are wrong.
      _said = wrong == null ? 'The keys work.' : 'Kept. They could not be checked just now: ${wrong.message}';
    });
  }

  Future<void> _check() async {
    final lovart = LovartClient.kept();
    if (lovart == null || _checking) return;
    setState(() {
      _checking = true;
      _problem = null;
      _said = null;
    });
    final wrong = await lovart.check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (wrong == null) {
        _said = 'The keys work.';
      } else {
        _problem = wrong.message;
      }
    });
  }

  void _forget() {
    _timer?.cancel();
    if (!_armed) {
      setState(() => _armed = true);
      HapticsProvider.of(context)(HapticKind.warning);
      _timer = Timer(armedFor, () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() {
      _armed = false;
      _said = null;
      _problem = null;
    });
    unawaited(host.secrets.write(accessKeySecret, null));
    unawaited(host.secrets.write(secretKeySecret, null));
    host.storage.remove(projectKey);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final keys = lovartKeys();
    final ready = _access.text.trim().isNotEmpty && _secret.text.trim().isNotEmpty;
    return PaneBody(
      children: [
        PluginSetupCard(setup: _setup),
        if (_problem != null) SettingsCallout(child: Text(_problem!)),
        if (_said != null) SettingsCallout(child: Text(_said!)),
        PaneSection(
          title: 'Lovart keys',
          description: const Text('Lovart makes the images with its design agent, using your own Lovart account: in Lovart, open your avatar menu › AK/SK Management and make a pair. Each image is made with your Lovart credits.'),
          footer: const Text('The keys are kept in this device’s secure storage and follow your account, sealed, to your other devices.'),
          children: [
            if (keys == null)
              SettingRow(
                key: const ValueKey('lovart-keys-new'),
                icon: const LovartMark(size: 18),
                label: 'Access key and secret key',
                layout: SettingRowLayout.stacked,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: t.space(2),
                  children: [
                    PlainField(key: const ValueKey('lovart-access'), label: 'Lovart access key', controller: _access, placeholder: 'Access key', secret: true),
                    PlainField(key: const ValueKey('lovart-secret'), label: 'Lovart secret key', controller: _secret, placeholder: 'Secret key', secret: true, onSubmitted: _keep),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: RowAction(onPress: _keep, disabled: _checking || !ready, child: Text(_checking ? 'Checking…' : 'Keep them')),
                    ),
                  ],
                ),
              )
            else ...[
              SettingRow(
                key: const ValueKey('lovart-keys-kept'),
                icon: const LovartMark(size: 18),
                label: 'Keys kept',
                hint: Text('Access key ${maskKey(keys.access)}'),
                value: RowAction(onPress: _check, disabled: _checking, child: Text(_checking ? 'Checking…' : 'Check')),
              ),
              SettingRow(
                key: const ValueKey('lovart-keys-forget'),
                label: 'Forget the keys',
                hint: const Text('Lovart can no longer be asked from this device until they are added again.'),
                value: RowAction(onPress: _forget, child: Text(_armed ? 'Tap again' : 'Forget')),
              ),
            ],
          ],
        ),
        PaneSection(
          title: 'Notes',
          children: [
            SettingRow(
              key: const ValueKey('lovart-banners'),
              label: 'Header images for notes',
              hint: const Text('When you leave a note, Lovart draws a banner for its top in the ghost’s dotwork, from its title and opening. Once per note, with your credits; not for tickets, meetings, mail or short notes. Make one any time from Header image on the note’s menu.'),
              control: GlacierSwitch(ariaLabel: 'Header images for notes', checked: bannersOn(), onCheckedChange: setBanners),
            ),
            if (lovartBannerJob != null)
              ValueListenableBuilder<BannerRun?>(
                valueListenable: lovartBannerRun,
                builder: (context, run, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingRow(
                      key: const ValueKey('lovart-banner-run'),
                      label: 'Header images for recent notes',
                      hint: Text(_runWords(run, takenOff: _takenOff, redoOld: _redoOld)),
                      value: run?.running == true
                          ? RowAction(onPress: stopBannerRun, child: const Text('Stop'))
                          : RowAction(onPress: () => unawaited(runBanners(takenOff: _takenOff, redoOld: _redoOld)), disabled: keys == null, child: const Text('Make them')),
                    ),
                    if (run?.running != true) ...[
                      SettingRow(
                        key: const ValueKey('lovart-banner-taken-off'),
                        label: 'Include notes whose header was taken off',
                        hint: const Text('Makes them again for notes that had one. Leaving a note never does.'),
                        control: GlacierSwitch(ariaLabel: 'Include notes whose header was taken off', checked: _takenOff, onCheckedChange: (on) => setState(() => _takenOff = on)),
                      ),
                      SettingRow(
                        key: const ValueKey('lovart-banner-redo'),
                        label: 'Redo black-and-white and square headers',
                        hint: const Text('The banners made before they were in colour and wide, made again and put in their place.'),
                        control: GlacierSwitch(ariaLabel: 'Redo black-and-white and square headers', checked: _redoOld, onCheckedChange: (on) => setState(() => _redoOld = on)),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
        // What is being made now and what waits, on this device (lovart_queue.dart).
        const LovartQueueSection(),
        PaneSection(
          title: 'Meetings',
          children: [
            SettingRow(
              key: const ValueKey('lovart-design-meetings'),
              label: 'Inspiration for design meetings',
              hint: const Text('Once a meeting about design is written up (mockups, branding, a layout, a logo), Lovart makes a moodboard of four from its summary, under Inspiration in the note. Once per meeting, with your credits.'),
              control: GlacierSwitch(ariaLabel: 'Inspiration for design meetings', checked: designMeetingsOn(), onCheckedChange: setDesignMeetings),
            ),
          ],
        ),
        const SettingsFootnote(child: Text('Only the words of a {image: …}, the note you ask inspiration for, or a note’s title and opening for its header image go to Lovart. Write {image: a prompt} anywhere in a note to make a picture there.')),
      ],
    );
  }
}
