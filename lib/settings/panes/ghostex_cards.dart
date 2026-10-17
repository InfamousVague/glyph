import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/iphone_app.dart' show recordsVoice;
import '../../export/ghostex.dart';
import '../../export/ghostex_calls.dart';
import '../../export/ghostex_seal.dart' show GhostexWrongPassword;
import '../../importer/ghostex.dart';
import '../../importer/import_report.dart' show ImportProgress, importSkippedSaid;
import '../account_forms.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';

/// What Settings' search finds of the .ghostex on Account, and on Import.
const SettingsFindable ghostexExportFindable = SettingsFindable('Export everything', 'ghostex export download backup archive all notes pictures files password move to another device');
const SettingsFindable ghostexImportFindable = SettingsFindable('A .ghostex file', 'ghostex import restore bring back export from ghost.md another device');

String _failure(Object failure, String otherwise) => switch (failure) {
      GhostexWrongPassword() => 'That password does not open this export.',
      StateError(:final message) => message,
      _ => otherwise,
    };

sealed class _Out {
  const _Out();
}

class _OutClosed extends _Out {
  const _OutClosed();
}

class _OutForm extends _Out {
  const _OutForm();
}

class _OutRunning extends _Out {
  const _OutRunning(this.progress);
  final GhostexProgress? progress;
}

class _OutDone extends _Out {
  const _OutDone(this.made);
  final GhostexMade made;
}

class _OutFailed extends _Out {
  const _OutFailed(this.why);
  final String why;
}

/// Settings › Account › Export everything (docs/INTEGRATIONS.md §5): the row, then in its place the options (archived
/// notes, organizations' notes, recordings, and a password), a line saying how far it has got, and the finished
/// `<handle>-<date>.ghostex` handed to the device's share sheet, where it is saved to Files or a drive or sent on.
///
/// Over the [Ghostex] it is handed (`SettingsFeatures.ghostex`); with none, or on a device that cannot hand a file
/// over, the row is drawn and cannot be pressed. A recording is offered only where the app records (not an iPhone),
/// and a password only where the build can seal.
class GhostexExportCard extends StatefulWidget {
  const GhostexExportCard({super.key, this.ghostex});

  final Ghostex? ghostex;

  @override
  State<GhostexExportCard> createState() => _GhostexExportCardState();
}

class _GhostexExportCardState extends State<GhostexExportCard> {
  _Out _state = const _OutClosed();
  bool _archived = false, _organizations = false, _recordings = false, _protect = false;
  String _password = '', _again = '';

  bool get _can => widget.ghostex?.exportOffered ?? false;

  String? get _passwordProblem {
    if (!_protect) return null;
    if (_password.isEmpty) return '';
    if (_again.isNotEmpty && _again != _password) return 'The two passwords are not the same.';
    if (_again.isEmpty) return '';
    return null;
  }

  void _export() {
    final ghostex = widget.ghostex;
    if (ghostex == null || _passwordProblem != null) return;
    final options = GhostexOptions(archived: _archived, organizations: _organizations, recordings: _recordings, password: _protect ? _password : null);
    setState(() => _state = const _OutRunning(null));
    unawaited(ghostex
        .export(options, progress: (progress) {
          if (mounted && _state is _OutRunning) setState(() => _state = _OutRunning(progress));
        })
        .then<void>((made) {
          if (!mounted) return;
          setState(() {
            _state = _OutDone(made);
            _password = _again = '';
          });
          _hand(made);
        }, onError: (Object failure) {
          if (mounted) setState(() => _state = _OutFailed(_failure(failure, 'The export could not be written.')));
        }));
  }

  void _hand(GhostexMade made) {
    unawaited(widget.ghostex?.handOver(made).then<void>((_) {}, onError: (Object failure) {
      if (mounted) setState(() => _state = _OutFailed(_failure(failure, 'The export could not be handed over.')));
    }));
  }

  void _close() => setState(() {
        _state = const _OutClosed();
        _password = _again = '';
      });

