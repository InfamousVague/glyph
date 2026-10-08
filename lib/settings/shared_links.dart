import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../account/ui_state.dart';
import '../art/art.dart';
import '../core/note_text.dart';
import 'kit/settings_kit.dart';

/// How long a share the list doesn't name must have gone unwritten before it counts as lost track of, in seconds
/// (`ORPHAN_AFTER_S`).
const int orphanAfterSeconds = 600;

/// Port of `SharedLinks` (src/app/settings/SharedLinks.tsx): everything shared by a link, in one place (Settings ›
/// Account). Each note or book with its link to copy and a way to stop it, whichever device shared it, since the
/// list travels with the synced settings (lib/share/share.dart). A share the server holds that no device lists any
/// more - two devices changed their settings at once and one list won - has no note to stop it from, so those are
/// counted and can be taken down together. Nothing is drawn while there is neither.
///
/// What differs from the web original:
/// - The list, the calls and this device's notes are the [AccountServices]' shares (`Shares.sharedLinks`,
///   `sharesOnServer`, `stopSharing`, `takeDownShare`, `listNotes`); with none, nothing is drawn.
/// - The titles are read as the card arrives and whenever the shares change, where the page also listened for
///   every save (`NOTES_CHANGED`, `NOTE_SAVED`): `notesChanged` is that, for whoever has it.
/// - What the card holds is a [SharedLinksModel], so the page around it can leave the card out of its column while
///   there is nothing to draw ([SharedLinksModel.any]) where the web's component returned null.
/// What the Shared links card holds: the list, each note's title, what the server holds that no device lists, and
/// what was last said.
class SharedLinksModel extends ChangeNotifier {
  SharedLinksModel(this.services, {this.notesChanged}) {
    services.shares?.addListener(_sharesChanged);
    services.account.addListener(_sharesChanged);
    notesChanged?.addListener(readTitles);
    _listed = _listKey();
    unawaited(readTitles());
    unawaited(readOrphans());
  }

  final AccountServices services;

  /// Told when this device's notes change, so a renamed note's row follows.
  final Listenable? notesChanged;

  Map<String, String> titles = const {};
  List<String> orphans = const [];
  String? said;
  bool busy = false;
  String _listed = '';
  bool _gone = false;

  /// Every note shared by a link (`sharedLinks`).
  List<({String noteId, String link, String id})> get links => services.signedIn ? (services.shares?.sharedLinks() ?? const []) : const [];

  /// Whether there is anything to draw.
  bool get any => services.shares != null && (links.isNotEmpty || orphans.isNotEmpty);

  String _listKey() => '${services.session?.accountId}:${[for (final link in links) link.id].join(',')}';

  void _tell() {
    if (!_gone) notifyListeners();
  }

  void _sharesChanged() {
    final now = _listKey();
    _tell();
    if (now == _listed) return;
    _listed = now;
    unawaited(readTitles());
    // What the server holds that the list doesn't: asked once the list is known, and again when it changes.
    unawaited(readOrphans());
  }

  Future<void> readTitles() async {
    final list = services.shares?.listNotes ?? services.listNotes;
    if (list == null) return;
    try {
      final notes = await list();
      titles = {
        for (final note in notes) note.id: noteTitle(note.body).isEmpty ? 'Untitled' : noteTitle(note.body),
      };
      _tell();
    } catch (_) {
      // The rows read as shared from another device until the notes can be read.
    }
  }

  Future<void> readOrphans() async {
    final shares = services.shares;
    if (shares == null || !services.signedIn) return;
    final listed = {for (final link in shares.sharedLinks()) link.id};
    try {
      final held = await shares.sharesOnServer();
      // Written in the last ten minutes, a share another device just made may not be in the synced list yet.
      final settled = services.now() / 1000 - orphanAfterSeconds;
      orphans = [for (final share in held) if (!listed.contains(share.id) && share.updated < settled) share.id];
      _tell();
    } catch (_) {
      // Offline: none are counted.
    }
  }

  Future<void> copy(String link) async {
    try {
      await Clipboard.setData(ClipboardData(text: link));
      said = 'The link is copied.';
    } catch (_) {
      said = link;
    }
    _tell();
  }

  Future<void> run(Future<void> Function() work) async {
    busy = true;
    said = null;
    _tell();
    try {
      await work();
    } catch (failure) {
      said = accountFailureText(failure);
    }
    busy = false;
    _tell();
  }

  Future<void> stop(String noteId) => run(() => services.shares!.stopSharing(noteId));

  Future<void> takeDown() => run(() async {
        for (final id in orphans) {
          await services.shares!.takeDownShare(id);
        }
        orphans = const [];
      });

  @override
  void dispose() {
    _gone = true;
    services.shares?.removeListener(_sharesChanged);
    services.account.removeListener(_sharesChanged);
    notesChanged?.removeListener(readTitles);
    super.dispose();
  }
}

/// The card ([SharedLinksModel] says what is in it). Made with [services] alone it keeps a model of its own.
class SharedLinks extends StatefulWidget {
  const SharedLinks({super.key, required this.services, this.model});

  final AccountServices services;
  final SharedLinksModel? model;

  @override
  State<SharedLinks> createState() => _SharedLinksState();
}

class _SharedLinksState extends State<SharedLinks> {
  SharedLinksModel? _own;
  SharedLinksModel get _model => widget.model ?? (_own ??= SharedLinksModel(widget.services));

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        if (!model.any) return const SizedBox.shrink();
        final orphans = model.orphans;
        return PaneSection(
          title: 'Shared links',
          footer: Text(model.said ?? 'Anyone with a link can read that note or notebook, and nobody else, the server included. Stopping a link means it reads nothing from then on.'),
          children: [
            for (final share in model.links)
              SettingRow(
                key: ValueKey('shared:${share.id}'),
                icon: const AppIcon(Lucide.link2, size: 20),
                label: model.titles[share.noteId] ?? 'A note not on this device',
                hint: Text(model.titles.containsKey(share.noteId) ? 'Read-only link. Your edits follow it.' : 'Shared from another device, or since deleted.'),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RowAction(onPress: () => unawaited(model.copy(share.link)), child: const Text('Copy')),
                    RowAction(disabled: model.busy, onPress: () => unawaited(model.stop(share.noteId)), child: const Text('Stop')),
                  ],
                ),
              ),
            if (orphans.isNotEmpty)
              SettingRow(
                label: orphans.length == 1 ? 'A link no device lists' : '${orphans.length} links no device lists',
                hint: const Text("Still readable by anyone who has them. Taking them down can't be undone."),
                control: RowAction(disabled: model.busy, onPress: () => unawaited(model.takeDown()), child: const Text('Take down')),
              ),
          ],
        );
      },
    );
  }
}
