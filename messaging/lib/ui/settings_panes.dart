/// Settings' sections and what is on each one's page (the frame is settings.dart). A page is a list of the kit's
/// cards and rows, handed over plain, so the search can read every setting's name off it.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../backgrounds.dart';
import '../effects.dart';
import '../emoji_sets.dart';
import '../kit/settings_kit.dart';
import '../plugins/settings.dart';
import '../sms.dart';
import 'background_picker.dart';
import 'common.dart';
import 'computers.dart';
import 'conversations.dart';
import 'encryption.dart';
import 'network.dart';
import 'settings.dart';

Widget _icon(LucideIcon icon) => AppIcon(icon, size: 18);

String _onOff(bool on) => on ? 'On' : 'Off';

/// Every section, in the order of the list. Rows with the same group share a card.
final List<SettingsSection> settingsSections = [
  SettingsSection(
    id: 'appearance',
    label: 'Appearance',
    icon: _icon(Lucide.sunMoon),
    hue: 'indigo',
    group: 'look',
    summary: (m) => [
      switch (m.app.theme) { 'light' => 'Light', 'dark' => 'Dark', _ => 'System theme' },
      '${bubbleColor(m.app.bubble).name} bubbles',
      if (m.app.textSize != 'default') '${m.app.textSize} text',
    ].join(' · '),
    page: _appearance,
  ),
  SettingsSection(
    id: 'background',
    label: 'Chat background',
    icon: _icon(Lucide.image),
    hue: 'purple',
    group: 'look',
    summary: (m) => ChatBackground.everyChat(m.app).label,
    page: (context, m) => const [],
    screen: (context, m) => const BackgroundPicker(),
  ),
  SettingsSection(
    id: 'emoji',
    label: 'Emoji',
    icon: _icon(LucideMore.smile),
    hue: 'amber',
    group: 'look',
    summary: (m) => emojiSet(m.app.emoji).name,
    page: _emoji,
  ),
  SettingsSection(
    id: 'effects',
    label: 'Effects',
    icon: _icon(Lucide.sparkles),
    hue: 'magenta',
    group: 'look',
    summary: (m) => m.app.effects ? 'On · ${ScreenEffect.values.length} effects' : 'Off',
    page: _effects,
  ),
  SettingsSection(
    id: 'messages',
    label: 'Messages',
    icon: _icon(Lucide.messageSquare),
    hue: 'blue',
    group: 'messages',
    summary: (m) => m.app.enterSends ? 'Enter sends' : 'Enter starts a new line',
    page: _messages,
  ),
  SettingsSection(
    id: 'receipts',
    label: 'Receipts',
    icon: _icon(Lucide.checkCheck),
    hue: 'cyan',
    group: 'messages',
    summary: (m) => 'Delivery ${_onOff(m.app.flag('delivery_reports')).toLowerCase()} · read ${_onOff(m.app.readReports).toLowerCase()}',
    page: _receipts,
  ),
  SettingsSection(
    id: 'notifications',
    label: 'Notifications',
    icon: _icon(Lucide.bell),
    hue: 'coral',
    group: 'messages',
    summary: (m) => m.status == null ? '' : (m.status!.notifications ? (m.app.flag('notif_preview') ? 'Allowed · previews shown' : 'Allowed · previews hidden') : 'Off in Android'),
    page: _notifications,
  ),
  // Plugins (lib/plugins/settings.dart): each with its switch and its own settings, once the app has one.
  ...pluginsSettings(),
  SettingsSection(
    id: 'encryption',
    label: 'Encryption',
    icon: _icon(Lucide.lock),
    hue: 'green',
    group: 'privacy',
    summary: (m) {
      final on = m.e2e.where((e) => e.on).length;
      final waiting = m.e2e.length - on;
      if (m.e2e.isEmpty) return 'Off';
      return [if (on > 0) 'On with $on ${on == 1 ? 'person' : 'people'}', if (waiting > 0) '$waiting waiting'].join(' · ');
    },
    page: _encryption,
  ),
  SettingsSection(
    id: 'blocked',
    label: 'Blocked numbers',
    icon: _icon(Lucide.ban),
    hue: 'red',
    group: 'privacy',
    summary: (m) => m.blocked.isEmpty ? 'None' : '${m.blocked.length} ${m.blocked.length == 1 ? 'number' : 'numbers'}',
    page: _blocked,
  ),
  SettingsSection(
    id: 'archived',
    label: 'Archived',
    icon: _icon(Lucide.archive),
    hue: 'slate',
    group: 'privacy',
    summary: (m) => m.archived == 0 ? 'Nothing archived' : '${m.archived} ${m.archived == 1 ? 'conversation' : 'conversations'}',
    page: (context, m) => const [],
    screen: (context, m) => const ConversationsScreen(archived: true),
  ),
  SettingsSection(
    id: 'number',
    label: 'Your number',
    icon: _icon(Lucide.phone),
    hue: 'orange',
    group: 'phone',
    summary: (m) => m.ownNumber == null || m.ownNumber!.isEmpty ? 'Not known' : m.ownNumber!,
    page: _number,
  ),
  SettingsSection(
    id: 'android',
    label: 'Android',
    icon: _icon(LucideMore.smartphone),
    hue: 'lime',
    group: 'phone',
    summary: (m) => m.status == null ? '' : (m.status!.isDefault ? 'Default SMS app' : 'Not the default SMS app'),
    page: _android,
  ),
  SettingsSection(
    id: 'keyboard',
    label: 'Ghost Keyboard',
    icon: _icon(LucideMore.keyboard),
    hue: 'yellow',
    group: 'phone',
    summary: (m) => !m.app.flag('kbd_codes') ? 'Sign-in codes not offered' : (m.keyboardHere ? 'Offers it sign-in codes' : 'Not on this phone'),
    page: _keyboard,
  ),
  SettingsSection(
    id: 'computers',
    label: 'Computers',
    icon: _icon(Lucide.laptop),
    hue: 'blue',
    group: 'phone',
    summary: (m) {
      if (m.computers.isEmpty) return 'None paired';
      final on = m.computers.where((c) => c.via != null).length;
      final names = m.computers.length == 1 ? m.computers.first.name : '${m.computers.length} computers';
      return on > 0 ? '$names · connected' : names;
    },
    page: computersPane,
  ),
  SettingsSection(
    id: 'network',
    label: 'Network',
    icon: _icon(Lucide.network),
    hue: 'blue',
    group: 'phone',
    summary: (m) => networkSummary(),
    page: networkPane,
  ),
  SettingsSection(
    id: 'updates',
    label: 'Updates',
    icon: _icon(Lucide.download),
    hue: 'mint',
    group: 'app',
    summary: (m) => updateSummary(m.update),
    page: _updates,
  ),
  SettingsSection(
    id: 'developer',
    label: 'Developer',
    icon: _icon(Lucide.terminal),
    hue: 'graphite',
    group: 'app',
    summary: (m) => m.devLines.isEmpty ? 'Nothing in the log' : '${m.devLines.length} ${m.devLines.length == 1 ? 'line' : 'lines'} in the log',
    page: _developer,
  ),
  SettingsSection(
    id: 'about',
    label: 'About',
    icon: _icon(Lucide.info),
    hue: 'graphite',
    group: 'app',
    summary: (m) => 'Ghost Messaging ${m.update.current.isEmpty ? appVersion : m.update.current}',
    page: _about,
  ),
];

