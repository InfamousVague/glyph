/// What the note offers to do with boards, where the caret is: `src/app/editor/boardActions.ts`.
///
/// It was ported with the press-and-hold band that offers its rows (band/board_actions.dart), before the boards
/// themselves were drawn, and stays there with the band that calls it. This hands it on under the boards' own
/// room, so whoever reaches for a board finds what can be done with one beside what draws it.
library;

export '../band/board_actions.dart';
