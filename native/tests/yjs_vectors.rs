//! `yrs` held to the web app's own Yjs (docs/STAGE7.md, "Live typing and team notes"): `fixtures/yjs_web.json`
//! is what yjs 13 and y-protocols wrote (tool/yjs_vectors.mjs make) - updates from members editing at once,
//! state vectors, the difference for a vector, relative positions, awareness. Every test here reads some of it
//! through the commands the app calls.
//!
//! And the reverse: the last test makes the same kinds of thing with those commands and writes them to
//! `target/vectors/yjs_from_rust.json`, which `node tool/yjs_vectors.mjs check` reads with Yjs.

use serde_json::{json, Value};

fn fixture() -> Value {
    serde_json::from_str(include_str!("fixtures/yjs_web.json")).expect("fixtures/yjs_web.json")
}

fn ask(command: &str, args: Value) -> Value {
    ghost_core::dispatch::invoke(command, args).unwrap_or_else(|e| panic!("{command}: {e}"))
}

fn list<'a>(value: &'a Value, field: &str) -> &'a Vec<Value> {
    value[field].as_array().unwrap_or_else(|| panic!("no {field}"))
}

/// A document on this side, with a client id no fixture uses, holding `updates`.
fn open(client: u64, updates: &[&Value]) -> Value {
    let doc = ask("crdt_open", json!({"clientId": client}))["doc"].clone();
    take(&doc, updates);
    doc
}

fn take(doc: &Value, updates: &[&Value]) -> Value {
    ask("crdt_apply", json!({"doc": doc, "updates": updates}))
}

fn text(doc: &Value) -> Value {
    ask("crdt_text", json!({"doc": doc}))
}

fn state(doc: &Value) -> Value {
    ask("crdt_state", json!({"doc": doc}))
}

fn vector(doc: &Value) -> Value {
    ask("crdt_vector", json!({"doc": doc}))
}

/// Two state vectors that say the same, whatever order each lists its clients in.
fn same_vector(mine: &Value, theirs: &Value) -> bool {
    ask("crdt_lacks", json!({"mine": mine, "theirs": theirs})) == false && ask("crdt_lacks", json!({"mine": theirs, "theirs": mine})) == false
}

#[test]
fn a_document_the_web_seeded_is_read_and_seeding_the_same_words_writes_the_same_bytes() {
    let web = fixture();
    let seed = &web["seed"];
    let doc = ask("crdt_open", json!({"state": seed["update"], "clientId": 8001}));
    assert_eq!(doc["text"], seed["words"]);
    assert!(same_vector(&vector(&doc["doc"]), &seed["vector"]));
    // One client, one insert: the state vector and the whole state are Yjs's own bytes.
    assert_eq!(vector(&doc["doc"]), seed["vector"]);
    assert_eq!(state(&doc["doc"]), seed["update"]);
    // And a document seeded here by the same client with the same words is the same update.
    let ours = ask("crdt_open", json!({"words": seed["words"], "clientId": seed["client"]}));
    assert_eq!(ask("crdt_pending", json!({"doc": ours["doc"]})), json!([seed["update"]]));
}

#[test]
fn two_members_changes_merge_to_the_words_yjs_arrived_at_in_any_order() {
    let web = fixture();
    let c = &web["concurrent"];
    let (b_made, c_made) = (list(&c["b"], "updates"), list(&c["c"], "updates"));
    let orders: [Vec<&Value>; 3] = [
        b_made.iter().chain(c_made).collect(),
        c_made.iter().chain(b_made).collect(),
        c_made.iter().rev().chain(b_made.iter().rev()).collect(),
    ];
    for (i, order) in orders.iter().enumerate() {
        let doc = open(8010 + i as u64, &[&c["base"]]);
        take(&doc, order);
        assert_eq!(text(&doc), c["merged"], "order {i}");
        assert!(same_vector(&vector(&doc), &vector(&open(8020, &[&c["state"]]))));
    }
    // Each member's own words before hearing the other, and its state vector.
    let b = open(8030, &[&c["base"]]);
    take(&b, &b_made.iter().collect::<Vec<_>>());
    assert_eq!(text(&b), c["b"]["text"]);
    assert!(same_vector(&vector(&b), &c["b"]["vector"]));
    let only_c = open(8031, &[&c["base"]]);
    take(&only_c, &c_made.iter().collect::<Vec<_>>());
    assert_eq!(text(&only_c), c["c"]["text"]);
    assert_eq!(ask("crdt_lacks", json!({"mine": vector(&b), "theirs": c["c"]["vector"]})), true);
    // What Yjs answered B's state vector is all B lacked; what it answers a device with nothing is everything.
    let took = take(&b, &[&c["diffForB"]]);
    assert_eq!((&took["changed"], &took["text"]), (&json!(true), &c["merged"]));
    assert_eq!(text(&open(8032, &[&c["diffForNobody"]])), c["merged"]);
    assert_eq!(text(&open(8033, &[&c["state"]])), c["merged"]);
}

