/// Lovart's setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-28: "For each of the plugins add a small
/// onboarding flow start with the lovart and Claude plugins walk the user through setting up an account and getting
/// their keys and have the onboarding test setup to make sure it was successful"). Six steps, in Lovart's purple:
///
/// 1. **Images by Lovart**: what it is and what it costs, the person's own credits, about [lovartCreditsPerImage] an
///    image ([aboutCredits]).
/// 2. **Make a Lovart account**: Open lovart.ai ([lovartSiteUrl]), to sign up or sign in. Lovart has no sign-up
///    address of its own; its home page's Get started is the way in (read on 2026-10-28).
/// 3. **Your keys**: your profile › Lovart Agent › OpenClaw, where the access key and secret key are (Matt, 2026-10-28:
///    "click their profile then lovart agent > OpenClaw and copy the keys"; the skill's README had said AK/SK Management). Lovart gives that page no address, so Open Lovart
///    opens its home ([lovartHomeUrl]), where the avatar menu is.
/// 4. **Paste your keys**: the access key and the secret key, kept where the plugin's page keeps them
///    ([accessKeySecret], [secretKeySecret] in the secure store, through the plugin's host), so the sealed sync
///    (lib/sync/connections.dart) follows them as it does keys typed on the page.
/// 5. **Check they work**: `POST /mode/query` ([LovartClient.check]), which changes nothing and spends nothing. Said in
///    the plugin's own words ([lovartSetupResult]): "Your Lovart keys work."; a 401 is Lovart's refusal as the client
///    says it, and the keys are let go of again, as the page never keeps refused keys; a 402 (plan or credits) is
///    Lovart's own sentence, the keys kept, with the way back to Lovart; no connection is the client's
///    [lovartUnreachable].
/// 6. **Try it**: a cue to copy, `{image: …}`, and the Header images for notes switch, since that one spends credits
///    by itself. Nothing is made here: no credits are spent by the setup.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../market/market_cards.dart' show MarketButton, MarketButtonLook;
import '../../settings/kit/settings_kit.dart' show Copied;
import '../../settings/kit/settings_type.dart' show pageText;
import '../host.dart' show onPluginStorage;
import '../onboarding/setup_flow.dart';
import '../types.dart' show PluginHost;
import 'banners.dart' show bannersOn, setBanners;
import 'client.dart';
import 'manifest.dart' as lovart;

/// Lovart's site, where an account is made: its Get started.
const String lovartSiteUrl = 'https://www.lovart.ai/';

/// Lovart signed in, where the profile menu is, and Lovart Agent › OpenClaw in it.
const String lovartHomeUrl = 'https://www.lovart.ai/home';

/// The cue the last step offers to copy.
const String lovartSampleCue = '{image: a lighthouse at dawn, in soft watercolour}';

/// What the check said, as the setup says it (see the header). [via] is the host the keys are read through.
Future<SetupResult> lovartSetupResult({PluginHost? via, LovartClient? Function()? client}) async {
  final on = via ?? lovart.host;
  final asked = (client ?? () => LovartClient.kept(via: via))();
  if (asked == null) return const SetupResult.failed('No keys are kept yet. Paste both first.', pasteAgain: true);
  final wrong = await asked.check();
  if (wrong == null) return const SetupResult.ok('Your Lovart keys work.');
  if (wrong.badKeys) {
    // Never kept once refused, as the page has it.
    await on.secrets.write(lovart.accessKeySecret, null);
    await on.secrets.write(lovart.secretKeySecret, null);
    return SetupResult.failed(wrong.message, pasteAgain: true);
  }
  if (wrong.status == 402 || wrong.code == 2012) return SetupResult.warn(wrong.message, link: const SetupLink('Open Lovart', lovartHomeUrl));
  return SetupResult.failed(wrong.message);
}

String? _keyShape(String text) => RegExp(r'\s').hasMatch(text) ? 'Paste the key alone: it has no spaces in it.' : null;

