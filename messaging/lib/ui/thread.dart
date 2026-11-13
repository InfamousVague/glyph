import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';

/// One conversation: its messages oldest at the top, newest by the composer.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({super.key, required this.thread, required this.people, this.draft});
  final int thread;
  final List<Person> people;
  final String? draft;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> with WidgetsBindingObserver {
  List<Message>? _messages;
  late List<Person> _people = widget.people;
  final Map<String, Person> _senders = {};
  StreamSubscription<int>? _changes;
  late final TextEditingController _text = TextEditingController(text: widget.draft ?? '');
  final _focus = FocusNode();
  final List<String> _attachments = [];
  bool _sending = false;

  bool get _group => _people.length > 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Sms.instance.setOpenThread(widget.thread);
    _load(markRead: true);
    if (_people.isEmpty) Sms.instance.people(widget.thread).then((p) { if (mounted) setState(() => _people = p); });
    _changes = Sms.instance.changes.stream.listen((t) {
      if (t == widget.thread || t < 0) _load(markRead: true);
    });
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Sms.instance.setOpenThread(null);
    _changes?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Sms.instance.setOpenThread(widget.thread);
      _load(markRead: true);
    }
  }

  Future<void> _load({bool markRead = false}) async {
    final list = await Sms.instance.messages(widget.thread);
    if (!mounted) return;
    setState(() => _messages = list);
    if (markRead && list.any((m) => !m.outgoing)) Sms.instance.markRead(widget.thread);
    if (_group) {
      for (final m in list) {
        if (!m.outgoing && m.address.isNotEmpty && !_senders.containsKey(m.address)) {
          _senders[m.address] = _people.firstWhere((p) => _same(p.address, m.address), orElse: () => Person(address: m.address));
        }
      }
    }
  }

  static bool _same(String a, String b) {
    String d(String s) {
      final x = s.replaceAll(RegExp(r'[^0-9]'), '');
      return x.length > 10 ? x.substring(x.length - 10) : x;
    }
    return d(a).isNotEmpty ? d(a) == d(b) : a == b;
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if ((body.isEmpty && _attachments.isEmpty) || _sending) return;
    final to = _people.map((p) => p.address).toList();
    if (to.isEmpty) return;
    setState(() => _sending = true);
    HapticFeedback.lightImpact();
    final files = List<String>.of(_attachments);
    _text.clear();
    _attachments.clear();
    try {
      await Sms.instance.send(to, body, attachments: files);
    } catch (e) {
      if (mounted) {
        _text.text = body;
        toast(context, 'Couldn\'t send: $e', tone: GlacierToastTone.danger);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _load();
    }
  }

  Future<void> _attach() async {
    final uris = await Sms.instance.pickImages();
    if (uris.isNotEmpty && mounted) setState(() => _attachments.addAll(uris.take(5 - _attachments.length)));
  }

  void _messageMenu(Message m) {
    showChoices(context, title: m.body.isEmpty ? null : (m.body.length > 80 ? '${m.body.substring(0, 80)}…' : m.body), choices: [
      if (m.body.isNotEmpty)
        Choice('Copy text', Lucide.copy, () {
          Clipboard.setData(ClipboardData(text: m.body));
          toast(context, 'Copied');
        }),
      if (m.state == 'failed') Choice('Send again', Lucide.rotateCcw, () => _retry(m)),
      Choice('Delete message', Lucide.trash2, () async {
        await Sms.instance.deleteMessage(m);
        _load();
      }, danger: true),
    ]);
  }

  Future<void> _retry(Message m) async {
    await Sms.instance.deleteMessage(m);
    try {
      await Sms.instance.send(_people.map((p) => p.address).toList(), m.body);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send: $e', tone: GlacierToastTone.danger);
    }
    _load();
  }

  void _showPeople() {
    showChoices(context, title: _group ? '${_people.length} people' : null, choices: [
      for (final p in _people)
        Choice(p.name != null ? '${p.name}  ·  ${p.address}' : p.address, Lucide.phone, () => const MethodChannel('ghost_messaging/sms').invokeMethod('dial', {'address': p.address})),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = _people.isEmpty ? '' : (_group ? _people.map((p) => p.label.split(' ').first).join(', ') : _people.first.label);
    final subtitle = _group ? '${_people.length} people' : (_people.isNotEmpty && _people.first.name != null ? _people.first.address : null);

    return GhostPage(
      title: title,
      titleWidget: GlacierPressable(
        onPressed: _showPeople,
        builder: (context, state) => Row(children: [
          Avatar(people: _people, size: t.lenOf('2.1rem')),
          SizedBox(width: t.space(2)),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold')),
              if (subtitle != null) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            ]),
          ),
        ]),
      ),
      actions: [
        if (!_group && _people.isNotEmpty)
          IconTap(icon: Lucide.phone, label: 'Call', onPressed: () => const MethodChannel('ghost_messaging/sms').invokeMethod('dial', {'address': _people.first.address})),
      ],
      body: _messages == null ? const SizedBox.shrink() : _list(t),
      footer: _composer(t),
    );
  }

  Widget _list(Tokens t) {
    final msgs = _messages!;
    // Newest first, drawn bottom up.
    final items = <Widget>[];
    String? lastOutgoingKey;
    for (final m in msgs) {
      if (m.outgoing) { lastOutgoingKey = m.key; break; }
    }
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final newer = i > 0 ? msgs[i - 1] : null;
      final older = i < msgs.length - 1 ? msgs[i + 1] : null;
      bool joins(Message? a, Message b) => a != null && a.outgoing == b.outgoing && a.address == b.address && a.date.difference(b.date).inMinutes.abs() < 3;
      final firstOfRun = !joins(older, m) || !_sameDay(older!.date, m.date);
      final lastOfRun = !joins(newer, m) || !_sameDay(newer!.date, m.date);
      final failed = m.state == 'failed';
      final showStatus = m.outgoing && (m.key == lastOutgoingKey || failed || m.state == 'sending');
      items.add(_Bubble(
        message: m,
        sender: _group && !m.outgoing && firstOfRun ? (_senders[m.address]?.label ?? m.address) : null,
        senderPerson: _group && !m.outgoing ? _senders[m.address] : null,
        showFace: _group && !m.outgoing && lastOfRun,
        group: _group,
        top: firstOfRun,
        bottom: lastOfRun,
        status: showStatus ? _statusText(m) : (lastOfRun && !m.outgoing ? clock(m.date) : null),
        onLongPress: () => _messageMenu(m),
        onTapFailed: failed ? () => _retry(m) : null,
      ));
      if (older == null || !_sameDay(older.date, m.date)) items.add(_DayHeading(date: m.date));
    }
    if (msgs.isEmpty) {
      items.add(Padding(
        padding: EdgeInsets.all(t.space(8)),
        child: Text('Say hello.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
      ));
    }
    return ListView(
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(2)),
      children: items,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _statusText(Message m) => switch (m.state) {
        'sending' => 'Sending…',
        'failed' => 'Not sent. Tap to try again.',
        'delivered' => 'Delivered · ${clock(m.date)}',
        _ => 'Sent · ${clock(m.date)}',
      };

  Widget _composer(Tokens t) {
    final canSend = (_text.text.trim().isNotEmpty || _attachments.isNotEmpty) && !_sending;
    final len = _text.text.length;
    final isMms = _group || _attachments.isNotEmpty;
    // An SMS is 160 GSM characters (70 with an emoji or other Unicode), and 153 / 67 a part once it is split.
    final unicode = _text.text.runes.any((r) => r > 0x7F);
    final per = unicode ? 67 : 153;
    final single = unicode ? 70 : 160;
    final parts = len <= single ? 1 : (len / per).ceil();
    return DecoratedBox(
      decoration: BoxDecoration(color: t.color('glacier-bg'), border: Border(top: BorderSide(color: t.color('app-rule')))),
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(2), t.space(2)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_attachments.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: t.space(2), bottom: t.space(2)),
              child: SizedBox(
                height: 72,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final a in _attachments)
                    Padding(
                      padding: EdgeInsets.only(right: t.space(2)),
                      child: Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(t.radius('md')),
                          child: FutureBuilder<Uint8List?>(
                            future: Sms.instance.photo(a),
                            builder: (context, s) => s.data == null
                                ? Container(width: 72, height: 72, color: t.color('app-paper-2'))
                                : Image.memory(s.data!, width: 72, height: 72, fit: BoxFit.cover, cacheWidth: 216),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: GlacierPressable(
                            onPressed: () => setState(() => _attachments.remove(a)),
                            semanticLabel: 'Remove picture',
                            builder: (context, state) => Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xB3000000)),
                              alignment: Alignment.center,
                              child: const AppIcon(Lucide.x, size: 14, color: Color(0xFFFFFFFF), wash: false),
                            ),
                          ),
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconTap(icon: Lucide.imagePlus, label: 'Add a picture', onPressed: _attachments.length >= 5 ? null : _attach),
            SizedBox(width: t.space(1)),
            Expanded(
              child: Container(
                constraints: BoxConstraints(minHeight: t.lenOf('2.75rem')),
                padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
                decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.lenOf('1.375rem'))),
                alignment: Alignment.centerLeft,
                child: Stack(children: [
                  if (_text.text.isEmpty)
                    IgnorePointer(child: Text(isMms ? 'Picture message' : 'Text message', style: pageText(t, t.fontSize('md'), color: t.color('app-ink-3')))),
                  EditableText(
                    controller: _text,
                    focusNode: _focus,
                    style: pageText(t, t.fontSize('md'), color: t.color('app-ink')),
                    cursorColor: t.color('app-ink'),
                    backgroundCursorColor: t.color('app-ink-3'),
                    selectionColor: t.colorOf('color-mix(in srgb, #4f5bd5 30%, transparent)'),
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    selectionControls: emptyTextSelectionControls,
                    contextMenuBuilder: (context, state) => _contextMenu(context, state),
                  ),
                ]),
              ),
            ),
            SizedBox(width: t.space(1)),
            IconTap(icon: Lucide.send, label: 'Send', filled: true, size: 18, onPressed: canSend ? _send : null),
          ]),
          if (!isMms && parts > 1)
            Padding(
              padding: EdgeInsets.only(top: t.space(1), right: t.space(3)),
              child: Text('$len · $parts texts', textAlign: TextAlign.end, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            ),
        ]),
      ),
    );
  }

  Widget _contextMenu(BuildContext context, EditableTextState state) {
    final t = context.tokens;
    final items = state.contextMenuButtonItems;
    return Stack(children: [
      Positioned(
        left: (state.contextMenuAnchors.primaryAnchor.dx - 120).clamp(8.0, MediaQuery.sizeOf(context).width - 248),
        top: (state.contextMenuAnchors.primaryAnchor.dy - 56).clamp(8.0, double.infinity),
        child: Container(
          padding: EdgeInsets.all(t.space(1)),
          decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('md'))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final item in items)
              GlacierPressable(
                onPressed: item.onPressed,
                builder: (context, s) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                  child: Text(_label(item.type, item.label), style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-paper'))),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }

  static String _label(ContextMenuButtonType type, String? label) => label ?? switch (type) {
        ContextMenuButtonType.cut => 'Cut',
        ContextMenuButtonType.copy => 'Copy',
        ContextMenuButtonType.paste => 'Paste',
        ContextMenuButtonType.selectAll => 'Select all',
        _ => '…',
      };
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(top: t.space(4), bottom: t.space(2)),
      child: Text(dayHeading(date), textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'))),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.top,
    required this.bottom,
    required this.group,
    required this.onLongPress,
    this.sender,
    this.senderPerson,
    this.showFace = false,
    this.status,
    this.onTapFailed,
  });

  final Message message;
  final bool top;
  final bool bottom;
  final bool group;
  final String? sender;
  final Person? senderPerson;
  final bool showFace;
  final String? status;
  final VoidCallback onLongPress;
  final VoidCallback? onTapFailed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = message;
    final out = m.outgoing;
    final failed = m.state == 'failed';
    final big = t.lenOf('1.15rem');
    final small = t.lenOf('0.3rem');
    final radius = BorderRadius.only(
      topLeft: Radius.circular(!out && !top ? small : big),
      bottomLeft: Radius.circular(!out && !bottom ? small : big),
      topRight: Radius.circular(out && !top ? small : big),
      bottomRight: Radius.circular(out && !bottom ? small : big),
    );
    final ground = out ? (failed ? t.colorOf('color-mix(in srgb, #dd3a30 18%, var(--app-paper-2))') : t.color('app-ink')) : t.color(t.isDark ? 'app-paper-3' : 'app-paper-2');
    final ink = out && !failed ? t.color('app-paper') : t.color('app-ink');
    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;
    final faceSize = t.lenOf('1.75rem');

    final content = <Widget>[
      for (final a in m.attachments)
        if (a.isImage)
          Padding(
            padding: EdgeInsets.only(bottom: m.body.isEmpty ? 0 : t.space(1)),
            child: _Picture(id: a.id, radius: radius, maxWidth: maxWidth),
          )
        else
          _Pill(text: a.name ?? a.type, ground: ground, ink: ink),
      if (m.state == 'pending_download') _Pill(text: 'Picture message not downloaded yet', ground: ground, ink: ink),
      if (m.body.isNotEmpty)
        Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: EdgeInsets.symmetric(horizontal: t.space(3) + 2, vertical: t.space(2)),
          decoration: BoxDecoration(color: ground, borderRadius: radius),
          child: Text.rich(
            _linked(m.body, ink),
            style: pageText(t, t.fontSize('md'), color: ink, height: 1.35),
          ),
        ),
    ];

    Widget bubble = Column(crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: content);
    bubble = GestureDetector(onLongPress: onLongPress, onTap: onTapFailed, child: bubble);

    return Padding(
      padding: EdgeInsets.only(top: top ? t.space(2) : 2),
      child: Column(
        crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (sender != null)
            Padding(
              padding: EdgeInsets.only(left: (group ? faceSize + t.space(2) : 0) + t.space(3), bottom: 2),
              child: Text(sender!, style: pageText(t, t.fontSize('xs'), weight: 'medium', color: t.color('app-ink-3'))),
            ),
          Row(
            mainAxisAlignment: out ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (group && !out) ...[
                SizedBox(width: faceSize, child: showFace && senderPerson != null ? Avatar(people: [senderPerson!], size: faceSize) : null),
                SizedBox(width: t.space(2)),
              ],
              Flexible(child: bubble),
            ],
          ),
          if (status != null)
            Padding(
              padding: EdgeInsets.only(top: 3, left: (group && !out ? faceSize + t.space(2) : 0) + t.space(2), right: t.space(2)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (failed) ...[AppIcon(Lucide.circleAlert, size: 12, color: t.colorOf('#dd3a30')), const SizedBox(width: 4)],
                Text(status!, style: pageText(t, t.fontSize('xs'), color: failed ? t.colorOf('#dd3a30') : t.color('app-ink-3'))),
              ]),
            ),
        ],
      ),
    );
  }

  /// Links underlined (they are tappable through the long press's Copy; a browser opening is for a later version).
  TextSpan _linked(String text, Color ink) {
    final re = RegExp(r'(https?://[^\s]+|www\.[^\s]+)');
    final spans = <TextSpan>[];
    var at = 0;
    for (final match in re.allMatches(text)) {
      if (match.start > at) spans.add(TextSpan(text: text.substring(at, match.start)));
      spans.add(TextSpan(text: match.group(0), style: TextStyle(decoration: TextDecoration.underline, decorationColor: ink)));
      at = match.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(children: spans);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.ground, required this.ink});
  final String text;
  final Color ground;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: EdgeInsets.only(bottom: t.space(1)),
      padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
      decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(t.lenOf('1rem'))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(Lucide.fileCode, size: 14, color: ink),
        SizedBox(width: t.space(1)),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: ink))),
      ]),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({required this.id, required this.radius, required this.maxWidth});
  final int id;
  final BorderRadius radius;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return FutureBuilder<Uint8List?>(
      future: Sms.instance.part(id),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Container(width: maxWidth * 0.7, height: maxWidth * 0.7, decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: radius));
        }
        return GestureDetector(
          onTap: () => Navigator.of(context).push(PageRouteBuilder<void>(
            opaque: false,
            barrierColor: const Color(0xF2000000),
            pageBuilder: (context, _, _) => _Viewer(bytes: bytes),
            transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
          )),
          child: ClipRRect(
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxWidth * 1.3),
              child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: (maxWidth * MediaQuery.devicePixelRatioOf(context)).round(), gaplessPlayback: true),
            ),
          ),
        );
      },
    );
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Stack(children: [
        Positioned.fill(child: InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(bytes)))),
        Positioned(
          top: pad.top + 8,
          right: 8,
          child: IconTap(icon: Lucide.x, label: 'Close', color: const Color(0xFFFFFFFF), onPressed: () => Navigator.of(context).pop()),
        ),
      ]),
    );
  }
}