#[test]
fn an_update_that_arrives_before_what_it_builds_on_waits_for_it() {
    let web = fixture();
    let o = &web["outOfOrder"];
    let doc = open(8040, &[]);
    for (index, expected) in list(o, "order").iter().zip(list(o, "texts")) {
        let update = &o["updates"][index.as_u64().unwrap() as usize];
        assert_eq!(take(&doc, &[update])["text"], *expected, "after update {index}");
    }
    assert_eq!(text(&doc), o["text"]);
}

/// A change from the web that cuts a character in two (its `applyTextDiff`, an emoji swapped for a near one).
/// Yjs writes U+FFFD over both halves; yrs 0.26 cannot, so the cut is read from the update first and the
/// character written as U+FFFD twice here too (crdt.rs `mended`, crdt_wire.rs): this side arrives at the words
/// the rest of the team reads, and at the same document.
#[test]
fn a_change_from_the_web_that_splits_a_character_is_read_as_yjs_reads_it() {
    let web = fixture();
    let s = &web["splitCharacter"];
    let doc = open(8050, &[&s["base"]]);
    assert_eq!(text(&doc), "a😀b");
    let taken = take(&doc, &[&s["update"]]);
    assert_eq!(taken["changed"], true);
    assert_eq!(text(&doc), s["heard"]);
    assert_eq!(s["heardUnits"], json!([97, 0xFFFD, 0xFFFD, 98]));
    // The same in one call with the document itself, and a second time changes nothing.
    assert_eq!(text(&open(8052, &[&s["base"], &s["update"]])), s["heard"]);
    assert_eq!(take(&doc, &[&s["update"]])["changed"], false);
    // A caret after the first half is where Yjs has it: between the two.
    let caret = ask("crdt_relative", json!({"doc": doc, "index": 2}));
    assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": caret})), 2);
    // The document still takes this device's own changes, as the same client, and other members' updates.
    assert_eq!(ask("crdt_apply_diff", json!({"doc": doc, "to": "a😁b!"}))["text"], "a😁b!");
    assert_eq!(text(&open(8051, &[&state(&doc)])), "a😁b!");
}

#[test]
fn three_devices_240_steps_end_with_yjs_s_words_in_any_order() {
    let web = fixture();
    let r = &web["random"];
    let updates: Vec<&Value> = list(r, "updates").iter().map(|one| &one["update"]).collect();
    assert!(updates.len() > 150);
    let in_order = open(8060, &[]);
    for update in &updates {
        take(&in_order, &[update]);
    }
    assert_eq!(text(&in_order), r["text"]);
    assert_eq!(text(&in_order).as_str().unwrap().encode_utf16().count() as u64, r["length"].as_u64().unwrap());
    // Backwards, one at a time: every update waits for what it builds on.
    let backwards = open(8061, &[]);
    for update in updates.iter().rev() {
        take(&backwards, &[update]);
    }
    assert_eq!(text(&backwards), r["text"]);
    // All at once in one transaction, by client rather than by time.
    let mut by_client: Vec<&Value> = list(r, "updates").iter().collect();
    by_client.sort_by_key(|one| std::cmp::Reverse(one["client"].as_u64()));
    assert_eq!(take(&open(8062, &[]), &by_client.iter().map(|one| &one["update"]).collect::<Vec<_>>())["text"], r["text"]);
    assert_eq!(text(&open(8063, &[&r["state"]])), r["text"]);
    assert!(same_vector(&vector(&in_order), &vector(&open(8064, &[&r["state"]]))));
    assert!(same_vector(&vector(&in_order), &vector(&backwards)));
}

