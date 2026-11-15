import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../friends/friends.dart';
import '../sms.dart';
import 'common.dart';
import 'new_group.dart';
import 'shell.dart';
import 'thread.dart';

/// The address book (Matt, 2026-11-14: "add an address book icon"): the phone's contacts, searched by name or
/// number, and a press on one opens the conversation with them. It is the phone's own list, asked of the phone: with
/// nothing typed it shows the people texted most, and typing finds anyone.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, String?>>? _found;
  String? _error;
  String _query = '';
  Timer? _debounce;
  int _asked = 0;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _look('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _look(String query) async {
    final asked = ++_asked;
    try {
      final found = await Sms.instance.searchContacts(query);
      if (mounted && asked == _asked) {
        setState(() {
          _found = found;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && asked == _asked) setState(() => _error = '$e');
    }
  }

  void _typed(String query) {
    _query = query.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () => _look(_query));
  }

  /// The conversation with [person], opened in place of this page.
  Future<void> _open(Person person) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final thread = await Sms.instance.threadFor([person.address]);
      if (!mounted) return;
      // In the app's frame the conversation takes this page's place in the pane, and the list marks it.
      final shell = AppShell.maybeOf(context);
      if (shell != null) return shell.openThread(thread, [person]);
      Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (context, _, _) => ThreadScreen(thread: thread, people: [person]),
        transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _opening = false);
        toast(context, 'Couldn\'t open that conversation: $e', tone: GlacierToastTone.danger);
      }
    }
  }

  /// What the list shows: the people added on Ghost Messaging (friends) first, under their own heading, then the
  /// phone's contacts without them (Matt, 2026-11-15: "Contacts added on Ghost Messaging should render at the top
  /// instead of the normal contacts"). A search narrows both. Headings are there only where there are friends to show.
  List<_Row> _rows(List<Map<String, String?>> found) {
    final byDigits = {for (final c in found) Friends.digits(c['address'] ?? ''): c};
    final q = _query.toLowerCase();
    final qDigits = Friends.digits(_query);
    final friends = <_Row>[];
    for (final s in Friends.instance.friends) {
      final contact = byDigits[Friends.digits(s.address)];
      final address = s.person?.address ?? contact?['address'] ?? s.address;
      final name = s.person?.name ?? contact?['name'];
      if (q.isNotEmpty) {
        final named = name != null && name.toLowerCase().contains(q);
        final numbered = qDigits.isNotEmpty && Friends.digits(address).contains(qDigits);
        if (!named && !numbered) continue;
      }
      friends.add(_Row(person: Person(address: address, name: name, photo: s.person?.photo ?? contact?['photo']), label: contact?['label'], friend: true));
    }
    friends.sort((a, b) => (a.person!.name ?? a.person!.address).toLowerCase().compareTo((b.person!.name ?? b.person!.address).toLowerCase()));
    final rest = [
      for (final c in found)
        if (!Friends.instance.isFriend(c['address'] ?? '')) _Row(person: Person(address: c['address'] ?? '', name: c['name'], photo: c['photo']), label: c['label']),
    ];
    if (friends.isEmpty) return rest;
    return [
      const _Row(heading: 'On Ghost Messaging'),
      ...friends,
      if (rest.isNotEmpty) const _Row(heading: 'Contacts'),
      ...rest,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final found = _found;
    return GhostPage(
      title: 'Contacts',
      back: true,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space(4), 0, t.space(4), t.space(2)),
          child: GlacierSearchField(placeholder: 'Search contacts', size: GlacierFieldSize.md, onValueChange: _typed),
        ),
        // A group of friends is made from here, where there is a friend to put in one (lib/ui/new_group.dart).
        if (!Sms.remote && _query.isEmpty && Friends.instance.available && Friends.instance.friends.isNotEmpty)
          GlacierPressable(
            onPressed: () {
              final shell = AppShell.maybeOf(context);
              if (shell != null) {
                shell.show(const NewGroupScreen(), showing: 'contacts');
              } else {
                push<void>(context, (_) => const NewGroupScreen());
              }
            },
            semanticLabel: 'New group',
            builder: (context, state) => ColoredBox(
              color: state.pressed || state.hovered ? t.color('app-paper-2') : const Color(0x00000000),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2) + 2),
                child: Row(children: [
                  Container(
                    width: t.lenOf('2.5rem'),
                    height: t.lenOf('2.5rem'),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('app-paper-3')),
                    child: Center(child: AppIcon(Lucide.users, size: 18, color: t.color('app-ink'))),
                  ),
                  SizedBox(width: t.space(3)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('New group', style: pageText(t, t.fontSize('md'), weight: 'medium')),
                      Text('Of your friends, over the internet', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        Expanded(
          child: found == null
              ? Center(
                  child: _error == null
                      ? const GhostSpinner(size: 26, label: 'Reading your contacts…')
                      : Padding(
                          padding: EdgeInsets.all(t.space(6)),
                          child: SettingsEmpty(
                            icon: AppIcon(Lucide.contactRound, size: 28, color: t.color('app-ink-3')),
                            title: 'Your contacts couldn\'t be read',
                            body: Text(Sms.remote ? 'They are on the phone, which isn\'t reachable just now.' : _error!),
                            action: SettingsEmptyAction('Try again', () => _look(_query)),
                          ),
                        ),
                )
              : ListenableBuilder(
                  listenable: Friends.instance,
                  builder: (context, _) {
                    final rows = _rows(found);
                    return rows.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(t.space(6)),
                      child: SettingsEmpty(
                        icon: AppIcon(Lucide.contactRound, size: 28, color: t.color('app-ink-3')),
                        title: _query.isEmpty ? 'No contacts' : 'Nobody found',
                        body: Text(_query.isEmpty ? 'People in the phone\'s contacts appear here.' : 'No name or number in your contacts matches "$_query".'),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(bottom: t.space(6)),
                      itemCount: rows.length + (_query.isEmpty ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == rows.length) {
                          return Padding(
                            padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), 0),
                            child: Text('The people you text most. Search to find anyone else.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
                          );
                        }
                        final row = rows[i];
                        if (row.heading != null) {
                          return Padding(
                            padding: EdgeInsets.fromLTRB(t.space(4), t.space(i == 0 ? 1 : 4), t.space(4), t.space(1)),
                            child: Text(row.heading!, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'))),
                          );
                        }
                        final person = row.person!;
                        final label = row.label;
                        return GlacierPressable(
                          onPressed: () => _open(person),
                          semanticLabel: person.name ?? person.address,
                          builder: (context, state) => ColoredBox(
                            color: state.pressed || state.hovered ? t.color('app-paper-2') : const Color(0x00000000),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2) + 2),
                              child: Row(children: [
                                Avatar(people: [person], size: t.lenOf('2.5rem')),
                                SizedBox(width: t.space(3)),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(person.name ?? person.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'medium')),
                                    if (person.name != null)
                                      Text([person.address, if (label != null && label.isNotEmpty) label].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                                  ]),
                                ),
                                // A friend (lib/friends/friends.dart): what is written to them goes over the internet.
                                if (row.friend) ...[
                                  SizedBox(width: t.space(2)),
                                  Semantics(label: 'Friend', child: AppIcon(Lucide.userCheck, size: 16, color: t.color('app-ink-3'))),
                                ],
                              ]),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// A line of the list: a heading, or someone in it.
class _Row {
  const _Row({this.heading, this.person, this.label, this.friend = false});
  final String? heading;
  final Person? person;
  final String? label;
  final bool friend;
}
