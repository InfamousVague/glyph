import '@testing-library/jest-dom/vitest';

/*
 * jsdom has no layout: CodeMirror measures its text by asking ranges for rectangles, and a measure scheduled on the
 * animation clock can fire after the test that made the view has finished - an uncaught TypeError that failed no
 * test and still made Vitest exit 1, which stopped a deploy at its test step with every test green.
 */
Range.prototype.getClientRects = () => ({ length: 0, item: () => null, [Symbol.iterator]: [][Symbol.iterator] }) as unknown as DOMRectList;
Range.prototype.getBoundingClientRect = () => new DOMRect();
