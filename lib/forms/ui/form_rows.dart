/// A form's rows in its note's sharing (lib/share/ui/share_rows.dart; docs/FORMS.md): under the link, whether the form
/// takes answers - open, paused or closed, each a row to choose, the link saying so to a visitor - how many came and
/// were filed as tickets, and Delete the answers waiting. A form not shared yet has one quiet row saying what sharing
/// it does. Drawn only for a note that holds a ```form fence (lib/forms/form_def.dart).
///
/// Opened just after its link was made, it says the share is a form (`PUT forms/<id>`), so the link takes answers at
/// once rather than after the next sync pass. In simple mode (Matt, 2026-10-18: GHST-103) the three states and the
/// count are drawn as in advanced; Delete the answers waiting is behind More, which opens in place.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/note.dart';
import '../../core/note_text.dart' show noteTitle;
import '../../sheet/css.dart';
import '../../sheet/flow.dart';
import '../../sheet/kit.dart';
import '../form_admin.dart';
import '../form_def.dart';
import '../form_inbox.dart' show formNotebook;

class FormRows extends StatefulWidget {
  const FormRows({super.key, required this.services, required this.noteId, this.admin});

  final AccountServices? services;
  final String noteId;

  /// The service's side; the account's own where it is left out (a test's).
  final FormAdmin? admin;

  @override
  State<FormRows> createState() => _FormRowsState();
}

class _FormRowsState extends State<FormRows> {
  Note? _note;
  List<Note> _notes = const [];
  FormStanding? _form;
  String? _asked;
  bool _busy = false;
  bool _more = false;
  String? _said;

  FormAdmin? get _admin => widget.admin ?? (widget.services == null ? null : FormAdmin.of(widget.services!));

  String? get _shareId {
    final link = widget.services?.shares?.linkFor(widget.noteId);
    if (link == null) return null;
    final hash = link.indexOf('#');
    final dot = link.lastIndexOf('.');
    return hash >= 0 && dot > hash ? link.substring(hash + 1, dot) : null;
  }

  @override
  void initState() {
    super.initState();
    widget.services?.shares?.addListener(_changed);
    unawaited(_read());
  }

  @override
  void didUpdateWidget(FormRows old) {
    super.didUpdateWidget(old);
    if (old.services?.shares != widget.services?.shares) {
      old.services?.shares?.removeListener(_changed);
      widget.services?.shares?.addListener(_changed);
    }
    if (old.noteId != widget.noteId) {
      _form = null;
      _asked = null;
      _said = null;
      unawaited(_read());
    }
  }

  @override
  void dispose() {
    widget.services?.shares?.removeListener(_changed);
    super.dispose();
  }

