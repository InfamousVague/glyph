import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/spoken_list.dart';

/// The items of a spoken list (lib/capture/spoken_list.dart), case for case with the web's
/// `capture/spokenList.test.ts`.
void main() {
  group('spoken list items', () {
    test('tells places apart by their state, with or without the commas Whisper writes', () {
      const places = ['Parkersburg, West Virginia', 'Marietta, Ohio', 'Balitmore, Maryland', 'Detroit, Michigan'];
      expect(spokenListItems('parkersburg west virginia marietta ohio balitmore maryland and detroit michigan'), places);
      expect(spokenListItems('Parkersburg, West Virginia, Marietta, Ohio, Balitmore, Maryland and Detroit, Michigan.'), places);
    });

    test('keeps a city named like a state, and state abbreviations', () {
      expect(spokenListItems('New York New York and Kansas City Missouri'), ['New York, New York', 'Kansas City, Missouri']);
      expect(spokenListItems('Austin TX, Columbus OH'), ['Austin, Texas', 'Columbus, Ohio']);
    });

    test('falls back to the ordinary split when the list is not places', () {
      expect(spokenListItems('milk, eggs and Texas toast'), ['milk', 'eggs', 'Texas toast']);
      expect(spokenListItems('Georgia and Virginia'), ['Georgia', 'Virginia']);
      expect(spokenListItems('milk eggs bread'), ['milk', 'eggs', 'bread']);
      expect(spokenListItems('Paris, Texas; Lyon, France'), ['Paris, Texas', 'Lyon, France']);
    });
  });
}
