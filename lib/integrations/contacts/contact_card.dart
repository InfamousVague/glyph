/// A person's card: what a tap on `@sam` opens once Sam is a contact (docs/INTEGRATIONS.md §2). Their picture or
/// initials and their name, then Call, Text, Email and Open in Contacts, then what the chip's own menu did (Remove,
/// taking them off the line), so a match takes nothing away.
///
///     ( SO )  Sam Ortiz
///             @Sam-Ortiz
///     Call                +1 555 0100
///     Text                +1 555 0100
///     Email               sam@example.com
///     Open in Contacts
///     Remove
///
/// On a phone it is a sheet from the bottom (lib/sheet); on a desktop a popover hung from the chip, as the kit's
/// panels are. Each press closes the card first and then does what it says.
///
/// Call, Text and Email hand `tel:`, `sms:` and `mailto:` to the device through [ContactLauncher] (Flutter's
/// `url_launcher` in the app, a fake in a test). A row is there only where the contact has a number or an address
/// for it; the first is the primary one where the phone marks one. Open in Contacts is the address book's own
/// ([ContactBook.open]). Nothing is written into the note but by the chip's own actions.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../art/app_icon.dart';
import '../../shell/pop_menu.dart' show coarsePointer;
import '../../sheet/css.dart';
import '../../sheet/flow.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import 'contact_book.dart';
import 'contact_match.dart';
import 'contacts.dart';

/// Hands an address to the device: answers whether anything took it.
typedef ContactLauncher = Future<bool> Function(Uri uri);

/// The device's own: `url_launcher`, to the app that answers the address. Quiet where nothing does.
Future<bool> launchContactUri(Uri uri) async {
  try {
    return await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// The characters a number is dialled by: the digits, a leading `+`, and the pauses and codes a dialler reads.
final RegExp _notDialled = RegExp(r'[^0-9+*#,;]');

/// A number as the dialler is handed it: `+1 (555) 010-0100` is `tel:+15550100100`.
Uri callUri(String number) => Uri(scheme: 'tel', path: number.replaceAll(_notDialled, ''));

/// The same number to the messages app: `sms:+15550100100`.
Uri textUri(String number) => Uri(scheme: 'sms', path: number.replaceAll(_notDialled, ''));

/// An address to the mail app: `mailto:sam@example.com`.
Uri mailUri(String address) => Uri(scheme: 'mailto', path: address.trim());

/// One of the chip's own actions on the card: Remove, as the chip's menu has it.
@immutable
class PersonCardAction {
  const PersonCardAction({required this.icon, required this.label, required this.onPress, this.name, this.danger = false});

  final LucideIcon icon;
  final String label;

  /// What a screen reader hears, where it is more than the label.
  final String? name;
  final VoidCallback onPress;
  final bool danger;
}

/// A contact's face: their small picture in a round, or their initials in the chip's purple where they have none.
class ContactFace extends StatelessWidget {
  const ContactFace({super.key, required this.contact, this.photo, required this.size});

  final PhoneContact contact;
  final Uint8List? photo;

  /// Its width and height.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bytes = photo;
    if (bytes != null) {
      return ExcludeSemantics(
        child: ClipOval(child: SizedBox.square(dimension: size, child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true))),
      );
    }
    final initials = contact.initials;
    // Two letters in the round of one: a little smaller, so they keep inside it.
    final letters = (initials.length > 1 ? 0.38 : 0.5) * size;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('color-mix(in oklch, var(--glacier-purple-9) 24%, transparent)')),
        child: Text(initials, maxLines: 1, softWrap: false, textScaler: TextScaler.noScaling, style: t.textAt(letters, weight: 'bold', color: t.color('glacier-purple-11'), height: 1)),
      ),
    );
  }
}

/// The card's blocks: the person, their ways to be reached, and the chip's own actions. The same in a sheet and in
/// a popover.
class PersonCard extends StatelessWidget {
  const PersonCard({super.key, required this.contact, required this.name, this.photo, required this.launch, required this.openInContacts, this.actions = const <PersonCardAction>[], required this.onClose});

  final PhoneContact contact;

  /// The person as the note names them (`Sam-Ortiz`), said under the contact's name.
  final String name;
  final Uint8List? photo;
  final ContactLauncher launch;