  /// A share made or stopped: the form's standing asked for again.
  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_shareId != _asked) unawaited(_ask());
  }

  Future<void> _read() async {
    final list = widget.services?.listNotes;
    if (list == null) return;
    try {
      final notes = await list();
      Note? note;
      for (final each in notes) {
        if (each.id == widget.noteId) note = each;
      }
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _note = note;
      });
      await _ask();
    } catch (_) {
      // Not readable just now: the rows stay away until the sheet opens again.
    }
  }

  /// What the service says of the form, and where it has not heard yet that the share is one, it is told.
  Future<void> _ask() async {
    final note = _note, admin = _admin, id = _shareId;
    _asked = id;
    if (note == null || admin == null || id == null || !isFormBody(note.body)) {
      if (mounted) setState(() => _form = null);
      return;
    }
    try {
      var form = await admin.standing(id);
      if (form == null) {
        final def = formOf(note.body);
        final notebook = formNotebook(def, note, _notes);
        final workspaces = widget.services?.workspaces;
        String? org;
        for (final each in [?notebook, note]) {
          final space = workspaces?.workspaceOf(each.id);
          org ??= space == null ? null : workspaces?.orgOf(space.id);
        }
        form = await admin.say(id, noteId: note.id, org: org, files: def?.takesFile ?? false);
      }
      if (mounted) setState(() => _form = form);
    } catch (failure) {
      if (mounted) setState(() => _said = accountFailureText(failure));
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      await work();
    } catch (failure) {
      if (mounted) setState(() => _said = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _set(FormTaking state) => _run(() async {
        final form = await _admin!.setState(_shareId!, state);
        if (mounted) setState(() => _form = form ?? _form);
      });

  Future<void> _deleteWaiting() => _run(() async {
        final gone = await _admin!.deleteWaiting(_shareId!);
        final form = await _admin!.standing(_shareId!);
        if (mounted) {
          setState(() {
            _form = form ?? _form;
            _said = gone == 1 ? 'One answer deleted, unfiled.' : '$gone answers deleted, unfiled.';
          });
        }
      });

  @override
  Widget build(BuildContext context) {
    final note = _note;
    if (note == null || !isFormBody(note.body) || !(widget.services?.signedIn ?? false)) return const SizedBox.shrink();
    final t = context.tokens;
    final def = formOf(note.body);
    final notebook = formNotebook(def, note, _notes);
    final where = notebook == null ? 'a ticket of its own' : 'a ticket in ${noteTitle(notebook.body)}';
    final simple = widget.services?.prefs.value.simple ?? false;
    final form = _form;
    final said = _said;
    const mark = AppIcon(Lucide.textCursorInput, size: 18, strokeWidth: 2.2);

    final List<Widget> rows;
    if (_shareId == null) {
      rows = [SheetRow(key: const ValueKey('form-unshared'), icon: mark, label: 'A form', hint: 'Share its link above and anyone can fill it in, with no account. Each answer becomes $where.')];
    } else if (form == null) {
      rows = [SheetRow(key: const ValueKey('form-asking'), icon: mark, label: 'A form', hint: said == null ? 'Asking the service…' : 'Its link can’t take answers until the service hears it is a form.')];
    } else {
      SheetRow state(FormTaking which, String label, String hint, LucideIcon icon) => SheetRow(
            key: ValueKey('form-${which.name}'),
            icon: AppIcon(icon, size: 18, strokeWidth: 2.2),
            label: label,
            hint: hint,
            chosen: form.state == which,
            disabled: _busy,
            onPress: form.state == which ? null : () => unawaited(_set(which)),
          );
      rows = [
        state(FormTaking.open, 'Taking answers', 'Anyone with the link can fill it in. Each answer becomes $where.', Lucide.play),
        state(FormTaking.paused, 'Paused', 'The link says it isn’t taking answers just now.', Lucide.pause),
        state(FormTaking.closed, 'Closed', 'The link says the form is closed.', Lucide.ban),
        SheetRow(key: const ValueKey('form-counts'), icon: const AppIcon(Lucide.ticket, size: 18, strokeWidth: 2.2), label: formCounts(form), hint: 'Sealed in the visitor’s browser: only ${form.org == null ? 'your devices' : 'your team'} can open them.'),
        if (form.waiting > 0 && simple && !_more) SheetRow(key: const ValueKey('form-more'), icon: const AppIcon(Lucide.ellipsis, size: 18, strokeWidth: 2.2), label: 'More', onPress: () => setState(() => _more = true)),
        if (form.waiting > 0 && (!simple || _more))
          SheetRow(
            key: const ValueKey('form-delete-waiting'),
            icon: const AppIcon(Lucide.trash2, size: 18, strokeWidth: 2.2),
            label: _busy ? 'Deleting…' : 'Delete the answers waiting',
            hint: 'They go unfiled. The service keeps none longer than thirty days in any case.',
            danger: true,
            disabled: _busy,
            onPress: () => unawaited(_deleteWaiting()),
          ),
      ];
    }

    return CssFlow(
      collapse: true,
      children: [
        const SheetHeading('Form'),
        SheetGroup(
          children: [
            ...rows,
            if (said != null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(4)),
                child: Semantics(liveRegion: true, child: Text(said, key: const ValueKey('form-said'), style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle')))),
              ),
          ],
        ),
      ],
    );
  }
}