  static String _saying(GhostexProgress? progress) {
    if (progress == null || progress.total == 0) return 'Reading the notes. Keep Ghost.md open.';
    if (progress.done >= progress.total && progress.step != 'Writing') return '${progress.step}. Keep Ghost.md open.';
    return 'Writing the export, ${progress.done} of ${progress.total}. Keep Ghost.md open.';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = _state;
    final ghostex = widget.ghostex;
    final row = SettingRow(
      icon: const AppIcon(Lucide.archive, size: 20),
      label: 'Export everything',
      hint: const Text('Every note, with its pictures and files, as one .ghostex file: to keep, or to bring into Ghost.md on another device.'),
      onPress: _can ? () => setState(() => _state = const _OutForm()) : null,
      disabled: !_can,
    );
    switch (state) {
      case _OutClosed():
        return PaneSection(children: [row]);
      case _OutRunning(:final progress):
        return SettingsCallout(
          icon: const AppIcon(Lucide.archive, size: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_saying(progress)),
              if (progress != null && progress.total > 0) ...[
                SizedBox(height: t.space(2)),
                GlacierProgressBar(ariaLabel: 'Exporting everything', value: progress.done.toDouble(), max: progress.total.toDouble(), size: GlacierProgressBarSize.sm),
              ],
            ],
          ),
        );
      case _OutDone(:final made):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(3),
          children: [
            SettingsCallout(icon: const AppIcon(Lucide.archive, size: 20), child: Text(ghostexDoneSaid(made.written, name: made.name))),
            PaneSection(
              footer: Align(alignment: AlignmentDirectional.centerStart, child: RowAction(onPress: _close, child: const Text('Done'))),
              children: [
                SettingRow(icon: const AppIcon(Lucide.share2, size: 20), label: 'Save or send it', hint: Text(made.name), onPress: () => _hand(made)),
              ],
            ),
          ],
        );
      case _OutFailed(:final why):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(3),
          children: [SettingsCallout(child: Text(why)), PaneSection(children: [row])],
        );
      case _OutForm():
        final problem = _passwordProblem;
        return PaneSection(
          title: 'Export everything',
          description: const Text('Notes in the trash are never in it. Choose what else goes in.'),
          footer: Align(alignment: AlignmentDirectional.centerStart, child: RowAction(onPress: _close, child: const Text('Cancel'))),
          children: [
            SettingRow(
              label: 'Include archived notes',
              control: GlacierSwitch(ariaLabel: 'Include archived notes', checked: _archived, onCheckedChange: (on) => setState(() => _archived = on)),
            ),
            SettingRow(
              label: 'Include organizations’ notes',
              hint: const Text('The notes filed in an organization’s workspace, which are the team’s and not only yours.'),
              control: GlacierSwitch(ariaLabel: 'Include organizations’ notes', checked: _organizations, onCheckedChange: (on) => setState(() => _organizations = on)),
            ),
            if (recordsVoice)
              SettingRow(
                label: 'Include recordings',
                hint: const Text('Each spoken note’s audio, as it was kept. It can make the file much larger.'),
                control: GlacierSwitch(ariaLabel: 'Include recordings', checked: _recordings, onCheckedChange: (on) => setState(() => _recordings = on)),
              ),
            if (ghostex?.seals ?? false)
              SettingRow(
                icon: const AppIcon(Lucide.lock, size: 20),
                label: 'Protect with a password',
                hint: const Text('The whole file is encrypted. Without the password nobody can open it, you included: it can’t be reset.'),
                control: GlacierSwitch(ariaLabel: 'Protect with a password', checked: _protect, onCheckedChange: (on) => setState(() => _protect = on)),
              ),
            SettingsForm(
              children: [
                if (_protect) ...[
                  GlacierInput(ariaLabel: 'Password', placeholder: 'Password', type: GlacierInputType.password, value: _password, onChange: (text) => setState(() => _password = text)),
                  GlacierInput(ariaLabel: 'The password again', placeholder: 'The password again', type: GlacierInputType.password, value: _again, onChange: (text) => setState(() => _again = text), onSubmitted: (_) => _export()),
                  if (problem != null && problem.isNotEmpty) FormProblem(problem),
                ],
                FormSubmit('Export', onPressed: problem == null ? _export : null),
              ],
            ),
          ],
        );
    }
  }
}

sealed class _In {
  const _In();
}

class _InIdle extends _In {
  const _InIdle();
}

class _InOpening extends _In {
  const _InOpening();
}

