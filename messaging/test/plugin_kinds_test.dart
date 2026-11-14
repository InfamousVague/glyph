import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/plugins/kinds.dart';
import 'package:ghost_messaging/plugins/plugin.dart';
import 'package:ghost_messaging/plugins/registry.dart';

/// Kinds of text (lib/plugins/kinds.dart): what a text from a number that is not a contact is about. Matt,
/// 2026-11-14: "tabs for messages with a intelligent spam filter, debt collectors, political messages, payment
/// reminders, tracking information, etc", and "also add in blocking of door to door sales and other sales messages
/// like tree trimming, gutter cleaning, buying the house, etc".
String? kindOf(String text, {bool contact = false, bool? outgoing}) {
  const plugin = KindsPlugin();
  final tags = plugin.classifiers.first(MessageFacts(thread: 1, senders: const ['+15559870001'], text: text, contact: contact, outgoing: outgoing));
  return tags.isEmpty ? null : tags.single.detail;
}

void main() {
  test('each kind is found by what the text says', () {
    expect(kindOf('This is an attempt to collect a debt. Call 800-555-0100.'), 'debt');
    expect(kindOf('Your account has been placed in collections. Settle your balance today.'), 'debt');
    expect(kindOf('Election day is Tuesday. Find your polling location at vote.example'), 'political');
    expect(kindOf('Chip in \$5 to keep us in this race! Paid for by Friends of Pat Rivera'), 'political');
    expect(kindOf('The GOP wants your input: take our 2-minute survey'), 'political');
    expect(kindOf('Your electric bill of \$84.12 is due on Nov 20.'), 'reminders');
    expect(kindOf('Payment reminder: your rent is due tomorrow.'), 'reminders');
    expect(kindOf('Your package is out for delivery. Tracking number 1Z999AA10123456784'), 'deliveries');
    expect(kindOf('Good news! Your order has shipped and is arriving Thursday.'), 'deliveries');
    expect(kindOf('Appointment reminder: Dr. Lee tomorrow at 9:30. Reply C to confirm.'), 'appointments');
    expect(kindOf('Your reservation is confirmed for 7pm Friday, party of 4.'), 'appointments');
  });

  test('door-to-door and other sales: tree trimming, gutters, buying the house, and the like', () {
    for (final pitch in [
      'Hi neighbor! Our crew is in your neighborhood this week doing tree trimming.',
      'Gutter cleaning special this fall, call for a free estimate!',
      'Hello, I would like to buy your house. Cash offer, close in 7 days.',
      'Have you thought about selling your home? We buy houses in any condition.',
      'We are working in your area tomorrow. Driveway sealing, 20% off.',
      'Free roof inspection after the storm, book now.',
      'Save on your power bill with solar panels: free consultation.',
      'Pressure washing and window cleaning, ask about our discount.',
      'FLASH SALE: 40% off everything, shop now. Reply STOP to opt out',
    ]) {
      expect(kindOf(pitch), 'sales', reason: pitch);
    }
  });

  test('the kinds that are hidden as the app ships, and the ones that are shown', () {
    final hidden = {for (final k in textKinds) if (k.hidden) k.id};
    expect(hidden, {'debt', 'political', 'sales'});
    for (final s in const KindsPlugin().sections) {
      expect(s.filter, isTrue, reason: '${s.id} is the filter\'s, not a tab');
    }
    expect(shippedPlugins.whereType<KindsPlugin>(), hasLength(1));
  });

  test('a contact is never sorted, nor your own words, and an everyday text is left alone', () {
    expect(kindOf('Paid for by Friends of Pat Rivera', contact: true), isNull);
    expect(kindOf('Your package is out for delivery', outgoing: true), isNull);
    for (final everyday in [
      'Can you vote on where we eat tonight?',
      'Running late, be there in 10',
      'Did you get the package I sent?',
      'Happy birthday!! 🎉',
      'Can you pay me back for the tickets?',
      'See you at the game on Saturday',
    ]) {
      expect(kindOf(everyday), isNull, reason: everyday);
    }
  });

  test('a scam dressed as a delivery or a bill is not shown as one: the Spam filter has it', () {
    expect(kindOf('USPS: your package could not be delivered, pay the redelivery fee now at bit.ly/3xYz'), isNull);
    expect(kindOf('URGENT: your bill payment failed, your account is suspended. Verify at http://pay.example'), isNull);
  });
}
