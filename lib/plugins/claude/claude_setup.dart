/// Claude's setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-28: "For each of the plugins add a small
/// onboarding flow start with the lovart and Claude plugins walk the user through setting up an account and getting
/// their keys and have the onboarding test setup to make sure it was successful"). Six steps, in Claude's coral:
///
/// 1. **Claude, with your own key**: the person's own Anthropic API key, billed by Anthropic, and what Claude does in
///    Ghost.md (the dock, meetings, the Ask Claude note).
/// 2. **Make an Anthropic account**: Open the Claude Console ([claudeConsoleUrl]) to sign up or sign in, and Billing
///    ([claudeBillingUrl]) beside it, since a new account has no credit.
/// 3. **Make a key**: Open API keys ([claudeKeysUrl]), then Create Key; copied at once, as the Console shows it once.
///    The addresses are the Console's own as the plugin's page names it (console.anthropic.com); each answers with
///    a permanent redirect to the same path on platform.claude.com, read on 2026-10-28.
/// 4. **Paste your key**: `sk-ant-…`, its shape checked ([claudeKeyShape]), then kept where the page keeps it
///    ([ClaudeSettings.setKey]: the secure store's `anthropic-api-key`), so the sealed sync follows it.
/// 5. **Check it works**: the cheapest call there is, `GET /v1/models?limit=1`, through the plugin's own check
///    ([ClaudeApi.check]). Said in plain words ([claudeSetupResult]): a 401 is "That key isn’t right." and the key is
///    let go of again, as the page never keeps a refused key; a 403 is a key not allowed the API; a 402, a 429 or a
///    word of the credit balance is "The key works but the account has no credit yet; add some under Billing.", with
///    Billing; no answer is the connection.
/// 6. **Your settings**: the two that matter, Write meeting summaries with Claude and the model, each with its default
///    in a line ([ClaudeSetupChoices]).
///
/// Listing the models is not billed, and a key with no credit may well list them: so a check that passes says the key
/// is right, not that the account can pay. Step 2 says to add credit, and the chat says so plainly at the first ask
/// where there is none.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../claude/claude_mark.dart';
import '../../claude/claude_settings.dart';
import '../../claude/messages_api.dart';
import '../../settings/kit/settings_type.dart' show pageText;
import '../../sheet/kit.dart';
import '../onboarding/setup_flow.dart';

/// The Claude Console, where an account is made.
const String claudeConsoleUrl = 'https://console.anthropic.com/';

/// The Console's API keys, where Create Key is.
const String claudeKeysUrl = 'https://console.anthropic.com/settings/keys';

/// The Console's Billing, where credit is added.
const String claudeBillingUrl = 'https://console.anthropic.com/settings/billing';

const Color _white = Color(0xFFFFFFFF);

/// What is wrong with the shape of a pasted key, or null where it looks like one.
String? claudeKeyShape(String text) {
  if (RegExp(r'\s').hasMatch(text)) return 'Paste the key alone: it has no spaces in it.';
  if (!text.startsWith('sk-ant-')) return 'That doesn’t look like an Anthropic API key. Those start with sk-ant-.';
  if (text.length < 24) return 'That key looks cut short. Copy all of it from the Console.';
  return null;
}

const String claudeNoCredit = 'The key works but the account has no credit yet; add some under Billing.';

/// The check's answer, as the setup says it (see the header). Lets go of a refused key from [settings].
Future<SetupResult> claudeSetupResult(ClaudeSettings settings, ClaudeError? wrong) async {
  if (wrong == null) return const SetupResult.ok('Your key works. Claude is ready.');
  final status = wrong.status;
  if (wrong.badKey) {
    await settings.setKey(null);
    return const SetupResult.failed('That key isn’t right. Copy it again from API keys in the Console: all of it, from sk-ant- to the end.', pasteAgain: true);
  }
  if (status == 403 || wrong.type == 'permission_error') {
    return const SetupResult.failed('Anthropic says this key may not use the API. Make a new key in the Console, in a workspace that can, and paste that.', pasteAgain: true);
  }
  final credit = wrong.message.toLowerCase().contains('credit');
  if (status == 402 || status == 429 || wrong.type == 'billing_error' || (status == 400 && credit)) {
    return const SetupResult.warn(claudeNoCredit, link: SetupLink('Open Billing', claudeBillingUrl));
  }
  if (status == null) {
    return SetupResult.failed(wrong.message.contains('too long') ? 'Anthropic took too long to answer. Check the connection, then check again.' : 'Anthropic couldn’t be reached. Check the connection, then check again.');
  }
  return SetupResult.failed(wrong.message);
}