/// The version this build is, where Android has not said (the screens drawn in tests).
const appVersion = '0.7.4';

// --- Appearance -------------------------------------------------------------------------------------------------------

List<Widget> _appearance(BuildContext context, SettingsModel m) {
  final app = m.app;
  final palette = PhonePalette.current != null;
  return [
    PaneSection(title: 'Theme', children: [
      SettingRow(
        icon: _icon(Lucide.sunMoon),
        label: 'Theme',
        layout: SettingRowLayout.stacked,
        control: GlacierSegmentedControl(
          fullWidth: true,
          value: app.theme,
          onValueChange: app.setTheme,
          options: const [
            GlacierSegmentedOption(value: 'system', label: Text('System')),
            GlacierSegmentedOption(value: 'light', label: Text('Light')),
            GlacierSegmentedOption(value: 'dark', label: Text('Dark')),
          ],
        ),
      ),
    ]),
    PaneSection(
      title: 'Bubbles',
      footer: Text('The colour of your own bubbles in every conversation. Ghost is Ghost Keyboard\'s teal, Ink is the page\'s own black and white${palette ? ', and Wallpaper is the accent Android takes from this phone\'s wallpaper' : ''}. A conversation can have a colour of its own, from the cog at its top.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.messageSquare),
          label: 'Your bubbles',
          layout: SettingRowLayout.stacked,
          control: BubbleSwatches(chosen: app.bubble == 'wallpaper' && !palette ? 'white' : app.bubble, onPick: app.setBubble),
        ),
      ],
    ),
    PaneSection(title: 'Text', footer: const Text('The size of the words in a message. Everything else follows Android\'s own font size.'), children: [
      SettingRow(
        icon: _icon(LucideMore.type),
        label: 'Text size',
        layout: SettingRowLayout.stacked,
        control: GlacierSegmentedControl(
          fullWidth: true,
          value: app.textSize,
          onValueChange: (v) => app.set('text_size', v),
          options: const [
            GlacierSegmentedOption(value: 'small', label: Text('Small')),
            GlacierSegmentedOption(value: 'default', label: Text('Default')),
            GlacierSegmentedOption(value: 'large', label: Text('Large')),
            GlacierSegmentedOption(value: 'larger', label: Text('Larger')),
          ],
        ),
      ),
      SettingRowBox(child: BackgroundPreview(background: ChatBackground.everyChat(app))),
    ]),
  ];
}

// --- Emoji ------------------------------------------------------------------------------------------------------------

