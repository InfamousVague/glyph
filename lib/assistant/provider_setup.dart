/// An AI provider's setup (lib/plugins/onboarding/setup_flow.dart; docs/AI_PROVIDERS.md, "Its page and its setup"),
/// the same steps for each, as Claude's are (lib/plugins/claude/claude_setup.dart), in the provider's own words
/// (lib/plugins/onboarding/setup_voice.dart). They were captions only at first (Matt, 2026-10-29: "leave voice clips
/// out, captions only"), and are said aloud as every plugin's are since the same day's "add the voiceover onboarding
/// for the rest of the plugins":
///
/// 1. **(Name), with your own key**: what it does in Ghost.md, that the provider bills the key, and where the words go.
/// 2. **Make an account** and 3. **Make a key**: the provider's own pages, opened in the browser. Not the custom
///    endpoint's, which has no one place to send a person.
/// 4. **Paste your key**: its shape checked where the provider's keys have one, then kept where the page keeps it
///    ([AiProviderSettings.setKey]), so the sealed sync follows it. The custom endpoint's has its address first, and
///    its key may be left empty (an endpoint on the person's own computer needs none).
/// 5. **Check it works**: the provider's models list, which none bills ([AiProvider.check]), said in plain words
///    ([providerSetupResult]); the list it answers is kept for the last step's picker.
/// 6. **Your settings**: Write meeting summaries with (its name) and the model, from the list just read (or typed, for the
///    custom endpoint), the default said in a line ([ProviderSetupChoices]).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../plugins/github/plain_field.dart';
import '../plugins/onboarding/setup_flow.dart';
import '../settings/kit/settings_type.dart' show pageText;
import '../sheet/kit.dart';
import 'provider.dart';
import 'provider_page.dart';
import 'provider_settings.dart';

/// The check's answer, as the setup says it. Lets go of a refused key from [settings].
Future<SetupResult> providerSetupResult(AiProviderPage page, AiError? wrong) async {
  final settings = page.settings;
  if (wrong == null) {
    return SetupResult.ok(page.custom ? 'The endpoint answers. ${settings.model.isEmpty ? 'Choose its model next.' : '${settings.model} is ready.'}' : 'Your key works. ${page.name} is ready.');
  }
  final status = wrong.status;
  if (wrong.badKey) {
    await settings.setKey(null);
    return SetupResult.failed('That key isn’t right. Copy it again${page.keys == null ? '' : ' from ${page.keys!.label}'}: all of it.', pasteAgain: true);
  }
  if (status == 403 || wrong.type == 'permission_error') {
    return SetupResult.failed('${page.company} says this key may not use the API. Make a new key that can, and paste that.', pasteAgain: true);
  }
  if (wrong.type == 'billing_error' || status == 402) {
    final billing = page.billing;
    return SetupResult.warn('The key works but the account has no credit yet; add some under Billing.', link: billing == null ? null : SetupLink(billing.label, billing.url, verified: false));
  }
  if (status == 429) return SetupResult.warn(wrong.message);
  if (page.custom && status == 404) {
    // An endpoint with no list of models is asked all the same, by the model's name typed next.
    return const SetupResult.warn('The endpoint has no list of models. That’s fine: type the model’s name next. If nothing answers later, check the address, which usually ends in /v1.');
  }
  if (status == null) return SetupResult.failed('${wrong.message.contains('too long') ? '${page.name} took too long to answer.' : '${page.name} couldn’t be reached.'} Check the connection${page.custom ? ' and the address' : ''}, then check again.');
  return SetupResult.failed(wrong.message);
}

/// What is wrong with an endpoint's address, or null.
String? endpointShape(String text) {
  if (RegExp(r'\s').hasMatch(text.trim())) return 'Paste the address alone: it has no spaces in it.';
  final url = aiBaseUrl(text);
  final host = url == null ? null : Uri.tryParse(url)?.host;
  if (host == null || host.isEmpty) return 'That doesn’t look like an address. It is like https://openrouter.ai/api/v1.';
  return null;
}

