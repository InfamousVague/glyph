---
id: 1b4e28ba-2fa1-11d2-883f-b9a761bde3fb
created: 2026-10-01T09:00:00Z
updated: 2026-10-30T18:30:00Z
pinned: true
archived: false
source: typed
---
# Welcome

This library is a **fixture** for the publisher. It links every way a note can: to [[Trip plan]], to [[Trip plan|the trip]] by another name, to [[Trip]] by an alias, into a heading at [[Launch#Milestones]], to a ticket by its key [[GHO-1]], by its folder [[Work/Plan]], and to [[Nowhere]], which no page has.

![[Trip plan#Packing]]

![The ticket](image/aaaa1111-0000-4000-8000-000000000001.jpg)

The report is [in a file](file/report.pdf), and a picture the library lacks: ![gone](image/missing.jpg).

## Plan

```gantt
title: Waitlist launch
- Interview five users [2026-11-02 → 2026-11-04] @matt 100%
- Design the waitlist [2026-11-05 → 2026-11-11] @sam after: Interview five users 60%
- ◆ Launch [2026-11-20]
```

## Open tickets

```query
from: tickets
where: status != Done
columns: id, title, status, assignee
```

## Tell us

```form
thanks: Thanks, we'll look into it.
button: Send report
- Summary: short, required
- What happened: long
- How bad: choice (Annoying | Blocking)
- Your email: email, optional
```

Mark it [Done](ghost:set?status=Done) when you are through.[^c1]

- [ ] Book the venue ^venue
- [x] Pick the weekend ^weekend

```board
To do: venue
Done: weekend
```

```rules
When a ticket moves to Done, tell #launch.
Every Monday, list the tickets due this week.
```

```comments
c1 matt 2026-10-04T19:00:12Z
Is this the right place for the button?
  sam 2026-10-04T19:05:40Z
  Yes, leave it.
```