List<Widget> _emoji(BuildContext context, SettingsModel m) {
  final t = context.tokens;
  final app = m.app;
  return [
    PaneSection(
      title: 'Emoji set',
      footer: const Text('How emoji are drawn in this app. What the other person sees is drawn by their own phone.'),
      children: [
        for (final set in emojiSets)
          SettingRow(
            label: set.name,
            hint: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(set.about),
              SizedBox(height: t.space(1)),
              // Each row in its own set, whichever is chosen: no fallback but the set's (or the phone's).
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final e in emojiSample)
                  Padding(
                    padding: EdgeInsets.only(right: t.space(2)),
                    child: Text(e, style: TextStyle(inherit: false, fontFamily: set.family, fontFamilyFallback: const [], fontSize: t.lenOf('1.35rem'), height: 1.3, color: t.color('app-ink'))),
                  ),
              ]),
            ]),
            control: Pick(checked: app.emoji == set.id, label: 'Use ${set.name} emoji', onPress: () => app.setEmoji(set.id)),
          ),
      ],
    ),
    PaneSection(title: 'In a conversation', children: [
      SettingRow(
        icon: _icon(LucideMore.smile),
        label: 'Large emoji',
        hint: const Text('A message of one to three emoji and nothing else is drawn large, with no bubble.'),
        control: GlacierSwitch(checked: app.bigEmoji, onCheckedChange: (v) => app.setFlag('big_emoji', v), ariaLabel: 'Large emoji'),
      ),
    ]),
  ];
}

// --- Effects ----------------------------------------------------------------------------------------------------------

List<Widget> _effects(BuildContext context, SettingsModel m) {
  final app = m.app;
  return [
    PaneSection(children: [
      SettingRow(
        icon: _icon(Lucide.sparkles),
        label: 'Message effects',
        hint: const Text('Confetti for "Congratulations", balloons for "Happy birthday", and more, as a message arrives or is sent.'),
        control: GlacierSwitch(checked: app.effects, onCheckedChange: app.setEffects, ariaLabel: 'Message effects'),
      ),
    ]),
    PaneSection(
      title: 'Every effect',
      description: const Text('Each with what sets it off. Tap one to play it here.'),
      footer: const Text('An effect plays once, as its message arrives or is sent while the conversation is open. A message\'s menu can play it again.'),
      children: [
        for (final effect in ScreenEffect.values)
          SettingRow(
            label: effectLabel(effect),
            hint: Text(effectTriggers(effect)),
            onPress: () => EffectsHost.maybeOf(context)?.play(effect),
          ),
      ],
    ),
  ];
}

// --- Messages ---------------------------------------------------------------------------------------------------------

List<Widget> _messages(BuildContext context, SettingsModel m) {
  final app = m.app;
  return [
    PaneSection(title: 'Writing', children: [
      SettingRow(
        icon: _icon(LucideMore.keyboard),
        label: 'Enter sends',
        hint: const Text('The keyboard\'s Enter key sends the message. Off, it starts a new line.'),
        control: GlacierSwitch(checked: app.enterSends, onCheckedChange: (v) => app.setFlag('enter_sends', v), ariaLabel: 'Enter sends'),
      ),
    ]),
    PaneSection(
      title: 'Reactions',
      footer: const Text('Other phones send a reaction as a text, like Loved “See you at 7”. On, it is drawn as a ❤️ on the message it names. Off, every text is shown as it came.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.messageSquare),
          label: 'Attach reactions to messages',
          control: GlacierSwitch(checked: app.foldReactions, onCheckedChange: (v) => app.setFlag('fold_reactions', v), ariaLabel: 'Attach reactions to messages'),
        ),
      ],
    ),
  ];
}

// --- Receipts ---------------------------------------------------------------------------------------------------------

List<Widget> _receipts(BuildContext context, SettingsModel m) {
  final app = m.app;
  return [
    PaneSection(
      title: 'Ask for',
      footer: const Text('Delivered is your carrier saying the message reached the other phone. Read exists only for picture and group messages, and only from phones that answer; a plain text has no way to say it was read.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.check),
          label: 'Delivery reports',
          hint: const Text('On every message you send.'),
          control: GlacierSwitch(checked: app.flag('delivery_reports'), onCheckedChange: (v) => app.setFlag('delivery_reports', v), ariaLabel: 'Delivery reports'),
        ),
        SettingRow(
          icon: _icon(Lucide.checkCheck),
          label: 'Read receipts',
          hint: const Text('On picture and group messages.'),
          control: GlacierSwitch(checked: app.readReports, onCheckedChange: app.setReadReports, ariaLabel: 'Read receipts'),
        ),
      ],
    ),
    PaneSection(title: 'The ticks', children: [
      SettingRow(icon: _icon(Lucide.clock), label: 'A clock', hint: const Text('Sending.')),
      SettingRow(icon: _icon(Lucide.check), label: 'One tick', hint: const Text('Sent.')),
      SettingRow(icon: _icon(Lucide.checkCheck), label: 'Two ticks', hint: const Text('Delivered. In colour: read.')),
      SettingRow(icon: _icon(Lucide.lock), label: 'A lock', hint: const Text('It went encrypted (Settings › Encryption).')),
    ]),
  ];
}

// --- Notifications ----------------------------------------------------------------------------------------------------

