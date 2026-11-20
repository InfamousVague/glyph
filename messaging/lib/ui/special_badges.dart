/// Special badges (Matt, 2026-11-19: "allow me to see all users who signed up on the relay and issue special badges and
/// souls"): given from the admin page (lib/ui/admin_page.dart) and kept by the relay (relay/lib/handles.dart
/// `specialBadges`), drawn beside a person's name where the verified-number badge is, and named on their profile card.
/// Who has which comes with the verified-number answer (Me.badges), so drawing them asks the relay nothing more.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import 'plugins_page/plugin_art.dart' show PluginHues;

/// One badge: its id on the relay, what it is called, its icon and colour.
@immutable
class SpecialBadge {
  const SpecialBadge(this.id, this.name, this.about, this.icon, this.hue);
  final String id;
  final String name;
  final String about;
  final LucideIcon icon;
  final String hue;
}

/// Lucide's bug and heart, which the app's sets don't carry (lucide-static, ISC licence).
const _bug = LucideIcon('bug', ['m8 2 1.88 1.88', 'M14.12 3.88 16 2', 'M9 7.13v-1a3.003 3.003 0 1 1 6 0v1', 'M12 20c-3.3 0-6-2.7-6-6v-3a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v3c0 3.3-2.7 6-6 6', 'M12 20v-9', 'M6.53 9C4.6 8.8 3 7.1 3 5', 'M6 13H2', 'M3 21c0-2.1 1.7-3.9 3.8-4', 'M20.97 5c0 2.1-1.6 3.8-3.5 4', 'M22 13h-4', 'M17.2 17c2.1.1 3.8 1.9 3.8 4'], []);
const _heart = LucideIcon('heart', ['M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z'], []);

/// The badges there are, in the order they are drawn (the relay's `specialBadges`).
const specialBadges = [
  SpecialBadge('team', 'Ghost team', 'Makes Ghost Messaging', Lucide.ghost, 'indigo'),
  SpecialBadge('founder', 'Founder', 'Here from the very start', Lucide.crown, 'amber'),
  SpecialBadge('bughunter', 'Bug hunter', 'Found and reported bugs', _bug, 'coral'),
  SpecialBadge('alpha', 'Alpha tester', 'Tried it before anyone else', Lucide.flaskConical, 'purple'),
  SpecialBadge('helper', 'Helper', 'Helps others find their way', Lucide.sparkles, 'teal'),
  SpecialBadge('supporter', 'Supporter', 'Supports Ghost Messaging', _heart, 'rose'),
];

SpecialBadge? specialBadge(String id) => specialBadges.where((b) => b.id == id).firstOrNull;

/// [ids] in the order [specialBadges] draws them, unknown ones left out.
List<SpecialBadge> specialBadgesOf(Iterable<String> ids) => [for (final b in specialBadges) if (ids.contains(b.id)) b];

/// Who has which badge, as the relay last said with its verified-number answer: by `i:<id>` and `u:<username>`.
class SpecialBadges extends ChangeNotifier {
  SpecialBadges() {
    Me.onSpecial ??= (ids, names, byId, byName) => instance.heard(ids: ids, names: names, byId: byId, byName: byName);
  }

  static SpecialBadges instance = SpecialBadges();

  final Map<String, List<String>> _known = {};

  /// What the relay said of [ids] and [names] it was asked of: those with badges, and none for the rest.
  void heard({required List<String> ids, required List<String> names, Map<String, List<String>> byId = const {}, Map<String, List<String>> byName = const {}}) {
    var changed = false;
    void put(String key, List<String> now) {
      final had = _known[key];
      if (had == null || had.join(',') != now.join(',')) changed = true;
      _known[key] = now;
    }

    for (final i in ids) {
      put('i:$i', byId[i] ?? const []);
    }
    for (final n in names) {
      put('u:${n.toLowerCase()}', byName[n.toLowerCase()] ?? byName[n] ?? const []);
    }
    if (changed) notifyListeners();
  }

  /// The badges [id] (or the person with [username]) has, as far as is known; this person's own for [me].
  List<SpecialBadge> of(String id, {String? username, bool me = false}) {
    if (me) return specialBadgesOf(Me.instance.special);
    final u = username == null || username.isEmpty ? null : 'u:${username.toLowerCase()}';
    return specialBadgesOf({...?_known['i:$id'], if (u != null) ...?_known[u]});
  }

  @visibleForTesting
  void reset() => _known.clear();
}

/// The badges' icons in a row, beside a name; nothing where there are none.
class SpecialBadgeMarks extends StatelessWidget {
  const SpecialBadgeMarks({super.key, required this.id, this.username, this.me = false, this.size = 14});
  final String id;
  final String? username;
  final bool me;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SpecialBadges.instance, if (me) Me.instance]),
      builder: (context, _) {
        final badges = SpecialBadges.instance.of(id, username: username, me: me);
        if (badges.isEmpty) return const SizedBox.shrink();
        final t = context.tokens;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          for (final b in badges)
            Padding(
              key: ValueKey('special-${b.id}-$id'),
              padding: EdgeInsets.only(left: t.space(1)),
              child: Semantics(label: b.name, child: AppIcon(b.icon, size: size, color: PluginHues.of(t, b.hue).accent)),
            ),
        ]);
      },
    );
  }
}

/// A badge as a chip, named, for a profile card and the admin page: its icon on its colour's wash, and its name.
class SpecialBadgeChip extends StatelessWidget {
  const SpecialBadgeChip({super.key, required this.badge, this.on = true});
  final SpecialBadge badge;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hues = PluginHues.of(t, badge.hue);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
      decoration: BoxDecoration(
        color: on ? hues.wash : const Color(0x00000000),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: on ? hues.accent.withValues(alpha: 0.4) : t.color('app-rule')),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(badge.icon, size: 14, color: on ? hues.accent : t.color('app-ink-3')),
        SizedBox(width: t.space(1)),
        Text(badge.name, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: on ? t.color('app-ink') : t.color('app-ink-3'))),
      ]),
    );
  }
}
