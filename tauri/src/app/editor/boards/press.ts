/**
 * A button on a board that answers a tap without the editor taking the press as a caret move: every control a board
 * draws - the tick, the words, the chevrons, the +, the card's menu and its rows - is pressed through this.
 *
 * A finger has to be stopped sooner than a mouse (Matt, on the phone: "I can't create a new issue on the board, as
 * soon as I open the board it closes again").
 *
 * A board shows its own lines instead of itself whenever the editor has the caret anywhere in its range, edges
 * included (editor/boards.ts `decorate`). A mouse is kept out by cancelling its `mousedown`. A tap is not: the phone
 * places a caret from the touch itself, before any mouse event is sent, and it lands at the board's edge - so the
 * board turned back into its lines at the moment the + was pressed, and the field that + opens went with it. It
 * worked with a mouse on a desktop every time, which is why it looked like a phone problem and was.
 *
 * Cancelling the `touchstart` is what keeps a caret from being placed, and it also stops the browser sending the
 * click that would follow, so the button answers on `touchend` instead - only when the finger lifts on the button,
 * so a finger that slides off to scroll does nothing.
 */

/** A click this soon after a tap that already ran is the browser sending the click anyway, and is not run again. */
const CLICK_AFTER_TAP_MS = 600;

export function press(button: HTMLElement, run: () => void): void {
  button.addEventListener('mousedown', (event) => event.preventDefault());
  let tapped = 0;
  button.addEventListener(
    'touchstart',
    (event) => {
      event.preventDefault();
    },
    { passive: false },
  );
  button.addEventListener('touchend', (event) => {
    event.preventDefault();
    const touch = event.changedTouches[0];
    const box = button.getBoundingClientRect();
    if (touch && (touch.clientX < box.left || touch.clientX > box.right || touch.clientY < box.top || touch.clientY > box.bottom)) return;
    tapped = Date.now();
    run();
  });
  button.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopPropagation();
    // A browser that sends the click anyway after a cancelled touch would run it twice.
    if (Date.now() - tapped < CLICK_AFTER_TAP_MS) return;
    run();
  });
}