class _InPassword extends _In {
  const _InPassword(this.chosen, [this.problem]);
  final GhostexChosen chosen;
  final String? problem;
}

class _InChoose extends _In {
  const _InChoose(this.opened);
  final GhostexOpened opened;
}

class _InRunning extends _In {
  const _InRunning(this.progress);
  final ImportProgress? progress;
}

class _InDone extends _In {
  const _InDone(this.report);
  final GhostexReport report;
}

class _InFailed extends _In {
  const _InFailed(this.why);
  final String why;
}

/// Settings › Import › A .ghostex file (docs/INTEGRATIONS.md §5): the file chosen (or opened from the phone's Files
/// or the Mac's Finder, [ghostexWaiting]), its password asked where it was protected, the person's choice for the
/// notes already here (skip them, or keep copies) with how many there are, then how far it has got, and the report.
///
/// Over the [Ghostex] it is handed; with none, or on a device with no picker, the row cannot be pressed.
class GhostexImportCard extends StatefulWidget {
  const GhostexImportCard({super.key, this.ghostex});

  final Ghostex? ghostex;

  @override
  State<GhostexImportCard> createState() => _GhostexImportCardState();
}

class _GhostexImportCardState extends State<GhostexImportCard> {
  _In _state = const _InIdle();
  String _password = '';
  GhostexCollision _collision = GhostexCollision.skip;
  bool _stop = false;

  @override
  void initState() {
    super.initState();
    ghostexWaiting.addListener(_waiting);
    // A file opened from Files before Settings was up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _waiting());
  }

  @override
  void dispose() {
    ghostexWaiting.removeListener(_waiting);
    final state = _state;
    if (state is _InChoose) unawaited(widget.ghostex?.close(state.opened));
    super.dispose();
  }

  bool get _busy => _state is _InOpening || _state is _InRunning;

  void _waiting() {
    final chosen = ghostexWaiting.value;
    if (!mounted || chosen == null || widget.ghostex == null || _busy) return;
    ghostexWaiting.value = null;
    _open(chosen);
  }

  void _choose() {
    final ghostex = widget.ghostex;
    if (ghostex == null) return;
    setState(() => _state = const _InOpening());
    unawaited(ghostex.choose().then<void>((chosen) {
      if (!mounted) return;
      if (chosen == null) {
        setState(() => _state = const _InIdle());
      } else {
        _open(chosen);
      }
    }, onError: (Object failure) {
      if (mounted) setState(() => _state = _InFailed(_failure(failure, 'That file could not be read.')));
    }));
  }

  void _open(GhostexChosen chosen, [String? password]) {
    final ghostex = widget.ghostex;
    if (ghostex == null) return;
    setState(() => _state = const _InOpening());
    unawaited(ghostex.open(chosen, password: password).then<void>((opened) {
      if (!mounted) {
        unawaited(ghostex.close(opened));
        return;
      }
      setState(() {
        _password = '';
        _collision = GhostexCollision.skip;
        _state = _InChoose(opened);
      });
    }, onError: (Object failure) {
      if (!mounted) return;
      setState(() {
        _password = '';
        _state = switch (failure) {
          GhostexNeedsPassword() => _InPassword(chosen),
          GhostexWrongPassword() => _InPassword(chosen, 'That password does not open this export.'),
          _ => _InFailed(_failure(failure, 'That file could not be read.')),
        };
      });
      if (failure is! GhostexNeedsPassword && failure is! GhostexWrongPassword) unawaited(chosen.done?.call());
    }));
  }

  void _read(GhostexOpened opened) {
    final ghostex = widget.ghostex;
    if (ghostex == null) return;
    _stop = false;
    setState(() => _state = const _InRunning(null));
    unawaited(ghostex
        .read(opened, collision: _collision, progress: (progress) {
          if (mounted && _state is _InRunning) setState(() => _state = _InRunning(progress));
        }, stopped: () => _stop)
        .then<void>((report) {
          if (mounted) setState(() => _state = _InDone(report));
        }, onError: (Object failure) {
          if (mounted) setState(() => _state = _InFailed(_failure(failure, 'The import could not finish.')));
        }));
  }

