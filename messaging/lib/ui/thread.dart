import 'blocking.dart';
import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../app_state.dart';
import '../mentions.dart';
import '../desktop/platform.dart' show MacPlatform;
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../backgrounds.dart';
import '../effects.dart';
import '../friends/friends.dart';
import '../friends/groups.dart';
import '../edits.dart';
import '../kit/settings_type.dart';
import '../links.dart';
import '../message_format.dart';
import '../plugins/conversation.dart';
import '../plugins/plugin.dart' show MessageFacts;
import '../reactions.dart';
import '../sms.dart';
import '../standalone/chats.dart' show UsernameChats;
import '../stickers.dart';
import 'chat_rail.dart';
import 'chat_settings.dart';
import 'text_attachment.dart';
import 'common.dart';
import 'emoji_picker.dart';
import 'emoji_suggestions.dart';
import 'markdown_field.dart';
import 'mention_field.dart' show mentionStyle;
import 'profile_card.dart';
import 'composer_box.dart';
import 'reaction_stickers.dart';
import 'poof.dart';
import 'shell.dart';
import 'window_title.dart';
import 'skeleton.dart';
import 'voice_screen.dart';
import '../voice/voice.dart';
import '../voice/channels.dart';
import '../voice/friend_calls.dart';
import '../friends/buddies.dart';
import '../net/net.dart' show Net;
import '../souls/souls_send.dart' show SoulsCard;
import 'souls_send.dart';
import '../me/me.dart' show Me;
import 'encryption.dart';
import 'message_popover.dart';
import 'report_sheet.dart';
import '../safety/abuse_report.dart' show ReportedMessage, withContext;
import 'sticker_picker.dart';
import 'video.dart';
import 'voice.dart';
import '../sounds.dart';
import '../kit/semantic_colors.dart';
import 'dialup/bevel.dart' show DialupColors, isDialup;
import 'message_line.dart';
import 'jump_to_latest.dart';
import 'schedule_ui.dart';
import '../scheduled.dart' show ScheduleTarget;
import 'translated_card.dart';
import 'paste_images.dart';

