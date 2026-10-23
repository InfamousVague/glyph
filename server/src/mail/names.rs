//! A readable name for a mail-to-note address: `sneaky_siren33` (Matt, 2026-10-23: "instead of random numbers and
//! letters we get somewhat readable names like sneaky_siren33@in.ghostmarkdown.com or gangly_goul84 etc").
//!
//! An adjective, an underscore, a ghostly noun and two digits (Matt, 2026-10-23: "I also want the nouns to be spooky
//! ghost themes"): every noun is a ghost, a haunting or something found where one walks. The lists are lower-case a to z only, so a name is
//! the same however a mail program cases it, and every word is one a person can read aloud and spell back.
//! 160 adjectives, 160 nouns and 90 numbers make about 2.3 million names: far fewer than the 80 random bits the
//! old addresses had, so a name is easier to guess. Mail to a guessed name still arrives sealed, and the
//! address takes at most thirty an hour (mail.rs).

pub const ADJECTIVES: &[&str] = &[
    "ancient", "angry", "antsy", "awful", "baffled", "bashful", "batty", "beastly", "bewitched", "bitter",
    "bleak", "blighted", "bony", "bored", "brave", "breezy", "brooding", "bubbly", "bumpy", "chilly",
    "clammy", "clumsy", "cobwebby", "cold", "creaky", "creepy", "crooked", "cryptic", "curious", "cursed",
    "damp", "dapper", "daring", "dark", "dashing", "dismal", "dizzy", "dreadful", "dreamy", "dreary",
    "drowsy", "dusky", "dusty", "eerie", "eldritch", "empty", "faded", "feral", "fickle", "fiendish",
    "fizzy", "floaty", "foggy", "forlorn", "frosty", "fuzzy", "gangly", "gaunt", "ghastly", "giddy",
    "gilded", "glassy", "gloomy", "glowing", "gnarled", "goofy", "grim", "grimy", "groggy", "grouchy",
    "grumpy", "haunted", "hazy", "hollow", "howling", "hungry", "icy", "inky", "itchy", "jittery",
    "jolly", "jumpy", "lanky", "lonely", "loopy", "lost", "lucky", "lumpy", "lunar", "mangy",
    "misty", "moaning", "moody", "mossy", "murky", "musty", "mystic", "nervous", "nimble", "noisy",
    "odd", "ominous", "pale", "peculiar", "pesky", "plucky", "prickly", "puzzled", "quiet", "quirky",
    "rattling", "restless", "rickety", "rotten", "rusty", "salty", "scary", "scrawny", "shadowy", "shaggy",
    "shifty", "shivery", "shy", "silent", "silly", "sleepy", "slimy", "sly", "smoky", "sneaky",
    "snoozy", "soggy", "somber", "sooty", "spectral", "spindly", "spooky", "squeaky", "stormy", "strange",
    "sulky", "swampy", "tattered", "thorny", "timid", "tipsy", "twisted", "uncanny", "vexed", "wailing",
    "wan", "wary", "weary", "weird", "whimsical", "wicked", "wild", "wispy", "witchy", "wobbly",
];

pub const NOUNS: &[&str] = &[
    "apparition", "banshee", "barghest", "bat", "boggart", "bogey", "bogeyman", "bogle", "boneyard", "bones",
    "bugbear", "cackle", "cadaver", "casket", "catacomb", "cauldron", "chains", "changeling", "chill", "cloak",
    "cobweb", "coffin", "corpse", "coven", "crypt", "curse", "demon", "dirge", "doom", "doppelganger",
    "draugr", "dread", "dullahan", "duppy", "dusk", "echo", "eclipse", "ectoplasm", "eidolon", "ember",
    "entity", "epitaph", "familiar", "fang", "fetch", "fiend", "fog", "gallows", "gargoyle", "ghast",
    "ghost", "ghostling", "ghoul", "goblin", "golem", "grave", "gravedigger", "gravestone", "graveyard", "gremlin",
    "grim", "grimoire", "groan", "hag", "haint", "hangman", "harbinger", "haunt", "haunting", "hearse",
    "headstone", "hellhound", "hex", "hobgoblin", "hollow", "homunculus", "hound", "howl", "imp", "jinn",
    "kelpie", "knell", "lament", "lantern", "lemure", "lich", "limbo", "lurker", "mare", "mausoleum",
    "midnight", "mist", "moan", "monster", "mortician", "mummy", "murk", "necromancer", "nightmare", "nightshade",
    "omen", "onryo", "oracle", "ossuary", "pall", "phantasm", "phantom", "plague", "poltergeist", "presence",
    "raven", "reaper", "relic", "remains", "requiem", "revenant", "rune", "sarcophagus", "scarecrow", "scream",
    "seance", "sepulcher", "shade", "shadow", "shapeshifter", "shriek", "shroud", "siren", "skeleton", "skull",
    "soul", "specter", "spellbook", "spider", "spirit", "spook", "strix", "tomb", "tombstone", "umbra",
    "undead", "undertaker", "urn", "vampire", "vapor", "vault", "veil", "vision", "wail", "wake",
    "warlock", "wendigo", "werewolf", "whisper", "wight", "wisp", "witch", "wraith", "yurei", "zombie",
];

/// A fresh name: `<adjective>_<noun><10 to 99>`.
pub fn readable() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let adjective = ADJECTIVES[rng.gen_range(0..ADJECTIVES.len())];
    let noun = NOUNS[rng.gen_range(0..NOUNS.len())];
    format!("{adjective}_{noun}{}", rng.gen_range(10..100))
}

/// Whether `local` has the shape [`readable`] makes: lower-case letters, one underscore, letters, two digits.
pub fn is_readable(local: &str) -> bool {
    let Some((adjective, rest)) = local.split_once('_') else { return false };
    let bytes = rest.as_bytes();
    if adjective.is_empty() || bytes.len() < 3 || adjective.len() + rest.len() > 40 {
        return false;
    }
    let (noun, digits) = bytes.split_at(bytes.len() - 2);
    adjective.bytes().all(|b| b.is_ascii_lowercase()) && noun.iter().all(|b| b.is_ascii_lowercase()) && digits.iter().all(|b| b.is_ascii_digit())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn the_lists_are_plain_words_each_once() {
        for list in [ADJECTIVES, NOUNS] {
            let set: HashSet<_> = list.iter().collect();
            assert_eq!(set.len(), list.len(), "a word twice");
            assert!(list.iter().all(|w| !w.is_empty() && w.bytes().all(|b| b.is_ascii_lowercase())));
        }
        assert_eq!((ADJECTIVES.len(), NOUNS.len()), (160, 160));
    }

    #[test]
    fn a_name_reads_like_sneaky_siren33() {
        for _ in 0..500 {
            let name = readable();
            assert!(is_readable(&name), "{name}");
            let (adjective, rest) = name.split_once('_').unwrap();
            let (noun, number) = rest.split_at(rest.len() - 2);
            assert!(ADJECTIVES.contains(&adjective) && NOUNS.contains(&noun), "{name}");
            assert!((10..100).contains(&number.parse::<u32>().unwrap()), "{name}");
        }
        assert!(is_readable("sneaky_siren33") && is_readable("gangly_ghoul84"));
        for not in ["sneaky_siren3", "sneakysiren33", "_siren33", "sneaky_33", "Sneaky_siren33", "sneaky_si_ren33", "k7m2q3xh4t5vbn6p"] {
            assert!(!is_readable(not), "{not}");
        }
    }
}
