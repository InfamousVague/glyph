/// The projects kept on this phone, one to link to a note, and a way to add one: paste a GitHub link (and a token
/// for a private repo), and watch it being read and distilled on the phone before it is linked. A port of
/// `src/app/plugins/github/ProjectPicker.tsx`, on the sheet's kit (lib/sheet/kit.dart).
///
/// What differs:
/// - It is one block of a sheet's flow (a [CssFlow] whose first and last margins pass through it), where React
///   returned a fragment into the sheet.
/// - The token typed here is kept only once its field has been opened: the page wrote back whatever it had read
///   at once from localStorage, and here a token not yet read from the secure store would be written back as none.
/// - The sheet kit's field has no way to be a secret or to be switched off, so this file wraps it: the token is
///   drawn as dots by its controller and kept from a screen reader, and a field is out of reach while a repo is
///   being read. The keyboard is told it is a password, and does not learn it.
/// - Reading a repo can be stood in for ([ProjectPicker.read]), as the page's tests mocked `addProject`.
library;

import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';

import '../../sheet/flow.dart';
import '../../sheet/kit.dart';
import '../details_cache.dart' show failureWords;
import 'marks.dart';
import 'repos.dart';

/// What the "Read and link" row says under its words as a repo is read (`describeStep`).
String describeStep(ReadStep step) => switch (step) {
      ReadReading() => 'Asking GitHub about the repo…',
      ReadFiles(:final done, :final total) => done < total ? 'Reading ${done + 1} of $total files…' : 'Read the files.',
      ReadDistilling(:final model, :final tokensPerSecond) => '$model is reading it${tokensPerSecond != 0 ? ', ${(tokensPerSecond + 0.5).floor()} words a second' : ''}…',
    };

class ProjectPicker extends StatefulWidget {
  const ProjectPicker({super.key, required this.noteId, required this.onDone, this.read = addProject});

  final String noteId;

  /// Goes back to the note's settings.
  final VoidCallback onDone;

  /// Reads a repo and keeps it: repos.dart's own, unless a test stands in for it.
  final Future<Project> Function(String input, void Function(ReadStep step) onStep) read;

  @override
  State<ProjectPicker> createState() => _ProjectPickerState();
}

class _ProjectPickerState extends State<ProjectPicker> {
  late Project? _chosen = projectFor(widget.noteId);
  late List<Project> _known = projects();
  String _link = '';
  late final _SecretController _token = _SecretController(text: githubToken());
  final FocusNode _tokenFocus = FocusNode(debugLabel: 'GitHub token');
  bool _showToken = false;
  ReadStep? _step;
  String? _trouble;

  @override
  void dispose() {
    _token.dispose();
    _tokenFocus.dispose();
    super.dispose();
  }

  void _choose(Project? project) {
    linkProject(widget.noteId, project?.id);
    setState(() => _chosen = project);
    widget.onDone();
  }

  Future<void> _add() async {
    setState(() => _trouble = null);
    if (_showToken) unawaited(setGithubToken(_token.text));
    try {
      final added = await widget.read(_link, (step) {
        if (mounted) setState(() => _step = step);
      });
      if (!mounted) return;
      setState(() {
        _known = projects();
        _step = null;
      });
      _choose(added);
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        _step = null;
        _trouble = failureWords(failure);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final working = step != null;
    final written = step is ReadDistilling && step.text.isNotEmpty ? step.text : null;
    return CssFlow(
      collapse: true,
      children: [
        SheetTitle.text('Project'),
        const SheetNote('The model on your phone reads the repo’s README and docs and keeps a short briefing, so names and terms come out right when this note is formatted.'),
        if (_known.isNotEmpty)
          SheetGroup(
            children: [
              for (final p in _known)
                SheetRow(
                  key: ValueKey(p.id),
                  icon: const RepoMark(),
                  label: '${p.owner}/${p.repo}',
                  hint: p.packModel != null ? 'Read by ${p.packModel}.' : 'Kept from its README.',
                  chosen: _chosen?.id == p.id,
                  onPress: () => _choose(p),
                  disabled: working,
                ),
            ],
          ),
        const SheetHeading('Add a GitHub repo'),
        SheetGroup(
          children: [
            _Field(
              disabled: working,
              child: SheetField(
                label: 'Link',
                inputMode: TextInputType.url,
                autoCapitalize: TextCapitalization.none,
                autoCorrect: false,
                placeholder: 'github.com/owner/repo',
                value: _link,
                onChange: (text) => setState(() => _link = text),
              ),
            ),
            if (_showToken)
              _Field(
                disabled: working,
                // Named once, as a secret, and typed into by a tap: what is in it is never said.
                child: Semantics(
                  label: 'Token, for a private repo',
                  textField: true,
                  obscured: true,
                  onTap: _tokenFocus.requestFocus,
                  child: ExcludeSemantics(
                    child: SheetField(
                      label: 'Token, for a private repo',
                      inputMode: TextInputType.visiblePassword,
                      autoCapitalize: TextCapitalization.none,
                      autoCorrect: false,
                      placeholder: 'github_pat_…',
                      controller: _token,
                      focusNode: _tokenFocus,
                    ),
                  ),
                ),
              )
            else
              SheetRow(label: 'Private repo?', hint: 'Add a GitHub token that can read it. It stays on this phone.', onPress: () => setState(() => _showToken = true), disabled: working),
            SheetRow(
              label: working ? 'Reading…' : 'Read and link',
              hint: step == null ? null : describeStep(step),
              onPress: () => unawaited(_add()),
              disabled: working || _link.trim().isEmpty,
            ),
          ],
        ),
        if (written != null) SheetNote(written.length <= 240 ? written : written.substring(written.length - 240)),
        if (_trouble != null) SheetNote(_trouble!),
        if (_chosen != null)
          SheetGroup(
            children: [SheetRow(label: 'Don’t link a project', onPress: () => _choose(null), disabled: working)],
          ),
      ],
    );
  }
}

/// A field of a group that can be out of reach (`disabled` on the page's `<input>`). It is ruled as the field in it
/// is.
class _Field extends StatelessWidget implements SheetRuled {
  const _Field({required this.disabled, required this.child});
  final bool disabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(ignoring: disabled, child: ExcludeFocus(excluding: disabled, child: child));
}

/// A token's text, drawn as a dot a character (`type="password"`).
class _SecretController extends TextEditingController {
  _SecretController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) => TextSpan(style: style, text: '•' * text.length);
}
