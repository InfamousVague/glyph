/// The Ask sheet (docs/ASK_THE_ORG.md, "The sheet"; Matt, 2026-11-02: "'Ask the org' with receipts: questions answered
/// only from your notes, every claim linked to the note and line it came from; when notes disagree, it shows both
/// instead of guessing"): one line to ask on, the scope it is asked of, who answers and what is sent, then the answer
/// with a numbered chip after each sentence, the notes that disagree side by side, newest first, and the receipts.
/// A chip or a receipt opens its note at its lines; Save as note files the answer, receipts and all.
///
/// In simple mode (GHST-103) it is the box and its answer: the scopes, the folders and general knowledge are behind a
/// More that opens in place. Elsewhere the scopes are chips over the box and only the folders and the switch are
/// behind More.
library;

import 'dart:async';

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/note.dart';
import '../sheet/css.dart';
import '../sheet/flow.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import 'ask.dart';
import 'ask_answer.dart';
import 'ask_model.dart';
import 'ask_scope.dart';

/// The sheet (see the library's doc).
class AskSheet extends StatefulWidget {
  const AskSheet({
    super.key,
    required this.scope,
    required this.scopes,
    this.folders = const [],
    required this.notesOf,
    required this.model,
    required this.onOpen,
    required this.onClose,
    this.onSave,
    this.simple = false,
    this.question,
    required this.now,
  });

  /// The scope it opens on.
  final AskScope scope;

  /// My notes and each organization: the chips.
  final List<AskScope> scopes;

  /// The folders, behind More.
  final List<AskScope> folders;

  /// The notes a scope reads ([notesInScope]).
  final List<Note> Function(AskScope scope) notesOf;

  /// Who answers now; null for nobody set up.
  final AskModel? Function() model;

  /// A receipt pressed: its note, and where to land ([AskCitation.at]).
  final void Function(String noteId, String at) onOpen;
  final VoidCallback onClose;

  /// Files the answer as a note, answering its title; absent, no Save as note.
  final Future<String?> Function(AskResult result)? onSave;
  final bool simple;

  /// A question to start with, asked as the sheet opens.
  final String? question;
  final int Function() now;

  static const Key fieldKey = ValueKey('ask-field'), askKey = ValueKey('ask-go'), moreKey = ValueKey('ask-more'), generalKey = ValueKey('ask-general');
  static const Key whoKey = ValueKey('ask-who'), notFoundKey = ValueKey('ask-not-found'), conflictsKey = ValueKey('ask-conflicts'), saveKey = ValueKey('ask-save');
  static Key scopeKey(AskScope scope) => ValueKey('ask-scope:${scope.key}');
  static Key chipKey(int sentence, int number) => ValueKey('ask-chip:$sentence:$number');
  static Key sideKey(int conflict, int side) => ValueKey('ask-side:$conflict:$side');
  static Key receiptKey(int number) => ValueKey('ask-receipt:$number');

  @override
  State<AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<AskSheet> {
  late final TextEditingController _question = TextEditingController(text: widget.question ?? '');
  late AskScope _scope = widget.scope;
  bool _general = false;
  bool _more = false;
  AskRun? _run;
  AskResult? _result;
  String? _problem;
  String? _saved;
  bool _saving = false;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    if ((widget.question ?? '').trim().isNotEmpty) scheduleMicrotask(_ask);
  }

  @override
  void dispose() {
    _run?.cancel();
    _question.dispose();
    super.dispose();
  }

  void _ask() {
    final question = _question.text.trim();
    final model = widget.model();
    if (question.isEmpty || model == null || !mounted) return;
    _run?.cancel();
    final asked = _asked += 1;
    final run = ask(question, scope: _scope, notes: widget.notesOf(_scope), model: model, general: _general, now: widget.now());
    setState(() {
      _run = run;
      _result = null;
      _problem = null;
      _saved = null;
    });
    run.done.then((result) {
      if (!mounted || asked != _asked) return;
      setState(() {
        _run = null;
        _result = result;
      });
    }, onError: (Object failure) {
      if (!mounted || asked != _asked) return;
      setState(() {
        _run = null;
        _problem = '$failure';
      });
    });
  }

