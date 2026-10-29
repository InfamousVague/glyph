/// A plugin's setup, from the head of its page in Settings (setup_flow.dart; Matt, 2026-10-28: "For each of the
/// plugins add a small onboarding flow"). While the plugin still needs its keys ([PluginSetup.ready] false), a card in
/// its colour with its mark: "Set up Lovart", what the steps are ([PluginSetup.about]), and Set up (Carry on, where a setup was left half
/// way). Once they are kept, one quiet row: Run setup again, which starts from the first step.
///
/// The sheet (setup_sheet.dart) is built here while it is open, so it stays up as the keys are kept and this turns
/// from the card to the row under it; it takes no room on the page, being drawn over the app.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/preferences.dart';
import '../../market/market_cards.dart' show MarketButton, MarketButtonLook;
import '../../settings/kit/settings_kit.dart';
import '../../settings/kit/settings_type.dart' show pageText;
import 'setup_flow.dart';
import 'setup_sheet.dart';

class PluginSetupCard extends StatefulWidget {
  const PluginSetupCard({super.key, required this.setup, this.memory, this.prefs, this.open, this.paste});

  final PluginSetup setup;

  /// Handed to the sheet (setup_sheet.dart [PluginSetupSheet]).
  final SetupMemory? memory;
  final ValueListenable<Preferences>? prefs;
  final Future<void> Function(String url)? open;
  final Future<String?> Function()? paste;

  @override
  State<PluginSetupCard> createState() => _PluginSetupCardState();
}

class _PluginSetupCardState extends State<PluginSetupCard> {
  late VoidCallback _stop;
  late final SetupMemory _memory = widget.memory ?? SetupMemory();

  /// Whether the sheet is up, and from its first step.
  bool _open = false;
  bool _fromStart = false;

  @override
  void initState() {
    super.initState();
    _stop = widget.setup.watch(_redraw);
    final prepare = widget.setup.prepare;
    if (prepare != null) prepare().then((_) => _redraw());
  }

  @override
  void didUpdateWidget(PluginSetupCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.setup, widget.setup)) {
      _stop();
      _stop = widget.setup.watch(_redraw);
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _show({required bool fromStart}) => setState(() {
        _open = true;
        _fromStart = fromStart;
      });

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup;
    final ready = setup.ready();
    return Column(
      key: ValueKey('plugin-setup-${setup.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ready) _again(context) else _card(context),
        if (_open)
          PluginSetupSheet(
            setup: setup,
            fromStart: _fromStart,
            memory: _memory,
            prefs: widget.prefs,
            open: widget.open,
            paste: widget.paste,
            onClose: () => setState(() => _open = false),
          ),
      ],
    );
  }

  /// The card while the keys are missing.
  Widget _card(BuildContext context) {
    final t = context.tokens;
    final setup = widget.setup;
    final ink = setupInk(t, setup);
    final left = _memory.leftAt(setup.id);
    final carryOn = left != null && left != setup.steps.first.id;
    return Container(
      key: const ValueKey('plugin-setup-card'),
      padding: EdgeInsets.all(t.space(4)),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: t.isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(t.radius('lg') * 1.5),
        border: Border.all(color: ink.withValues(alpha: t.isDark ? 0.4 : 0.25), width: t.len('glacier-hairline')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: t.space(3),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: t.space(3),
            children: [
              SetupTile(setup: setup, size: t.lenOf('2.75rem')),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: t.space(1),
                  children: [
                    Semantics(header: true, child: Text('Set up ${setup.name}', style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink')))),
                    Text(
                      carryOn ? 'You were part of the way through. Carry on where you left off.' : setup.about ?? 'A few short steps: an account, your keys, and a check that they work.',
                      style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-2')),
                    ),
                  ],
                ),
              ),
            ],
          ),
          MarketButton(
            key: const ValueKey('plugin-setup-start'),
            label: carryOn ? 'Carry on' : 'Set up',
            semantics: '${carryOn ? 'Carry on setting up' : 'Set up'} ${setup.name}',
            icon: Lucide.arrowRight,
            look: MarketButtonLook.filled,
            color: setupWash(setup).first,
            large: true,
            onPress: () => _show(fromStart: false),
          ),
        ],
      ),
    );
  }

  /// The row once they are kept.
  Widget _again(BuildContext context) => PaneSection(
        children: [
          SettingRow(
            key: const ValueKey('plugin-setup-again'),
            icon: const AppIcon(Lucide.refreshCw, size: 16),
            label: 'Run setup again',
            hint: Text(widget.setup.again ?? 'The steps from the start: the account, the keys, and a check that they work.'),
            value: RowAction(onPress: () => _show(fromStart: true), child: const Text('Run')),
          ),
        ],
      );
}