/// [page]'s setup (see the header). [check] asks the provider whether a key works, and [models] what it lists: the
/// page's own when null.
PluginSetup providerSetup(AiProviderPage page, {Future<AiError?> Function(String? key)? check, Future<List<AiModelInfo>> Function()? models}) {
  final settings = page.settings;
  final ask = check ?? page.check;
  final list = models ?? page.models;
  final hue = page.hue;
  return PluginSetup(
    id: page.id,
    name: page.name,
    hues: [hue, 'indigo', 'purple'],
    tiles: [page.icon, Lucide.squarePen, Lucide.users, Lucide.listChecks],
    ready: () => settings.ready,
    watch: (listener) {
      settings.addListener(listener);
      return () => settings.removeListener(listener);
    },
    prepare: settings.load,
    steps: [
      SetupIntro(
        id: 'intro',
        title: page.custom ? 'Any OpenAI-compatible model' : '${page.name}, with your own key',
        icon: page.icon,
        mark: false,
        points: [
          (Lucide.squarePen, 'Ask from the dock on any page, and watch it write into the note'),
          (Lucide.users, 'Meetings written up, where you let it'),
          (Lucide.lock, 'Your words go from this device to ${page.company}, under your key, and nowhere else'),
          (Lucide.gauge, page.custom ? 'A monthly limit, at the prices you set, is on its page' : 'Billed by ${page.company} to your key. A monthly limit is on its page.'),
        ],
      ),
      if (page.account != null)
        SetupOpen(
          id: 'account',
          title: 'Make ${page.company == 'Google' ? 'a Google AI Studio' : 'an ${page.company}'} account',
          icon: Lucide.userPlus,
          links: [SetupLink(page.account!.label, page.account!.url, verified: false), if (page.billing != null) SetupLink(page.billing!.label, page.billing!.url, verified: false)],
        ),
      if (page.keys != null) SetupOpen(id: 'key', title: 'Make a key', icon: Lucide.keyRound, links: [SetupLink(page.keys!.label, page.keys!.url, verified: false)]),
      SetupPaste(
        id: 'paste',
        title: page.custom ? 'Its address and key' : 'Paste your key',
        icon: Lucide.clipboardPaste,
        fields: [
          if (page.custom) const SetupField(id: 'base', label: 'Address', placeholder: 'https://openrouter.ai/api/v1', shape: endpointShape),
          SetupField(id: 'key', label: page.custom ? 'API key, if it has one' : 'API key', placeholder: page.keyPlaceholder, shape: page.keyShape, optional: page.custom),
        ],
        save: (values) async {
          if (page.custom) await settings.setBaseUrl(values['base']);
          await settings.setKey(values['key']);
          return null;
        },
      ),
      SetupCheck(
        id: 'check',
        title: 'Check it works',
        icon: Lucide.shieldCheck,
        checking: 'Asking ${page.custom ? 'the endpoint' : page.company}…',
        run: () async {
          await settings.load();
          if (page.custom ? !settings.hasBase : !settings.hasKey) return SetupResult.failed(page.custom ? 'No address is kept yet. Paste it first.' : 'No key is kept yet. Paste it first.', pasteAgain: true);
          final wrong = await ask(settings.key);
          if (wrong == null) {
            try {
              settings.setModels(await list());
            } catch (_) {
              // The picker offers the plugin's own few, said to be possibly out of date.
            }
          }
          return providerSetupResult(page, wrong);
        },
      ),
      SetupDone(id: 'done', title: 'Your settings', icon: Lucide.slidersHorizontal, body: (context, simple) => ProviderSetupChoices(page: page, simple: simple)),
    ],
  );
}

/// The last step's part: Write meeting summaries with (its name), and the model, the default said in a line.
class ProviderSetupChoices extends StatefulWidget {
  const ProviderSetupChoices({super.key, required this.page, required this.simple});
  final AiProviderPage page;
  final bool simple;

  @override
  State<ProviderSetupChoices> createState() => _ProviderSetupChoicesState();
}

class _ProviderSetupChoicesState extends State<ProviderSetupChoices> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _keepTyped() {
    final typed = _typed.text.trim();
    if (typed.isEmpty) return;
    unawaited(widget.page.settings.setModel(typed));
    _typed.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final page = widget.page, settings = page.settings;
    final quiet = pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3'));
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final listed = settings.listed;
        final models = (listed.isEmpty ? settings.fallbackModels : listed).take(8).toList();
        final chosen = settings.model;
        final String defaultSaid;
        if (models.isEmpty) {
          defaultSaid = chosen.isEmpty ? 'Type the model’s name as the endpoint knows it.' : 'Using $chosen.';
        } else if (listed.isEmpty) {
          defaultSaid = '${models.first.name} unless you choose another. This list may be out of date: ${page.name}’s own couldn’t be read.';
        } else {
          defaultSaid = '${models.first.name} unless you choose another: the first ${page.name} lists for your key.';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: t.space(2),
          children: [
            SheetGroup(
              children: [
                Padding(
                  key: ValueKey('${page.id}-setup-meetings'),
                  padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
                  child: Row(
                    spacing: t.space(3),
                    children: [
                      AppIcon(Lucide.users, size: 18, color: t.color('app-ink-2')),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            Text('Write meeting summaries with ${page.name}', style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink'))),
                            Text(
                              settings.meetings
                                  ? 'On: a meeting’s transcript may go from this device to ${page.company} under your key, where no other AI writes it up first (Settings › AI).'
                                  : 'Off: ${page.name} never writes meetings up, and nothing of them goes to ${page.company}.',
                              style: quiet,
                            ),
                          ],
                        ),
                      ),
                      GlacierSwitch(ariaLabel: 'Write meeting summaries with ${page.name}', checked: settings.meetings, onCheckedChange: (on) => unawaited(settings.setMeetings(on))),
                    ],
                  ),
                ),
              ],
            ),
            const SheetHeading('Model'),
            Text(defaultSaid, key: ValueKey('${page.id}-setup-model-default'), style: quiet),
            if (models.isNotEmpty)
              SheetGroup(
                children: [
                  for (final model in models)
                    SheetRow(
                      key: ValueKey('${page.id}-setup-model:${model.id}'),
                      label: model.name,
                      hint: widget.simple || model.name == model.id ? null : model.id,
                      chosen: chosen == model.id,
                      onPress: () => unawaited(settings.setModel(model.id)),
                    ),
                ],
              ),
            if (page.typesModel) ...[
              PlainField(label: 'Model name', controller: _typed, placeholder: chosen.isEmpty ? 'The model’s name' : chosen, onSubmitted: _keepTyped),
              SheetGroup(children: [SheetRow(key: ValueKey('${page.id}-setup-model-typed'), label: 'Use the name typed', onPress: _keepTyped)]),
            ],
          ],
        );
      },
    );
  }
}