/// Claude's setup (see the header). [settings] are the ones the key is kept in, the app's when null; [check] asks
/// Anthropic whether a key works, the plugin's own check when null.
PluginSetup claudeSetup({ClaudeSettings? settings, Future<ClaudeError?> Function(String key)? check}) {
  final claude = settings ?? claudeSettings;
  final ask = check ?? (key) => ClaudeApi(key: key).check();
  return PluginSetup(
    id: 'claude',
    name: 'Claude',
    hues: const ['coral', 'orange', 'amber'],
    tiles: const [Lucide.sparkles, Lucide.squarePen, Lucide.users, Lucide.listChecks],
    mark: (size) => ClaudeMark(size: size, color: _white),
    ready: () => claude.hasKey,
    watch: (listener) {
      claude.addListener(listener);
      return () => claude.removeListener(listener);
    },
    prepare: claude.load,
    steps: [
      const SetupIntro(
        id: 'intro',
        title: 'Claude, with your own key',
        icon: Lucide.bot,
        points: [
          (Lucide.squarePen, 'Ask from the dock on any page, and watch Claude write into the note'),
          (Lucide.users, 'Meetings written up: what was said, what was decided, who does what'),
          (Lucide.listChecks, 'The to-dos in your Ask Claude note, done as you write them'),
          (Lucide.gauge, 'Billed by Anthropic to your key, at each model’s own price. A monthly limit is on Claude’s page.'),
        ],
      ),
      const SetupOpen(
        id: 'account',
        title: 'Make an Anthropic account',
        icon: Lucide.userPlus,
        links: [SetupLink('Open the Console', claudeConsoleUrl), SetupLink('Billing', claudeBillingUrl)],
      ),
      const SetupOpen(id: 'key', title: 'Make a key', icon: Lucide.keyRound, links: [SetupLink('Open API keys', claudeKeysUrl)]),
      SetupPaste(
        id: 'paste',
        title: 'Paste your key',
        icon: Lucide.clipboardPaste,
        fields: const [SetupField(id: 'key', label: 'API key', placeholder: 'sk-ant-…', shape: claudeKeyShape)],
        save: (values) async {
          await claude.setKey(values['key']);
          return null;
        },
      ),
      SetupCheck(
        id: 'check',
        title: 'Check it works',
        icon: Lucide.shieldCheck,
        checking: 'Asking Anthropic…',
        run: () async {
          await claude.load();
          final key = claude.key;
          if (key == null) return const SetupResult.failed('No key is kept yet. Paste it first.', pasteAgain: true);
          return claudeSetupResult(claude, await ask(key));
        },
      ),
      SetupDone(id: 'done', title: 'Your settings', icon: Lucide.slidersHorizontal, body: (context, simple) => ClaudeSetupChoices(settings: claude, simple: simple)),
    ],
  );
}

/// The last step's part: Write meeting summaries with Claude, and the model, each with its default in a line. The
/// same settings as the plugin's page (lib/plugins/claude/claude_in_app.dart), written through [settings].
class ClaudeSetupChoices extends StatelessWidget {
  const ClaudeSetupChoices({super.key, required this.settings, required this.simple});
  final ClaudeSettings settings;
  final bool simple;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final quiet = pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3'));
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: t.space(2),
        children: [
          SheetGroup(
            children: [
              Padding(
                key: const ValueKey('claude-setup-meetings'),
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
                          Text('Write meeting summaries with Claude', style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink'))),
                          Text(
                            settings.meetings
                                ? 'On by default: each meeting’s transcript goes from this device to Anthropic under your key, and Claude writes it up.'
                                : 'Off: your device’s own model writes meetings up, and nothing of them goes to Anthropic.',
                            style: quiet,
                          ),
                        ],
                      ),
                    ),
                    GlacierSwitch(ariaLabel: 'Write meeting summaries with Claude', checked: settings.meetings, onCheckedChange: (on) => unawaited(settings.setMeetings(on))),
                  ],
                ),
              ),
            ],
          ),
          const SheetHeading('Model'),
          Text('${claudeModelLabel(defaultClaudeModel)} unless you choose another: quick and able. Each is billed at its own price.', key: const ValueKey('claude-setup-model-default'), style: quiet),
          SheetGroup(
            children: [
              for (final model in claudeModels)
                SheetRow(
                  key: ValueKey('claude-setup-model:${model.id}'),
                  label: model.name,
                  hint: simple ? null : model.about,
                  chosen: settings.model == model.id,
                  onPress: () => unawaited(settings.setModel(model.id)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