  void _choose(AskScope scope) {
    if (scope == _scope) return;
    _run?.cancel();
    _asked += 1;
    setState(() {
      _scope = scope;
      _run = null;
      _result = null;
      _problem = null;
      _saved = null;
    });
  }

  Future<void> _save(AskResult result) async {
    final save = widget.onSave;
    if (save == null || _saving) return;
    setState(() => _saving = true);
    try {
      final title = await save(result);
      if (mounted) setState(() => _saved = title ?? 'Saved');
    } catch (failure) {
      if (mounted) setState(() => _problem = 'It was not saved: $failure');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _whoWords(AskModel? model) {
    if (model == null) return 'Set up an AI in Settings › AI, or download a model for this device, to ask ${_scope.whose}.';
    if (model.onDevice) return 'Answered on this device by ${model.name}, from ${_scope.whose}. A small model may miss or misread passages.';
    return 'Answered by ${model.name}, from ${_scope.whose}. Only the passages found are sent.';
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model();
    final result = _result;
    final chipsShown = !widget.simple || _more;
    return Sheet(
      label: _scope.title,
      onClose: widget.onClose,
      children: [
        SheetTitle.text(_scope.title),
        if (chipsShown && widget.scopes.length > 1)
          CssFlow.block(
            margin: EdgeInsets.only(bottom: context.tokens.space(3)),
            child: Wrap(
              spacing: context.tokens.space(2),
              runSpacing: context.tokens.space(2),
              children: [for (final scope in widget.scopes) _ScopeChip(key: AskSheet.scopeKey(scope), words: scope.kind == AskScopeKind.mine ? 'My notes' : scope.name, chosen: scope == _scope, onPressed: () => _choose(scope))],
            ),
          ),
        SheetGroup(
          children: [
            SheetField(
              key: AskSheet.fieldKey,
              label: 'Question',
              controller: _question,
              placeholder: 'When do we launch?',
              autoFocus: (widget.question ?? '').isEmpty,
              enterKeyHint: TextInputAction.search,
              onSubmitted: (_) => _ask(),
            ),
            SheetRow(key: AskSheet.askKey, label: _run != null ? 'Asking…' : 'Ask', disabled: model == null || _run != null, onPress: model == null || _run != null ? null : _ask),
          ],
        ),
        Semantics(key: AskSheet.whoKey, child: SheetNote(_whoWords(model))),
        if (!_more)
          CssFlow.block(
            margin: EdgeInsets.only(bottom: context.tokens.space(3)),
            child: Align(alignment: AlignmentDirectional.centerStart, child: _Quiet(key: AskSheet.moreKey, words: 'More', icon: Lucide.chevronDown, onPressed: () => setState(() => _more = true))),
          )
        else ...[
          SheetGroup(
            children: [
              SheetRow(key: AskSheet.generalKey, label: 'Use general knowledge too', hint: 'Marked where it is used; never passed off as your notes', chosen: _general, onPress: () => setState(() => _general = !_general)),
            ],
          ),
          if (widget.folders.isNotEmpty) ...[
            const SheetHeading('A folder'),
            SheetGroup(children: [for (final folder in widget.folders) SheetRow(key: AskSheet.scopeKey(folder), label: folder.name, chosen: folder == _scope, onPress: () => _choose(folder))]),
          ],
        ],
        if (_run != null) Semantics(liveRegion: true, child: const SheetNote('Finding the passages and reading them…')),
        if (_problem != null) Semantics(liveRegion: true, child: SheetNote(_problem!)),
        if (result != null) ..._answer(context, result),
      ],
    );
  }

  List<Widget> _answer(BuildContext context, AskResult result) {
    final t = context.tokens;
    final md = t.fontSize('md');
    final sm = t.fontSize('sm');
    final answer = result.answer;
    final ink = t.color('glacier-text');
    final quiet = t.color('glacier-text-subtle');
    final out = <Widget>[];

    Widget chip(Key key, AskCitation c) => _Chip(key: key, number: answer.numberOf(c), label: 'Receipt ${answer.numberOf(c)}: ${c.title}, ${c.lines}', onPressed: () => widget.onOpen(c.noteId, c.at));

    if (answer.notFound) {
      out.add(CssFlow.block(
        key: AskSheet.notFoundKey,
        margin: EdgeInsets.only(bottom: t.space(3)),
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your notes don’t say.', style: pageText(t, md, weight: 'semibold', color: ink)),
              SizedBox(height: t.space(1)),
              Text(
                'Nothing in ${result.scope.whose} answers this${result.retrieval.words.isEmpty ? '' : ' (looked for ${result.retrieval.words.take(6).join(', ')})'}.',
                style: pageText(t, sm, color: quiet),
              ),
            ],
          ),
        ),
      ));
    }
    for (var i = 0; i < answer.sentences.length; i += 1) {
      final s = answer.sentences[i];
      out.add(CssFlow.block(
        margin: EdgeInsets.only(bottom: t.space(2)),
        child: Text.rich(
          TextSpan(children: [
            if (s.general) TextSpan(text: 'General knowledge, not from your notes: ', style: pageText(t, sm, weight: 'semibold', color: quiet)),
            TextSpan(text: s.text, style: pageText(t, md, color: s.general ? quiet : ink)),
            for (final c in s.citations) ...[const TextSpan(text: ' '), WidgetSpan(alignment: PlaceholderAlignment.middle, child: chip(AskSheet.chipKey(i, answer.numberOf(c)), c))],
          ]),
        ),
      ));
    }
    if (answer.conflicts.isNotEmpty) {
      out.add(const SheetHeading('Your notes disagree'));
      out.add(CssFlow.block(
        key: AskSheet.conflictsKey,
        margin: EdgeInsets.only(bottom: t.space(3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < answer.conflicts.length; i += 1) ...[
              if (answer.conflicts[i].about.isNotEmpty) Padding(padding: EdgeInsets.only(bottom: t.space(1)), child: Text(answer.conflicts[i].about, style: pageText(t, sm, weight: 'semibold', color: quiet))),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < answer.conflicts[i].sides.length; j += 1) ...[
                      if (j > 0) SizedBox(width: t.space(2)),
                      Expanded(child: _Side(key: AskSheet.sideKey(i, j), side: answer.conflicts[i].sides[j], newest: j == 0, chip: chip(AskSheet.chipKey(1000 + i, answer.numberOf(answer.conflicts[i].sides[j].citation)), answer.conflicts[i].sides[j].citation))),
                    ],
                  ],
                ),
              ),
              SizedBox(height: t.space(3)),
            ],
          ],
        ),
      ));
    }
    if (answer.leftOut > 0 || answer.dropped > 0) {
      final words = [
        if (answer.leftOut > 0) '${answer.leftOut == 1 ? 'One sentence was' : '${answer.leftOut} sentences were'} left out: nothing in the notes held it up',
        if (answer.dropped > 0) '${answer.dropped == 1 ? 'one quote' : '${answer.dropped} quotes'} named ${answer.dropped == 1 ? 'was' : 'were'} not in the note and dropped',
      ].join('; ');
      out.add(SheetNote('${words[0].toUpperCase()}${words.substring(1)}.'));
    }
    final receipts = answer.receipts;
    if (receipts.isNotEmpty) {
      out.add(const SheetHeading('Receipts'));
      out.add(SheetGroup(
        children: [
          for (final c in receipts)
            SheetRow(key: AskSheet.receiptKey(answer.numberOf(c)), label: '${answer.numberOf(c)}. ${c.title} · ${c.lines}', hint: '“${c.quote}”', onPress: () => widget.onOpen(c.noteId, c.at)),
        ],
      ));
    }
    if (widget.onSave != null) {
      out.add(SheetGroup(
        children: [
          SheetRow(key: AskSheet.saveKey, label: _saved != null ? 'Saved as “$_saved”' : (_saving ? 'Saving…' : 'Save as note'), disabled: _saved != null || _saving, onPress: _saved != null || _saving ? null : () => unawaited(_save(result))),
        ],
      ));
    }
    return out;
  }
}

