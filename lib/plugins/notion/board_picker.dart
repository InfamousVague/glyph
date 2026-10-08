/// The boards Notion let Ghost.md see, one to choose for a note, on the note's cog sheet. Not signed in, it offers
/// sign-in, and the list appears when Ghost.md comes back from the browser. A port of
/// `src/app/plugins/notion/BoardPicker.tsx`.
///
/// What differs: it is one block of the sheet's flow (a [CssFlow] of the kit's pieces) where the page returned a
/// fragment of them; the account is a [NotionAccountWatch] it makes and disposes.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../sheet/flow.dart';
import '../../sheet/kit.dart';
import '../details_cache.dart' show failureWords;
import 'client.dart';
import 'marks.dart';

class BoardPicker extends StatefulWidget {
  const BoardPicker({super.key, required this.noteId, required this.onDone});

  final String noteId;

  /// Back to the note's settings.
  final VoidCallback onDone;

  @override
  State<BoardPicker> createState() => _BoardPickerState();
}

class _BoardPickerState extends State<BoardPicker> {
  late final NotionAccountWatch _watch = NotionAccountWatch()..addListener(_changed);
  late Board? _chosen = boardFor(widget.noteId);
  List<Board>? _boards;
  String? _trouble;
  bool _connected = false;

  /// Which asking of the boards an answer belongs to: one from before a sign-out is dropped.
  int _asking = 0;

  @override
  void dispose() {
    _watch
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final connected = _watch.account?.connected ?? false;
    if (connected && !_connected) unawaited(_look());
    if (!connected) _asking += 1;
    setState(() => _connected = connected);
  }

  Future<void> _look() async {
    final asking = ++_asking;
    try {
      final found = await listBoards();
      if (mounted && asking == _asking) setState(() => _boards = found);
    } catch (failure) {
      if (mounted && asking == _asking) setState(() => _trouble = failureWords(failure));
    }
  }

  void _choose(Board? board) {
    linkBoard(widget.noteId, board);
    setState(() => _chosen = board);
    widget.onDone();
  }

  Future<void> _signIn() async {
    try {
      await startNotionSignIn();
    } catch (failure) {
      if (mounted) setState(() => _trouble = failureWords(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _watch.account;
    final problem = _watch.problem;
    final trouble = _trouble;
    if (account == null) return const CssFlow(children: [SheetNote('Checking Notion…')]);
    if (!account.connected) {
      return CssFlow(
        children: [
          SheetTitle.text('Sign in to Notion'),
          if (problem != null && problem.isNotEmpty) SheetNote(problem),
          const SheetNote('Notion opens in your browser and asks which boards Ghost.md may use. Pick them, then come back here.'),
          SheetGroup(
            children: [SheetRow(icon: const NotionMark(), label: 'Sign in with Notion', onPress: () => unawaited(_signIn()))],
          ),
          if (trouble != null && trouble.isNotEmpty) SheetNote(trouble),
        ],
      );
    }
    final boards = _boards;
    final workspace = account.workspaceName;
    return CssFlow(
      children: [
        SheetTitle.text('Where tasks go'),
        SheetNote('Boards in ${workspace != null && workspace.isNotEmpty ? workspace : 'Notion'} that Ghost.md can see.'),
        if (trouble != null && trouble.isNotEmpty) SheetNote(trouble),
        SheetGroup(
          children: [
            if (boards == null)
              const SheetRow(label: 'Looking for boards…')
            else if (boards.isNotEmpty)
              for (final board in boards) SheetRow(key: ValueKey(board.id), icon: const NotionMark(), label: board.title, chosen: _chosen?.id == board.id, onPress: () => _choose(board))
            else
              const SheetRow(label: 'No boards yet', hint: 'Sign in again from Settings › Plugins › Notion and tick the boards you want.'),
          ],
        ),
        if (_chosen != null)
          SheetGroup(
            children: [SheetRow(label: 'Don’t send this note to Notion', onPress: () => _choose(null))],
          ),
      ],
    );
  }
}
