/// The switch for the anonymous usage stats (lib/core/metrics.dart, docs/ANALYTICS.md): Settings › Privacy's row, and
/// the walkthrough's on its sync-and-privacy page (Matt, 2026-11-04: onboarding "gets an actual 'Anonymous usage stats'
/// toggle, on by default"). Both are [usageStatsPref], this device's own, so moving either moves the other. It shows
/// in Simple mode as in Advanced, being a privacy control; Simple says it in fewer words.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/metrics.dart' show usageStatsPref;
import '../core/preferences.dart';
import 'kit/settings_kit.dart';

/// The switch's name.
const String usageStatsLabel = 'Anonymous usage stats';

/// What is collected and what never is, in one sentence (two in Advanced).
String usageStatsHint({required bool simple}) => simple
    ? 'Counts of which features are used, with a random ID. Never your notes or who you are.'
    : 'Counts of which screens, features and plugins are used, and errors by type, with a random ID made on this device. Never your notes, titles, searches, names or account.';

/// Settings › Privacy's row.
class UsageStatsRow extends StatelessWidget {
  const UsageStatsRow({super.key, this.store});

  /// The preferences Simple is read from; the app's own when null.
  final ValueListenable<Preferences>? store;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: usageStatsPref,
        builder: (context, on, _) => SettingRow(
          label: usageStatsLabel,
          hint: Text(usageStatsHint(simple: (store ?? preferences).value.simple)),
          control: GlacierSwitch(ariaLabel: usageStatsLabel, checked: on, onCheckedChange: usageStatsPref.set),
        ),
      );
}

/// The walkthrough's row: the switch, its name and the sentence, in the guide's own type.
class GuideUsageStats extends StatelessWidget {
  const GuideUsageStats({super.key, this.store});

  /// The preferences Simple is read from; the app's own when null.
  final ValueListenable<Preferences>? store;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final prefs = store ?? preferences;
    return ValueListenableBuilder<Preferences>(
      valueListenable: prefs,
      builder: (context, now, _) => ValueListenableBuilder<bool>(
        valueListenable: usageStatsPref,
        builder: (context, on, _) => Padding(
          padding: EdgeInsets.only(top: t.space(6)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(usageStatsLabel, style: t.textAt(t.fontSize('md'), weight: 'semibold')),
                      Padding(
                        padding: EdgeInsets.only(top: t.space(1)),
                        child: Text('${usageStatsHint(simple: now.simple)} Change it any time in Settings › Privacy.', style: t.textAt(t.fontSize('sm'), height: 1.4, color: t.color('glacier-text-muted'))),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: t.space(4)),
                GlacierSwitch(ariaLabel: usageStatsLabel, checked: on, onCheckedChange: usageStatsPref.set),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