List<Widget> _notifications(BuildContext context, SettingsModel m) {
  final app = m.app;
  final s = m.status;
  return [
    PaneSection(title: 'Android', children: [
      SettingRow(
        icon: _icon(Lucide.bell),
        label: 'Notifications',
        hint: s != null && !s.notifications ? const Text('Android isn\'t letting this app notify you. Tap to allow it.') : null,
        value: Text(s == null ? '' : (s.notifications ? 'Allowed' : 'Off')),
        onPress: s == null || s.notifications
            ? null
            : () async {
                await Sms.instance.requestPermissions();
                m.refresh();
              },
      ),
      SettingRow(
        icon: _icon(LucideMore.vibrate),
        label: 'Sound and vibration',
        hint: const Text('Android\'s own page for this app: the sound, vibration, the lock screen and Do Not Disturb.'),
        onPress: () => Sms.instance.notificationSettings(),
      ),
    ]),
    PaneSection(
      title: 'What a notification shows',
      footer: const Text('A conversation you muted arrives without a notification (long press it in the list).'),
      children: [
        SettingRow(
          icon: _icon(Lucide.eye),
          label: 'Message previews',
          hint: const Text('The message\'s words. Off, a notification says "New message" and who it is from.'),
          control: GlacierSwitch(checked: app.flag('notif_preview'), onCheckedChange: (v) => app.setFlag('notif_preview', v), ariaLabel: 'Message previews'),
        ),
        SettingRow(
          icon: _icon(Lucide.copy),
          label: 'Copy code button',
          hint: const Text('A text with a sign-in code gets a button that copies it.'),
          control: GlacierSwitch(checked: app.flag('notif_code'), onCheckedChange: (v) => app.setFlag('notif_code', v), ariaLabel: 'Copy code button'),
        ),
      ],
    ),
  ];
}

// --- Encryption -------------------------------------------------------------------------------------------------------

List<Widget> _encryption(BuildContext context, SettingsModel m) {
  String stateLine(E2eState e) => switch (e.state) {
        'on' => e.verified ? 'On · verified' : 'On · not verified yet',
        'pending' => e.changed ? 'Sent a NEW key: review it' : 'Wants to encrypt: waiting for your yes',
        'offered' => 'Your key was sent: waiting for them',
        _ => 'Off',
      };
  return [
    PaneSection(
      title: 'What it is',
      children: [
        SettingRow(
          icon: _icon(Lucide.lock),
          label: 'Encrypted texts',
          hint: const Text('With someone who also has Ghost Messaging, your texts go sealed so only your two phones can read them. Not your carrier, and not another app on either phone.'),
        ),
        SettingRow(
          icon: _icon(Lucide.info),
          label: 'What it doesn\'t cover',
          hint: const Text('One person at a time: group conversations and pictures go as they always have. The keys travel by text, so compare the safety number in person or on a call to be sure nobody swapped one. There is no forward secrecy: this is not Signal\'s protocol. A sealed text is longer, so it can cost more texts. To any other app a sealed text is a line of letters.'),
        ),
      ],
    ),
    PaneSection(
      title: 'Finding each other',
      footer: const Text('The hello is three invisible characters at the end of a text, now and then, and only where they add nothing to what the text costs. Every other app draws them as nothing. Nothing else is sent: encryption starts only when one of you taps Turn on, which sends a key, and the other accepts. The safety number is how you check nobody is in the middle.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.sparkles),
          label: 'Find people who have Ghost Messaging',
          hint: const Text('When someone you text has Ghost Messaging too, the two phones recognise each other, and the conversation shows a banner offering to encrypt it. Off, your phone says nothing of itself, and you turn encryption on from a conversation\'s header.'),
          control: GlacierSwitch(checked: m.app.flag('e2e_detect'), onCheckedChange: (v) => m.app.setFlag('e2e_detect', v), ariaLabel: 'Find people who have Ghost Messaging'),
        ),
      ],
    ),
    PaneSection(
      title: 'People',
      footer: m.e2e.isEmpty ? const Text('Nobody yet. A conversation with someone who has Ghost Messaging offers it in a banner, or open any conversation, tap the name at the top, and choose Encryption.') : null,
      children: [
        for (final e in m.e2e)
          SettingRow(
            icon: _icon(e.on ? (e.verified ? Lucide.shieldCheck : Lucide.lock) : Lucide.keyRound),
            label: (e.person ?? Person(address: e.address)).label,
            hint: Text(stateLine(e)),
            onPress: () => showEncryptionChoices(context, e.person ?? Person(address: e.address), e, m.refresh),
          ),
      ],
    ),
    PaneSection(
      title: 'This phone',
      footer: const Text('A new key ends encryption with everyone. Each conversation is exchanged again to go on, and texts sealed under the old key can no longer be opened.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.keyRound),
          label: 'This phone\'s key',
          hint: Text(m.myKey == null ? 'Made the first time you send your key to someone.' : 'A short name for it. The private half never leaves this phone.'),
          value: m.myKey == null ? null : Text(m.myKey!),
        ),
        SettingRow(
          icon: _icon(Lucide.rotateCcw),
          label: 'New key for this phone',
          disabledReason: m.myKey == null ? 'There is no key yet.' : null,
          onPress: () => showChoices(
            context,
            title: 'Make a new key for this phone? Encryption ends with everyone until each conversation is exchanged again, and texts sealed under the old key can\'t be opened afterwards.',
            choices: [
              Choice('Make a new key', Lucide.rotateCcw, () async {
                await Sms.instance.e2eReset();
                await m.refresh();
                if (context.mounted) toast(context, 'This phone has a new key');
              }, danger: true),
            ],
          ),
        ),
      ],
    ),
  ];
}

