import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/compound.dart';

/// One recording with several requests (lib/capture/compound.dart), case for case with the web's
/// `capture/compound.test.ts`.
void main() {
  group('splitCommands', () {
    test('leaves one request as it was', () {
      for (final said in [
        'make a new list called games and add to the list Zelda and Kirby',
        'add to the vegetables list spinach and kale',
        'make a new list called games? Add to the games list. Zelda. Can you also add? Spiderman PS4. And Lego Star Wars.',
      ]) {
        expect(splitCommands(said), [said]);
      }
    });

    test('splits at a second addition to another list', () {
      expect(splitCommands('add to the elements list? Gold. Carbon. And. . Helium. And then add to the posters list. Genes. Chroma copia. And. On air.'), [
        'add to the elements list? Gold. Carbon. And. . Helium',
        'add to the posters list. Genes. Chroma copia. And. On air.',
      ]);
    });

    test('splits at a new note or list being made', () {
      expect(splitCommands('add to the movies list? . Captain America. Shawn of the Dead. And can you make a new note called? Elements. And add magnesium, aluminum, titanium.'), [
        'add to the movies list? . Captain America. Shawn of the Dead',
        'make a new note called? Elements. And add magnesium, aluminum, titanium.',
      ]);
      expect(
        splitCommands('make me a new list called tools. And put in that list hammer. Screwdriver. And then can you make me a new note called thoughts for the day. And put in thoughts for the day that I am thinking about starting a podcast'),
        [
          'make me a new list called tools. And put in that list hammer. Screwdriver',
          'make me a new note called thoughts for the day. And put in thoughts for the day that I am thinking about starting a podcast',
        ],
      );
    });

    test('does not split at a verb that is part of an item or is not about notes', () {
      const said = 'make a new list called chores and add make dinner, put away dishes and start laundry';
      expect(splitCommands(said), [said]);
    });
  });
}