/// A scope's chip: My notes, an organization.
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({super.key, required this.words, required this.chosen, required this.onPressed});
  final String words;
  final bool chosen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return Semantics(
      selected: chosen,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: 'Ask $words',
        builder: (context, state) => GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('full'),
          child: Container(
            constraints: BoxConstraints(minHeight: t.space(8)),
            padding: EdgeInsets.symmetric(horizontal: t.space(3)),
            decoration: BoxDecoration(
              color: chosen ? t.color('glacier-text') : (state.pressed || state.hovered ? t.color('app-wash') : null),
              border: Border.all(color: chosen ? t.color('glacier-text') : t.color('app-ink-3').withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(t.radius('full')),
            ),
            // Sized to its words: an alignment here would stretch the chip across the sheet.
            child: Center(widthFactor: 1, heightFactor: 1, child: ExcludeSemantics(child: Text(words, style: pageText(t, sm, weight: 'medium', color: chosen ? t.color('app-paper') : t.color('glacier-text-subtle'))))),
          ),
        ),
      ),
    );
  }
}

/// A receipt's small numbered chip after a sentence.
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.number, required this.label, required this.onPressed});
  final int number;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('sm'),
        child: Container(
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(color: state.pressed || state.hovered ? t.color('glacier-text') : t.color('app-wash'), borderRadius: BorderRadius.circular(t.radius('sm'))),
          child: Center(widthFactor: 1, heightFactor: 1, child: ExcludeSemantics(child: Text('$number', style: pageText(t, xs, weight: 'bold', color: state.pressed || state.hovered ? t.color('app-paper') : t.color('glacier-text-subtle'))))),
        ),
      ),
    );
  }
}

