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

// --- a name of one's own -------------------------------------------------------------------------------------------

/// The shortest and the longest a name of a person's own may be (Matt, 2026-10-24: "i'd like you to add the ability
/// to create our own custom name for the email if the name is available like matt@in.ghostmarkdown.com").
pub const CHOSEN_LENGTH: std::ops::RangeInclusive<usize> = 3..=30;

/// Names nobody is given, compared with their dots, dashes and underscores taken out, so `no-reply`, `no.reply` and
/// `noreply` are one name. The mailboxes RFC 2142 and the mail providers expect a domain to answer for (postmaster,
/// abuse, hostmaster and the rest), the ones a person would take for the service speaking (ghost, support, billing),
/// and the words mail is filed under (calendar, invite, bounce): an address that reads as Ghost.md's own would be the
/// easiest way to pass as it.
pub const RESERVED: &[&str] = &[
    "abuse", "account", "accounts", "admin", "administrator", "alerts", "all", "api", "app", "billing", "bot", "bounce",
    "bounces", "calendar", "contact", "daemon", "dkim", "dmarc", "email", "everyone", "ftp", "ghost", "ghostbot", "ghostmd",
    "ghostmarkdown", "glyph", "hello", "help", "hostmaster", "imap", "info", "invite", "invites", "legal", "list",
    "listserv", "mail", "mailer", "mailerdaemon", "mailgun", "majordomo", "meet", "meeting", "meetings", "mx", "news",
    "nobody", "noreply", "notifications", "null", "official", "operator", "owner", "pop", "postmaster", "privacy",
    "recordings", "reply", "root", "sales", "security", "smtp", "spf", "staff", "support", "sysadmin", "system", "team",
    "test", "webmaster", "www",
];

/// Why a name a person typed may not be theirs, each with the words a device is told it in. The app checks the same
/// before it asks (lib/mail/mail_name.dart), so these words are what a person sees only from an older app.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Unfit {
    /// Something besides a to z, 0 to 9, `.`, `-` and `_`.
    Characters,
    Short,
    Long,
    /// A dot, dash or underscore first, last, or beside another.
    Separators,
    /// The shape the service's own names have: sixteen base32 letters and digits, or `sneaky_siren33` from the lists.
    Generated,
    Reserved,
}

impl Unfit {
    /// The word a device is told it by, `reason` in the answer.
    pub fn code(self) -> &'static str {
        match self {
            Unfit::Characters => "characters",
            Unfit::Short => "short",
            Unfit::Long => "long",
            Unfit::Separators => "separators",
            Unfit::Generated => "generated",
            Unfit::Reserved => "reserved",
        }
    }

    pub fn words(self) -> &'static str {
        match self {
            Unfit::Characters => "Only letters, numbers, dots, dashes and underscores.",
            Unfit::Short => "At least 3 characters.",
            Unfit::Long => "At most 30 characters.",
            Unfit::Separators => "A dot, dash or underscore goes between letters or numbers, one at a time.",
            Unfit::Generated => "That looks like a name Ghost.md makes up. Choose one of your own.",
            Unfit::Reserved => "That name is reserved.",
        }
    }
}

/// A name as typed, as it is kept and compared: trimmed and lower-cased, so `Matt` and `matt` are one name.
pub fn normal(typed: &str) -> String {
    typed.trim().to_ascii_lowercase()
}

/// Whether `local` is shaped as a person's own name may be: 3 to 30 of a to z and 0 to 9, with single dots, dashes
/// or underscores between them. What a mail's recipient is read by (mail.rs `locals`); [`chosen`] asks more.
pub fn shaped(local: &str) -> bool {
    unfit_shape(local).is_none()
}

fn separator(b: u8) -> bool {
    matches!(b, b'.' | b'-' | b'_')
}

fn unfit_shape(local: &str) -> Option<Unfit> {
    let bytes = local.as_bytes();
    if !bytes.iter().all(|&b| b.is_ascii_lowercase() || b.is_ascii_digit() || separator(b)) {
        return Some(Unfit::Characters);
    }
    if bytes.len() < *CHOSEN_LENGTH.start() {
        return Some(Unfit::Short);
    }
    if bytes.len() > *CHOSEN_LENGTH.end() {
        return Some(Unfit::Long);
    }
    let doubled = bytes.windows(2).any(|pair| separator(pair[0]) && separator(pair[1]));
    if separator(bytes[0]) || separator(bytes[bytes.len() - 1]) || doubled {
        return Some(Unfit::Separators);
    }
    None
}

