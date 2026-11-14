import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../app_state.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../backgrounds.dart';
import '../effects.dart';
import '../edits.dart';
import '../kit/settings_type.dart';
import '../reactions.dart';
import '../sms.dart';
import '../stickers.dart';
import 'chat_settings.dart';
import 'common.dart';
import 'encryption.dart';
import 'message_popover.dart';
import 'sticker_picker.dart';
import 'video.dart';
import 'voice.dart';

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

  /// The message field itself, to ask it for the keyboard. A tap on a field that already has the cursor where it was
  /// tapped changes nothing, so Flutter asks for no keyboard: after leaving the app and coming back, or after the
  /// keyboard was put away, the field kept its cursor and no tap would bring the keys back (Matt, 2026-11-13:
  /// "the keyboard disappears but the input stays selected so there is no way to re open the keyboard").
  final _field = GlobalKey<EditableTextState>();
  Offset? _fieldDown;
  final List<String> _attachments = [];
  bool _sending = false;

  /// A voice message is being recorded (lib/ui/voice.dart): the most seconds it may run. Null when none is.
  int? _recordingLimit;
  StreamSubscription<void>? _voiceStopped;

  /// What [_messages] draws as: reaction texts folded onto their messages, your corrections onto your edits.
  Folded _folded = const Folded(messages: [], reactions: {});
  Set<String> _corrected = const {};

  /// The message being edited in the composer, and what the composer held before.
  Message? _editing;
  String _draftBeforeEdit = '';

  /// The layer effects play on, and the newest message seen, so only one that arrives while this is open plays.
  final _effects = GlobalKey<EffectLayerState>();
  String? _newestKey;

  /// The message that just came or went, whose bubble effect plays as it is drawn; and the invisible-ink
  /// messages tapped open.
  String? _freshKey;
  final Set<String> _revealed = {};
  Timer? _draftSave;

  /// The reactions already seen on this conversation's messages, so one that is a screen effect plays once, as it
  /// arrives or is sent, and not again each time the conversation is read.
  final Set<String> _reactionsSeen = {};

  /// Where Ghost Messaging's own encryption stands with the one person here (android/.../E2e.kt); none in a group.
  E2eState _e2e = const E2eState();

  /// Settings › Messages: reaction texts hung on their messages. Read as the page's choices change.
  bool _foldOn = true;

  bool get _group => _people.length > 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Sms.instance.setOpenThread(widget.thread);
    _load(markRead: true);
    _loadMms();
    if (_people.isEmpty) {
      Sms.instance.people(widget.thread).then((p) {
        if (!mounted) return;
        setState(() => _people = p);
        _loadE2e();
      });
    }
    _changes = Sms.instance.changes.stream.listen((t) {
      if (t == widget.thread || t < 0) _load(markRead: true);
    });
    _text.addListener(() {
      // The composer draws itself again as the words change (it listens to them): the messages above are not
      // redrawn for a keystroke.
      // What is typed and not sent is kept for this conversation, a moment after the typing stops.
      if (_editing != null) return;
      _draftSave?.cancel();
      _draftSave = Timer(const Duration(milliseconds: 500), () => Sms.instance.setDraft(widget.thread, _text.text));
    });
    if (widget.draft == null) {
      Sms.instance.draft(widget.thread).then((d) {
        if (mounted && d != null && d.isNotEmpty && _text.text.isEmpty) _text.text = d;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Sms.instance.setOpenThread(null);
    _changes?.cancel();
    _voiceStopped?.cancel();
    _draftSave?.cancel();
    // Leaving the conversation: a recording under way is thrown away, and whatever is playing stops.
    if (_recordingLimit != null) Sms.instance.cancelVoice().catchError((_) {});
    if (!Sms.remote) Sms.instance.stopVoice().catchError((_) {});
    if (_editing == null) Sms.instance.setDraft(widget.thread, _text.text);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Sms.instance.setOpenThread(widget.thread);
      _load(markRead: true);
      _loadMms();
      // Back in the app with the cursor still in the field: the keys come back with it.
      if (_focus.hasFocus) WidgetsBinding.instance.addPostFrameCallback((_) => _field.currentState?.requestKeyboard());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fold = AppState.of(context).foldReactions;
    if (fold == _foldOn) return;
    _foldOn = fold;
    if (_messages != null) _load();
  }

  /// Where encryption stands with the one person here: asked again each time the conversation changes, since a key
  /// arriving is a text like any other.
  Future<void> _loadE2e() async {
    if (_group || _people.isEmpty) return;
    try {
      final s = await Sms.instance.e2e(_people.first.address);
      if (mounted) setState(() => _e2e = s);
    } catch (_) {}
  }

  void _e2eChanged() {
    _loadE2e();
    _load();
  }

  /// The banner's Turn on: this phone's key goes to them, and encryption starts when they accept.
  Future<void> _e2eStart() async {
    final person = _people.first;
    try {
      await Sms.instance.e2eOffer(person.address);
      if (mounted) toast(context, 'Key sent. Encryption starts when ${person.label} accepts.');
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send the key: $e', tone: GlacierToastTone.danger);
    }
    _e2eChanged();
  }

  /// Their key is here and yours goes back: encryption is on from this text.
  Future<void> _e2eAccept() async {
    final person = _people.first;
    try {
      await Sms.instance.e2eOffer(person.address);
      if (mounted) toast(context, 'Encryption is on with ${person.label}');
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send the key: $e', tone: GlacierToastTone.danger);
    }
    _e2eChanged();
  }

  /// Whether picture messages can go from this phone (mobile data on, the carrier allowing them), asked as the
  /// conversation opens and again whenever the app comes back to the front.
  MmsStatus? _mms;

  Future<void> _loadMms() async {
    try {
      final s = await Sms.instance.mmsStatus();
      if (mounted) setState(() => _mms = s);
    } catch (_) {}
  }

  /// How many of the newest messages are held. A conversation opens on its newest [_opening], which is several
  /// screens of them, and takes [_step] more each time the reader nears the oldest held (Matt, 2026-11-13: "load by
  /// most recent first so that things are faster"). Before this it held the newest 300 and no way to the rest.
  int _limit = _opening;
  static const _opening = 120;
  static const _step = 300;

  /// There are older messages than the ones held, and whether they are being read.
  bool _older = false;
  bool _readingOlder = false;

  Future<void> _readOlder() async {
    if (_readingOlder || !_older) return;
    _readingOlder = true;
    _limit += _step;
    try {
      await _load();
    } finally {
      // Let go once the longer list is laid out: until then the reader still looks to be at its old top, and
      // would be read for again at once.
      WidgetsBinding.instance.addPostFrameCallback((_) => _readingOlder = false);
    }
  }

  Future<void> _load({bool markRead = false}) async {
    _loadE2e();
    final asked = _limit;
    final list = await Sms.instance.messages(widget.thread, limit: asked);
    if (!mounted) return;
    final edits = foldCorrections(list);
    setState(() {
      _messages = list;
      // As many as were asked for: there may be more behind them.
      _older = list.length >= asked;
      _folded = _foldOn ? foldReactions(edits.messages) : Folded(messages: edits.messages, reactions: const {});
      _corrected = edits.corrected;
    });
    _playReactions();
    // A message that came or went while the conversation is open sets off its effect, once.
    final newest = _folded.messages.isEmpty ? null : _folded.messages.first;
    if (newest != null && _newestKey != null && newest.key != _newestKey && newest.state != 'failed') _playFor(newest);
    _newestKey = newest?.key ?? '';
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
    _draftSave?.cancel();
    Sms.instance.setDraft(widget.thread, '');
    try {
      await Sms.instance.send(to, body, attachments: files);
    } catch (e) {
      if (mounted) {
        // What was to be sent is put back, pictures too: nothing went.
        _text.text = body;
        setState(() => _attachments.addAll(files));
        toast(context, 'Couldn\'t send: ${_said(e)}', tone: GlacierToastTone.danger);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _load();
    }
  }

  /// The stickers' sheet; the one tapped is sent straight away, as a picture message.
  Future<void> _sticker() async {
    final to = _people.map((p) => p.address).toList();
    if (to.isEmpty || _sending) return;
    final asset = await pickSticker(context, encrypted: _e2e.on);
    if (asset == null || !mounted) return;
    setState(() => _sending = true);
    HapticFeedback.lightImpact();
    try {
      final data = await rootBundle.load(asset);
      await Sms.instance.sendSticker(to, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), stickerName(asset));
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send the sticker: $e', tone: GlacierToastTone.danger);
    } finally {
      if (mounted) setState(() => _sending = false);
      _load();
    }
  }

  /// The microphone: starts recording a voice message, asking Android for the microphone the first time
  /// (Matt, 2026-11-13: "I also want to have the ability to send audio messages").
  Future<void> _record() async {
    if (_sending || _recordingLimit != null) return;
    try {
      final limit = await Sms.instance.startVoice();
      if (!mounted) {
        if (limit != null) Sms.instance.cancelVoice().catchError((_) {});
        return;
      }
      if (limit == null) {
        toast(context, 'Allow the microphone for Ghost Messaging in Android\'s settings to record a voice message.', tone: GlacierToastTone.danger);
        return;
      }
      HapticFeedback.lightImpact();
      // The phone throws the recording away if the app leaves the screen: the microphone is never left open.
      _voiceStopped ??= Sms.instance.voiceStopped.stream.listen((_) {
        if (!mounted || _recordingLimit == null) return;
        setState(() => _recordingLimit = null);
        toast(context, 'The recording was thrown away when you left Ghost Messaging.');
      });
      setState(() => _recordingLimit = limit);
    } catch (e) {
      if (mounted) toast(context, voiceProblem(e), tone: GlacierToastTone.danger);
    }
  }

  void _discardVoice() {
    Sms.instance.cancelVoice().catchError((_) {});
    setState(() => _recordingLimit = null);
  }

  /// Ends the recording and sends it: a picture message with the sound in it, which any phone can play.
  Future<void> _sendVoice() async {
    final to = _people.map((p) => p.address).toList();
    if (to.isEmpty || _sending) return _discardVoice();
    setState(() {
      _recordingLimit = null;
      _sending = true;
    });
    HapticFeedback.lightImpact();
    try {
      await Sms.instance.sendVoice(to);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send the voice message: ${voiceProblem(e)}', tone: GlacierToastTone.danger);
    } finally {
      if (mounted) setState(() => _sending = false);
      _load();
    }
  }

  Future<void> _attach() async {
    final uris = await Sms.instance.pickImages();
    if (uris.isNotEmpty && mounted) setState(() => _attachments.addAll(uris.take(5 - _attachments.length)));
  }

  /// A reaction that is a screen effect (a balloon, fireworks: lib/effects.dart) plays over the conversation when it
  /// has just come or gone. Only a new one, and only a recent one: reading further back finds old ones, which stay
  /// chips.
  void _playReactions() {
    ({ScreenEffect effect, String text})? fresh;
    final now = DateTime.now();
    for (final entry in _folded.reactions.entries) {
      for (final r in entry.value) {
        if (!_reactionsSeen.add('${entry.key}|${r.by}|${r.emoji}')) continue;
        final effect = effectForReaction(r.emoji);
        if (effect == null || now.difference(r.date).abs() > const Duration(seconds: 45)) continue;
        final on = _folded.messages.where((m) => m.key == entry.key).firstOrNull;
        fresh = (effect: effect, text: on == null ? '' : sentWith(on.body).text);
      }
    }
    if (fresh != null && mounted && AppState.of(context).effects) _effects.currentState?.play(fresh.effect, text: fresh.text);
  }

  /// Reacts to [m] with [effect]: its emoji goes as a reaction, and the effect plays here as it goes.
  Future<void> _reactWith(Message m, ScreenEffect effect) => _react(m, effectReactionEmoji[effect]!);

  void _playFor(Message m) {
    if (!AppState.of(context).effects) return;
    _freshKey = m.key;
    final effect = effectFor(m.body);
    if (effect != null) _effects.currentState?.play(effect, text: sentWith(m.body).text);
  }

  /// Sends [emoji] as your reaction to [m], or takes it off if it is already yours: a text the other phone turns
  /// back into a reaction (lib/reactions.dart).
  Future<void> _react(Message m, String emoji) async {
    final mine = (_folded.reactions[m.key] ?? const <Reaction>[]).any((r) => r.by.isEmpty && r.emoji == emoji);
    HapticFeedback.lightImpact();
    try {
      await Sms.instance.send(_people.map((p) => p.address).toList(), reactionText(emoji, m, removed: mine));
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send the reaction: $e', tone: GlacierToastTone.danger);
    }
    _load();
  }

  bool _canEdit(Message m) => m.outgoing && m.body.isNotEmpty && m.state != 'sending' && m.state != 'pending_download' && m.state != 'downloading';

  void _startEdit(Message m) {
    setState(() {
      if (_editing == null) _draftBeforeEdit = _text.text;
      _editing = m;
      _text.text = m.body;
      _text.selection = TextSelection.collapsed(offset: m.body.length);
    });
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editing = null;
      _text.text = _draftBeforeEdit;
      _draftBeforeEdit = '';
    });
  }

  /// A failed message is simply sent again with its new words. A sent one is changed on this phone, and the new
  /// words go to the other people as a follow-up text if you choose: SMS can't change what they already have.
  Future<void> _saveEdit() async {
    final m = _editing;
    if (m == null) return;
    final body = _text.text.trim();
    if (body.isEmpty || body == m.body.trim()) {
      _cancelEdit();
      return;
    }
    if (m.state == 'failed') {
      _cancelEdit();
      await _retry(m, body: body);
      return;
    }
    FocusScope.of(context).unfocus();
    await showChoices(context, title: 'Texts can\'t be changed on the other person\'s phone. Send them the change?', choices: [
      Choice('Send correction', Lucide.send, () => _applyEdit(m, body, send: true)),
      Choice('Change on this phone only', Lucide.pencil, () => _applyEdit(m, body, send: false)),
    ]);
  }

  Future<void> _applyEdit(Message m, String body, {required bool send}) async {
    _cancelEdit();
    try {
      await Sms.instance.editMessage(m, body);
      if (send) await Sms.instance.send(_people.map((p) => p.address).toList(), correctionText(body));
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t edit: $e', tone: GlacierToastTone.danger);
    }
    _load();
  }

  void _showOriginal(Message m) {
    showChoices(context, title: 'First sent as:\n${m.original ?? ''}', choices: [
      Choice('Copy original', Lucide.copy, () {
        Clipboard.setData(ClipboardData(text: m.original ?? ''));
        toast(context, 'Copied');
      }),
    ]);
  }

  void _showReactions(List<Reaction> list) {
    String who(String by) {
      if (by.isEmpty) return 'You';
      final p = _senders[by] ?? _people.where((p) => _same(p.address, by)).firstOrNull;
      return p?.label ?? by;
    }
    showChoices(context, title: 'Reactions', choices: [
      for (final r in list.reversed) Choice('${r.emoji}   ${who(r.by)}', Lucide.userRound, () {}),
    ]);
  }

  /// A long press on a message. [at] is where its bubble is on the screen: the reactions, the screen effects and
  /// what else can be done come up beside it (lib/ui/message_popover.dart). A line that is no bubble (a key, a
  /// background) has the sheet from the foot of the screen.
  void _messageMenu(Message m, [Rect? at]) {
    final canReact = m.state != 'sending' && m.state != 'waiting' && m.state != 'failed' && m.state != 'pending_download' && m.state != 'downloading' && m.notice == null;
    final mine = {for (final r in _folded.reactions[m.key] ?? const <Reaction>[]) if (r.by.isEmpty) r.emoji};
    final choices = [
      if (m.body.isNotEmpty)
        Choice('Copy text', Lucide.copy, () {
          Clipboard.setData(ClipboardData(text: m.body));
          toast(context, 'Copied');
        }),
      if (_canEdit(m) && !Sms.remote) Choice(m.state == 'failed' ? 'Edit and send again' : 'Edit', Lucide.pencil, () => _startEdit(m)),
      if (m.edited && m.original != null) Choice('Show original', Lucide.clock, () => _showOriginal(m)),
      if (m.state == 'failed' && !Sms.remote) Choice('Send again', Lucide.rotateCcw, () => _retry(m)),
      if (effectFor(m.body) != null) Choice('Play effect', Lucide.sparkles, () => _effects.currentState?.play(effectFor(m.body)!, text: sentWith(m.body).text)),
      if (!Sms.remote)
        Choice('Delete message', Lucide.trash2, () async {
          await Sms.instance.deleteMessage(m);
          _load();
        }, danger: true),
    ];
    if (at == null) {
      showChoices(
        context,
        title: m.body.isEmpty ? null : (m.body.length > 80 ? '${m.body.substring(0, 80)}…' : m.body),
        header: canReact ? _ReactionRow(mine: mine, onPick: (emoji) { Navigator.of(context).pop(); _react(m, emoji); }) : null,
        choices: choices,
      );
      return;
    }
    HapticFeedback.mediumImpact();
    showMessagePopover(
      context,
      bubble: at,
      outgoing: m.outgoing,
      reactions: canReact ? reactionChoices : const [],
      mine: mine,
      onReact: (emoji) => _react(m, emoji),
      // The screen effects, where they are switched on (Settings › Effects).
      effects: canReact && AppState.of(context).effects ? ScreenEffect.values : const [],
      onEffect: (effect) => _reactWith(m, effect),
      choices: choices,
    );
  }

  Future<void> _retry(Message m, {String? body}) async {
    try {
      if (m.kind == 'mms') {
        // A picture message goes again with its own pictures, read back from Android's store. Sending its words
        // alone, as this did, lost the picture of every picture message that was tried again.
        await Sms.instance.resendMms(m.id, body: body);
      } else {
        await Sms.instance.deleteMessage(m);
        await Sms.instance.send(_people.map((p) => p.address).toList(), body ?? m.body);
      }
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send: ${_said(e)}', tone: GlacierToastTone.danger);
    }
    _load();
  }

  /// What went wrong, as the phone put it, without the wrapping a channel's error comes in.
  static String _said(Object e) => e is PlatformException ? (e.message ?? e.code) : '$e';

  /// The conversation's own settings (lib/ui/chat_settings.dart): its people, its background and bubbles, its
  /// encryption, whether it is muted or pinned. From the cog at the top, and from a tap on the name.
  Future<void> _openSettings() async {
    await push<void>(context, (_) => ChatSettingsScreen(thread: widget.thread, people: _people));
    _e2eChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final background = ChatBackground.of(AppState.of(context), widget.thread);
    final title = _people.isEmpty ? '' : (_group ? _people.map((p) => p.label.split(' ').first).join(', ') : _people.first.label);
    final subtitle = _group
        ? '${_people.length} people'
        : _e2e.on
            ? (_e2e.verified ? 'Encrypted · verified' : 'Encrypted')
            : (_people.isNotEmpty && _people.first.name != null ? _people.first.address : null);

    // On a computer (Sms.remote) the conversation fills a pane beside the list: there is no way back to draw, and
    // what only the phone can do (call, the conversation's own settings, pictures, stickers, editing, deleting,
    // turning encryption on) is not offered.
    final remote = Sms.remote;
    return GhostPage(
      title: title,
      back: !remote,
      titleWidget: GlacierPressable(
        onPressed: remote ? null : _openSettings,
        builder: (context, state) => Row(children: [
          Avatar(people: _people, size: t.lenOf('2.1rem')),
          SizedBox(width: t.space(2)),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold')),
              if (subtitle != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_e2e.on && !_group) ...[AppIcon(Lucide.lock, size: 11, strokeWidth: 2.4, wash: false, color: t.color('app-ink-3')), const SizedBox(width: 3)],
                  Flexible(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3')))),
                ]),
            ]),
          ),
        ]),
      ),
      actions: [
        if (!remote && !_group && _people.isNotEmpty)
          IconTap(icon: Lucide.phone, label: 'Call', onPressed: () => const MethodChannel('ghost_messaging/sms').invokeMethod('dial', {'address': _people.first.address})),
        // Each conversation's own settings: its background, your bubbles in it, its encryption, mute and pin.
        if (!remote) IconTap(icon: Lucide.settings, label: 'Conversation settings', onPressed: _openSettings),
      ],
      body: Stack(children: [
        if (!background.isNone) Positioned.fill(child: ChatBackgroundLayer(background: background)),
        Positioned.fill(child: _messages == null ? const Center(child: GhostSpinner(size: 26, label: 'Loading messages…')) : _list(t, background)),
        Positioned.fill(child: EffectLayer(key: _effects, style: pageText(t, 26, color: t.color('app-ink')))),
      ]),
      footer: ListenableBuilder(listenable: _text, builder: (context, _) => _composer(t)),
    );
  }

  Widget _list(Tokens t, ChatBackground background) {
    final msgs = _folded.messages;
    final busy = background.busy;
    // Newest first, drawn bottom up.
    final items = <Widget>[];
    String? lastOutgoingKey;
    for (final m in msgs) {
      if (m.outgoing && !_isLine(m)) { lastOutgoingKey = m.key; break; }
    }
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final newer = i > 0 ? msgs[i - 1] : null;
      final older = i < msgs.length - 1 ? msgs[i + 1] : null;
      bool joins(Message? a, Message b) => a != null && !_isLine(a) && a.outgoing == b.outgoing && a.address == b.address && a.date.difference(b.date).inMinutes.abs() < 3;
      if (_isLine(m)) {
        // A text that carried an encryption key, or a chat background: a line saying so, where its letters would
        // have been a bubble.
        final who = m.outgoing ? 'You' : (_senders[m.address]?.label ?? (_people.length == 1 ? _people.first.label : (m.address.isEmpty ? 'They' : m.address)));
        items.add(_Notice(
          icon: m.notice == 'key' ? Lucide.keyRound : Lucide.image,
          text: m.notice == 'key' ? (m.outgoing ? 'You sent your encryption key' : '$who sent an encryption key') : '$who changed the chat background',
          busy: busy,
          onLongPress: () => _messageMenu(m),
        ));
        if (older == null || !_sameDay(older.date, m.date)) items.add(_DayHeading(date: m.date, busy: busy));
        continue;
      }
      final firstOfRun = !joins(older, m) || !_sameDay(older!.date, m.date);
      final lastOfRun = !joins(newer, m) || !_sameDay(newer!.date, m.date);
      final failed = m.state == 'failed';
      final showStatus = m.outgoing && (m.key == lastOutgoingKey || failed || m.state == 'sending' || m.state == 'waiting');
      items.add(_Bubble(
        message: m,
        sender: _group && !m.outgoing && firstOfRun ? (_senders[m.address]?.label ?? m.address) : null,
        senderPerson: _group && !m.outgoing ? _senders[m.address] : null,
        showFace: _group && !m.outgoing && lastOfRun,
        group: _group,
        top: firstOfRun,
        bottom: lastOfRun,
        status: showStatus ? _statusText(m) : (lastOfRun ? clock(m.date) : null),
        onLongPress: (at) => _messageMenu(m, at),
        // A picture that could not be brought down: asked for again from here (the phone's to do, not a computer's).
        onRetryDownload: m.state == 'pending_download' && !Sms.remote
            ? () async {
                try {
                  await Sms.instance.retryDownload(m);
                } catch (e) {
                  if (mounted) toast(context, 'Couldn\'t try again: $e', tone: GlacierToastTone.danger);
                }
                _load();
              }
            : null,
        onTapFailed: failed && !Sms.remote ? () => _retry(m) : null,
        reactions: _folded.reactions[m.key] ?? const [],
        onReactionsTap: () => _showReactions(_folded.reactions[m.key] ?? const []),
        edited: m.edited ? (_corrected.contains(m.key) ? 'Edited · correction sent' : 'Edited') : null,
        onEditedTap: m.edited ? () => _showOriginal(m) : null,
        highlighted: _editing?.key == m.key,
        playEntrance: _freshKey == m.key && AppState.of(context).effects,
        concealed: !_revealed.contains(m.key),
        onReveal: () => setState(() => _revealed.add(m.key)),
        onBackground: !background.isNone,
        busy: busy,
        thread: widget.thread,
      ));
      if (older == null || !_sameDay(older.date, m.date)) items.add(_DayHeading(date: m.date, busy: busy));
    }
    if (msgs.isEmpty) {
      items.add(Padding(
        padding: EdgeInsets.all(t.space(8)),
        child: Center(child: OnBackground(busy: busy, child: Text('Say hello.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))))),
      ));
    }
    // Older ones are read as the reader nears the oldest held: said at the top while they come.
    if (_older) {
      items.add(Padding(
        padding: EdgeInsets.symmetric(vertical: t.space(4)),
        child: const Center(child: GhostSpinner(size: 18, label: 'Loading earlier messages…')),
      ));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Drawn bottom up, so what lies after is the older end.
        if (_older && !_readingOlder && n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 900) _readOlder();
        return false;
      },
      child: ListView(
        reverse: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(2)),
        children: items,
      ),
    );
  }

  /// Drawn as a line in the conversation, not a bubble: a text that carried a key or a chat background.
  static bool _isLine(Message m) => m.notice == 'key' || m.notice == 'background';

  static const _evenLeading = TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even);

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// A picture message says why, where the phone was told (Matt: "almost like MMS isn't working"); trying again is
  /// a tap on the phone, and not offered on a computer (lib/desktop).
  String _notSent(Message m) {
    final said = m.why == null || m.why!.isEmpty ? 'Not sent' : 'Not sent: ${m.why}';
    return Sms.remote ? said : '$said. Tap to try again.';
  }

  String _statusText(Message m) => switch (m.state) {
        'sending' => 'Sending…',
        // Typed on a computer while the phone could not be reached: it goes when the phone is back (lib/desktop).
        'waiting' => 'Waiting for your phone',
        'failed' => _notSent(m),
        'read' => 'Read · ${clock(m.date)}',
        'delivered' => 'Delivered · ${clock(m.date)}',
        _ => 'Sent · ${clock(m.date)}',
      };

  Widget _composer(Tokens t) {
    final editing = _editing != null;
    final composerText = pageText(t, t.fontSize('md'), color: t.color('app-ink'), height: 1.3);
    final composerStrut = StrutStyle.fromTextStyle(composerText, forceStrutHeight: true, leadingDistribution: TextLeadingDistribution.even);
    final canSend = editing ? _text.text.trim().isNotEmpty : (_text.text.trim().isNotEmpty || _attachments.isNotEmpty) && !_sending;
    final isMms = _group || _attachments.isNotEmpty;
    // Nothing written and nothing attached: the microphone stands where Send would, to record a voice message.
    final voiceOffered = !Sms.remote && !editing && _people.isNotEmpty && _text.text.isEmpty && _attachments.isEmpty;
    // A sealed text goes as `ghost:e1:` and base64 of its bytes with 28 more (E2eCrypto.seal): longer than what was
    // typed, and plain letters whatever was typed.
    final sealed = _e2e.on && !isMms;
    final len = sealed ? 9 + ((28 + utf8.encode(_text.text.trim()).length) * 4 / 3).ceil() : _text.text.length;
    // An SMS is 160 GSM characters (70 with an emoji or other Unicode), and 153 / 67 a part once it is split.
    final unicode = !sealed && _text.text.runes.any((r) => r > 0x7F);
    final enterSends = AppState.of(context).enterSends;
    final per = unicode ? 67 : 153;
    final single = unicode ? 70 : 160;
    final parts = len <= single ? 1 : (len / per).ceil();
    return DecoratedBox(
      decoration: BoxDecoration(color: t.color('glacier-bg'), border: Border(top: BorderSide(color: t.color('app-rule')))),
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(2), t.space(2)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Both phones have Ghost Messaging and nothing has been exchanged: encryption is offered, until it is
          // turned on or the banner is dismissed (Matt, 2026-11-13: "a banner that can be dismissed asking the user
          // to enable encryption for better security").
          if (!Sms.remote && !_group && _people.isNotEmpty && _e2e.offerable && AppState.of(context).flag('e2e_banner_${widget.thread}'))
            _E2eBar(
              text: '${_people.first.label} has Ghost Messaging too. Encrypt this conversation for better security?',
              action: 'Turn on',
              onAction: _e2eStart,
              onPress: () => showEncryptionChoices(context, _people.first, _e2e, _e2eChanged),
              onDismiss: () => AppState.of(context).setFlag('e2e_banner_${widget.thread}', false),
            ),
          if (!Sms.remote && !_group && _people.isNotEmpty && (_e2e.state == 'pending' || _e2e.state == 'offered'))
            _E2eBar(
              text: switch (_e2e.state) {
                'pending' => _e2e.changed ? '${_people.first.label} sent a NEW encryption key' : '${_people.first.label} wants to encrypt this conversation',
                _ => 'Waiting for ${_people.first.label} to accept encryption',
              },
              // A new key is looked at before it is taken: the sheet says why.
              action: _e2e.state != 'pending' ? null : (_e2e.changed ? 'Review' : 'Turn on'),
              onAction: _e2e.changed ? () => showEncryptionChoices(context, _people.first, _e2e, _e2eChanged) : _e2eAccept,
              onPress: () => showEncryptionChoices(context, _people.first, _e2e, _e2eChanged),
            ),
          // What would stop a picture message going from this phone, said before it is tried.
          if (isMms && !editing && _mms?.obstacle != null)
            Padding(
              padding: EdgeInsets.only(left: t.space(3), right: t.space(3), bottom: t.space(2)),
              child: Text('${_mms!.obstacle}.', style: pageText(t, t.fontSize('xs'), color: t.colorOf('#dd3a30'))),
            ),
          if (_e2e.on && _attachments.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: t.space(3), right: t.space(3), bottom: t.space(2)),
              child: Text('Pictures aren\'t encrypted. This goes as an ordinary picture message.', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            ),
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
          if (editing)
            Padding(
              padding: EdgeInsets.only(left: t.space(3), bottom: t.space(1)),
              child: Row(children: [
                AppIcon(Lucide.pencil, size: 14, color: t.color('app-ink-2')),
                SizedBox(width: t.space(2)),
                Expanded(
                  child: Text(
                    _editing!.state == 'failed' ? 'Edit, then send again' : 'Editing message',
                    style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-2')),
                  ),
                ),
                IconTap(icon: Lucide.x, label: 'Stop editing', size: 16, onPressed: _cancelEdit),
              ]),
            ),
          if (_recordingLimit != null)
            VoiceRecorder(
              limit: _recordingLimit!,
              onDiscard: _discardVoice,
              onSend: _sendVoice,
              note: _e2e.on ? 'Voice messages aren\'t encrypted. This goes as an ordinary message.' : null,
            )
          else
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (!Sms.remote) IconTap(icon: Lucide.plus, label: 'Add an attachment', onPressed: editing || _attachments.length >= 5 ? null : _attach),
            SizedBox(width: t.space(1)),
            Expanded(
              // The field with Send inside it, at its end: a smaller disc that keeps to the bottom as the text grows.
              child: Container(
                constraints: BoxConstraints(minHeight: t.lenOf('2.75rem')),
                padding: EdgeInsets.only(left: t.space(4), right: t.lenOf('0.25rem'), top: t.lenOf('0.25rem'), bottom: t.lenOf('0.25rem')),
                decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.lenOf('1.375rem'))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    // One line of words sits on the middle of the button beside it: the row is as tall as the button
                    // at least, and the words are centred in it, with a line box the same above and below the
                    // letters (the face's own leaves more below, which is what sat the words low).
                    // Any tap on the words' place asks for the keyboard: a Listener, so it hears the tap whatever
                    // else takes it.
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (e) => _fieldDown = e.position,
                      onPointerUp: (e) {
                        final down = _fieldDown;
                        _fieldDown = null;
                        if (down != null && (e.position - down).distance < 18) _field.currentState?.requestKeyboard();
                      },
                      child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: t.lenOf('2.25rem')),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                        padding: EdgeInsets.symmetric(vertical: t.lenOf('0.3rem')),
                      child: Stack(children: [
                        if (_text.text.isEmpty)
                          IgnorePointer(child: Text(isMms ? 'Picture message' : (sealed ? 'Encrypted message' : 'Text message'), style: composerText.copyWith(color: t.color('app-ink-3')), strutStyle: composerStrut, textHeightBehavior: _evenLeading)),
                        EditableText(
                          key: _field,
                          controller: _text,
                          focusNode: _focus,
                          style: composerText,
                          strutStyle: composerStrut,
                          textHeightBehavior: _evenLeading,
                          cursorColor: t.color('app-ink'),
                          backgroundCursorColor: t.color('app-ink-3'),
                          selectionColor: t.colorOf('color-mix(in srgb, #4f5bd5 30%, transparent)'),
                          minLines: 1,
                          maxLines: 6,
                          // Settings › Messages › Enter sends: the keyboard's Enter is Send, and the words still wrap.
                          keyboardType: enterSends ? TextInputType.text : TextInputType.multiline,
                          textInputAction: enterSends ? TextInputAction.send : TextInputAction.newline,
                          onSubmitted: enterSends ? (_) => editing ? _saveEdit() : _send() : null,
                          // Sending leaves the keyboard up for the next one.
                          onEditingComplete: enterSends ? () {} : null,
                          textCapitalization: TextCapitalization.sentences,
                          selectionControls: emptyTextSelectionControls,
                          contextMenuBuilder: (context, state) => _contextMenu(context, state),
                        ),
                      ]),
                    ),
                      ),
                    )),
                  ),
                  // Stickers, while nothing is being written: once there are words the room is theirs.
                  if (!Sms.remote && !editing && _text.text.isEmpty && _attachments.isEmpty)
                    IconTap(icon: Lucide.sticker, label: 'Stickers', size: 19, box: t.lenOf('2.25rem'), color: t.color('app-ink-2'), onPressed: _sending ? null : _sticker),
                  SizedBox(width: t.space(1)),
                  if (voiceOffered)
                    IconTap(icon: Lucide.mic, label: 'Record a voice message', size: 19, box: t.lenOf('2.25rem'), color: t.color('app-ink-2'), onPressed: _sending ? null : _record)
                  else
                  editing
                      ? IconTap(icon: Lucide.check, label: 'Save edit', filled: true, size: 16, box: t.lenOf('2.25rem'), onPressed: canSend ? _saveEdit : null)
                      : IconTap(icon: Lucide.send, label: 'Send', filled: true, size: 16, box: t.lenOf('2.25rem'), onPressed: canSend ? _send : null),
                ]),
              ),
            ),
            SizedBox(width: t.space(1)),
          ]),
          if (!isMms && !editing && parts > 1)
            Padding(
              padding: EdgeInsets.only(top: t.space(1), right: t.space(3)),
              child: Text(sealed ? '$parts texts once encrypted' : '$len · $parts texts', textAlign: TextAlign.end, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
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

/// Over the composer while encryption waits on someone: their key is here and wants a yes, or yours went and theirs
/// has not come. A press anywhere opens what can be done about it.
class _E2eBar extends StatelessWidget {
  const _E2eBar({required this.text, required this.onPress, this.action, this.onAction, this.onDismiss});
  final String text;
  final VoidCallback onPress;
  final String? action;
  final VoidCallback? onAction;

  /// An offer can be put away: a small cross at its end.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(left: t.space(1), right: t.space(1), bottom: t.space(2)),
      child: GlacierPressable(
        onPressed: onPress,
        builder: (context, state) => Container(
          padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(2), t.space(2)),
          decoration: BoxDecoration(color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'), borderRadius: BorderRadius.circular(t.radius('lg'))),
          child: Row(children: [
            AppIcon(Lucide.lock, size: 16, color: t.color('app-ink-2')),
            SizedBox(width: t.space(2)),
            Expanded(child: Text(text, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink'), height: 1.3))),
            if (action != null) ...[
              SizedBox(width: t.space(2)),
              GlacierPressable(
                onPressed: onAction,
                semanticLabel: action,
                builder: (context, s) => Container(
                  padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                  decoration: BoxDecoration(color: t.color(s.pressed ? 'app-ink-2' : 'app-ink'), borderRadius: BorderRadius.circular(t.lenOf('1rem'))),
                  child: Text(action!, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-paper'))),
                ),
              ),
            ],
            if (onDismiss != null) IconTap(icon: Lucide.x, label: 'Not now', size: 16, box: t.lenOf('2.25rem'), onPressed: onDismiss),
          ]),
        ),
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.date, this.busy = false});
  final DateTime date;

  /// Over a picture or a colour of the person's: the words stand on a pill ([OnBackground]).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(top: t.space(4), bottom: t.space(2)),
      child: Center(child: OnBackground(busy: busy, child: Text(dayHeading(date), textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'))))),
    );
  }
}

/// A line in the conversation that is not a message's words: a text that carried an encryption key.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.onLongPress, this.busy = false});
  final LucideIcon icon;
  final String text;
  final VoidCallback? onLongPress;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space(2)),
        child: Center(
          child: OnBackground(
            busy: busy,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(icon, size: 12, strokeWidth: 2.2, wash: false, color: t.color('app-ink-3')),
              SizedBox(width: t.space(1)),
              Flexible(child: Text(text, textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), weight: 'medium', color: t.color('app-ink-3')))),
            ]),
          ),
        ),
      ),
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
    this.onRetryDownload,
    this.sender,
    this.senderPerson,
    this.showFace = false,
    this.status,
    this.onTapFailed,
    this.reactions = const [],
    this.onReactionsTap,
    this.edited,
    this.onEditedTap,
    this.highlighted = false,
    this.playEntrance = false,
    this.concealed = true,
    this.onReveal,
    this.onBackground = false,
    this.busy = false,
    this.thread,
  });

  final Message message;
  final bool top;
  final bool bottom;
  final bool group;
  final String? sender;
  final Person? senderPerson;
  final bool showFace;
  final String? status;
  /// Told where the bubble is on the screen, so what a long press brings up can sit beside it.
  final ValueChanged<Rect> onLongPress;
  final VoidCallback? onTapFailed;

  /// Try again, for a picture message that could not be brought down; null where it is not this one's to offer.
  final VoidCallback? onRetryDownload;
  final List<Reaction> reactions;
  final VoidCallback? onReactionsTap;

  /// "Edited" or "Edited · correction sent", under the bubble.
  final String? edited;
  final VoidCallback? onEditedTap;

  /// Being edited in the composer.
  final bool highlighted;

  /// The message just arrived: its bubble effect (an iPhone's "sent with Slam") plays.
  final bool playEntrance;

  /// An invisible-ink message not yet tapped open.
  final bool concealed;
  final VoidCallback? onReveal;

  /// The conversation has a background (lib/backgrounds.dart), and one the small words need a pill on.
  final bool onBackground;
  final bool busy;

  /// The conversation, for its own bubble colour.
  final int? thread;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = message;
    // The words without an iPhone's "(sent with Slam)" at their end, which is played and not shown.
    final sent = sentWith(m.body);
    // Sealed, and the key that opens it is not on this phone (a reinstall, a new key since): said in its place.
    final unopened = m.notice == 'undecryptable';
    final body = unopened ? 'Encrypted message that can\'t be opened on this phone' : sent.text;
    final app = AppState.of(context);
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
    // Your own bubbles: this conversation's colour, else everywhere's (Settings › Appearance).
    final (mine, onMine) = myBubble(t, app, thread);
    final ground = out ? (failed ? t.colorOf('color-mix(in srgb, #dd3a30 18%, var(--app-paper-2))') : mine) : theirBubble(t, onBackground: onBackground);
    final ink = out && !failed ? onMine : t.color('app-ink');
    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;
    final faceSize = t.lenOf('1.75rem');
    final emojis = m.attachments.isEmpty && !unopened && app.bigEmoji ? emojiOnly(body) : 0;
    final jumbo = emojis >= 1 && emojis <= 3;

    final content = <Widget>[
      for (final a in m.attachments)
        if (a.isSticker)
          // One of the app's stickers: small, on the page, with no bubble and no corners cut.
          _Sticker(id: a.id, side: math.min(t.lenOf('9.5rem'), maxWidth))
        else if (a.isImage)
          Padding(
            padding: EdgeInsets.only(bottom: body.isEmpty ? 0 : t.space(1)),
            // A picture that did not go: a tap sends it again, where it would have opened the picture. Its own tap
            // used to win, so "Tap to try again" did nothing on a message that was a picture and no words.
            child: _Picture(id: a.id, radius: radius, maxWidth: maxWidth, onTap: failed ? onTapFailed : null),
          )
        else if (a.isVideo)
          // A video: a picture of where it starts, and a button that plays it (it was drawn as its file's name).
          Padding(
            padding: EdgeInsets.only(bottom: body.isEmpty ? 0 : t.space(1)),
            child: VideoBubble(video: a, radius: radius, maxWidth: maxWidth, ground: ground, ink: ink),
          )
        else if (a.isAudio)
          // A voice message: a player (on a computer, its name: the sound stays on the phone).
          Padding(
            padding: EdgeInsets.only(bottom: body.isEmpty ? 0 : t.space(1)),
            child: VoiceBubble(
              part: a.id,
              ground: ground,
              ink: ink,
              radius: radius,
              rim: !onBackground && bubbleNeedsRim(ground, t.color('glacier-bg')) ? Border.all(color: t.color('app-rule')) : null,
              playable: !Sms.remote,
            ),
          )
        else
          _Pill(text: a.name ?? a.type, ground: ground, ink: ink),
      // A picture message the carrier announced that is not here: coming down now, or it could not be, with a way to
      // ask for it again (Matt, 2026-11-13: "show the failed image with a retry if needed").
      if (m.state == 'downloading' || m.state == 'pending_download') _Undelivered(downloading: m.state == 'downloading', ground: ground, ink: ink, onRetry: onRetryDownload),
      if (body.isNotEmpty && jumbo)
        // One to three emoji and nothing else: large, on the page, with no bubble.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(1)),
          child: Text(body.trim(), style: pageText(t, t.lenOf(emojis == 1 ? '3.2rem' : '2.5rem'), color: t.color('app-ink'), height: 1.2)),
        )
      else if (body.isNotEmpty)
        Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: EdgeInsets.symmetric(horizontal: t.space(3) + 2, vertical: t.space(2)),
          // A bubble the page would swallow (white on the light page) wears a line round it.
          decoration: BoxDecoration(color: ground, borderRadius: radius, border: !onBackground && bubbleNeedsRim(ground, t.color('glacier-bg')) ? Border.all(color: t.color('app-rule')) : null),
          child: unopened
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon(Lucide.lock, size: 14, strokeWidth: 2.2, wash: false, color: ink),
                  SizedBox(width: t.space(2)),
                  Flexible(child: Text(body, style: pageText(t, t.fontSize('sm') * app.textScale, color: ink, height: 1.35).copyWith(fontStyle: FontStyle.italic))),
                ])
              : Text.rich(
                  _linked(body, ink),
                  // Settings › Appearance › Text size.
                  style: pageText(t, t.fontSize('md') * app.textScale, color: ink, height: 1.35),
                ),
        ),
    ];

    Widget bubble = Column(crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: content);
    final ink0 = sent.bubble == BubbleEffect.invisibleInk && concealed;
    if (ink0) {
      // Invisible ink: blurred past reading until it is tapped.
      bubble = Stack(alignment: Alignment.center, children: [
        ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7), child: bubble),
        Text('Tap to reveal', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: ink)),
      ]);
    }
    // Where the bubble is on the screen goes with the long press, so what it brings up sits beside the bubble.
    final held = bubble;
    bubble = Builder(
      builder: (at) => GestureDetector(
        onLongPress: () {
          final box = at.findRenderObject();
          if (box is RenderBox && box.hasSize) onLongPress(box.localToGlobal(Offset.zero) & box.size);
        },
        onTap: ink0 ? onReveal : onTapFailed,
        child: held,
      ),
    );
    if (sent.bubble != null && sent.bubble != BubbleEffect.invisibleInk) {
      bubble = BubbleEntrance(effect: sent.bubble!, play: playEntrance, child: bubble);
    }
    if (highlighted) {
      bubble = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: t.colorOf('#4f5bd5'), width: 2)),
        child: bubble,
      );
    }
    if (reactions.isNotEmpty) {
      // The chip sits on the bubble's lower edge, on the side away from the screen's edge, as both phones draw it.
      bubble = Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(padding: EdgeInsets.only(bottom: t.lenOf('1rem')), child: bubble),
          Positioned(
            bottom: 0,
            left: out ? t.space(2) : null,
            right: out ? null : t.space(2),
            child: _ReactionChip(reactions: reactions, onPressed: onReactionsTap),
          ),
        ],
      );
    }
    final faceGap = group && !out ? faceSize + t.space(2) : 0.0;

    return Padding(
      padding: EdgeInsets.only(top: top ? t.space(2) : 2),
      child: Column(
        crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (sender != null)
            Padding(
              padding: EdgeInsets.only(left: (group ? faceSize + t.space(2) : 0) + t.space(3), bottom: 2),
              child: OnBackground(busy: busy, child: Text(sender!, style: pageText(t, t.fontSize('xs'), weight: 'medium', color: t.color('app-ink-3')))),
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
          if (edited != null)
            GestureDetector(
              onTap: onEditedTap,
              child: Padding(
                padding: EdgeInsets.only(top: 3, left: faceGap + t.space(2), right: t.space(2)),
                child: OnBackground(busy: busy, child: Text(edited!, style: pageText(t, t.fontSize('xs'), weight: 'medium', color: t.color('app-ink-3')))),
              ),
            ),
          if (status != null)
            GestureDetector(
              // "Tap to try again" is said here, so here is where a tap is taken.
              behavior: HitTestBehavior.opaque,
              onTap: failed ? onTapFailed : null,
              child: Padding(
              padding: EdgeInsets.only(top: 3, left: faceGap + t.space(2), right: t.space(2), bottom: failed ? 6 : 0),
              child: OnBackground(busy: busy, child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: failed ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
                if (failed) ...[Padding(padding: const EdgeInsets.only(top: 2), child: AppIcon(Lucide.circleAlert, size: 12, color: t.colorOf('#dd3a30'))), const SizedBox(width: 4)],
                // It travelled sealed, and was opened here.
                if (m.encrypted) ...[Semantics(label: 'Encrypted', child: AppIcon(Lucide.lock, size: 11, strokeWidth: 2.4, wash: false, color: t.color('app-ink-3'))), const SizedBox(width: 4)],
                // Why a message did not go can run to two lines: it wraps under the bubble, where a time never needs to.
                Flexible(child: Text(status!, textAlign: out ? TextAlign.end : TextAlign.start, style: pageText(t, t.fontSize('xs'), color: failed ? t.colorOf('#dd3a30') : t.color('app-ink-3')))),
                // Your messages' ticks: a clock while it goes, one for sent, two for delivered, two in colour for read.
                if (out && !failed) ...[
                  const SizedBox(width: 4),
                  Semantics(
                    label: m.state,
                    child: AppIcon(
                      switch (m.state) { 'sending' || 'waiting' => Lucide.clock, 'delivered' || 'read' => Lucide.checkCheck, _ => Lucide.check },
                      size: 14,
                      strokeWidth: 2.4,
                      wash: false,
                      color: m.state == 'read' ? t.colorOf('#4f5bd5') : t.color('app-ink-3'),
                    ),
                  ),
                ],
              ])),
            ),
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

/// Where a picture would be, for one that is not here: being brought down, or it could not be.
class _Undelivered extends StatelessWidget {
  const _Undelivered({required this.downloading, required this.ground, required this.ink, this.onRetry});
  final bool downloading;
  final Color ground;
  final Color ink;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: t.lenOf('14rem'),
      padding: EdgeInsets.all(t.space(3)),
      decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(t.lenOf('1.1rem'))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (downloading) const GhostSpinner(size: 18) else AppIcon(LucideMore.imageOff, size: 20, color: ink),
          SizedBox(width: t.space(2)),
          Expanded(
            child: Text(
              downloading ? 'Downloading picture…' : 'This picture couldn\'t be downloaded',
              style: pageText(t, t.fontSize('sm'), weight: 'medium', color: ink, height: 1.3),
            ),
          ),
        ]),
        if (!downloading) ...[
          SizedBox(height: t.space(1)),
          Text('Check mobile data is on: pictures come over it even on Wi-Fi.', style: pageText(t, t.fontSize('xs'), color: ink.withValues(alpha: 0.7), height: 1.35)),
          if (onRetry != null) ...[
            SizedBox(height: t.space(2)),
            GlacierPressable(
              onPressed: onRetry,
              semanticLabel: 'Try again',
              builder: (context, state) => Container(
                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                decoration: BoxDecoration(color: ink.withValues(alpha: state.pressed ? 0.24 : 0.14), borderRadius: BorderRadius.circular(t.lenOf('1rem'))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon(Lucide.rotateCcw, size: 15, color: ink, wash: false),
                  SizedBox(width: t.space(2)),
                  Text('Try again', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: ink)),
                ]),
              ),
            ),
          ],
        ],
      ]),
    );
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
  const _Picture({required this.id, required this.radius, required this.maxWidth, this.onTap});
  final int id;
  final BorderRadius radius;
  final double maxWidth;

  /// What a tap does in place of opening the picture: sending a message that failed again.
  final VoidCallback? onTap;

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
          onTap: onTap ?? () => Navigator.of(context).push(PageRouteBuilder<void>(
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

/// A sticker in the conversation: its picture as it is, clear round its edge.
class _Sticker extends StatelessWidget {
  const _Sticker({required this.id, required this.side});
  final int id;
  final double side;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: Sms.instance.part(id),
      builder: (context, snap) {
        final bytes = snap.data;
        return SizedBox(
          width: side,
          height: side,
          child: bytes == null ? null : Image.memory(bytes, fit: BoxFit.contain, cacheWidth: (side * MediaQuery.devicePixelRatioOf(context)).round(), gaplessPlayback: true, filterQuality: FilterQuality.medium),
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

/// The reactions on a message as one chip: each kind once, in the order they came, with the count when there are
/// several. A press lists who reacted with what.
class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reactions, this.onPressed});
  final List<Reaction> reactions;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final kinds = <String>[];
    for (final r in reactions) {
      if (!kinds.contains(r.emoji)) kinds.add(r.emoji);
    }
    final mine = reactions.any((r) => r.by.isEmpty);
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: '${reactions.length} reaction${reactions.length == 1 ? '' : 's'}: ${kinds.join(' ')}',
      builder: (context, state) => Container(
        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 3),
        decoration: BoxDecoration(
          color: t.color(state.pressed ? 'app-paper-3' : (t.isDark ? 'app-paper-2' : 'app-paper')),
          borderRadius: BorderRadius.circular(t.lenOf('1rem')),
          border: Border.all(color: mine ? t.colorOf('#4f5bd5') : t.color('glacier-bg'), width: 2),
          boxShadow: t.shadowOf('0 1px 4px rgba(0,0,0,0.12)'),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(kinds.take(4).join(), style: pageText(t, t.fontSize('sm'), height: 1.2)),
          if (reactions.length > 1) ...[
            SizedBox(width: t.space(1)),
            Text('${reactions.length}', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-2'))),
          ],
        ]),
      ),
    );
  }
}

/// The reactions offered over a message's menu: the six every phone knows, then more. One that is already yours is
/// ringed, and a press on it takes it off.
class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.mine, required this.onPick});
  final Set<String> mine;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.lenOf('2.75rem');
    return Padding(
      padding: EdgeInsets.only(top: t.space(3), bottom: t.space(1)),
      child: SizedBox(
        height: side,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: t.space(3)),
          children: [
            for (final emoji in reactionChoices)
              GlacierPressable(
                onPressed: () => onPick(emoji),
                semanticLabel: mine.contains(emoji) ? 'Remove $emoji' : 'React $emoji',
                builder: (context, state) => AnimatedScale(
                  scale: state.pressed ? 1.25 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    width: side,
                    height: side,
                    margin: EdgeInsets.only(right: t.space(1)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: mine.contains(emoji) ? t.colorOf('color-mix(in srgb, #4f5bd5 22%, transparent)') : t.color('app-paper-3'),
                      border: mine.contains(emoji) ? Border.all(color: t.colorOf('#4f5bd5'), width: 2) : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: pageText(t, t.lenOf('1.35rem'), height: 1.15)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