#[test]
fn a_relative_position_is_written_as_yjs_writes_it_and_placed_where_yjs_places_it() {
    let web = fixture();
    let p = &web["positions"];
    let doc = open(8070, &[&p["state"]]);
    assert_eq!(text(&doc), p["text"]);
    let at = list(p, "at");
    assert!(at.len() > 40);
    for one in at {
        let made = ask("crdt_relative", json!({"doc": doc, "index": one["index"], "assoc": one["assoc"]}));
        assert_eq!(made, one["json"], "index {} assoc {}", one["index"], one["assoc"]);
        assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": one["json"]})), one["index"], "{}", one["json"]);
    }
    // The words move under the carets: typed before them, typed after, some of what they sat in deleted.
    take(&doc, &list(p, "then").iter().collect::<Vec<_>>());
    assert_eq!(text(&doc), p["textAfter"]);
    for (one, index) in at.iter().zip(list(p, "after")) {
        assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": one["json"]})), *index, "{} (was {})", one["json"], one["index"]);
    }
    assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": p["stranger"]})), Value::Null);
    assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": p["elsewhere"]})), Value::Null);
}

#[test]
fn awareness_from_y_protocols_is_heard_as_y_protocols_hears_it() {
    let web = fixture();
    let a = &web["awareness"];
    let room = ask("awareness_open", json!({"clientId": a["hearer"]}))["awareness"].clone();
    for step in list(a, "steps") {
        let heard = ask("awareness_apply", json!({"awareness": room, "update": step["update"]}));
        for field in ["added", "updated", "removed"] {
            assert_eq!(heard[field], step["change"][field], "{}: {field}", step["label"]);
        }
        let mut states = serde_json::Map::new();
        let mut clocks = serde_json::Map::new();
        for one in ask("awareness_states", json!({"awareness": room})).as_array().unwrap() {
            if one["client"] != a["hearer"] {
                states.insert(one["client"].to_string(), one["state"].clone());
            }
        }
        // Clocks are kept for those who left too: read them back off the wire.
        for client in step["clocks"].as_object().unwrap().keys() {
            let update = ask("awareness_encode", json!({"awareness": room, "clients": [client.parse::<u64>().unwrap()]}));
            let bytes = ghost_core::crypto::from_base64url(update.as_str().unwrap()).unwrap();
            // count, client (two bytes for 4001 and 4002), clock.
            clocks.insert(client.clone(), json!(bytes[3]));
        }
        assert_eq!(Value::Object(states), step["states"], "{}", step["label"]);
        assert_eq!(Value::Object(clocks), step["clocks"], "{}", step["label"]);
    }
}

/// A team's canvas the web's Yjs made (core/team/canvas.ts's types: maps, an array, a text inside a map), read
/// here as the canvas it is, and written: only what differs, a card's words changed as words, a reply added to
/// the replies it has.
#[test]
fn a_canvas_the_web_made_is_read_from_its_types_and_written_into_them() {
    let web = fixture();
    let doc = open(8080, &[&web["canvas"]["state"]]);
    assert_eq!(text(&doc), web["canvas"]["text"]);
    assert_eq!(ask("crdt_canvas_has", json!({"doc": doc})), true);
    let read = ask("crdt_canvas_read", json!({"doc": doc}));
    let card = json!({"id": "card-1", "type": "text", "x": 120.5, "y": -40, "width": 260, "text": "A card día ✓ 😀"});
    assert_eq!(read, json!({"nodes": [card], "edges": [], "comments": [{"id": "t1", "replies": [{"by": "sam", "text": "yes", "at": 1759000000000u64}]}]}));
    // The same canvas written back is no change at all.
    let same = ask("crdt_canvas_write", json!({"doc": doc, "canvas": read}));
    assert_eq!((same["changed"].clone(), same["update"].clone()), (json!(false), Value::Null));
    // A document with no structure has none, and reads as an empty canvas.
    let plain = open(8081, &[&web["seed"]["update"]]);
    assert_eq!(ask("crdt_canvas_has", json!({"doc": plain})), false);
    assert_eq!(ask("crdt_canvas_read", json!({"doc": plain})), json!({"nodes": [], "edges": [], "comments": []}));
    // What is not a canvas is refused, and nothing is written.
    assert!(ghost_core::dispatch::invoke("crdt_canvas_write", json!({"doc": doc, "canvas": {"nodes": [{"x": 1}]}})).is_err());
    assert_eq!(ask("crdt_canvas_read", json!({"doc": doc})), read);
}

