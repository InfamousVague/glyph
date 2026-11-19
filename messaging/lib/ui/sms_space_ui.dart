/// An SMS space's people by text (lib/circles/sms_space.dart; Matt, 2026-11-19: "a special space in the circle called a
/// "SMS Space" to text members"): who is in it by text, and, on the phone that texts for it, adding and taking out.
library;

import 'package:flutter/services.dart' show TextCapitalization, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../circles/circles.dart';
import '../circles/sms_space.dart';
import '../kit/settings_kit.dart';
import '../voice/channels.dart';
import '../voice/voice.dart';
import 'common.dart';

/// [space]'s entry in its circle, where it is an SMS space; null otherwise.
CircleSpace? smsSpaceOf(VoiceChannel space) {
  final c = Circles.instance.circleOf(space);
  final s = c?.space(space.seed);
  return s != null && smsTexterOf(s) != null ? s : null;
}

class TextedPeopleScreen extends StatefulWidget {
  const TextedPeopleScreen({super.key, required this.space});
  final VoiceChannel space;

  @override
  State<TextedPeopleScreen> createState() => _TextedPeopleScreenState();
}

class _TextedPeopleScreenState extends State<TextedPeopleScreen> {
  final _name = TextEditingController();
  final _number = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final ok = await SmsSpaces.instance.add(widget.space, _name.text, _number.text);
    if (!mounted) return;
    if (!ok) {
      toast(context, 'They couldn\'t be added: a number is needed, and once is enough.');
      return;
    }
    toast(context, '${_name.text.trim().isEmpty ? _number.text.trim() : _name.text.trim()} is texted now');
    _name.clear();
    _number.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = smsSpaceOf(widget.space);
    final texter = s == null ? null : smsTexterOf(s);
    final mine = texter != null && texter == SmsSpaces.instance.me;
    return ListenableBuilder(
      listenable: SmsSpaces.instance,
      builder: (context, _) {
        final people = mine ? SmsSpaces.instance.people(widget.space.seed) : const <TextedPerson>[];
        return GhostPage(
          title: 'People by text',
          subtitle: widget.space.name,
          body: ListView(padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8)), children: [
            SettingsCallout(
              child: Text(texter == null
                  ? 'This isn\'t an SMS space.'
                  : mine
                      ? 'Your phone texts for ${widget.space.name}: what is written here goes to each person below by text, from your number and on your plan, and what they text back comes in here. Keep Ghost Messaging running for it to carry on.'
                      : '${Voice.instance.nameOf(texter)}\'s phone texts for ${widget.space.name}: people without the app are in it by text, and what they send comes in marked 📱. Only that phone knows their numbers.'),
            ),
            if (mine) ...[
              SizedBox(height: t.space(5)),
              PaneSection(title: 'In it by text', children: [
                if (people.isEmpty) const SettingRowBox(child: Text('Nobody yet. Add someone below; they get a text saying how it works and how to leave.')),
                for (final p in people)
                  SettingRow(
                    key: ValueKey('texted-${p.number}'),
                    icon: AppIcon(Lucide.smartphone, size: 18),
                    label: p.name,
                    hint: Text(p.number),
                    onPress: () => showChoices(context, title: p.name, choices: [
                      Choice('Take out of the space', Lucide.userMinus, () => SmsSpaces.instance.remove(widget.space, p.number), danger: true),
                    ]),
                  ),
              ]),
              SizedBox(height: t.space(5)),
              PaneSection(title: 'Add someone by text', children: [
                SettingRowBox(child: GlacierInput(controller: _name, placeholder: 'Name', ariaLabel: 'Their name', autoCapitalize: TextCapitalization.words, size: GlacierFieldSize.md)),
                SettingRowBox(child: GlacierInput(controller: _number, placeholder: 'Phone number', ariaLabel: 'Their phone number', inputMode: TextInputType.phone, size: GlacierFieldSize.md)),
                SettingRow(key: const ValueKey('texted-add'), icon: AppIcon(Lucide.userPlus, size: 18), label: 'Add and text them', onPress: _add),
              ]),
            ],
          ]),
        );
      },
    );
  }
}