// --- Blocked numbers --------------------------------------------------------------------------------------------------

List<Widget> _blocked(BuildContext context, SettingsModel m) {
  return [
    PaneSection(
      title: 'Blocked',
      description: const Text('Android\'s own list: it stops a number\'s texts and calls before any app sees them. Block one from a conversation\'s long press.'),
      footer: m.blocked.isEmpty ? const Text('No numbers are blocked.') : const Text('Tap a number to unblock it.'),
      children: [
        for (final p in m.blocked)
          SettingRow(
            icon: _icon(Lucide.ban),
            label: p.label,
            hint: p.name != null && p.name!.isNotEmpty ? Text(p.address) : null,
            onPress: () => showChoices(context, title: 'Unblock ${p.label}? Their texts and calls will reach you again.', choices: [
              Choice('Unblock', Lucide.check, () async {
                try {
                  await Sms.instance.setBlocked(p.address, false);
                  if (context.mounted) toast(context, 'Unblocked');
                } catch (e) {
                  if (context.mounted) toast(context, 'Couldn\'t unblock: $e', tone: GlacierToastTone.danger);
                }
                m.refresh();
              }),
            ]),
          ),
      ],
    ),
  ];
}

// --- Your number ------------------------------------------------------------------------------------------------------

List<Widget> _number(BuildContext context, SettingsModel m) {
  final own = m.ownNumber;
  return [
    PaneSection(
      title: 'This phone',
      footer: Text(own == null || own.isEmpty
          ? 'Android didn\'t say this phone\'s number. Type it here so group picture messages don\'t list you as one of the people.'
          : 'Used to leave you out of a group message\'s list of people.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.phone),
          label: 'Your number',
          layout: SettingRowLayout.stacked,
          control: _OwnNumberField(model: m),
        ),
      ],
    ),
  ];
}

class _OwnNumberField extends StatefulWidget {
  const _OwnNumberField({required this.model});
  final SettingsModel model;

  @override
  State<_OwnNumberField> createState() => _OwnNumberFieldState();
}

class _OwnNumberFieldState extends State<_OwnNumberField> {
  late final _number = TextEditingController(text: widget.model.ownNumber ?? '');

  @override
  void didUpdateWidget(_OwnNumberField old) {
    super.didUpdateWidget(old);
    // Android's answer came after the page was drawn.
    final own = widget.model.ownNumber;
    if (_number.text.isEmpty && own != null && own.isNotEmpty) _number.text = own;
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _save({bool say = false}) async {
    await Sms.instance.setOwnNumber(_number.text.trim());
    if (say && mounted) toast(context, 'Saved');
    widget.model.refresh();
  }

  @override
  Widget build(BuildContext context) => GlacierInput(
        controller: _number,
        placeholder: '+1 555 123 4567',
        ariaLabel: 'This phone\'s number',
        inputMode: TextInputType.phone,
        size: GlacierFieldSize.md,
        onSubmitted: (_) => _save(say: true),
        onBlur: _save,
      );
}

// --- Android ----------------------------------------------------------------------------------------------------------

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => ',');