/// The canvas this side writes, for the test above's last half and for Yjs to read (`check`).
fn canvas_written(web: &Value, client: u64) -> (Value, Value, Value) {
    let doc = open(client, &[&web["canvas"]["state"]]);
    let next = json!({
        "nodes": [
            {"id": "card-2", "type": "text", "x": 0, "y": 0, "width": 200, "height": 80, "text": "New 😀 card"},
            {"id": "card-1", "type": "text", "x": 300, "y": -40, "width": 260, "text": "A card día ✓ 😁, moved", "color": "4"},
        ],
        "edges": [{"id": "e1", "fromNode": "card-1", "toNode": "card-2", "label": "to"}],
        "comments": [{"id": "t1", "replies": [{"by": "sam", "text": "yes", "at": 1759000000000u64}, {"by": "matt", "text": "and here", "at": 1759000001000u64}], "resolved": {"by": "matt", "at": "2026-10-09"}}],
    });
    let wrote = ask("crdt_canvas_write", json!({"doc": doc, "canvas": next}));
    assert_eq!(wrote["changed"], true);
    assert_eq!(ask("crdt_canvas_read", json!({"doc": doc})), next);
    (doc, next, wrote["update"].clone())
}

#[test]
fn a_canvas_written_here_holds_what_was_handed_in_and_a_second_copy_follows_from_the_update_alone() {
    let web = fixture();
    let (doc, next, update) = canvas_written(&web, 8082);
    let other = open(8083, &[&web["canvas"]["state"], &update]);
    assert_eq!(ask("crdt_canvas_read", json!({"doc": other})), next);
    // Two copies change different cards, and one card's words, apart: both keep what they did.
    let mut mine = next.clone();
    mine["nodes"][0]["x"] = json!(50);
    mine["nodes"][1]["text"] = json!("A card día ✓ 😁, moved by me");
    let mut theirs = next.clone();
    theirs["nodes"][1]["y"] = json!(99.5);
    theirs["nodes"][1]["text"] = json!("Their card día ✓ 😁, moved");
    theirs["nodes"].as_array_mut().unwrap().push(json!({"id": "card-3", "type": "group", "x": 1, "y": 2, "width": 3, "height": 4}));
    let a = ask("crdt_canvas_write", json!({"doc": doc, "canvas": mine}))["update"].clone();
    let b = ask("crdt_canvas_write", json!({"doc": other, "canvas": theirs}))["update"].clone();
    take(&doc, &[&b]);
    take(&other, &[&a]);
    let merged = ask("crdt_canvas_read", json!({"doc": doc}));
    assert_eq!(merged, ask("crdt_canvas_read", json!({"doc": other})));
    assert_eq!(merged["nodes"][0]["x"], 50);
    assert_eq!(merged["nodes"][1]["y"], 99.5);
    assert_eq!(merged["nodes"][1]["text"], "Their card día ✓ 😁, moved by me");
    assert_eq!(merged["nodes"][2]["id"], "card-3");
    // A structure seeded from words: marked as there.
    let fresh = ask("crdt_open", json!({"clientId": 8084, "words": "---\ntitle: Board\n---\n{}"}))["doc"].clone();
    assert_eq!(ask("crdt_canvas_has", json!({"doc": fresh})), false);
    ask("crdt_canvas_write", json!({"doc": fresh, "canvas": {"nodes": [], "edges": []}, "seed": true}));
    assert_eq!(ask("crdt_canvas_has", json!({"doc": fresh})), true);
}

