/// A group's chip, before its first tab in the tab row: its name in its colour, as Chrome draws one. The web's
/// `src/app/notes/GroupChip.tsx`.
///
/// It was ported with the tab row it belongs to: [GroupChip] in lib/notes/tabs/tab_parts.dart (see there for what
/// differs from the page). The All notes page draws no chip; this file hands the widget on under the web's own name
/// for the file, so a port that follows the web's imports finds it.
library;

export 'tabs/tab_parts.dart' show GroupChip;