  /// Opens the address book at them.
  final Future<bool> Function() openInContacts;

  /// The chip's own actions, after the contact's.
  final List<PersonCardAction> actions;
  final VoidCallback onClose;

  /// Closes the card, then does [then].
  VoidCallback _press(void Function() then) => () {
    onClose();
    then();
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final phone = contact.phones.isEmpty ? null : contact.phones.first;
    final email = contact.emails.isEmpty ? null : contact.emails.first;
    final shown = contact.name.isNotEmpty ? contact.name : '${contact.first} ${contact.last}'.trim();
    Widget icon(LucideIcon of) => AppIcon(of, size: 18);
    return CssFlow(
      children: <Widget>[
        // The person: their face beside their name, and the name the note writes under it.
        CssFlow.block(
          margin: EdgeInsets.only(bottom: t.space(4)),
          child: Semantics(
            header: true,
            label: shown,
            child: ExcludeSemantics(
              child: Row(
                spacing: t.space(3),
                children: <Widget>[
                  ContactFace(contact: contact, photo: photo, size: t.lenOf('2.75rem')),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(shown, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('glacier-text'))),
                        Text('@$name', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle'))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SheetGroup(
          children: <Widget>[
            if (phone != null) ...<Widget>[
              SheetRow(key: const ValueKey<String>('contact-call'), icon: icon(Lucide.phone), label: 'Call', hint: phone, onPress: _press(() => unawaited(launch(callUri(phone))))),
              SheetRow(key: const ValueKey<String>('contact-text'), icon: icon(Lucide.messageSquare), label: 'Text', hint: phone, onPress: _press(() => unawaited(launch(textUri(phone))))),
            ],
            if (email != null) SheetRow(key: const ValueKey<String>('contact-email'), icon: icon(Lucide.mail), label: 'Email', hint: email, onPress: _press(() => unawaited(launch(mailUri(email))))),
            SheetRow(key: const ValueKey<String>('contact-open'), icon: icon(Lucide.contactRound), label: 'Open in Contacts', onPress: _press(() => unawaited(openInContacts()))),
          ],
        ),
        if (actions.isNotEmpty)
          SheetGroup(
            children: <Widget>[
              for (final action in actions)
                Semantics(
                  label: action.name,
                  child: SheetRow(key: ValueKey<String>('contact-action:${action.label}'), icon: icon(action.icon), label: action.label, danger: action.danger, onPress: _press(action.onPress)),
                ),
            ],
          ),
      ],
    );
  }
}

/// Opens [contact]'s card for the person named [name]: a sheet on a phone, a popover hung from [at] (the chip's box)
/// on a desktop. [coarse] says which where a test says; the device's answer otherwise.
void showPersonCard(
  BuildContext context, {
  required PhoneContact contact,
  required String name,
  required Rect at,
  ContactsStore? store,
  ContactLauncher launch = launchContactUri,
  List<PersonCardAction> actions = const <PersonCardAction>[],
  bool? coarse,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final book = store ?? phoneContacts;
  final phone = coarse ?? coarsePointer;
  final said = mentionOf(contact) ?? name;
  late final OverlayEntry entry;
  var shut = false;
  void close() {
    if (shut) return;
    shut = true;
    entry.remove();
    entry.dispose();
  }

  Widget card(BuildContext context) => ListenableBuilder(
    listenable: book,
    builder: (context, _) => PersonCard(
      contact: contact,
      name: name.isNotEmpty ? name : said,
      photo: book.photoOf(contact),
      launch: launch,
      openInContacts: () => book.book.open(contact.id),
      actions: actions,
      onClose: close,
    ),
  );

  entry = OverlayEntry(
    builder: (context) => phone
        ? Sheet(label: contact.name.isNotEmpty ? contact.name : said, onClose: close, children: <Widget>[card(context)])
        : GlacierPopover(
            anchor: GlacierAnchor.rect(at),
            open: true,
            onOpenChange: (open) {
              if (!open) close();
            },
            ariaLabel: contact.name.isNotEmpty ? contact.name : said,
            minWidth: context.tokens.lenOf('18rem'),
            padding: EdgeInsets.all(context.tokens.space(3)),
            child: Builder(builder: card),
          ),
  );
  overlay.insert(entry);
}