/// What `node tool/yjs_vectors.mjs check` reads with Yjs.
#[test]
fn what_yrs_writes_is_written_down_for_yjs_to_read() {
    let web = fixture();

    // doc.ts `make`: a note's words seeded into a new document.
    let words = "# Packing\n\n- [ ] tent\n- [ ] día ✓ 😀\n";
    let seeded = ask("crdt_open", json!({"words": words, "clientId": 6001}));
    let doc = &seeded["doc"];
    let pending = ask("crdt_pending", json!({"doc": doc}));
    let seeded_out = json!({"text": seeded["text"], "state": state(doc), "pending": pending[0], "vector": vector(doc)});

    // Changes made here, each an update.
    let mut steps = Vec::new();
    let mut diff = |label: &str, to: &str| {
        let said = ask("crdt_apply_diff", json!({"doc": doc, "to": to}));
        assert_eq!(said["text"], to);
        steps.push(json!({"label": label, "update": said["update"], "text": said["text"]}));
    };
    diff("a word in the middle", "# Packing\n\n- [ ] the tent\n- [ ] día ✓ 😀\n");
    diff("a line at the end", "# Packing\n\n- [ ] the tent\n- [ ] día ✓ 😀\n- [ ] stove\n");
    diff("an emoji swapped whole", "# Packing\n\n- [ ] the tent\n- [ ] día ✓ 😁\n- [ ] stove\n");
    diff("a line gone", "# Packing\n\n- [ ] día ✓ 😁\n- [ ] stove\n");
    diff("a title changed and a family added", "# Packing list\n\n- [ ] día ✓ 😁\n- [ ] stove 👩‍👧\n");
    diff("everything gone", "");
    diff("and written again", "# Again\n\n日本語 ✓\n");
    let edited = ask("crdt_edit", json!({"doc": doc, "edits": [{"index": 2, "remove": 5, "insert": "Once more 😀"}, {"index": 0, "insert": "\u{feff}"}]}));
    steps.push(json!({"label": "an editor's two changes as one", "update": edited["update"], "text": edited["text"]}));
    let steps_state = state(doc);

    // Relative positions in that document, at every index a caret can sit.
    let units: Vec<u16> = text(doc).as_str().unwrap().encode_utf16().collect();
    let mut at = Vec::new();
    for index in 0..=units.len() {
        if index > 0 && index < units.len() && (0xD800..0xDC00).contains(&units[index - 1]) {
            continue;
        }
        for assoc in [0, -1, 1] {
            let position = ask("crdt_relative", json!({"doc": doc, "index": index, "assoc": assoc}));
            assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": position})), index, "{position}");
            at.push(json!({"index": index, "assoc": assoc, "json": position}));
        }
    }

    // A third member of the web's concurrent edit: holds the base and B's changes, changes the words itself,
    // then hears C.
    let c = &web["concurrent"];
    let third = open(6002, &[&c["base"]]);
    take(&third, &list(&c["b"], "updates").iter().collect::<Vec<_>>());
    let mut made = Vec::new();
    for to in [format!("{}P.S. from the phone\n", c["b"]["text"].as_str().unwrap()), format!("📱 {}P.S. from the phone 😀\n", c["b"]["text"].as_str().unwrap())] {
        made.push(ask("crdt_apply_diff", json!({"doc": third, "to": to}))["update"].clone());
    }
    take(&third, &list(&c["c"], "updates").iter().collect::<Vec<_>>());
    let merge = json!({
        "updates": made,
        "text": text(&third),
        "state": state(&third),
        "vector": vector(&third),
        "diffForB": ask("crdt_state", json!({"doc": third, "vector": c["b"]["vector"]})),
    });

    // The random run, held here and encoded again.
    let random = open(6003, &list(&web["random"], "updates").iter().map(|one| &one["update"]).collect::<Vec<_>>());
    assert_eq!(text(&random), web["random"]["text"]);
    let random = json!({"state": state(&random), "vector": vector(&random)});

    // Awareness: a device says who it is, where its caret is, where it is; a second joins; the first leaves.
    let mine = ask("awareness_open", json!({"clientId": 6004}));
    let other = ask("awareness_open", json!({"clientId": (1u64 << 40) + 5}));
    let hearer = ask("awareness_open", json!({"clientId": 6999}))["awareness"].clone();
    let mut awareness = Vec::new();
    let mut said = |label: &str, update: &Value| {
        ask("awareness_apply", json!({"awareness": hearer, "update": update}));
        let mut states = serde_json::Map::new();
        for one in ask("awareness_states", json!({"awareness": hearer})).as_array().unwrap() {
            if one["client"] != 6999 {
                states.insert(one["client"].to_string(), one["state"].clone());
            }
        }
        awareness.push(json!({"label": label, "update": update, "states": states}));
    };
    said("a device that has said nothing yet", &mine["update"]);
    let user = json!({"name": "matt", "hue": "moss", "color": "oklch(var(--app-hue-lift) var(--app-hue-chroma) 150)", "colorLight": "oklch(var(--app-hue-lift) var(--app-hue-chroma) 150 / 0.24)"});
    said("who it is", &ask("awareness_set", json!({"awareness": mine["awareness"], "field": "user", "value": user}))["update"]);
    let caret = json!({"anchor": at[9]["json"], "head": at[at.len() - 3]["json"]});
    said("where its caret is", &ask("awareness_set", json!({"awareness": mine["awareness"], "field": "cursor", "value": caret}))["update"]);
    let place = json!({"note": "n1", "title": "Roadmap día ✓ 😀", "kind": "note", "cursor": caret, "pointer": null});
    said("where it is in the organization", &ask("awareness_set", json!({"awareness": mine["awareness"], "field": "at", "value": place}))["update"]);
    let theirs = ask("awareness_set", json!({"awareness": other["awareness"], "state": {"user": {"name": "sam", "hue": null}, "at": {"note": "c1", "title": "Board", "kind": "canvas", "cursor": null, "pointer": {"x": 120.5, "y": -40}}}}));
    ask("awareness_apply", json!({"awareness": mine["awareness"], "update": theirs["update"]}));
    said("two devices in one update, one with a long id", &ask("awareness_encode", json!({"awareness": mine["awareness"]})));
    said("leaving", &ask("awareness_set", json!({"awareness": mine["awareness"], "state": null}))["update"]);

    // A canvas written through this side's own types: what Yjs must read of it, and the update alone.
    let (written, wrote, wrote_update) = canvas_written(&web, 6008);
    let canvas_types = json!({"state": state(&written), "canvas": wrote, "update": wrote_update});

    // A canvas's document through this side: its words changed here, everything else carried.
    let canvas = open(6006, &[&web["canvas"]["state"]]);
    let changed = ask("crdt_apply_diff", json!({"doc": canvas, "to": "---\ntitle: Board 2\n---\n"}));
    let canvas = json!({"state": state(&canvas), "text": changed["text"]});

    // The web's cut through a character, read here as Yjs reads it and then typed after: this side's document,
    // and what it sends on, for Yjs to read.
    let split = open(6007, &[&web["splitCharacter"]["base"], &web["splitCharacter"]["update"]]);
    let typed = ask("crdt_edit", json!({"doc": split, "edits": [{"index": 2, "insert": "😀"}, {"index": 6, "insert": "!"}]}));
    let split = json!({"state": state(&split), "text": typed["text"], "update": typed["update"]});

    let out = json!({
        "fixture": web["made"],
        "split": split,
        "seeded": seeded_out,
        "steps": steps,
        "stepsState": steps_state,
        "positions": {"state": steps_state, "at": at},
        "merge": merge,
        "random": random,
        "awareness": awareness,
        "canvas": canvas,
        "canvasTypes": canvas_types,
    });
    let target = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("target/vectors");
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(target.join("yjs_from_rust.json"), serde_json::to_string(&out).unwrap()).unwrap();
}