List<Widget> _android(BuildContext context, SettingsModel m) {
  final s = m.status;
  final a = m.arriving;
  // What Android's store holds, said so a person can tell "nothing was read" from "there was little to read".
  final held = a.texts == null
      ? null
      : '${_thousands(a.texts!)} ${a.texts == 1 ? 'text' : 'texts'}'
          '${a.pictures == null ? '' : ', ${_thousands(a.pictures!)} picture ${a.pictures == 1 ? 'message' : 'messages'}'}'
          '${a.recentTexts == null ? '' : ' · ${_thousands(a.recentTexts!)} in the last 30 days'}';
  return [
    if (a.rcsLikely)
      PaneSection(
        title: 'Coming from ${a.app}',
        description: Text('Android can\'t tell this app whether RCS chats are on for your number. ${a.app} is on this phone, and RCS chats are on there unless you turned them off.'),
        footer: const Text('After RCS is off, people\'s phones go back to sending you texts. It can take a few minutes to a few hours for their phones to notice.'),
        children: [
          SettingRow(
            icon: _icon(Lucide.triangleAlert),
            label: 'Texts from some people not arriving',
            hint: Text('While RCS chats are on in ${a.app}, people who use RCS keep sending you chats there, not texts. They never reach this app. Turn RCS chats off one of the two ways below.'),
          ),
          SettingRow(
            icon: _icon(Lucide.keyRound),
            label: 'Turn RCS off with a code',
            hint: const Text('Google\'s page asks for your number and texts you a six-digit code. The text arrives here. Type the code there and RCS is off for your number. No need to switch apps.'),
            onPress: () => Sms.instance.openRcsOff(),
          ),
          SettingRow(
            icon: _icon(Lucide.rotateCcw),
            label: 'Or turn it off in ${a.app}',
            hint: Text('Make ${a.app} the default SMS app again here, open its settings, switch off RCS chats, then come back and make Ghost Messaging the default.'),
            onPress: () => Sms.instance.openDefaultApps(),
          ),
          SettingRow(
            icon: _icon(Lucide.messageSquare),
            label: 'Your old chats',
            hint: Text('RCS chats are kept inside ${a.app}, where Android lets no other app read them. They are not deleted: they show again whenever ${a.app} is the default. Texts and picture messages are Android\'s, and all of them show here.'
                '${a.samsungChats != null && a.samsungChats! > 0 ? ' Samsung Messages is keeping ${_thousands(a.samsungChats!)} RCS chat messages.' : ''}'),
          ),
        ],
      ),
    // Picture messages: what would stop them, how the last ones went, and all of it to copy (Matt, 2026-11-13: "It
    // seems like picture sending is also not working at all almost like MMS isn't working").
    PaneSection(
      title: 'Picture messages',
      description: const Text('Pictures, stickers and group messages travel as picture messages (MMS), over mobile data even when the phone is on Wi-Fi.'),
      footer: const Text('A picture message that fails says why under it in the conversation. If they keep failing, copy the report and send it to whoever is helping.'),
      children: [
        SettingRow(
          icon: _icon(m.mms.obstacle == null ? Lucide.image : Lucide.triangleAlert),
          label: m.mms.obstacle == null ? 'Nothing seen to stop them' : 'They can\'t go just now',
          hint: Text(m.mms.obstacle == null
              ? 'Mobile data is ${m.mms.dataOn == null ? 'not reported' : 'on'}${m.mms.carrier == null ? '' : ' with ${m.mms.carrier}'}'
                  '${m.mms.maxBytes == null ? '' : ', which carries up to ${m.mms.maxBytes! ~/ 1024} KB a message'}.'
              : '${m.mms.obstacle}.'),
        ),
        if (m.mms.lastSend != null)
          SettingRow(icon: _icon(m.mms.lastSend!.ok ? Lucide.check : Lucide.circleAlert), label: 'Last one sent', hint: Text('${m.mms.lastSend!.ok ? 'Went' : 'Did not go'}: ${m.mms.lastSend!.detail} · ${listWhen(m.mms.lastSend!.at)}')),
        if (m.mms.lastDownload != null)
          SettingRow(icon: _icon(m.mms.lastDownload!.ok ? Lucide.check : Lucide.circleAlert), label: 'Last one received', hint: Text('${m.mms.lastDownload!.ok ? 'Came' : 'Did not come'}: ${m.mms.lastDownload!.detail} · ${listWhen(m.mms.lastDownload!.at)}')),
        if (m.mms.waiting > 0)
          SettingRow(
            icon: _icon(Lucide.rotateCcw),
            label: '${m.mms.waiting} waiting to be fetched',
            hint: const Text('Announced by the carrier and not yet fetched. They are asked for again each time the app opens; tap to ask now.'),
            onPress: () async {
              final n = await Sms.instance.mmsRetry();
              if (context.mounted) toast(context, n == 0 ? 'Already being fetched' : 'Asking for $n again');
            },
          ),
        SettingRow(
          icon: _icon(Lucide.copy),
          label: 'Copy a report',
          hint: const Text('The lines above as text. No messages, names or numbers are in it.'),
          onPress: () async {
            await Clipboard.setData(ClipboardData(text: m.mms.report(appVersion)));
            if (context.mounted) toast(context, 'Report copied');
          },
        ),
      ],
    ),
    PaneSection(
      title: 'Android\'s store of texts',
      footer: Text(a.recentTexts != null && a.rcsLikely && a.recentTexts! < 10
          ? 'Few of your recent messages are texts, so most of your chats were probably RCS. Those are in ${a.app}.'
          : 'What this app reads and shows. If these numbers are right and the list is not, pull the list down to read it again.'),
      children: [
        SettingRow(icon: _icon(Lucide.archive), label: 'Held on this phone', hint: Text(held ?? 'Android hasn\'t said. It says once this is the default SMS app.')),
        if (a.lastReceived != null) SettingRow(icon: _icon(Lucide.clock), label: 'Last text received', value: Text('${listWhen(a.lastReceived!)}${listWhen(a.lastReceived!) == clock(a.lastReceived!) ? '' : ', ${clock(a.lastReceived!)}'}')),
      ],
    ),
    if (a.sideloaded)
      PaneSection(
        title: 'Until it is on the Play Store',
        footer: const Text('Android does this to every app installed from a file. It is asked once.'),
        children: [
          SettingRow(
            icon: _icon(LucideMore.shieldCheck),
            label: 'Allow restricted settings',
            hint: const Text('If Android says a setting is restricted or unavailable (the default SMS app, a permission), open Android\'s page for Ghost Messaging, tap ⋮ at the top, and choose Allow restricted settings. Then try again.'),
            onPress: () => Sms.instance.openAppInfo(),
          ),
        ],
      ),
    PaneSection(
      title: 'What Android has allowed',
      footer: const Text('Your messages are kept by Android, not by this app: every one is still there if you make another app the default.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.messageSquare),
          label: 'Default SMS app',
          hint: const Text('Only the default app may send texts and is handed the ones that arrive.'),
          value: Text(s == null ? '' : (s.isDefault ? 'Yes' : 'No')),
          onPress: s == null || s.isDefault
              ? null
              : () async {
                  await Sms.instance.requestDefault();
                  m.refresh();
                },
        ),
        SettingRow(
          icon: _icon(Lucide.users),
          label: 'Contacts',
          hint: const Text('Names and photos in place of numbers.'),
          value: Text(s == null ? '' : (s.contacts ? 'Allowed' : 'Off')),
          onPress: s == null || s.contacts
              ? null
              : () async {
                  await Sms.instance.requestPermissions();
                  m.refresh();
                },
        ),
        SettingRow(
          icon: _icon(Lucide.phone),
          label: 'Phone number',
          hint: const Text('So Android can say this phone\'s number, for group messages.'),
          value: Text(s == null ? '' : (s.phone ? 'Allowed' : 'Off')),
          onPress: s == null || s.phone
              ? null
              : () async {
                  await Sms.instance.requestPermissions();
                  m.refresh();
                },
        ),
      ],
    ),
  ];
}

