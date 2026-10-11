/**
 * The note the board tests share (core/boards/*.test.ts): a title, one ```board fence of three columns, and five
 * to-dos, four of them anchored and on the board - one ticked, and in Done - and one on no board at all.
 *
 * Its line numbers are what the tests point at, counting from 1: the title is line 1, the fence lines 3 to 7, the
 * items lines 9 to 13. It was one file's fixture until that file was split with the module it tests, and a copy in
 * each part would have been three notes free to drift.
 */
export const LAUNCH_WEEK = `# Launch week

\`\`\`board
To do: ship-page, email-list
In progress: fix-login
Done: pick-date
\`\`\`

- [ ] Ship the pricing page ^ship-page
- [ ] Email the beta list ^email-list
- [ ] Fix the login button ^fix-login
- [x] Pick a launch date ^pick-date
- [ ] Something not on the board
`;
