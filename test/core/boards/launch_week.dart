/// The note the board tests share (test/core/boards/*_test.dart): a title, one ```board fence of three columns, and
/// five to-dos, four of them anchored and on the board - one ticked, and in Done - and one on no board at all. The
/// web's `src/test/boards.ts`.
///
/// Its line numbers are what the tests point at, counting from 1: the title is line 1, the fence lines 3 to 7, the
/// items lines 9 to 13. A copy in each test file would have been three notes free to drift.
library;

/// `LAUNCH_WEEK`.
const String launchWeek = '''
# Launch week

```board
To do: ship-page, email-list
In progress: fix-login
Done: pick-date
```

- [ ] Ship the pricing page ^ship-page
- [ ] Email the beta list ^email-list
- [ ] Fix the login button ^fix-login
- [x] Pick a launch date ^pick-date
- [ ] Something not on the board
''';