// --- Ghost Keyboard ---------------------------------------------------------------------------------------------------

List<Widget> _keyboard(BuildContext context, SettingsModel m) {
  final app = m.app;
  return [
    PaneSection(
      title: 'Sign-in codes',
      footer: Text(m.keyboardHere
          ? 'Ghost Keyboard is on this phone. Its own switch is in its Settings › Row tools.'
          : 'Ghost Keyboard isn\'t on this phone (ghostkbd.com). Nothing is offered to any other app.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.keyRound),
          label: 'Offer sign-in codes to Ghost Keyboard',
          hint: const Text('When a text arrives with a code, like "Your code is 482913", Ghost Keyboard shows the code above its keys to tap in. Only the code is handed over, for ten minutes, and only to Ghost Keyboard, which is checked by its signature.'),
          control: GlacierSwitch(checked: app.flag('kbd_codes'), onCheckedChange: (v) => app.setFlag('kbd_codes', v), ariaLabel: 'Offer sign-in codes to Ghost Keyboard'),
        ),
      ],
    ),
    PaneSection(title: 'Why', children: [
      SettingRow(
        icon: _icon(Lucide.info),
        label: 'Android keeps codes from keyboards',
        hint: const Text('A keyboard needs Android\'s permission to receive texts, which newer versions refuse apps from outside a store, and Android 17 holds code texts back from every app but the default SMS app. This app is the default SMS app, so it has the code at once.'),
      ),
    ]),
  ];
}

// --- Updates ----------------------------------------------------------------------------------------------------------

String _host(UpdateState u) => u.source.isEmpty ? 'ghost-sms.com' : u.source.replaceFirst('https://', '');

/// Whether the look for an update failed because the site is not there to ask: no certificate, no such name, nothing
/// answering, or no release published (Updater.kt says `notServing`; the words are what a copy before 0.4.0's
/// native half would say).
bool _notServing(UpdateState u) {
  final e = (u.error ?? '').toLowerCase();
  return e == 'notserving' || e.contains('ssl') || e.contains('handshake') || e.contains('certpath') || e.contains('trust anchor') || e.contains('answered 404') || e.contains('unable to resolve host') || e.contains('failed to connect');
}

/// Where the update stands, in a sentence.
String updateLine(UpdateState u) => switch (u.phase) {
      'checking' => 'Checking ${_host(u)}…',
      'upToDate' => 'Up to date.',
      'available' => '${u.available} is available.',
      'downloading' => 'Downloading ${u.available}${u.progress == null ? '' : ' · ${(u.progress! * 100).round()}%'}',
      'ready' => u.error == 'needsPermission' || !u.canInstall
          ? '${u.available} is downloaded. Allow Ghost Messaging to install its own updates, then tap Update now.'
          : '${u.available} is downloaded and ready.',
      'installing' => 'Installing ${u.available}…',
      'failed' => u.error == 'offline'
          ? 'This phone is offline. It will look again the next time the app is in front.'
          : u.error != null && u.error!.contains('not signed by this app')
              ? 'This copy is a test build, signed differently from the release. Install the release from ${_host(u)} once, and it updates itself from then on.'
              : _notServing(u)
                  ? '${_host(u)} isn\'t serving updates yet.'
                  : 'Couldn\'t update: ${u.error ?? 'something went wrong'}',
      'disabled' => 'Updates are off in debug builds.',
      _ => 'Looks for a new version whenever the app is in front.',
    };

/// The same, short, for the row on Settings' list.
String updateSummary(UpdateState u) => switch (u.phase) {
      'upToDate' => 'Up to date',
      'available' || 'ready' => '${u.available} is available',
      'downloading' => 'Downloading ${u.available}',
      'installing' => 'Installing ${u.available}',
      'checking' => 'Checking…',
      'failed' => u.error == 'offline' ? 'Offline' : (_notServing(u) ? '${_host(u)} isn\'t serving updates yet' : 'Couldn\'t update'),
      'disabled' => 'Off in debug builds',
      _ => u.auto ? 'Automatic' : 'Automatic updates off',
    };

