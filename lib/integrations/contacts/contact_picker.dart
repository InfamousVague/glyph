/// "A person": a contact picked from the phone's address book, in a sheet with a field to search it by
/// (docs/INTEGRATIONS.md §2). What the + beside a line and a list item's Assign offer once Settings › Contacts is on;
/// the caller writes the name ([mentionOf]), `@Sam-Ortiz`, where it belongs.
///
/// The field narrows the book by the names that hold what is typed, accents and case aside ([contactsLike]); the
/// first fifty are listed, each with their face and the name it writes. Where the book cannot be read (turned off,
/// or not allowed since), the sheet says so in place of the list.
///
/// Built while it is open, as every sheet of the app is ([ContactPicker]); [pickContact] opens one over the app and
/// answers the contact pressed, or null where it was closed.
library;

import 'dart:async';

import 'package:flutter/services.dart' show TextInputAction, TextCapitalization;
import 'package:flutter/widgets.dart';

import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import 'contact_book.dart';
import 'contact_card.dart' show ContactFace;
import 'contact_match.dart';
import 'contacts.dart';

/// How many contacts the sheet lists at once: type to find the rest.
const int contactsListed = 50;

/// The sheet of contacts to pick from.
class ContactPicker extends StatefulWidget {
  const ContactPicker({super.key, required this.store, required this.onPick, required this.onClose, this.title = 'A person'});

  final ContactsStore store;
  final String title;

  /// A contact pressed; the sheet is closed first.
  final void Function(PhoneContact contact) onPick;
  final VoidCallback onClose;

  @override
  State<ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<ContactPicker> {
  String _typed = '';

  void _choose(PhoneContact contact) {
    final onPick = widget.onPick;
    widget.onClose();
    onPick(contact);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final found = contactsLike(store.everyone, _typed);
        final blocks = <Widget>[SheetTitle.text(widget.title)];
        if (!store.ready) {
          blocks.add(SheetNote(store.busy ? 'Reading your contacts…' : 'Turn on Settings › Contacts to pick someone from your contacts.'));
        } else {
          blocks
            ..add(
              SheetField(
                label: 'Search contacts',
                value: _typed,
                placeholder: 'Type a name',
                autoCorrect: false,
                autoCapitalize: TextCapitalization.words,
                enterKeyHint: TextInputAction.done,
                onChange: (text) => setState(() => _typed = text),
                onSubmitted: (_) {
                  if (found.isNotEmpty) _choose(found.first);
                },
              ),
            )
            ..add(
              found.isEmpty
                  ? SheetNote(store.everyone.isEmpty ? 'There is no one in your contacts.' : 'No contact by that name.')
                  : SheetGroup(
                      children: <Widget>[
                        for (final contact in found.take(contactsListed))
                          SheetRow.rich(
                            key: ValueKey<String>('contact:${contact.id}'),
                            icon: ContactFace(contact: contact, photo: store.photoOf(contact), size: 18),
                            label: Text(contact.name.isNotEmpty ? contact.name : (mentionOf(contact) ?? '')),
                            hint: mentionOf(contact) == null ? null : Text('@${mentionOf(contact)}'),
                            onPress: () => _choose(contact),
                          ),
                      ],
                    ),
            );
        }
        return Sheet(label: widget.title, onClose: widget.onClose, children: blocks);
      },
    );
  }
}

/// Opens the sheet of contacts over the app; answers the one pressed, or null for none.
Future<PhoneContact?> pickContact(BuildContext context, {ContactsStore? store, String title = 'A person'}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future<PhoneContact?>.value();
  final book = store ?? phoneContacts;
  // The book read again as the sheet opens, so someone just added is there.
  unawaited(book.read());
  final picked = Completer<PhoneContact?>();
  late final OverlayEntry entry;
  var shut = false;
  void close() {
    if (shut) return;
    shut = true;
    entry.remove();
    entry.dispose();
    // After the press that closed it has said whom it picked.
    scheduleMicrotask(() {
      if (!picked.isCompleted) picked.complete(null);
    });
  }

  entry = OverlayEntry(
    builder: (context) => ContactPicker(
      store: book,
      title: title,
      onClose: close,
      onPick: (contact) {
        if (!picked.isCompleted) picked.complete(contact);
      },
    ),
  );
  overlay.insert(entry);
  return picked.future;
}