/// Whether `local` is one the service could have made itself: the old sixteen base32 letters and digits, or a
/// [`readable`] name from the lists. A person may take neither, so no chosen name passes for a made one, or is in
/// the way of one: the old addresses replaced before 2026-10-24 were not kept (store/mail.rs), and this keeps any
/// of them from being someone else's by choice.
fn generated(local: &str) -> bool {
    let old = local.len() == super::LOCAL_LENGTH && local.bytes().all(|b| super::ALPHABET.contains(&b));
    let made = is_readable(local) && {
        let (adjective, rest) = local.split_once('_').unwrap_or_default();
        let (noun, _) = rest.split_at(rest.len() - 2);
        ADJECTIVES.contains(&adjective) && NOUNS.contains(&noun)
    };
    old || made
}

/// Why `name`, [`normal`] already, may not be a person's own, or `None` when it may (whether it is free is the
/// store's to say).
pub fn chosen(name: &str) -> Option<Unfit> {
    if let Some(unfit) = unfit_shape(name) {
        return Some(unfit);
    }
    if generated(name) {
        return Some(Unfit::Generated);
    }
    let bare: String = name.chars().filter(|c| !matches!(c, '.' | '-' | '_')).collect();
    if RESERVED.contains(&bare.as_str()) {
        return Some(Unfit::Reserved);
    }
    None
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

    #[test]
    fn a_name_of_one_s_own_is_three_to_thirty_letters_digits_and_single_separators_between() {
        let thirty = "a".repeat(30);
        for fit in ["matt", "m.t", "sam-lee", "sam_lee", "a.b-c_d", "abc", "x2024", "123", "matt.smith.1987", thirty.as_str()] {
            assert_eq!(chosen(fit), None, "{fit}");
            assert!(shaped(fit), "{fit}");
        }
        let long = "a".repeat(31);
        for (unfit, why) in [
            ("ma", Unfit::Short),
            ("", Unfit::Short),
            (long.as_str(), Unfit::Long),
            ("matt smith", Unfit::Characters),
            ("Matt", Unfit::Characters),
            ("matt+tag", Unfit::Characters),
            ("mätt", Unfit::Characters),
            ("matt@x", Unfit::Characters),
            (".matt", Unfit::Separators),
            ("matt-", Unfit::Separators),
            ("ma..tt", Unfit::Separators),
            ("ma-_tt", Unfit::Separators),
            ("k7m2q3xh4t5vbn6p", Unfit::Generated),
            ("abcdefghijklmnop", Unfit::Generated),
            ("sneaky_siren33", Unfit::Generated),
            ("postmaster", Unfit::Reserved),
            ("abuse", Unfit::Reserved),
            ("no-reply", Unfit::Reserved),
            ("no.reply", Unfit::Reserved),
            ("mailer-daemon", Unfit::Reserved),
            ("ghost.md", Unfit::Reserved),
            ("ghost", Unfit::Reserved),
            ("calendar", Unfit::Reserved),
        ] {
            assert_eq!(chosen(unfit), Some(why), "{unfit:?}");
        }
        assert!(!shaped("sneaky_siren33x!") && shaped("sneaky_siren33"), "the shape alone lets made names by");
        // Sixteen with a 1, 8, 9 or 0 in them is no base32 the service made; the readable shape with words not on
        // the lists is a person's.
        assert_eq!(chosen("k7m2q3xh4t5vbn61"), None);
        assert_eq!(chosen("matt_smith42"), None);
        assert_eq!(normal("  Matt.Smith "), "matt.smith");
        for unfit in [Unfit::Characters, Unfit::Short, Unfit::Long, Unfit::Separators, Unfit::Generated, Unfit::Reserved] {
            assert!(!unfit.code().is_empty() && unfit.words().ends_with('.'));
        }
        let mut sorted = RESERVED.to_vec();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(sorted.len(), RESERVED.len(), "a reserved name twice");
        assert!(RESERVED.iter().all(|r| r.bytes().all(|b| b.is_ascii_lowercase())), "kept bare, as they are compared");
    }
}
