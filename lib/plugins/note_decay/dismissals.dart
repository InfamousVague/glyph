/// "Still right": a mark put away until its source changes again (docs/NOTE_DECAY.md §2, §3; Matt, 2026-11-02, on
/// the plugin's marks). Kept in the page itself, a `decay-ok:` list in its front matter, one signal's token each
/// (`ticket:GHO-12@Done 2026-10-30`), so a git restore, a move, another device and an old build all keep it, as
/// docs/MARKDOWN_FIRST.md §6 has per-note facts kept. A token holds its stamp: once the ticket closes again on another
/// day, the signal's token differs and the mark is back.
library;

import '../../core/front_matter.dart' show frontMatterValue;
import '../../core/properties.dart' show propertyList, withProperty;
import 'signals.dart';

/// The front matter key.
const String decayOkKey = 'decay-ok';

/// The tokens [body] keeps as still right.
Set<String> stillRightIn(String body) => propertyList(frontMatterValue(body, decayOkKey)).map((t) => t.trim()).where((t) => t.isNotEmpty).toSet();

/// [signals] less those [body] keeps as still right, each by its whole token (its stamp with it).
List<DecaySignal> withoutStillRight(String body, List<DecaySignal> signals) {
  final kept = stillRightIn(body);
  return kept.isEmpty ? signals : [for (final signal in signals) if (!kept.contains(signal.token)) signal];
}

/// [body] keeping [signal] as still right: its token added, and any older token of the same signal dropped, so the
/// list holds one per signal.
String withStillRight(String body, DecaySignal signal) {
  final kept = [for (final token in stillRightIn(body)) if (!token.startsWith('${signal.id}@')) token, signal.token];
  return withProperty(body, decayOkKey, kept);
}