/// One conversation: its messages oldest at the top, newest by the composer.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({super.key, required this.thread, required this.people, this.draft, this.onExpand});
  final int thread;
  final List<Person> people;
  final String? draft;

  /// In a conversation's bubble (lib/bubble.dart): the header's way into the whole app, on this conversation.
  final VoidCallback? onExpand;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> with WidgetsBindingObserver {
  List<Message>? _messages;
  late List<Person> _people = widget.people;
  final Map<String, Person> _senders = {};
  StreamSubscription<int>? _changes;
  // Its formatting markers dimmed as they are typed to a friend or a group of them; a text shows them as written
  // (GMFB-35, lib/ui/markdown_field.dart).
  late final MarkdownController _text = MarkdownController(text: widget.draft ?? '')..dims = () => _isGhost || _byName;

  /// The emoji a ":jo" being written finds, over the box, and a whole ":joy:" put in as 😂 (lib/ui/emoji_suggestions.dart;
  /// GMFB-22, Matt, Mac 0.12.6: "typing :joy: or something should expand the emoji to the joy emoji and auto suggest
  /// with a popup"). Its list has the keys first while it is open, so Enter there picks rather than sends.
  late final EmojiShortcodeSuggester _shortcodes;
  late final _focus = FocusNode(onKeyEvent: (node, e) => _shortcodes.key(e) ?? KeyEventResult.ignored);

  /// What the plugins put in a conversation (lib/plugins/conversation.dart): buttons in the header and the
  /// composer's row, lines in a message's menu, a card under a message, replies over the composer (Matt, 2026-11-14:
  /// "let's add all of the additional ones to a plugins ... I also want smart embeds added").
  late final ConversationPlugins _plugins = ConversationPlugins(thread: widget.thread, people: () => _people, write: _writeIn);

  /// A plugin writes into the composer: in place of what is there, the cursor after it.
  void _writeIn(String text) {
    _text.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    _focus.requestFocus();
  }

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

  /// Messages sent from here and not yet back from the phone, drawn at once as sending (Matt, 2026-11-15:
  /// "optimistically render a sent message bubble so it appears instantly"); each goes once the phone's own copy is
  /// read ([_settlePending]), or once it fails, or after two minutes.
  final List<Message> _pending = [];
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

  /// The name this conversation was given on this phone, where it was: a group's (lib/ui/chat_settings.dart).
  String? _name;

  /// Settings › Messages: reaction texts hung on their messages. Read as the page's choices change.
  bool _foldOn = true;

  /// More than one person here, or a group of friends: senders are named, and there is no encryption to read.
  bool get _group => _people.length > 1 || _isGhost;

  /// The group of friends this conversation is (lib/friends/groups.dart), where it is one: as the phone's own
  /// groups have it, or (on a computer, and before those are read) by the id its conversation carries.
  Group? get _ghost => Groups.instance.ofThread(widget.thread);
  String? _groupId;
  bool get _isGhost => _ghost != null || _groupId != null;

  /// Written to by username (`@name`, lib/standalone): words alone go that way, no pictures, stickers or voice yet.
  bool get _byName => _people.isNotEmpty && _people.every((p) => p.address.startsWith('@'));

  /// Why nothing can be written here, where nothing can: a group this phone has left, or one seen from a computer.
  String? get _closed {
    if (!_isGhost) return null;
    if (_ghost?.gone ?? false) return 'You are no longer in this group.';
    if (Sms.remote) return 'Write in this group from your phone for now.';
    return null;
  }

  void _groupsChanged() {
    if (mounted) setState(() {});
  }

  /// Where a message scheduled from Send goes (lib/ui/schedule_ui.dart): this group of friends, or these people by
  /// text (to a friend by the app's routes where one is up, as Send does); none in a group that can't be written to.
  ScheduleTarget? get _scheduleTarget {
    if (_people.isEmpty) return null;
    final who = _people.map((p) => p.label).join(', ');
    if (_isGhost) return _closed != null ? null : (kind: 'group', target: _ghost?.id ?? _groupId!, who: who);
    return (kind: 'text', target: _people.map((p) => p.address).join(','), who: who);
  }

  /// Send pressed and held, or right-clicked: the menu that schedules what is written (words alone).
  void _sendMenu() {
    if (_attachments.isNotEmpty) {
      toast(context, 'Pictures can\'t be scheduled yet. Send them now, or schedule the words alone.');
      return;
    }
    openSendMenu(context, to: _scheduleTarget, text: _text.text, onScheduled: () {
      _text.clear();
      _draftSave?.cancel();
      Sms.instance.setDraft(widget.thread, '');
    });
  }

  /// Sends [body] as words alone: a text to the people here, or in a group of friends to each member by the app's
  /// routes, which is the only way one is written to. Throws [_NotSent] where the group can't be written to or reached.
  Future<void> _sendWords(String body) async {
    if (!_isGhost) {
      await Sms.instance.send(_people.map((p) => p.address).toList(), body);
      return;
    }
    final closed = _closed;
    if (closed != null) throw _NotSent(closed);
    if (!await Groups.instance.sendText(_ghost?.id ?? _groupId!, body)) throw _NotSent('no connection. A group of friends needs the internet');
  }


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
    // Friends (lib/friends/friends.dart): a request that came or was answered, or a relay server found to answer.
    Friends.instance.addListener(_friendsChanged);
    Groups.instance.addListener(_groupsChanged);
    _shortcodes = EmojiShortcodeSuggester(_text, app: () => mounted ? AppState.maybeOf(context) : null);
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
    Friends.instance.removeListener(_friendsChanged);
    Groups.instance.removeListener(_groupsChanged);
    _changes?.cancel();
    _voiceStopped?.cancel();
    _draftSave?.cancel();
    // Leaving the conversation: a recording under way is thrown away, and whatever is playing stops.
    if (_recordingLimit != null) Sms.instance.cancelVoice().catchError((_) {});
    Sms.instance.stopVoice().catchError((_) {});
    if (_editing == null) Sms.instance.setDraft(widget.thread, _text.text);
    // The spot itself was kept by the arrow (JumpToLatest) as it went; how many messages it took to get there goes with it.
    ScrollMemory.hold(_spot, _limit);
    _scroll.dispose();
    _shortcodes.dispose();
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

  /// Reads the conversation's name and which group it is again, and redraws if either changed.
  Future<void> _loadName() async {
    try {
      final c = await Sms.instance.conversation(widget.thread);
      if (mounted && (c?.name != _name || c?.groupId != _groupId)) {
        setState(() {
          _name = c?.name;
          _groupId = c?.groupId;
        });
      }
    } catch (_) {}
  }

  /// Reads the conversation's name, and with one person here where encryption stands with them: asked again each
  /// time the conversation changes, since a key arriving is a text like any other.
  Future<void> _loadE2e() async {
    // A group has no encryption to read, and may have a name: read as the conversation opens, and again after its
    // settings close.
    _loadName();
    if (_group || _people.isEmpty) return;
    try {
      final s = await Sms.instance.e2e(_people.first.address);
      if (mounted) setState(() => _e2e = s);
      // Both have the app: whether friends can be offered is looked for, where it is not known yet.
      if (!Sms.paired && (s.on || s.offerable)) Friends.instance.look();
    } catch (_) {}
  }

  /// Whether Add friend is offered here: one person, who has the app, nothing said yet about being friends, a
  /// relay server known to answer, and the offer not put away.
  bool _offersFriend(BuildContext context) =>
      !Sms.paired && !_group && _people.isNotEmpty && Friends.instance.offers(_e2e) && AppState.of(context).flag('friend_banner_${widget.thread}');

  void _friendsChanged() {
    if (mounted) _loadE2e();
  }

  /// Add friend (Matt, 2026-11-14: "If both users chatting are on ghost messenger show an 'add friend' button").
  Future<void> _addFriend() async {
    final who = _people.first;
    try {
      await Friends.instance.add(who.address);
      if (mounted) toast(context, 'Friend request sent to ${who.label}');
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t ask: ${_said(e)}', tone: GlacierToastTone.danger);
    }
    _e2eChanged();
  }

  /// Accepts ([yes]) or declines the friend request the one person here sent.
  Future<void> _answerFriend(bool yes) async {
    final who = _people.first;
    try {
      await (yes ? Friends.instance.accept(who.address) : Friends.instance.decline(who.address));
      if (mounted && yes) toast(context, 'You and ${who.label} are friends');
    } catch (_) {}
    _e2eChanged();
  }

  void _e2eChanged() {
    _loadE2e();
    _load();
  }

  /// The warning's Turn off: their texts are coming plain, so this conversation goes plain too and they can read it.
  Future<void> _e2eStop() async {
    final person = _people.first;
    try {
      await Sms.instance.e2eOff(person.address);
      if (mounted) toast(context, 'Encryption is off with ${person.label}. Texts go as ordinary texts again.');
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t turn it off: $e', tone: GlacierToastTone.danger);
    }
    _e2eChanged();
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
  late int _limit = math.max(_opening, ScrollMemory.of(_spot)?.held ?? 0);
  static const _opening = 120;
  static const _step = 300;

  /// There are older messages than the ones held, and whether they are being read.
  bool _older = false;
  bool _readingOlder = false;

  /// Holds [_step] more messages and reads the conversation again; one reading at a time.
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

  /// Where this conversation was left, and its list's controller, which starts there (lib/ui/jump_to_latest.dart; Matt,
  /// 2026-11-17: "remember the scroll position when switching between chats").
  String get _spot => 'sms:${widget.thread}';
  late final ScrollController _scroll = ScrollMemory.controllerFor(() => _spot);

  /// The messages from others, newest first, for the down arrow to count what came while the person was reading back.
  Iterable<Object> get _incoming => _folded.messages.where((m) => !m.outgoing && !_isLine(m)).map((m) => m.key);

  /// The first message unread as the chat was opened (a group's), and whether that has been looked for yet.
  String? _firstNewKey;
  bool _newKnown = false;

  /// Reads the newest [_limit] messages and folds them for drawing; run as the conversation opens and at every
  /// change to it. [markRead] also marks what came as read, once where the unread began has been noted.
  Future<void> _load({bool markRead = false}) async {
    _loadE2e();
    final asked = _limit;
    final list = await Sms.instance.messages(widget.thread, limit: asked);
    if (!mounted) return;
    final edits = foldCorrections(list);
    final folded = _foldOn ? foldReactions(edits.messages) : Folded(messages: edits.messages, reactions: const {});
    setState(() {
      _messages = list;
      // As many as were asked for: there may be more behind them.
      _older = list.length >= asked;
      _settlePending(list);
      _folded = _pending.isEmpty ? folded : Folded(messages: [..._pending, ...folded.messages], reactions: folded.reactions);
      _corrected = edits.corrected;
    });
    _playReactions();
    // A message that came or went while the conversation is open sets off its effect, once.
    final newest = folded.messages.isEmpty ? null : folded.messages.first;
    if (newest != null && _newestKey != null && newest.key != _newestKey && newest.state != 'failed') _playFor(newest);
    _newestKey = newest?.key ?? '';
    // Where the unread began as the group chat was opened, before it is marked read: the New messages divider stays
    // above it while the chat is open (NewMessagesDivider).
    if (markRead && !_newKnown) {
      _newKnown = true;
      // Looked for in every chat: who is in it may not be known yet, and the divider is drawn for a group alone.
      final firstNew = list.where((m) => !m.outgoing && !m.read).lastOrNull;
      if (firstNew != null) setState(() => _firstNewKey = firstNew.key);
    }
    if (markRead && list.any((m) => !m.outgoing)) Sms.instance.markRead(widget.thread);
    if (_group) {
      for (final m in list) {
        if (!m.outgoing && m.address.isNotEmpty && !_senders.containsKey(m.address)) {
          _senders[m.address] = _people.firstWhere((p) => _same(p.address, m.address), orElse: () => Person(address: m.address));
        }
      }
    }
  }

  /// Whether two addresses are one person's: numbers by their last ten digits, anything without digits as written.
  static bool _same(String a, String b) {
    String d(String s) {
      final x = s.replaceAll(RegExp(r'[^0-9]'), '');
      return x.length > 10 ? x.substring(x.length - 10) : x;
    }
    return d(a).isNotEmpty ? d(a) == d(b) : a == b;
  }

  /// Drops from [_pending] each message the phone's [list] now has (your own, the same words, from a minute before it
  /// on), and any two minutes old.
  void _settlePending(List<Message> list) {
    final now = DateTime.now();
    _pending.removeWhere((p) =>
        // A picture message takes longer than words to reach the phone's list.
        now.difference(p.date) > Duration(minutes: p.attachments.isEmpty ? 2 : 5) ||
        list.any((m) =>
            m.outgoing &&
            m.body.trim() == p.body &&
            (p.attachments.isEmpty || m.attachments.isNotEmpty) &&
            !m.date.isBefore(p.date.subtract(const Duration(minutes: 1)))));
  }

  /// [body], and the pictures [files], drawn at once as your newest message, sending (Matt, 2026-11-16, of a picture
  /// sent: it "takes a long time to even appear in chat in the first place").
  Message _showPending(String body, {List<String> files = const []}) {
    final now = DateTime.now();
    final held = <Attachment>[];
    // The pictures as the composer showed them (Sms.photo of each one picked), held under numbers of their own.
    for (final (i, uri) in files.indexed) {
      final id = -(now.microsecondsSinceEpoch % 1000000000) * 10 - i;
      Sms.instance.holdPart(id, Sms.instance.photo(uri));
      held.add(Attachment(id: id, type: 'image/jpeg', name: uri.split('/').last));
    }
    final m = Message(id: -now.microsecondsSinceEpoch, kind: 'pending', address: '', body: body, date: now, outgoing: true, state: 'sending', attachments: held);
    setState(() {
      _pending.insert(0, m);
      _folded = Folded(messages: [m, ..._folded.messages], reactions: _folded.reactions);
    });
    return m;
  }

  /// Takes [m] back out of the messages drawn as sending (it failed, or was only ever held here).
  void _dropPending(Message m) {
    if (!_pending.remove(m)) return;
    setState(() => _folded = Folded(messages: _folded.messages.where((x) => x.key != m.key).toList(), reactions: _folded.reactions));
  }

  /// Send: what is written and the pictures picked go, drawn at once as sending. If nothing went, the words and
  /// pictures are put back in the composer.
  Future<void> _send() async {
    final body = _text.text.trim();
    if ((body.isEmpty && _attachments.isEmpty) || _sending) return;
    final to = _people.map((p) => p.address).toList();
    if (to.isEmpty) return;
    final files = List<String>.of(_attachments);
    final pending = body.isEmpty && files.isEmpty ? null : _showPending(body, files: files);
    setState(() => _sending = true);
    HapticFeedback.lightImpact();
    _text.clear();
    _attachments.clear();
    _draftSave?.cancel();
    Sms.instance.setDraft(widget.thread, '');
    try {
      // To a friend, words alone go by the app's routes where one that costs nothing is up, and are kept with the
      // conversation as a text is (lib/friends/friends.dart); anything else, and anything the routes could not
      // take, goes as a text.
      if (_isGhost) {
        await _sendWords(body);
      } else {
        // A computer with friends of its own (lib/desktop/own_calls.dart) writes to a friend by username itself.
        final own = !Sms.paired || (Sms.ownNetwork && to.length == 1 && UsernameChats.isUsername(to.first));
        final byRoute = files.isEmpty && to.length == 1 && body.isNotEmpty && own && await Friends.instance.sendText(to.first, body);
        // A friend by username has no number: what the routes didn't take is never handed to texting (here, or on the
        // phone a computer is paired with), which would write the words, unsealed, into the phone's own store of texts
        // (or open Google Messages beside it) for an "@name" no carrier can deliver (found in review, 2026-11-23). It
        // fails here with the reason, and what was written is put back.
        if (!byRoute && to.any(UsernameChats.isUsername)) {
          throw _NotSent(files.isNotEmpty
              ? 'pictures and files can\'t be sent to a friend by username yet'
              : own
                  // A relay that refused them says why (their relay can't be reached from yours, or won't take them).
                  ? Friends.instance.lastRefusal ?? 'no connection. A friend by username is reached over the internet, through the relay'
                  : 'a friend by username is written to from the phone itself, or from a computer with an account of its own');
        }
        if (!byRoute) await Sms.instance.send(to, body, attachments: files);
      }
      // No sound for one's own message going: only one coming in is heard (Matt, 2026-11-18: "remove the sound for
      // sending a message we only need to hear when were sent a message not when we send one").
    } catch (e) {
      Sounds.instance.play(UiSound.messageFailed);
      if (pending != null && mounted) _dropPending(pending);
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
        toast(context, micRefusedWords(), tone: GlacierToastTone.danger);
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

  /// Picks pictures to send with the next message: five at most in all.
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

  /// [m] just came or went: its bubble's effect plays as it is drawn, and its screen effect over the conversation,
  /// where effects are on.
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
    if (!mine) Sounds.instance.play(UiSound.reaction);
    try {
      await _sendWords(reactionText(emoji, m, removed: mine));
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send the reaction: $e', tone: GlacierToastTone.danger);
    }
    _load();
  }

  /// Your own words, once they have left the composer for good: not while sending, nor one still coming down.
  bool _canEdit(Message m) => m.outgoing && m.body.isNotEmpty && m.state != 'sending' && m.state != 'pending_download' && m.state != 'downloading';

  /// Puts [m]'s words in the composer to be changed, keeping what was being written to put back after.
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

  /// Changes [m]'s words on this phone, and with [send] texts the others the correction.
  Future<void> _applyEdit(Message m, String body, {required bool send}) async {
    _cancelEdit();
    try {
      await Sms.instance.editMessage(m, body);
      if (send) await _sendWords(correctionText(body));
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

  /// Who reacted with what, newest first: a tap on a message's reactions.
  void _showReactions(List<Reaction> list) {
    String who(String by) {
      if (by.isEmpty) return 'You';
      if (by == '?') return 'Someone';
      final p = _senders[by] ?? _people.where((p) => _same(p.address, by)).firstOrNull;
      return p?.label ?? by;
    }
    showChoices(context, title: 'Reactions', choices: [
      for (final r in list.reversed) Choice('${r.emoji}   ${who(r.by)}', Lucide.userRound, () {}),
    ]);
  }

  /// Messages going in a puff, deleted once it has gone off ([_gone]).
  final Set<String> _poofing = {};

  /// A message's puff has gone off: gone from the screen, and deleted; put back, with why, if Android would not.
  Future<void> _gone(Message m) async {
    final before = _messages;
    setState(() {
      _poofing.remove(m.key);
      _messages = _messages?.where((x) => x.key != m.key).toList();
      _folded = Folded(messages: _folded.messages.where((x) => x.key != m.key).toList(), reactions: _folded.reactions);
    });
    try {
      await Sms.instance.deleteMessage(m);
    } catch (e) {
      if (mounted) {
        setState(() => _messages = before);
        toast(context, 'Couldn\'t delete: ${_said(e)}', tone: GlacierToastTone.danger);
      }
    }
    _load();
  }

  /// The facts the plugins are asked [m]'s words by (a translation): its words as its bubble shows them, and none while
  /// it is invisible ink not yet tapped open, whose words a card over it would give away.
  MessageFacts? _wordsFacts(Message m) {
    final sent = sentWith(m.body);
    if (sent.bubble == BubbleEffect.invisibleInk && !_revealed.contains(m.key)) return null;
    return _plugins.words(m, sent.text);
  }

  /// A long press on [m]. [at] is where its bubble is on the screen: the reactions, the screen effects and what else
  /// can be done come up beside it (lib/ui/message_popover.dart). With no [at], a line that is no bubble (a key, a
  /// background), it is the sheet from the foot of the screen.
  void _messageMenu(Message m, [Rect? at]) {
    // One drawn before the phone has it (_pending) has nothing on the phone to act on yet.
    if (m.kind == 'pending') return;
    final canReact = m.state != 'sending' && m.state != 'waiting' && m.state != 'failed' && m.state != 'pending_download' && m.state != 'downloading' && m.notice == null;
    final mine = {for (final r in _folded.reactions[m.key] ?? const <Reaction>[]) if (r.by.isEmpty) r.emoji};
    final choices = [
      if (m.body.isNotEmpty)
        Choice('Copy text', Lucide.copy, () {
          Clipboard.setData(ClipboardData(text: m.body));
          toast(context, 'Copied');
        }),
      if (_canEdit(m) && Sms.can('editMessage')) Choice(m.state == 'failed' ? 'Edit and send again' : 'Edit', Lucide.pencil, () => _startEdit(m)),
      if (m.edited && m.original != null) Choice('Show original', Lucide.clock, () => _showOriginal(m)),
      if (m.state == 'failed' && _canRetry(m)) Choice('Send again', Lucide.rotateCcw, () => _retry(m)),
      if (effectFor(m.body) != null) Choice('Play effect', Lucide.sparkles, () => _effects.currentState?.play(effectFor(m.body)!, text: sentWith(m.body).text)),
      // The plugins' own lines (remind me about this, and the like).
      if (m.notice == null) ..._plugins.message(context, m),
      // Report (GMFB-40): someone else's message, in a chat by username or a group of friends.
      if (_reportable && !m.outgoing && m.notice == null) Choice('Report', Lucide.flag, () => _report(m)),
      if (Sms.can('deleteMessage'))
        // At once, nothing asked (Matt, 2026-11-15: "Don't ask for confirmation when deleting a message and show a poof
        // animation when one is deleted"): the bubble goes in a puff (Poof), then the message is deleted (_gone).
        Choice('Delete message', Lucide.trash2, () {
          HapticFeedback.lightImpact();
          setState(() => _poofing.add(m.key));
        }, danger: true),
    ];
    if (at == null) {
      showChoices(
        context,
        title: m.body.isEmpty ? null : (m.body.length > 80 ? '${m.body.substring(0, 80)}…' : m.body),
        header: canReact ? _ReactionRow(mine: mine, onPick: (emoji) { Navigator.of(context, rootNavigator: true).pop(); _react(m, emoji); }) : null,
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

  /// Whether a message here can be reported (GMFB-40): a chat by username, or a group of friends, both on Ghost. Texts
  /// and the other networks have their own ways to report.
  bool get _reportable => _byName || _isGhost;

  /// Who wrote [m], by address: the person of a chat with one, else the address the message carries.
  String _fromOf(Message m) => m.address.isNotEmpty ? m.address : (_people.length == 1 ? _people.first.address : '');

  /// The report sheet for [m], with what was said round it, oldest first.
  void _report(Message m) {
    final shown = _folded.messages.reversed.where((x) => x.kind != 'pending' && x.notice == null).toList();
    final index = shown.indexWhere((x) => x.key == m.key);
    String nameOf(Message x) => x.outgoing ? 'You' : (_senders[x.address]?.label ?? (_people.length == 1 ? _people.first.label : (x.address.isEmpty ? 'They' : x.address)));
    final list = [
      for (final x in shown) ReportedMessage(from: x.outgoing ? (Me.instance.username == null ? 'me' : '@${Me.instance.username}') : _fromOf(x), name: nameOf(x), at: x.date.millisecondsSinceEpoch, text: x.body, mine: x.outgoing),
    ];
    final from = _fromOf(m);
    final username = from.startsWith('@') ? from.substring(1).toLowerCase() : '';
    final buddy = username.isEmpty ? null : Buddies.instance.all.where((b) => b.username.toLowerCase() == username).firstOrNull;
    unawaited(showReportSheet(
      context,
      ReportTarget(
        id: buddy?.id ?? '',
        username: username,
        name: nameOf(m),
        place: 'chat',
        placeName: _name ?? _ghost?.name ?? (_people.length == 1 ? _people.first.label : ''),
        messages: index < 0 ? [ReportedMessage(from: from, name: nameOf(m), at: m.date.millisecondsSinceEpoch, text: m.body, reported: true)] : withContext(list, index),
      ),
    ));
  }

  Future<void> _retry(Message m, {String? body}) async {
    try {
      if (_isGhost) {
        // In a group of friends what did not go is taken away and written again, by the routes.
        await Sms.instance.deleteMessage(m);
        await _sendWords(body ?? m.body);
      } else if (m.kind == 'mms') {
        // A picture message goes again with its own pictures, read back from Android's store. Sending its words
        // alone, as this did, lost the picture of every picture message that was tried again.
        await Sms.instance.resendMms(m.id, body: body);
      } else {
        await Sms.instance.deleteMessage(m);
        await _sendWords(body ?? m.body);
      }
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send: ${_said(e)}', tone: GlacierToastTone.danger);
    }
    _load();
  }

  /// What went wrong, as the phone put it, without the wrapping a channel's error comes in.
  static String _said(Object e) => e is PlatformException ? (e.message ?? e.code) : '$e';

  /// Hops into the group's channel, and shows it.
  Future<void> _voice(VoiceChannel c, {bool video = false}) async {
    try {
      await Voice.instance.join(c, video: video);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t join: $e', tone: GlacierToastTone.danger);
      return;
    }
    if (!mounted) return;
    // Left while it was connecting (the call's banner has Leave from the first moment): there is no call to show.
    if (Voice.instance.session?.channel.room != c.room) return;
    final shell = AppShell.maybeOf(context);
    if (shell != null) {
      shell.go('voice');
    } else {
      push(context, (_) => const VoiceScreen());
    }
  }

  /// The friend by username this conversation is with, where they can be called: one person, a friend.
  Buddy? get _callable {
    if (_group || _people.length != 1 || !_people.first.address.startsWith('@')) return null;
    final name = _people.first.address.substring(1).toLowerCase();
    return Buddies.instance.all.where((b) => b.state == 'yes' && b.username.toLowerCase() == name).firstOrNull;
  }

  /// The friend by username souls can be sent to from here, and whose souls cards are drawn here (GMFB-39, "Payments
  /// between friends"; Matt, 2026-11-23: "Tip souls in a chat"): one person, a friend, written to by this app itself
  /// (a computer that shows its phone's conversations leaves it to the phone). Where they are here under two ids, the
  /// newest, which is the one the relay knows their username by.
  Buddy? get _soulsFriend {
    if (_group || _people.length != 1 || !UsernameChats.isUsername(_people.first.address) || !Sms.ownNetwork) return null;
    final name = _people.first.address.substring(1).toLowerCase();
    return Buddies.instance.shownFriends.where((b) => b.state == 'yes' && b.username.toLowerCase() == name).firstOrNull;
  }

  /// The composer's + in a chat with a friend by username, where pictures can't go yet: what can be added instead.
  void _plusForFriend() {
    showChoices(context, choices: [
      Choice('Send souls', Lucide.flame, _sendSouls, hint: 'A thank-you from your souls to theirs'),
    ]);
  }

  /// Opens the page souls are sent from (lib/ui/souls_send.dart). The card goes into this conversation as a message
  /// to the friend, by the app's routes, as words written here do.
  Future<void> _sendSouls() async {
    final b = _soulsFriend;
    if (b == null) return;
    // Souls are kept by one relay and stay on it: a friend who lives on another has no count here to add to.
    if (Buddies.instance.elsewhere(b)) {
      toast(context, '${b.shown} is on another relay. Souls can only be sent to friends on yours.');
      return;
    }
    final address = _people.first.address;
    await push<void>(context, (_) => SendSoulsScreen(to: b.id, name: b.shown, write: (words) => Friends.instance.sendText(address, words)));
    if (mounted) _load();
  }

  /// [m] as a souls card, where it is one in a chat with a friend souls can be sent to ([_soulsFriend]); null for
  /// every other message, which is drawn as its words.
  ({SoulsCard card, Buddy friend})? _soulsCardOf(Message m) {
    if (m.notice != null || m.attachments.isNotEmpty) return null;
    final card = SoulsCard.of(m.body);
    if (card == null) return null;
    final friend = _soulsFriend;
    return friend == null ? null : (card: card, friend: friend);
  }

  /// The souls card the message at [i] of [msgs] (newest first) is. Who sent to whom is who wrote the message, never
  /// what it says: the relay's receipt has to agree with that before the card says souls were sent, and the same
  /// receipt on a message further up makes this one a repeat that says so.
  Widget _soulsCard(({SoulsCard card, Buddy friend}) souls, List<Message> msgs, int i, {double maxWidth = 320, Widget Function(String words)? line}) {
    final m = msgs[i];
    final me = Net.instance.hub?.signer.id ?? '';
    final receipt = 'Souls receipt: ${souls.card.id}';
    return SoulsSentCard(
      key: ValueKey('souls-${m.key}'),
      card: souls.card,
      mine: m.outgoing,
      name: souls.friend.shown,
      from: m.outgoing ? me : souls.friend.id,
      to: m.outgoing ? souls.friend.id : me,
      repeat: msgs.skip(i + 1).any((o) => o.body.contains(receipt)),
      maxWidth: maxWidth,
      onLongPress: () => _messageMenu(m),
      line: line,
    );
  }

  /// Rings the friend this conversation is with ([_callable]) and goes to the call. Where they couldn't be reached, says
  /// so and leaves the call it had made.
  Future<void> _callFriend({required bool video}) async {
    final b = _callable;
    if (b == null) return;
    // A call's room is on one relay (docs/OPEN_NETWORK.md, section 4: rooms don't cross relays yet): a friend on
    // another would ring and never be met in it, so they are not rung.
    if (Buddies.instance.apart(b)) {
      toast(context, callElsewhereWords(b.shown, Buddies.instance.relayOf(b)));
      return;
    }
    bool rang;
    try {
      rang = await FriendCalls.instance.call(b, video: video);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t call: $e', tone: GlacierToastTone.danger);
      return;
    }
    if (!mounted) return;
    if (!rang) {
      toast(context, '${b.shown} can\'t be reached right now');
      if (Voice.instance.session != null && FriendCalls.isCall(Voice.instance.session!.channel)) unawaited(Voice.instance.leave());
      return;
    }
    final shell = AppShell.maybeOf(context);
    if (shell != null) {
      shell.go('voice');
    } else {
      push(context, (_) => const VoiceScreen());
    }
  }

  /// Rings everyone in the group, and hops into its channel.
  Future<void> _callGroup() async {
    final g = _ghost;
    if (g == null) return;
    final told = await Voice.instance.ring(g);
    if (mounted) toast(context, told == 0 ? 'Nobody could be rung right now. You\'re in the group\'s space for them.' : 'Calling ${g.name}');
    await _voice(VoiceChannel.ofGroup(g.id, g.name));
  }

  /// Opens the conversation's own settings (lib/ui/chat_settings.dart): its people, its background and bubbles, its
  /// encryption, whether it is muted or pinned. From the cog at the top, and from a tap on the name. Reads the
  /// conversation again once they close.
  Future<void> _openSettings() async {
    await push<void>(context, (_) => ChatSettingsScreen(thread: widget.thread, people: _people));
    _e2eChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final background = ChatBackground.of(AppState.of(context), widget.thread);
    final ghost = _ghost;
    final title = ghost != null ? ghost.title : (_people.isEmpty ? (_name ?? '') : (_group ? (_name ?? Conversation.peopleTitle(_people)) : _people.first.label));
    final subtitle = _isGhost
        ? (ghost == null ? 'Group' : '${ghost.members.length} ${ghost.members.length == 1 ? 'member' : 'members'}')
        : _group
        ? '${_people.length} people'
        : _e2e.on
            ? (_e2e.isFriend ? (_e2e.verified ? 'Friend · verified' : 'Friend · encrypted') : (_e2e.verified ? 'Encrypted · verified' : 'Encrypted'))
            : (_people.isNotEmpty && _people.first.name != null ? _people.first.address : null);

    // Beside the list the conversation draws no way back (PaneRoot, lib/ui/common.dart). On a computer what the
    // phone at the other end does for one is offered (Sms.can); calling is the phone's alone.
    final remote = Sms.remote;
    // What a plugin's widget in the conversation may do: write into the composer.
    // The window is named for the conversation while it is open (lib/ui/window_title.dart).
    return WindowTitle(name: title, child: PluginThread(write: _writeIn, child: GhostPage(
      title: title,
      back: true,
      titleWidget: GlacierPressable(
        onPressed: _openSettings,
        // One to one, a long press offers Block, as a Telegram or Signal chat's name does (lib/ui/blocking.dart).
        onLongPress: !_group && _people.length == 1 && Sms.can('setBlocked')
            ? () => showPersonBlock(context, BlockTarget.number(_people.first.address, title, thread: widget.thread))
            : null,
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
        ..._plugins.header(context, newest: _messages?.firstOrNull),
        // A phone call needs a number: a friend by username (`@name`, lib/standalone) has none.
        if (!remote && !_group && _people.isNotEmpty && !_people.first.address.startsWith('@'))
          IconTap(icon: Lucide.phone, label: 'Call', onPressed: () => const MethodChannel('ghost_messaging/sms').invokeMethod('dial', {'address': _people.first.address})),
        // A friend by username rung with a voice or a video call, as a phone would (GMFB-28, from the Uplink gap review:
        // "Ring one friend with a voice or video call, the way you would a phone, without making a space first").
        if (_callable != null && Sms.callsHere) ...[
          IconTap(key: const ValueKey('call-friend'), icon: LucideMore.phoneCall, label: 'Voice call', onPressed: () => _callFriend(video: false)),
          IconTap(key: const ValueKey('video-call-friend'), icon: Lucide.video, label: 'Video call', onPressed: () => _callFriend(video: true)),
        ],
        // A group of friends' voice and video channel, open to hop in and out of, and calling the whole group into it
        // (Matt, 2026-11-14: "allow for group chat video and voice calls to hop in the voice and video channel at any
        // time with the option to call the group"; lib/voice).
        if (_ghost != null && !_ghost!.gone && Sms.callsHere) ...[
          ListenableBuilder(
            listenable: Voice.instance,
            builder: (context, _) {
              final c = VoiceChannel.ofGroup(_ghost!.id, _ghost!.name);
              final n = Voice.instance.inChannel(c).length;
              return IconTap(icon: LucideMore.headphones, label: n == 0 ? 'Join voice' : 'Join voice, $n in it', onPressed: () => _voice(c));
            },
          ),
          IconTap(icon: LucideMore.phoneCall, label: 'Call the group', onPressed: _callGroup),
        ],
        // A bubble's way into the whole app (GMFB-8: "message bubbles that just sit on the side of the screen").
        if (widget.onExpand != null) IconTap(icon: Lucide.maximize, label: 'Open in Ghost Messaging', onPressed: widget.onExpand),
        // Each conversation's own settings: its background, your bubbles in it, its encryption, mute and pin.
        // On a computer too (Matt, 2026-11-14: "There needs to be chat settings on desktop as well"): what a computer
        // can change of a conversation, and what it can only show (lib/ui/chat_settings.dart).
        IconTap(icon: Lucide.settings, label: 'Conversation settings', onPressed: _openSettings),
      ],
      body: Stack(children: [
        if (!background.isNone) Positioned.fill(child: ChatBackgroundLayer(background: background)),
        // Dial-Up writes the conversation as a chat room's transcript (lib/ui/message_line.dart); every other look draws
        // its bubbles, untouched.
        Positioned.fill(child: _messages == null ? SkeletonChat(label: 'Loading messages…', faces: _group) : (isDialup(context) ? _lines(t, background, title) : _list(t, background))),
        Positioned.fill(child: EffectLayer(key: _effects, style: pageText(t, 26, color: t.color('app-ink')))),
        // The group's call while others are in it: who, and Join.
        if (_ghost != null && !_ghost!.gone && Sms.callsHere)
          Positioned(left: t.space(3), right: t.space(3), top: t.space(2), child: SpaceLiveBar(channel: VoiceChannel.ofGroup(_ghost!.id, _ghost!.name), onJoin: () => _voice(VoiceChannel.ofGroup(_ghost!.id, _ghost!.name)))),
      ]),
      // Where nothing can be written (a group this phone has left, or one seen from a computer) it says why.
      footer: _closed != null
          ? Padding(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(4) + MediaQuery.paddingOf(context).bottom),
              child: Text(_closed!, textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
            )
          : ListenableBuilder(
              listenable: _text,
              builder: (context, _) {
                // Over the composer, what the plugins put there: replies to choose from, a word about who wrote.
                final newest = _folded.messages.where((m) => !_isLine(m)).firstOrNull;
                final above = _messages == null || _editing != null
                    ? const <Widget>[]
                    : _plugins.aboveComposer(
                        context,
                        text: _text.text,
                        lastIn: newest != null && !newest.outgoing ? newest.body : null,
                        lastOut: newest != null && newest.outgoing ? newest.body : null,
                        title: title,
                        count: _folded.messages.length,
                      );
                if (above.isEmpty) return _composer(t);
                return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [...above, _composer(t)]);
              },
            ),
    )));
  }

  Widget _list(Tokens t, ChatBackground background) {
    final msgs = _folded.messages;
    final busy = background.busy;
    // Newest first, drawn bottom up.
    String? lastOutgoingKey;
    for (final m in msgs) {
      if (m.outgoing && !_isLine(m)) { lastOutgoingKey = m.key; break; }
    }
    // What stands over the oldest message: "Say hello." in an empty conversation, the wait for earlier ones.
    final tail = <Widget>[
      if (msgs.isEmpty)
        Padding(
          padding: EdgeInsets.all(t.space(8)),
          child: Center(child: OnBackground(busy: busy, child: Text('Say hello.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))))),
        ),
      // Older ones are read as the reader nears the oldest held: said at the top while they come.
      if (_older)
        SkeletonChat(label: 'Loading earlier messages…', most: 3, shrink: true, faces: _group),
    ];
    // Each message's place by its key, so a row keeps what it holds (a bubble leaving, words shown) when a newer
    // message moves it down the list.
    final places = <String, int>{for (var i = 0; i < msgs.length; i++) msgs[i].key: i};
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Drawn bottom up, so what lies after is the older end.
        if (_older && !_readingOlder && n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 900) _readOlder();
        return false;
      },
      child: JumpToLatest(
        controller: _scroll,
        chat: _spot,
        incoming: _incoming,
        inset: EdgeInsets.only(right: t.space(3), bottom: t.space(3)),
        // Built a row at a time, as each comes near the screen: every message held was made a widget at every build
        // (120 at first, 300 more a page), with what the plugins find in each one's words
        // (docs/performance-audit.md, finding 3).
        // The chat's map in the gutter at its right (lib/ui/chat_rail.dart).
        child: ChatRail(
          controller: _scroll,
          chat: _spot,
          marks: [
            for (final m in msgs)
              RailMark(
                at: m.date.millisecondsSinceEpoch,
                who: m.outgoing ? 'me' : m.address,
                mine: m.outgoing,
                name: m.outgoing ? 'You' : (_senders[m.address]?.label ?? (_people.length == 1 ? _people.first.label : m.address)),
                text: _isLine(m) ? '' : m.body,
                quiet: _isLine(m),
              ),
          ],
          face: (who, name, mine, size) => Avatar(people: [mine ? const Person(address: '', name: 'You') : (_senders[who] ?? _people.where((p) => p.address == who).firstOrNull ?? (_people.length == 1 ? _people.first : Person(address: who)))], size: size, presence: false),
          child: ListView.builder(
          controller: _scroll,
          reverse: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), ChatRail.gutter, t.space(2)),
          itemCount: msgs.length + tail.length,
          findChildIndexCallback: (key) => key is ValueKey<String> && key.value.startsWith('row-') ? places[key.value.substring(4)] : null,
          itemBuilder: (context, i) {
            if (i >= msgs.length) return tail[i - msgs.length];
            final parts = _row(t, background, msgs, i, lastOutgoingKey);
            // Bottom up in the list, so the first part made is the lowest on the page.
            return Column(key: ValueKey('row-${msgs[i].key}'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: parts.reversed.toList());
          },
        ),
        ),
      ),
    );
  }

  /// The message at [i] of [msgs] (newest first) as its row's parts, the lowest first: what the plugins put under it,
  /// its bubble, the line over the first new one, the day over the day's first.
  List<Widget> _row(Tokens t, ChatBackground background, List<Message> msgs, int i, String? lastOutgoingKey) {
    final busy = background.busy;
    final items = <Widget>[];
      final m = msgs[i];
      final newer = i > 0 ? msgs[i - 1] : null;
      final older = i < msgs.length - 1 ? msgs[i + 1] : null;
      bool joins(Message? a, Message b) => a != null && !_isLine(a) && a.outgoing == b.outgoing && a.address == b.address && a.date.difference(b.date).inMinutes.abs() < 3;
      // Souls a friend sent, or you sent them: the card, on the side of whoever sent (lib/ui/souls_send.dart; GMFB-39).
      final souls = _soulsCardOf(m);
      if (souls != null) {
        items.add(Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
          child: Align(alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft, child: _soulsCard(souls, msgs, i, maxWidth: MediaQuery.sizeOf(context).width * 0.8)),
        ));
        if (older == null || !_sameDay(older.date, m.date)) items.add(_DayHeading(date: m.date, busy: busy));
        return items;
      }
      if (_isLine(m)) {
        // A text that carried an encryption key, or a chat background: a line saying so, where its letters would
        // have been a bubble.
        final who = m.outgoing ? 'You' : (_senders[m.address]?.label ?? (_people.length == 1 ? _people.first.label : (m.address.isEmpty ? 'They' : m.address)));
        items.add(_Notice(
          // A line about a group of friends itself ("Ann added Dan") is its own words.
          icon: m.notice == 'call' ? LucideMore.phoneCall : (m.notice == 'group' ? Lucide.users : (m.notice == 'key' ? Lucide.keyRound : Lucide.image)),
          text: m.notice == 'group' || m.notice == 'call' ? m.body : (m.notice == 'key' ? (m.outgoing ? 'You sent your encryption key' : '$who sent an encryption key') : '$who changed the chat background'),
          busy: busy,
          onLongPress: () => _messageMenu(m),
        ));
        if (older == null || !_sameDay(older.date, m.date)) items.add(_DayHeading(date: m.date, busy: busy));
        return items;
      }
      final firstOfRun = !joins(older, m) || !_sameDay(older!.date, m.date);
      final lastOfRun = !joins(newer, m) || !_sameDay(newer!.date, m.date);
      final failed = m.state == 'failed';
      final showStatus = m.outgoing && (m.key == lastOutgoingKey || failed || m.state == 'sending' || m.state == 'waiting');
      // Under the bubble (drawn first: the list is drawn bottom up), what the plugins put there: a link's card, things
      // to do with what it says.
      final under = m.state == 'sending' || m.state == 'waiting' ? const <Widget>[] : _plugins.under(context, m);
      if (under.isNotEmpty) {
        items.add(Padding(
          padding: EdgeInsets.only(left: m.outgoing ? t.lenOf('3rem') : t.space(3) + (_group ? t.lenOf('2.1rem') : 0), right: m.outgoing ? t.space(3) : t.lenOf('3rem'), top: t.space(1), bottom: t.space(1)),
          child: Align(
            alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
            child: OnBackground(busy: busy, child: Column(crossAxisAlignment: m.outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: under)),
          ),
        ));
      }
      items.add(Poof(
        key: ValueKey('poof-${m.key}'),
        gone: _poofing.contains(m.key),
        side: m.outgoing ? AxisDirection.right : AxisDirection.left,
        onDone: () => _gone(m),
        // What the plugins show its words as (a translation, lib/plugins/translate.dart): the bubble says that, and a
        // dimmed card over it the words as they came.
        child: ShownWords(
        facts: _wordsFacts(m),
        builder: (_, shown) => _Bubble(
        message: m,
        shown: shown,
        sender: _group && !m.outgoing && firstOfRun ? (_senders[m.address]?.label ?? m.address) : null,
        senderPerson: _group && !m.outgoing ? _senders[m.address] : null,
        showFace: _group && !m.outgoing && lastOfRun,
        group: _group,
        top: firstOfRun,
        bottom: lastOfRun,
        status: showStatus ? _statusText(m) : (lastOfRun ? clock(m.date) : null),
        onLongPress: (at) => _messageMenu(m, at),
        // A picture that could not be brought down: asked for again from here (the phone's to do, not a computer's).
        onRetryDownload: m.state == 'pending_download' && Sms.can('retryDownload')
            ? () async {
                try {
                  await Sms.instance.retryDownload(m);
                } catch (e) {
                  if (mounted) toast(context, 'Couldn\'t try again: $e', tone: GlacierToastTone.danger);
                }
                _load();
              }
            : null,
        onTapFailed: failed && _canRetry(m) ? () => _retry(m) : null,
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
      ))));
      if (_group && m.key == _firstNewKey) items.add(Padding(key: const ValueKey('new-messages'), padding: EdgeInsets.symmetric(horizontal: t.space(3)), child: const NewMessagesDivider()));
      if (older == null || !_sameDay(older.date, m.date)) items.add(_DayHeading(date: m.date, busy: busy));
    return items;
  }

  /// [_list] as Dial-Up writes it: one transcript in a white well, each message a line, "Name: words", no faces and no
  /// bubbles (Matt, 2026-11-16: "base one of them heavily on the old AOL chatrooms"). The room's own speaker says where
  /// it starts, that it is sealed, what a key or a background was, and where the day turns. What a message does (held
  /// down, tapped to try again, its reactions, its pictures and cards) is as it is in a bubble.
  Widget _lines(Tokens t, ChatBackground background, String title) {
    final c = DialupColors.of(t);
    final msgs = _folded.messages;
    final items = <Widget>[];
    final mediaWidth = math.min(MediaQuery.sizeOf(context).width * 0.7, 320.0);
    String? lastOutgoingKey;
    for (final m in msgs) {
      if (m.outgoing && !_isLine(m)) { lastOutgoingKey = m.key; break; }
    }
    String nameOf(Message m) => m.outgoing ? 'You' : (_senders[m.address]?.label ?? (_people.length == 1 ? _people.first.label : (m.address.isEmpty ? 'They' : m.address)));
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final newer = i > 0 ? msgs[i - 1] : null;
      final older = i < msgs.length - 1 ? msgs[i + 1] : null;
      // Souls sent, as the room's speaker says it (lib/ui/souls_send.dart; GMFB-39).
      final souls = _soulsCardOf(m);
      if (souls != null) {
        items.add(_soulsCard(souls, msgs, i, line: (words) => HostLine(words, onLongPress: () => _messageMenu(m))));
        if (older == null || !_sameDay(older.date, m.date)) items.add(HostLine.day(m.date));
        continue;
      }
      if (_isLine(m)) {
        final who = nameOf(m);
        items.add(HostLine(
          m.notice == 'group' || m.notice == 'call' ? m.body : (m.notice == 'key' ? (m.outgoing ? 'You sent your encryption key.' : '$who sent an encryption key.') : '$who changed the chat background.'),
          onLongPress: () => _messageMenu(m),
        ));
        if (older == null || !_sameDay(older.date, m.date)) items.add(HostLine.day(m.date));
        continue;
      }
      final failed = m.state == 'failed';
      final showStatus = m.outgoing && (m.key == lastOutgoingKey || failed || m.state == 'sending' || m.state == 'waiting');
      // A time only where a run from one person ends, as under bubbles; most of the era's rooms showed none at all.
      final lastOfRun = newer == null || _isLine(newer) || newer.outgoing != m.outgoing || newer.address != m.address || newer.date.difference(m.date).inMinutes.abs() >= 3 || !_sameDay(newer.date, m.date);
      final sent = sentWith(m.body);
      final unopened = m.notice == 'undecryptable';
      final media = <Widget>[
        for (final a in m.attachments)
          if (a.isSticker)
            // At most 96px in a transcript (the design), on the page with nothing round it.
            _Sticker(id: a.id, side: math.min(96, mediaWidth))
          else if (a.isImage)
            _Picture(id: a.id, radius: BorderRadius.zero, maxWidth: mediaWidth, onTap: failed && _canRetry(m) ? () => _retry(m) : null)
          else if (a.isVideo)
            VideoBubble(video: a, radius: BorderRadius.zero, maxWidth: mediaWidth, ground: c.chrome, ink: c.onChrome, received: !m.outgoing, title: nameOf(m))
          else if (a.isAudio)
            VoiceBubble(part: a.id, ground: c.chrome, ink: c.onChrome, radius: BorderRadius.zero, rim: Border.all(color: c.shadow), playable: true)
          else
            TextAttachmentPill(attachment: a, ground: c.chrome, ink: c.onChrome),
        if (m.state == 'downloading' || m.state == 'pending_download')
          _Undelivered(
            downloading: m.state == 'downloading',
            ground: c.chrome,
            ink: c.onChrome,
            onRetry: m.state == 'pending_download' && Sms.can('retryDownload')
                ? () async {
                    try {
                      await Sms.instance.retryDownload(m);
                    } catch (e) {
                      if (mounted) toast(context, 'Couldn\'t try again: $e', tone: GlacierToastTone.danger);
                    }
                    _load();
                  }
                : null,
          ),
      ];
      final reactions = _folded.reactions[m.key] ?? const <Reaction>[];
      items.add(Poof(
        key: ValueKey('poof-${m.key}'),
        gone: _poofing.contains(m.key),
        side: m.outgoing ? AxisDirection.right : AxisDirection.left,
        onDone: () => _gone(m),
        child: ShownWords(
          facts: _wordsFacts(m),
          builder: (_, shown) => MessageLine(
          name: nameOf(m),
          // Yours in your colour, the other person's in theirs; in a group each keeps one of six, picked by their address.
          nameColor: m.outgoing ? c.nameMine : (_group ? c.nameFor(m.address) : c.nameTheirs),
          mine: m.outgoing,
          body: unopened ? 'Encrypted message that can\'t be opened on this phone' : (shown?.bubble ?? sent.text),
          // The words as they came, as a dim line under a translated one (lib/ui/translated_card.dart).
          original: shown == null ? null : OriginalLine(view: shown),
          italic: unopened,
          concealed: sent.bubble == BubbleEffect.invisibleInk && !_revealed.contains(m.key),
          onReveal: () => setState(() => _revealed.add(m.key)),
          media: media,
          under: m.state == 'sending' || m.state == 'waiting' ? const <Widget>[] : _plugins.under(context, m),
          status: showStatus ? _statusText(m) : (lastOfRun ? clock(m.date) : null),
          failed: failed,
          onTapFailed: failed && _canRetry(m) ? () => _retry(m) : null,
          reactions: [for (final r in reactions) r.emoji],
          onReactionsTap: () => _showReactions(reactions),
          edited: m.edited ? (_corrected.contains(m.key) ? 'Edited · correction sent' : 'Edited') : null,
          onEditedTap: m.edited ? () => _showOriginal(m) : null,
          highlighted: _editing?.key == m.key,
          onLongPress: (at) => _messageMenu(m, at),
        )),
      ));
      if (older == null || !_sameDay(older.date, m.date)) items.add(HostLine.day(m.date));
    }
    if (_older) {
      items.add(SkeletonChat(label: 'Loading earlier messages…', most: 3, shrink: true, faces: _group));
    } else {
      // The top of the conversation, where the era's room said who you had walked in on.
      if (_e2e.on) items.add(const HostLine('Messages here are sealed end to end.'));
      items.add(HostLine('*** You are in "$title". ***'));
    }
    return Transcript(
      overBackground: !background.isNone,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (_older && !_readingOlder && n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 900) _readOlder();
          return false;
        },
        // The arrow inside the well, at its corner: a raised square button, as the room's own are.
        child: JumpToLatest(
          controller: _scroll,
          chat: _spot,
          incoming: _incoming,
          inset: const EdgeInsets.only(right: 8, bottom: 8),
          child: ListView(
            controller: _scroll,
            reverse: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: items,
          ),
        ),
      ),
    );
  }


  /// Drawn as a line in the conversation, not a bubble: a text that carried a key or a chat background.
  static bool _isLine(Message m) => m.notice == 'key' || m.notice == 'background' || m.notice == 'group' || m.notice == 'call';

  static const _evenLeading = TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even);

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// A picture message says why, where the phone was told (Matt: "almost like MMS isn't working"); trying again is
  /// a tap, where it can be tried from here ([_canRetry]).
  String _notSent(Message m) {
    final said = m.why == null || m.why!.isEmpty ? 'Not sent' : 'Not sent: ${m.why}';
    return _canRetry(m) ? '$said. Tap to try again.' : said;
  }

  /// Whether [m], which did not go, can be sent again from here: always on the phone; on a computer where the phone
  /// it is paired with does that for one (a picture message goes again whole, a text is deleted and sent anew).
  static bool _canRetry(Message m) => Sms.can(m.kind == 'mms' ? 'resendMms' : 'deleteMessage');

  /// The line under your own message: where it stands, with the time once it has gone.
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
    final isMms = !_isGhost && (_group || _attachments.isNotEmpty);
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
    return _FootGround(
      child: Padding(
        padding: composerFootPadding(t),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Both phones have Ghost Messaging and nothing has been exchanged: encryption is offered, until it is
          // turned on or the banner is dismissed (Matt, 2026-11-13: "a banner that can be dismissed asking the user
          // to enable encryption for better security").
          // They asked to be friends: said here until it is answered.
          if (!Sms.paired && !_group && _people.isNotEmpty && _e2e.on && _e2e.friend == 'invited')
            _E2eBar(
              icon: Lucide.userPlus,
              text: '${_people.first.label} wants to add you as a friend. Friends chat over the internet, encrypted, not by text.',
              action: 'Accept',
              onAction: () => _answerFriend(true),
              onPress: () {},
              onDismiss: () => _answerFriend(false),
            ),
          // Both have Ghost Messaging and nothing has been said about being friends (Matt, 2026-11-14: "If both
          // users chatting are on ghost messenger show an 'add friend' button"): offered where a relay server
          // answers, until it is asked or put away. It stands in for the offer of encryption below, which adding a
          // friend turns on.
          if (_offersFriend(context))
            _E2eBar(
              icon: Lucide.userPlus,
              text: '${_people.first.label} has Ghost Messaging too. Friends chat over the internet, encrypted, not by text.',
              action: 'Add friend',
              onAction: _addFriend,
              onPress: () {},
              onDismiss: () => AppState.of(context).setFlag('friend_banner_${widget.thread}', false),
            ),
          if (_e2e.friend == 'want' || _e2e.friend == 'asked')
            _E2eBar(
              icon: Lucide.userCheck,
              text: 'Friend request sent. Waiting for ${_people.isEmpty ? 'them' : _people.first.label} to accept.',
              onPress: () {},
            ),
          if (!_offersFriend(context) && Sms.can('e2eOffer') && !_group && _people.isNotEmpty && _e2e.offerable && AppState.of(context).flag('e2e_banner_${widget.thread}'))
            _E2eBar(
              text: '${_people.first.label} has Ghost Messaging too. Encrypt this conversation for better security?',
              action: 'Turn on',
              onAction: _e2eStart,
              onPress: () => showEncryptionChoices(context, _people.first, _e2e, _e2eChanged),
              onDismiss: () => AppState.of(context).setFlag('e2e_banner_${widget.thread}', false),
            ),
          // Encryption is on and their texts are coming without it (Matt, 2026-11-14: "we need to be able to detect
          // if a user is sending us unencrypted messages and let us know so we can disable it"): said here, with Turn
          // off beside it. Put away, it comes back with their next plain text; it goes by itself when one comes sealed.
          // Where encryption cannot be turned off from here (a computer whose phone has an older app) it is said and
          // not offered.
          if (!_group && _people.isNotEmpty && _e2e.plainWarning)
            _E2eBar(
              warning: true,
              text: '${_people.first.label}\'s ${_e2e.plain == 1 ? 'last text' : 'last ${_e2e.plain} texts'} came without encryption. '
                  'They may have turned it off or changed phones, and then can\'t read what you send.${Sms.can('e2eOff') ? '' : ' Turn it off from the phone.'}',
              action: Sms.can('e2eOff') ? 'Turn off' : null,
              onAction: _e2eStop,
              onPress: Sms.can('e2eOff') ? () => showEncryptionChoices(context, _people.first, _e2e, _e2eChanged) : () {},
              onDismiss: Sms.can('e2ePlainSeen') ? () => Sms.instance.e2ePlainSeen(_people.first.address).then((_) => _e2eChanged()).catchError((_) {}) : null,
            ),
          if (Sms.can('e2eOffer') && !_group && _people.isNotEmpty && (_e2e.state == 'pending' || (_e2e.state == 'offered' && _e2e.friend.isEmpty)))
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
              child: Text('${_mms!.obstacle}.', style: pageText(t, t.fontSize('xs'), color: t.danger)),
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
          // The field, with everything in its box (Matt, 2026-11-15: "Put the plus symbol inside thr compose input and
          // animate them below when typijg just like this screenshot"): empty, Add an attachment at its start and the
          // stickers and microphone at its end; once there are words they have the whole width and the buttons slide
          // into a row under them, Send at its end. The words' field keeps its place in the tree whichever way it is
          // laid out, so the keyboard stays up as it changes.
          Builder(builder: (context) {
            final typing = _text.text.isNotEmpty || editing;
            final hint = _isGhost ? 'Message' : isMms ? 'Picture message' : (sealed ? 'Encrypted message' : 'Text message');
            final field = Listener(
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
                          composerHint(IgnorePointer(child: Text(hint, style: composerText.copyWith(color: t.color('app-ink-3')), strutStyle: composerStrut, textHeightBehavior: _evenLeading))),
                        // On a computer the paste keys bring in a picture on the clipboard first, then words as ever
                        // (Matt, 2026-11-16: "add the ability to paste images into the chatbar on desktop"; on the Mac
                        // the window catches ⌘V ahead of its Edit menu: lib/ui/paste_images.dart).
                        // Named and pressed into in a browser's tree for screen readers (composerSemantics).
                        composerSemantics(
                          hint: hint,
                          onPress: () {
                            _focus.requestFocus();
                            _field.currentState?.requestKeyboard();
                          },
                          child: PasteImages(
                          focusNode: _focus,
                          enabled: Sms.remote && _attachments.length < 5,
                          onImage: (path) => setState(() => _attachments.add(path)),
                          child: KeyedSubtree(
                            child: EditableText(
                          key: _field,
                          controller: _text,
                          focusNode: _focus,
                          style: composerText,
                          strutStyle: composerStrut,
                          textHeightBehavior: _evenLeading,
                          cursorColor: t.color('app-ink'),
                          backgroundCursorColor: t.color('app-ink-3'),
                          selectionColor: t.textSelection,
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
                          ),
                        ),
                        ),
                      ]),
                    ),
                      ),
                    ));
            // The same buttons in the same places as every other conversation (lib/ui/composer_box.dart), each greyed out
            // where this one can't do it.
            final reach = !_isGhost && !_byName && !editing && _people.isNotEmpty;
            final buttons = composerButtons(
              t,
              hasSomething: _text.text.isNotEmpty || _attachments.isNotEmpty || editing,
              // To a friend by username, where pictures can't go yet, the + offers what can: Send souls (GMFB-39).
              onAttach: Sms.can('sendPictures') && !_isGhost && !_byName && !editing && _attachments.length < 5 ? _attach : (!editing && _soulsFriend != null ? _plusForFriend : null),
              onSticker: Sms.can('sendSticker') && reach && !_sending && _attachments.isEmpty ? _sticker : null,
              onRecord: Sms.can('sendVoice') && Sms.canRecordVoice && reach && !_sending && _attachments.isEmpty ? _record : null,
              onSend: canSend ? _send : null,
              emoji: Sms.remote,
              // The app's own picker (lib/ui/emoji_picker.dart), into the box where the cursor is.
              onEmoji: () async {
                await showEmojiPicker(context, onPick: (e) => insertEmoji(_text, e));
                if (mounted) _focus.requestFocus();
              },
              send: editing ? IconTap(key: const ValueKey('composer-send'), icon: Lucide.check, label: 'Save edit', filled: true, size: 16, box: t.lenOf('2.25rem'), onPressed: canSend ? _saveEdit : null) : null,
              onSendMenu: editing ? null : _sendMenu,
            );
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              EmojiSuggestions(suggester: _shortcodes),
              if (!editing) ScheduledStrip(to: _scheduleTarget),
              ComposerBox(field: field, typing: typing, plus: buttons.plus, ends: buttons.ends, below: buttons.below),
            ]);
          }),
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
    // Words chosen to a friend: made bold, italic or code from here too (GMFB-35), the markers put round them.
    final chosen = _text.selection;
    final format = chosen.isValid && !chosen.isCollapsed && (_text.dims?.call() ?? true);
    ContextMenuButtonItem wrap(String label, String marker) => ContextMenuButtonItem(
          label: label,
          onPressed: () {
            _text.wrapSelection(marker);
            state.hideToolbar();
          },
        );
    final items = [
      ...state.contextMenuButtonItems,
      if (format) ...[wrap('Bold', '**'), wrap('Italic', '*'), wrap('Code', '`')],
    ];
    final width = MediaQuery.sizeOf(context).width;
    final left = (state.contextMenuAnchors.primaryAnchor.dx - 120).clamp(8.0, math.max(8.0, width - 248)).toDouble();
    return Stack(children: [
      Positioned(
        left: left,
        top: (state.contextMenuAnchors.primaryAnchor.dy - 56).clamp(8.0, double.infinity),
        child: Container(
          constraints: BoxConstraints(maxWidth: math.max(0.0, width - left - 8)),
          padding: EdgeInsets.all(t.space(1)),
          decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('md'))),
          // More than fit across (with Bold, Italic and Code on a phone) scroll sideways.
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final item in items)
              GlacierPressable(
                onPressed: item.onPressed,
                builder: (context, s) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                  child: Text(_label(item.type, item.label), style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-paper'))),
                ),
              ),
          ])),
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
  const _E2eBar({required this.text, required this.onPress, this.action, this.onAction, this.onDismiss, this.warning = false, this.icon});
  final String text;

  /// The mark at its start, where it is not the lock: a friend's.
  final LucideIcon? icon;

  /// Something is wrong, not waiting: a warning's mark in place of the lock.
  final bool warning;
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
            if (warning) AppIcon(Lucide.triangleAlert, size: 16, color: t.warn, wash: false) else AppIcon(icon ?? Lucide.lock, size: 16, color: t.color('app-ink-2')),
            SizedBox(width: t.space(2)),
            Expanded(child: Text(text, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink'), height: 1.3))),
            if (action != null) ...[
              SizedBox(width: t.space(2)),
              GlacierPressable(
                onPressed: onAction,
                semanticLabel: action,
                builder: (context, s) => Container(
                  padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                  decoration: BoxDecoration(color: t.color(s.pressed ? 'app-ink-2' : 'app-ink'), borderRadius: BorderRadius.circular(lookCorner(t, '1rem', most: 1))),
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

/// The day, centred above the first message of each day.
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

/// One message drawn: its words and attachments in a bubble, the sender's name and face where the list asks for
/// them, its reactions, and the status line where one is given.
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
    this.shown,
  });

  final Message message;

  /// What a plugin shows its words as (lib/ui/translated_card.dart): the bubble says [ShownView.bubble], and a card
  /// over it the words as they came.
  final ShownView? shown;
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
    final body = unopened ? 'Encrypted message that can\'t be opened on this phone' : (shown?.bubble ?? sent.text);
    final app = AppState.of(context);
    final out = m.outgoing;
    final failed = m.state == 'failed';
    // On a computer a bubble is a size smaller than on the phone: its words, the room round them and its corners
    // (Matt, 2026-11-14: "the chat bubbles are a bit too large on mac"). A window is read from further off than a
    // phone is held, but it is also far wider, and the phone's bubbles filled it.
    final desk = Sms.computer;
    final size = desk ? 0.88 : 1.0;
    final big = lookCorner(t, desk ? '1rem' : '1.15rem', most: 1);
    final small = lookCorner(t, '0.3rem', most: 1);
    final radius = BorderRadius.only(
      topLeft: Radius.circular(!out && !top ? small : big),
      bottomLeft: Radius.circular(!out && !bottom ? small : big),
      topRight: Radius.circular(out && !top ? small : big),
      bottomRight: Radius.circular(out && !bottom ? small : big),
    );
    // Your own bubbles: this conversation's colour, else everywhere's (Settings › Appearance).
    final (mine, onMine) = myBubble(t, app, thread);
    final ground = out ? (failed ? t.failedGround : mine) : theirBubble(t, onBackground: onBackground);
    final ink = out && !failed ? onMine : t.color('app-ink');
    // A look that rims bubbles (Sharp, Phosphor) rims a failed one of yours in the failure's red, as its dark half's
    // near-black failed ground already got a rim and its light half's pink one did not.
    final failedRim = failed && theirRim(t) != null ? Border.all(color: t.danger, width: 1.5) : null;
    final maxWidth = MediaQuery.sizeOf(context).width * (desk ? 0.62 : 0.76);
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
            child: VideoBubble(video: a, radius: radius, maxWidth: maxWidth, ground: ground, ink: ink, received: !out, title: out ? 'You' : sender),
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
              rim: (out ? failedRim : theirRim(t)) ?? (!onBackground && bubbleNeedsRim(ground, t.color('glacier-bg')) ? Border.all(color: t.color('app-rule')) : null),
              playable: true,
            ),
          )
        else
          // Any other file (a contact's card, a PDF): a press opens, saves or shares it (lib/ui/text_attachment.dart).
          TextAttachmentPill(attachment: a, ground: ground, ink: ink),
      // A picture message the carrier announced that is not here: coming down now, or it could not be, with a way to
      // ask for it again (Matt, 2026-11-13: "show the failed image with a retry if needed").
      if (m.state == 'downloading' || m.state == 'pending_download') _Undelivered(downloading: m.state == 'downloading', ground: ground, ink: ink, onRetry: onRetryDownload),
      // The words as they came, dimmed, in a card over a translated bubble (Matt, 2026-11-17: "show the original text
      // dimmed in a card with the translated text for the actual message bubble").
      if (shown != null && body.isNotEmpty && !jumbo && !unopened) OriginalCard(view: shown!, maxWidth: maxWidth, mine: out, scale: app.textScale * size),
      if (body.isNotEmpty && jumbo)
        // One to three emoji and nothing else: large, on the page, with no bubble.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(1)),
          child: Text(body.trim(), style: pageText(t, t.lenOf(emojis == 1 ? '3.2rem' : '2.5rem') * size, color: t.color('app-ink'), height: 1.2)),
        )
      else if (body.isNotEmpty)
        Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: desk ? EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2) - 2) : EdgeInsets.symmetric(horizontal: t.space(3) + 2, vertical: t.space(2)),
          // A bubble the page would swallow (white on the light page) wears a line round it.
          decoration: BoxDecoration(color: ground, borderRadius: radius, border: (out ? failedRim : theirRim(t)) ?? (!onBackground && bubbleNeedsRim(ground, t.color('glacier-bg')) ? Border.all(color: t.color('app-rule')) : null)),
          child: unopened
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon(Lucide.lock, size: 14, strokeWidth: 2.2, wash: false, color: ink),
                  SizedBox(width: t.space(2)),
                  Flexible(child: Text(body, style: pageText(t, t.fontSize('sm') * app.textScale * size, color: ink, height: 1.35).copyWith(fontStyle: FontStyle.italic))),
                ])
              : LinkedText(
                  body,
                  ink: ink,
                  // Settings › Appearance › Text size.
                  style: pageText(t, t.fontSize('md') * app.textScale * size, color: ink, height: 1.35),
                  // An "@username" pressed opens who it is on Ghost (Matt, 2026-11-19: "when clicking on a @mention
                  // anywhere ... show this profile popup").
                  mentions: handleMentions(body),
                  mentionStyle: mentionStyle(t, on: ink),
                  onMention: (m) => showProfile(context, subjectOfMention(m.id)),
                ),
        ),
    ];
    // A message with nothing in it to draw (a picture message whose picture this phone was never told of) is still a
    // message: a pill says what it was, where only its "Delivered" stood (Matt, 2026-11-19).
    if (content.isEmpty) content.add(_Pill(text: m.outgoing ? 'Picture or file, not kept on this phone' : 'Attachment', ground: ground, ink: ink));

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
          // Measured against the pane the conversation is in, which is where what it brings up is drawn: beside
          // the list (lib/ui/shell.dart) that is not the whole window.
          final pane = Navigator.of(at).context.findRenderObject();
          if (box is RenderBox && box.hasSize) onLongPress(box.localToGlobal(Offset.zero, ancestor: pane) & box.size);
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
        decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: t.chosen, width: 2)),
        child: bubble,
      );
    }
    if (reactions.isNotEmpty) {
      // Stickers on its lower edge and corners, each kind its own, a little askew (lib/ui/reaction_stickers.dart; Matt,
      // 2026-11-17: "Make reactions pin at randomish places slightly askue so multiple reactions look like stickers").
      final kinds = <String, int>{};
      for (final r in reactions) {
        kinds[r.emoji] = (kinds[r.emoji] ?? 0) + 1;
      }
      bubble = ReactionStickers(bubble: bubble, seed: message.key, kinds: [for (final e in kinds.entries) (emoji: e.key, count: e.value)], onTap: onReactionsTap);
    }
    final faceGap = group && !out ? faceSize + t.space(2) : 0.0;

    return Padding(
      padding: EdgeInsets.only(top: top ? t.space(2) : 2),
      child: Column(
        crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (sender != null)
            Padding(
              // On the same left edge as the time under the bubble (Matt, 2026-11-16: "Make sure the username and the
              // timestamp are aligned on the same left side of the bubble").
              padding: EdgeInsets.only(left: (group ? faceSize + t.space(2) : 0) + t.space(2), bottom: 2),
              // A sender's name over their bubble in the app's primary colour (Matt, 2026-11-16: "Make the names of people above
              // chat bubbles the primary color"): the accent chosen in Settings, as the read ticks are.
              child: OnBackground(busy: busy, child: Text(sender!, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-accent')))),
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
                if (failed) ...[Padding(padding: const EdgeInsets.only(top: 2), child: AppIcon(Lucide.circleAlert, size: 12, color: t.danger)), const SizedBox(width: 4)],
                // It travelled sealed, and was opened here.
                if (m.encrypted) ...[Semantics(label: 'Encrypted', child: AppIcon(Lucide.lock, size: 11, strokeWidth: 2.4, wash: false, color: t.color('app-ink-3'))), const SizedBox(width: 4)],
                // It came or went by the internet, between friends, not as a text.
                if (m.via == 'net') ...[Semantics(label: 'Sent over the internet', child: AppIcon(Lucide.globe, size: 11, strokeWidth: 2.4, wash: false, color: t.color('app-ink-3'))), const SizedBox(width: 4)],
                // Why a message did not go can run to two lines: it wraps under the bubble, where a time never needs to.
                Flexible(child: Text(status!, textAlign: out ? TextAlign.end : TextAlign.start, style: pageText(t, t.fontSize('xs'), color: failed ? t.danger : t.color('app-ink-3')))),
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
                      // Read in the app's accent, the colour chosen for your bubbles (Matt, 2026-11-15: "The read
                      // checkmarks should be the same color as the apps selected primary color").
                      color: m.state == 'read' ? t.color('app-accent') : t.color('app-ink-3'),
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
      decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(lookCorner(t, '1.1rem', most: 1))),
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
                decoration: BoxDecoration(color: ink.withValues(alpha: state.pressed ? 0.24 : 0.14), borderRadius: BorderRadius.circular(lookCorner(t, '1rem', most: 1))),
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

/// The composer's strip, coloured where it is drawn: under Dial-Up it stands in GhostPage's silver foot, whose
/// `.dialup-panel` makes the ground the window's face and whose light edge replaces the rule, where the page's own
/// tokens, read before, painted it white between two silver strips (the review of the looks, 2026-11-16).
class _FootGround extends StatelessWidget {
  const _FootGround({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(color: t.color('glacier-bg'), border: isDialup(context) ? null : Border(top: BorderSide(color: t.color('app-rule')))),
      child: child,
    );
  }
}

/// An attachment that is not drawn (a file, or one this phone no longer has): a file mark and its name or kind.
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
      decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(lookCorner(t, '1rem', most: 1))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(Lucide.fileCode, size: 14, color: ink),
        SizedBox(width: t.space(1)),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: ink))),
      ]),
    );
  }
}