/// Lovart's setup (see the header). [via] is the host its keys are kept through; [client] a test's own Lovart.
PluginSetup lovartSetup({PluginHost? via, LovartClient? Function()? client}) {
  final on = via ?? lovart.host;
  return PluginSetup(
    id: 'lovart',
    name: 'Lovart',
    hues: const ['purple', 'magenta', 'rose'],
    tiles: const [Lucide.image, Lucide.palette, Lucide.wandSparkles, Lucide.sparkles],
    ready: () => hasLovartKeys(on),
    watch: onPluginStorage,
    prepare: on.secrets.warm,
    steps: [
      SetupIntro(
        id: 'intro',
        title: 'Images by Lovart',
        icon: Lucide.palette,
        points: [
          (Lucide.image, 'A header across the top of a note, in the ghost’s dotwork'),
          (Lucide.users, 'A moodboard of four for a design meeting, once it is written up'),
          (Lucide.wandSparkles, 'A picture wherever you write {image: …} in a note'),
          (Lucide.gauge, 'With your Lovart credits: ${aboutCredits(1)} an image'),
        ],
      ),
      const SetupOpen(id: 'account', title: 'Make a Lovart account', icon: Lucide.userPlus, links: [SetupLink('Open lovart.ai', lovartSiteUrl)]),
      const SetupOpen(id: 'keys', title: 'Copy your keys', icon: Lucide.keyRound, links: [SetupLink('Open Lovart', lovartHomeUrl)]),
      SetupPaste(
        id: 'paste',
        title: 'Paste your keys',
        icon: Lucide.clipboardPaste,
        fields: const [
          SetupField(id: 'access', label: 'Access key', placeholder: 'Access key', shape: _keyShape),
          SetupField(id: 'secret', label: 'Secret key', placeholder: 'Secret key', shape: _keyShape),
        ],
        save: (values) async {
          final access = values['access']!, secret = values['secret']!;
          if (access == secret) return 'That is the same key twice: the secret key is the other one of the pair.';
          await on.secrets.write(lovart.accessKeySecret, access);
          await on.secrets.write(lovart.secretKeySecret, secret);
          return null;
        },
      ),
      SetupCheck(id: 'check', title: 'Check they work', icon: Lucide.shieldCheck, checking: 'Asking Lovart…', run: () => lovartSetupResult(via: via, client: client)),
      SetupDone(id: 'done', title: 'Try it', icon: Lucide.wandSparkles, body: (context, simple) => LovartTryIt(simple: simple)),
    ],
  );
}

/// The last step's part: the cue to copy, and the switch that spends credits by itself.
class LovartTryIt extends StatefulWidget {
  const LovartTryIt({super.key, required this.simple});
  final bool simple;

  @override
  State<LovartTryIt> createState() => _LovartTryItState();
}

class _LovartTryItState extends State<LovartTryIt> {
  late final Copied _copied = Copied(lovartSampleCue)..addListener(_redraw);
  late final VoidCallback _stop;

  @override
  void initState() {
    super.initState();
    _stop = onPluginStorage(_redraw);
  }

  @override
  void dispose() {
    _stop();
    _copied
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = bannersOn();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: t.space(3),
      children: [
        Container(
          key: const ValueKey('lovart-try-cue'),
          padding: EdgeInsets.all(t.space(3)),
          decoration: BoxDecoration(color: t.color('glacier-bg'), borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline'))),
          child: Row(
            spacing: t.space(2),
            children: [
              Expanded(child: Text(lovartSampleCue, style: t.textAt(t.fontSize('sm'), mono: true, color: t.color('app-ink')))),
              MarketButton(key: const ValueKey('lovart-try-copy'), label: _copied.value ? 'Copied' : 'Copy', semantics: 'Copy the example', icon: Lucide.copy, look: MarketButtonLook.ring, onPress: _copied.copy),
            ],
          ),
        ),
        Row(
          key: const ValueKey('lovart-try-banners'),
          spacing: t.space(3),
          children: [
            AppIcon(Lucide.image, size: 18, color: t.color('app-ink-2')),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text('Header images for notes', style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink'))),
                  Text(
                    on ? (widget.simple ? 'On: a banner for each longer note, with your credits.' : 'On: a banner as you leave a note of 25 words or more, once per note, ${aboutCredits(1)} each.') : 'Off: banners are made only when you ask, from a note’s menu.',
                    style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3')),
                  ),
                ],
              ),
            ),
            GlacierSwitch(ariaLabel: 'Header images for notes', checked: on, onCheckedChange: setBanners),
          ],
        ),
      ],
    );
  }
}
