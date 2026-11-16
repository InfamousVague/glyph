import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

/// The few colours that mean something whatever the look (lib/looks.dart): danger, unread, chosen, online and the
/// rest. Each was a hex written where it was drawn, so no look could reach it; now each is a token of the app's
/// (assets/css/app.css, `--app-danger` and so on) with that same hex as its value and as the fallback here, so Ghost's
/// own look draws them exactly as before and a look may name its own.
extension AppColors on Tokens {
  /// Something failed or will be lost: a message that did not go, Delete, a muted microphone.
  Color get danger => colorOf('var(--app-danger, #dd3a30)');

  /// The dot of a conversation with something unread.
  Color get unread => colorOf('var(--app-unread, #4f5bd5)');

  /// What is picked: a ticked row, a reaction of your own, a message found again.
  Color get chosen => colorOf('var(--app-chosen, #4f5bd5)');

  /// The wash under a reaction or a choice of your own.
  Color get chosenWash => colorOf('color-mix(in srgb, var(--app-chosen, #4f5bd5) 22%, transparent)');

  /// Archive, as a row slid aside shows it.
  Color get info => colorOf('var(--app-info, #4f5bd5)');

  /// Someone in a call, talking, or a step done.
  Color get online => colorOf('var(--app-online, #2fb35a)');

  /// A warning that is not yet a failure.
  Color get warn => colorOf('var(--app-warn, #c27c00)');

  /// Pin, as a row slid aside shows it.
  Color get pinned => colorOf('var(--app-pinned, #d38b00)');

  /// Selected words in a message or a field.
  Color get textSelection => colorOf('var(--app-text-selection, color-mix(in srgb, #4f5bd5 30%, transparent))');

  /// The dimmed page behind a sheet.
  Color get sheetScrim => colorOf('var(--app-sheet-scrim, #00000066)');

  /// The dimmed page behind a held message's menu.
  Color get menuScrim => colorOf('var(--app-menu-scrim, #00000073)');

  /// A failed message of your own: a wash of danger on the paper.
  Color get failedGround => colorOf('color-mix(in srgb, var(--app-danger, #dd3a30) 18%, var(--app-paper-2))');
}