  void _cancel() {
    final state = _state;
    if (state is _InChoose) unawaited(widget.ghostex?.close(state.opened));
    if (state is _InPassword) unawaited(state.chosen.done?.call());
    setState(() => _state = const _InIdle());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = _state;
    final can = (widget.ghostex?.importOffered ?? false) && !_busy;
    final row = SettingRow(
      icon: const AppIcon(Lucide.archiveRestore, size: 20),
      label: 'A .ghostex file',
      hint: const Text('An export from Ghost.md. Its notes come back with their workspaces, pictures and files.'),
      onPress: can ? _choose : null,
      disabled: !can,
    );
    final cancel = Align(alignment: AlignmentDirectional.centerStart, child: RowAction(onPress: _cancel, child: const Text('Cancel')));
    final section = PaneSection(children: [row]);
    switch (state) {
      case _InIdle():
        return section;
      case _InOpening():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(3),
          children: [const SettingsCallout(icon: AppIcon(Lucide.archiveRestore, size: 20), child: Text('Opening the export.')), section],
        );
      case _InFailed(:final why):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(3),
          children: [SettingsCallout(child: Text(why)), section],
        );
      case _InPassword(:final chosen, :final problem):
        return PaneSection(
          title: chosen.name,
          description: const Text('This export is protected with a password.'),
          footer: cancel,
          children: [
            SettingsForm(
              children: [
                GlacierInput(ariaLabel: 'The export’s password', placeholder: 'Password', type: GlacierInputType.password, value: _password, onChange: (text) => setState(() => _password = text), onSubmitted: (_) => _password.isEmpty ? null : _open(chosen, _password)),
                if (problem != null) FormProblem(problem),
                FormSubmit('Open', onPressed: _password.isEmpty ? null : () => _open(chosen, _password)),
              ],
            ),
          ],
        );
      case _InChoose(:final opened):
        final here = opened.here;
        return PaneSection(
          title: opened.chosen.name,
          description: Text(here == 0
              ? '${opened.notes == 1 ? 'One note' : '${opened.notes} notes'}, none of them here yet.'
              : '${opened.notes == 1 ? 'One note' : '${opened.notes} notes'}, ${here == opened.notes ? (here == 1 ? 'and it is' : 'all of them') : (here == 1 ? 'one of them' : '$here of them')} here already.'),
          footer: cancel,
          children: [
            if (here > 0)
              SettingRow(
                label: 'The notes already here',
                hint: Text(_collision == GhostexCollision.skip ? 'Left as they are: the export’s copy is not brought in.' : 'Kept, and the export’s brought in beside them as copies.'),
                control: GlacierSegmentedControl(
                  ariaLabel: 'The notes already here',
                  size: GlacierSegmentedSize.sm,
                  options: const [GlacierSegmentedOption(value: 'skip', label: Text('Skip')), GlacierSegmentedOption(value: 'copy', label: Text('Keep copies'))],
                  value: _collision.name,
                  onValueChange: (value) => setState(() => _collision = value == 'copy' ? GhostexCollision.copy : GhostexCollision.skip),
                ),
              ),
            SettingsForm(children: [FormSubmit('Import', onPressed: opened.notes == 0 ? null : () => _read(opened))]),
          ],
        );
      case _InRunning(:final progress):
        return SettingsCallout(
          icon: const AppIcon(Lucide.archiveRestore, size: 20),
          action: progress == null ? null : RowAction(onPress: () => _stop = true, child: const Text('Stop')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(progress == null || progress.total == 0 ? 'Importing the export. Keep Ghost.md open.' : 'Importing the export, ${progress.done} of ${progress.total}. Keep Ghost.md open.'),
              if (progress != null && progress.total > 0) ...[
                SizedBox(height: t.space(2)),
                GlacierProgressBar(ariaLabel: 'Importing the export', value: progress.done.toDouble(), max: progress.total.toDouble(), size: GlacierProgressBarSize.sm),
              ],
            ],
          ),
        );
      case _InDone(:final report):
        final skipped = importSkippedSaid(report);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(3),
          children: [
            SettingsCallout(
              icon: const AppIcon(Lucide.archiveRestore, size: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: t.space(2),
                children: [Text(ghostexImportSaid(report)), if (skipped != null) Text(skipped)],
              ),
            ),
            section,
          ],
        );
    }
  }
}