/// One side of a disagreement: "[[Standup Oct 29]] says Monday", its chip, and Newest over the first.
class _Side extends StatelessWidget {
  const _Side({super.key, required this.side, required this.newest, required this.chip});
  final AskSide side;
  final bool newest;
  final Widget chip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final md = t.fontSize('md');
    return Container(
      padding: EdgeInsets.all(t.space(3)),
      decoration: BoxDecoration(border: Border.all(color: t.color('app-ink-3').withValues(alpha: 0.35)), borderRadius: BorderRadius.circular(t.radius('md'))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(newest ? 'Newest' : 'Earlier', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: t.color('app-ink-3'))),
          SizedBox(height: t.space(1)),
          Text.rich(TextSpan(children: [
            TextSpan(text: '[[${side.citation.title}]]', style: pageText(t, sm, weight: 'semibold', color: t.color('glacier-text'))),
            TextSpan(text: ' says ', style: pageText(t, sm, color: t.color('glacier-text-subtle'))),
          ])),
          SizedBox(height: t.space(1)),
          Text.rich(TextSpan(children: [
            TextSpan(text: side.text, style: pageText(t, md, color: t.color('glacier-text'))),
            const TextSpan(text: ' '),
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: chip),
          ])),
        ],
      ),
    );
  }
}

/// A quiet word with its mark: More.
class _Quiet extends StatelessWidget {
  const _Quiet({super.key, required this.words, required this.icon, required this.onPressed});
  final String words;
  final LucideIcon icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: words,
      builder: (context, state) => Padding(
        padding: EdgeInsets.symmetric(vertical: t.space(1)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: AppIcon(icon, size: 14, color: t.color('app-ink-3'))),
            SizedBox(width: t.space(1)),
            Text(words, style: pageText(t, sm, weight: 'medium', color: state.hovered ? t.color('glacier-text') : t.color('glacier-text-subtle'))),
          ],
        ),
      ),
    );
  }
}