List<Widget> _updates(BuildContext context, SettingsModel m) {
  final u = m.update;
  return [
    PaneSection(
      title: 'Updates',
      footer: Text(updateLine(u)),
      children: [
        SettingRow(
          icon: _icon(Lucide.download),
          label: 'Automatic updates',
          hint: Text('New versions from ${_host(u)}, downloaded and installed by the app. It is the only connection the app makes.'),
          control: GlacierSwitch(
            checked: u.auto,
            ariaLabel: 'Automatic updates',
            onCheckedChange: (on) async {
              await Sms.instance.setAutoUpdate(on);
              m.refresh();
            },
          ),
        ),
        if (u.phase == 'downloading') SettingRowBox(child: GlacierProgressBar(value: (u.progress ?? 0) * 100, ariaLabel: 'Downloading the update')),
        if (u.phase == 'ready' && (!u.canInstall || u.error == 'needsPermission'))
          SettingRow(icon: _icon(LucideMore.settings), label: 'Allow installing updates', onPress: () => Sms.instance.allowInstalls()),
        if (const {'available', 'ready', 'failed'}.contains(u.phase) && u.available != null)
          SettingRow(icon: _icon(Lucide.rotateCcw), label: 'Update now', value: Text(u.available!), onPress: () => Sms.instance.updateInstall())
        else if (!const {'checking', 'downloading', 'installing', 'disabled'}.contains(u.phase))
          SettingRow(icon: _icon(Lucide.refreshCw), label: 'Check for updates', onPress: () => Sms.instance.updateCheck()),
      ],
    ),
  ];
}

// --- About ------------------------------------------------------------------------------------------------------------

/// Settings › Developer (Matt, 2026-11-13: "Maybe it would be good to include a developer setting with copying
/// errors and reporting"): the app's own log of what went wrong and how its picture messages went, to copy or to
/// send to whoever is helping. A phone that is not plugged into a computer has no other way to say.
List<Widget> _developer(BuildContext context, SettingsModel m) {
  final t = context.tokens;
  // The newest first: what just happened is what is being looked for.
  final lines = m.devLines.reversed.toList();
  return [
    PaneSection(
      title: 'Report',
      description: const Text('What this phone is, how picture messages stand, and the log below, as text.'),
      footer: const Text('It holds no message\'s words, and anything that looks like a phone number is struck out. It leaves the phone only if you copy or share it.'),
      children: [
        SettingRow(
          icon: _icon(Lucide.copy),
          label: 'Copy the report',
          onPress: () async {
            await Clipboard.setData(ClipboardData(text: m.devReport));
            if (context.mounted) toast(context, 'Report copied');
          },
        ),
        SettingRow(
          icon: _icon(Lucide.send),
          label: 'Share the report',
          hint: const Text('To an email, a note or another app.'),
          onPress: () => Sms.instance.shareText('Ghost Messaging report', m.devReport),
        ),
        SettingRow(
          icon: _icon(Lucide.trash2),
          label: 'Clear the log',
          onPress: lines.isEmpty
              ? null
              : () async {
                  await Sms.instance.devLogClear();
                  await m.refresh();
                  if (context.mounted) toast(context, 'Log cleared');
                },
        ),
      ],
    ),
    PaneSection(
      title: lines.isEmpty ? 'Log' : 'Log · ${lines.length} ${lines.length == 1 ? 'line' : 'lines'}, newest first',
      footer: const Text('Errors, and each picture message: what it was made into, how large, and what the carrier answered. The last 300 lines are kept.'),
      children: [
        SettingRowBox(
          child: lines.isEmpty
              ? Text('Nothing has gone wrong that the app knows of.', style: TextStyle(fontSize: t.fontSize('sm'), color: t.color('app-ink-3')))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final line in lines.take(120))
                    Padding(
                      padding: EdgeInsets.only(bottom: t.space(2)),
                      child: Text(line, style: TextStyle(fontFamily: 'JetBrains Mono Variable', fontSize: t.fontSize('xs'), height: 1.4, color: t.color('app-ink-2'))),
                    ),
                ]),
        ),
      ],
    ),
  ];
}

List<Widget> _about(BuildContext context, SettingsModel m) {
  return [
    PaneSection(
      title: 'Ghost Messaging',
      footer: const Text('Your messages stay in Android\'s own message store, so they\'re all still there if you switch back to another app.'),
      children: [
        SettingRow(icon: _icon(Lucide.ghost), label: 'Version', value: Text(m.update.current.isEmpty ? appVersion : m.update.current)),
        SettingRow(
          icon: _icon(Lucide.info),
          label: 'Texts and picture messages',
          hint: const Text('SMS and MMS through your carrier. RCS and iMessage aren\'t available to apps other than Google\'s and Apple\'s own.'),
        ),
        SettingRow(
          icon: _icon(Lucide.lock),
          label: 'Nothing leaves the phone',
          hint: const Text('No account and no server of ours. The app connects to ghost-sms.com for its own updates and to nothing else.'),
        ),
      ],
    ),
    PaneSection(title: 'Licences', children: [
      SettingRow(
        icon: _icon(LucideMore.smile),
        label: 'Emoji sets',
        hint: const Text('Noto Color Emoji and Noto Emoji © Google (SIL OFL 1.1). Twemoji © Twitter and contributors (CC-BY 4.0). All emojis designed by OpenMoji, the open-source emoji and icon project (CC BY-SA 4.0).'),
      ),
      SettingRow(icon: _icon(Lucide.info), label: 'Icons', hint: const Text('Lucide (ISC licence).')),
    ]),
  ];
}
