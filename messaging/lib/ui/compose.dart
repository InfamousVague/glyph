import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';
import 'thread.dart';

/// A new message: who it is to (contacts as they are typed, or a number), then the conversation with them.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.addresses = const [], this.body});
  final List<String> addresses;
  final String? body;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final List<Person> _to = [];
  final _field = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, String?>> _matches = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    for (final a in widget.addresses) {
      _to.add(Person(address: a));
      Sms.instance.contact(a).then((p) { if (mounted) setState(() => _to[_to.indexWhere((x) => x.address == a)] = p); });
    }
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      final found = await Sms.instance.searchContacts(q);
      if (mounted) setState(() => _matches = found);
    });
  }

  bool get _typedNumber {
    final q = _field.text.trim();
    return RegExp(r'^[+()\-\s0-9.]{3,}$').hasMatch(q) || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(q);
  }

  void _add(Person p) {
    if (!_to.any((x) => x.address == p.address)) setState(() => _to.add(p));
    _field.clear();
    _search('');
    _focus.requestFocus();
  }

  Future<void> _next() async {
    if (_typedNumber) _add(Person(address: _field.text.trim()));
    if (_to.isEmpty) return;
    final addresses = _to.map((p) => p.address).toList();
    final thread = await Sms.instance.threadFor(addresses);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) => ThreadScreen(thread: thread, people: List.of(_to), draft: widget.body),
      transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gutter = t.space(4);
    final ready = _to.isNotEmpty || _typedNumber;
    return GhostPage(
      title: 'New message',
      actions: [
        Padding(
          padding: EdgeInsets.only(right: t.space(2)),
          child: GlacierPressable(
            onPressed: ready ? _next : null,
            builder: (context, state) => Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
              decoration: BoxDecoration(color: t.color(ready ? 'app-ink' : 'app-paper-3'), borderRadius: BorderRadius.circular(t.lenOf('1.2rem'))),
              child: Text('Next', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color(ready ? 'app-paper' : 'app-ink-3'))),
            ),
          ),
        ),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, t.space(2)),
          child: Wrap(
            spacing: t.space(2),
            runSpacing: t.space(2),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final p in _to)
                GlacierPressable(
                  onPressed: () => setState(() => _to.remove(p)),
                  semanticLabel: 'Remove ${p.label}',
                  builder: (context, state) => Container(
                    padding: EdgeInsets.fromLTRB(t.space(1), t.space(1), t.space(3), t.space(1)),
                    decoration: BoxDecoration(color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'), borderRadius: BorderRadius.circular(t.lenOf('1rem'))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Avatar(people: [p], size: t.lenOf('1.5rem')),
                      SizedBox(width: t.space(2)),
                      Text(p.label, style: pageText(t, t.fontSize('sm'), weight: 'medium')),
                      SizedBox(width: t.space(1)),
                      AppIcon(Lucide.x, size: 14, color: t.color('app-ink-3'), wash: false),
                    ]),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, t.space(2)),
          child: GlacierInput(
            controller: _field,
            focusNode: _focus,
            autoFocus: true,
            placeholder: _to.isEmpty ? 'Name or number' : 'Add someone else',
            ariaLabel: 'To',
            size: GlacierFieldSize.md,
            inputMode: TextInputType.text,
            enterKeyHint: TextInputAction.next,
            autoCorrect: false,
            onChange: (v) { setState(() {}); _search(v); },
            onSubmitted: (_) => _typedNumber ? _add(Person(address: _field.text.trim())) : _next(),
          ),
        ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: t.space(4)),
            children: [
              if (_typedNumber)
                _ContactRow(
                  person: Person(address: _field.text.trim()),
                  line: 'Send to ${_field.text.trim()}',
                  onPress: () => _add(Person(address: _field.text.trim())),
                ),
              for (final c in _matches)
                _ContactRow(
                  person: Person(address: c['address'] ?? '', name: c['name'], photo: c['photo']),
                  line: [c['label'], c['address']].where((s) => s != null && s.isNotEmpty).join(' · '),
                  onPress: () => _add(Person(address: c['address'] ?? '', name: c['name'], photo: c['photo'])),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.person, required this.line, required this.onPress});
  final Person person;
  final String line;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPress,
      builder: (context, state) => ColoredBox(
        color: state.pressed ? t.color('app-paper-2') : const Color(0x00000000),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2) + 2),
          child: Row(children: [
            Avatar(people: [person], size: t.lenOf('2.5rem')),
            SizedBox(width: t.space(3)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(person.name ?? person.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'medium')),
                if (person.name != null || line.isNotEmpty)
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