/// A message's picture, read from the phone by its part's [id]; a tap opens it over the whole screen ([_Viewer]).
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
            // Grown a little into place over the darkening (the barrier's own fade), not faded: cheaper to draw.
            transitionsBuilder: (context, a, _, child) => ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
          )),
          child: ClipRRect(
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxWidth * 1.3),
              // One that cannot be drawn keeps its place as the grey of one coming: it drew as nothing at all, and
              // a picture message showed only its "Delivered".
              child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: (maxWidth * MediaQuery.devicePixelRatioOf(context)).round(), gaplessPlayback: true,
                  errorBuilder: (context, _, _) => Container(width: maxWidth * 0.7, height: maxWidth * 0.7, decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: radius))),
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

/// A picture over the whole screen; a tap anywhere closes it.
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
                      color: mine.contains(emoji) ? t.chosenWash : t.color('app-paper-3'),
                      border: mine.contains(emoji) ? Border.all(color: t.chosen, width: 2) : null,
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

/// A message's words with its links underlined, and a press on one opening it in the browser (lib/links.dart).
/// A long press is still the message's own, wherever it lands.
///
/// And drawn with the formatting written into them (GMFB-35, lib/message_format.dart): bold, italic, strike, code and
/// blocks of it, quotes behind a bar, and spoilers as a block of ink until pressed. The markers are not drawn; links
/// and mentions work inside formatting as outside it, and nothing in code is a link.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {super.key, required this.ink, required this.style, this.before = const [], this.after = const [], this.mentions = const [], this.mentionStyle, this.onMention});
  final String text;
  final Color ink;
  final TextStyle style;

  /// The "@Name"s in [text] that mean someone (lib/mentions.dart), drawn in [mentionStyle] and pressed for [onMention]
  /// (Matt, 2026-11-19: "Add mentions support to spaces and circles with the @user prefix"). A link inside one is
  /// part of the mention.
  final List<Mention> mentions;
  final TextStyle? mentionStyle;
  final ValueChanged<Mention>? onMention;

  /// Drawn in the same run of words, before and after the message's own: Dial-Up's bold "Name: " and its small status,
  /// so a wrapped line goes back to the left edge under the name (lib/ui/message_line.dart).
  final List<InlineSpan> before, after;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  List<MessageLink> _links = const [];
  final List<TapGestureRecognizer> _taps = [];
  List<Mention> _mentions = const [];
  final List<TapGestureRecognizer> _mentionTaps = [];
  MessageFormat _format = MessageFormat.parse('');
  final List<TapGestureRecognizer> _spoilerTaps = [];

  /// The spoilers pressed open.
  final Set<int> _revealed = {};

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(LinkedText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || !listEquals(old.mentions, widget.mentions) || (old.onMention == null) != (widget.onMention == null)) _read();
  }

  /// Finds the links and mentions in the words and makes a tap for each; a link inside a mention is left to the
  /// mention. The old taps are let go first.
  void _read() {
    for (final t in [..._taps, ..._mentionTaps, ..._spoilerTaps]) {
      t.dispose();
    }
    _taps.clear();
    _mentionTaps.clear();
    _spoilerTaps.clear();
    _revealed.clear();
    _mentions = Mention.checked(widget.mentions, widget.text);
    bool inMention(MessageLink l) => _mentions.any((m) => l.start < m.end && l.end > m.start);
    _links = [for (final l in MessageLink.find(widget.text)) if (!inMention(l)) l];
    _format = MessageFormat.parse(widget.text, keep: [for (final m in _mentions) (m.start, m.end)], links: [for (final l in _links) (l.start, l.end)]);
    for (final link in _links) {
      _taps.add(TapGestureRecognizer()..onTap = () => _open(link.address));
    }
    for (final m in _mentions) {
      _mentionTaps.add(TapGestureRecognizer()..onTap = () => widget.onMention?.call(m));
    }
    for (var i = 0; i < _format.spoilers; i++) {
      _spoilerTaps.add(TapGestureRecognizer()..onTap = () => setState(() => _revealed.add(i)));
    }
  }

  Future<void> _open(String address) async {
    var opened = false;
    try {
      opened = await Sms.instance.openLink(address);
    } catch (_) {}
    if (!opened && mounted) toast(context, 'Couldn\'t open that link', tone: GlacierToastTone.danger);
  }

  @override
  void dispose() {
    for (final t in [..._taps, ..._mentionTaps, ..._spoilerTaps]) {
      t.dispose();
    }
    super.dispose();
  }

  /// How a formatted stretch looks, over the words' own style.
  TextStyle? _look(FormatRun r) {
    if (r.flags == 0) return null;
    final ink = widget.ink;
    final size = widget.style.fontSize ?? 14;
    final lines = <TextDecoration>[
      if (r.has(Fmt.strike)) TextDecoration.lineThrough,
      if (r.has(Fmt.link)) TextDecoration.underline,
    ];
    return TextStyle(
      fontWeight: r.has(Fmt.bold) ? FontWeight.w700 : null,
      fontStyle: r.has(Fmt.italic) ? FontStyle.italic : null,
      decoration: lines.isEmpty ? null : TextDecoration.combine(lines),
      decorationColor: lines.isEmpty ? null : ink,
      color: r.has(Fmt.quote) ? ink.withValues(alpha: 0.72) : null,
      fontFamily: r.has(Fmt.code) ? 'JetBrains Mono Variable' : null,
      fontSize: r.has(Fmt.code) ? size * 0.9 : null,
      backgroundColor: r.has(Fmt.code) ? ink.withValues(alpha: 0.1) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final ink = widget.ink;
    final spans = <InlineSpan>[...widget.before];
    // Links and mentions in the order they come in the words (none over another: a link in a mention was left out).
    final marks = <(int, int, bool, int)>[
      for (var i = 0; i < _links.length; i++) (_links[i].start, _links[i].end, false, i),
      for (var i = 0; i < _mentions.length; i++) (_mentions[i].start, _mentions[i].end, true, i),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    // Cut where a formatted stretch, a link or a mention begins or ends; each piece drawn as all three say.
    final cuts = <int>{0, text.length, for (final r in _format.runs) ...[r.start, r.end], for (final m in marks) ...[m.$1, m.$2]}.toList()..sort();
    var ri = 0, mi = 0;
    for (var c = 0; c + 1 < cuts.length; c++) {
      final a = cuts[c], b = cuts[c + 1];
      if (b <= a) continue;
      while (ri < _format.runs.length && _format.runs[ri].end <= a) {
        ri++;
      }
      while (mi < marks.length && marks[mi].$2 <= a) {
        mi++;
      }
      final r = ri < _format.runs.length ? _format.runs[ri] : FormatRun(a, b, 0);
      if (r.marker) continue;
      if (r.bar) {
        // A quote's "> " as a bar at the line's start.
        if (a == r.start) spans.add(TextSpan(text: '\u258D ', style: TextStyle(color: ink.withValues(alpha: 0.45), fontWeight: FontWeight.w700, fontStyle: FontStyle.normal)));
        continue;
      }
      final words = text.substring(a, b);
      final mark = mi < marks.length && marks[mi].$1 <= a && marks[mi].$2 >= b ? marks[mi] : null;
      final hidden = r.spoiler >= 0 && !_revealed.contains(r.spoiler);
      var style = _look(r);
      if (r.spoiler >= 0) {
        // Ink on ink until pressed; then a faint wash says it was one.
        style = (style ?? const TextStyle()).merge(hidden ? TextStyle(color: ink, backgroundColor: ink, decorationColor: ink) : TextStyle(backgroundColor: ink.withValues(alpha: 0.1)));
      }
      if (hidden) {
        spans.add(TextSpan(text: words, style: style, recognizer: _spoilerTaps[r.spoiler], mouseCursor: SystemMouseCursors.click, semanticsLabel: 'Spoiler, tap to reveal'));
        continue;
      }
      // Nothing in code is a link.
      final code = r.has(Fmt.code);
      if (mark != null && mark.$3) {
        final m = _mentions[mark.$4];
        final press = widget.onMention != null;
        spans.add(TextSpan(
          text: words,
          style: (style ?? const TextStyle()).merge(widget.mentionStyle ?? const TextStyle(fontWeight: FontWeight.w600)),
          recognizer: press ? _mentionTaps[mark.$4] : null,
          mouseCursor: press ? SystemMouseCursors.click : null,
          semanticsLabel: a == m.start && b == m.end ? 'Mention: ${words.substring(1)}' : null,
        ));
      } else if ((mark != null && !code) || r.link >= 0) {
        // A link as written, or the words of a [words](address) one.
        final i = r.link >= 0 ? r.link : mark!.$4;
        spans.add(TextSpan(
          text: words,
          style: (style ?? const TextStyle()).merge(TextStyle(decoration: TextDecoration.underline, decorationColor: ink)),
          recognizer: _taps[i],
          mouseCursor: SystemMouseCursors.click,
          semanticsLabel: r.link >= 0 ? 'Link: $words, ${_links[i].address}' : 'Link: $words',
        ));
      } else {
        spans.add(TextSpan(text: words, style: style));
      }
    }
    spans.addAll(widget.after);
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}

/// Why something was not sent, in words for the person.
class _NotSent implements Exception {
  _NotSent(this.why);
  final String why;
  @override
  String toString() => why;
}


