# Forms from a share link

Matt, 2026-10-30, the ninth of a list of plain-Markdown features ("add all 12"): a share link that lets anyone
outside the team fill in a few fields, and lands a ticket in a notebook. Bug reports and requests.

## The note

A form is a note with a ```` ```form ```` fence. What the note says outside the fence is the form's introduction.

````markdown
# Report a bug

Something not working? Tell us what happened.

```form
to: [[Bug reports]]
ticket: Bug: {Summary}
template: Bug report
thanks: Thanks, we'll look into it.
button: Send report
- Summary: short, required
- What happened: long, required
- How bad: choice (Annoying | Blocking | Lost work)
- Your email: email, optional
- Screenshot: file
```
````

- A field is `- Label: kind`. The kind is `short` (one line), `long` (a paragraph), `choice` (one of the options
  in brackets, split by `|` or `,`), `email` or `file`. Then `required` or `optional`; optional unless it says so. A
  field with no kind is short, and `- Label*` is required. Thirty fields at most.
- `to` is the notebook its tickets go into; left out, the notebook the form is a page of. `ticket` is a ticket's
  title, `{Label}` standing for that field's answer; left out, the first answer. `template` names a ticket template
  (a Templates notebook's page, or the built-in Bug report and Feature).
- `to`, `ticket` and `template` are the owner's. The share carries only the introduction and the rest of the fence
  (`publicFormBody`).
- A notebook's index offers **New form…**, which makes a page starting with a fence that files into that notebook.

The grammar is read twice, the same way: lib/forms/form_def.dart and tauri/src/read/form.ts.

## Sharing it

A form is shared as any note is (docs/SHARING.md). The device then tells glyph-api the share is a form
(`PUT /api/v1/forms/{share id}`): its note's id, whether it takes a file, and the organization whose members file it
(the team's whose workspace the form's notebook is in, or none). The share sheet does this at once; the sync pass
does it too. The reader page draws a share that holds a form fence as a form rather than a note.

The share sheet's Form rows: Taking answers, Paused, Closed (the link says so), the count of answers filed and
waiting, and Delete the answers waiting (behind More in simple mode).

## Answering

No account, no sign-in. The reader asks `GET /api/forms/{id}` for the form's state, the public keys to seal to (the
owner's encryption key, or every member's of the team who has one) and a ticket. On Send the browser seals:

1. a fresh 32-byte key; the answers as JSON (`{ v: 1, answers: [[label, words], ...], file?, at }`) sealed under it
   as `sealBytes` seals (version byte, IV, AES-256-GCM) with `form:<form id>:<answer id>` as associated data: the
   `blob`;
2. that key wrapped to each recipient by `wrapFor` (ECDH P-256, HKDF-SHA-256, AES-256-GCM) in the context
   `form-key:<form id>:<answer id>`: the `wraps`, each `{ to, wrap }`.

It sends `POST /api/forms/{id}` with `{ id, ticket, wraps, blob, hp }` and nothing else; the service refuses a body
with any other field, a blob or a wrap not shaped as a seal, and a wrap to a key that is not a recipient. Then the
owner's thanks.

Against abuse: twenty answers an hour per address, thirty a minute per form; 64 KB sealed, 3 MB for a form with a file
(the page takes files of up to 2 MB); five hundred waiting per form, fifty with a file; a hidden field (`hp`, named
`website` on the page) that a bot fills is answered as if kept and keeps nothing; the ticket, signed by the service
with a key in its database, must be three seconds to a day old.

## Filing

A step of the sync pass (lib/forms/form_inbox.dart `syncForms`), before the notes step, on every device:

- the inbox, a hundred at a time; an answer not sealed to this account's key is left for a teammate;
- **claimed** first (`POST /api/v1/forms/inbox/{id}/claim`, held two minutes by one device; another's live claim is
  409 and passed over);
- opened with the account's pair; filed as a ticket under an id made from the answer's (`formTicketId`), its
  notebook's next key and workflow, the template filled; `via: form`, `form: [[the form]]`, `answered:`, `email:`
  and the short answers in the front matter; each answer under its label in the body; a picture or a file kept; the
  line saying it came by the form and when; into the notebook's index and its workspace;
- the bell told (`form-answer`, shown as an invitation is);
- then acked (`DELETE /api/v1/forms/inbox/{id}`): the answer goes, and the form counts it filed.

Exactly once: the claim keeps an answer to one device; a ticket already here (filed by another device and synced) is
only acked; one filed by two devices after a lapsed claim is one note, as both write the same id. Whatever is never
filed goes after thirty days.

## Mixed versions

Deploy glyph-api first, then the reader, then the app. An older app knows nothing of forms: a form note shares as a
plain note, and the reader shows its fence as code until the app says the share is a form. An older reader shows a
form share as a note. A reader on a service without the form routes says the form was taken down. A newer app against
an older service is quiet (the routes answer 404 `no such route`, which the step reads as not yet). An older build
does not draw the `form-answer` notification.
