//! The one way this crate takes a `std::sync::Mutex`: poison is recovered,
//! never obeyed.
//!
//! A poisoned `Mutex` means some earlier holder panicked while it had the
//! guard. `lock().unwrap()` turns that one panic into a panic in every later
//! caller, and `if let Ok(..) = lock()` quietly skips the work instead - both
//! of which are how an app goes from having a bug to being a brick. Every value
//! this crate keeps behind a lock is either whole or `None` between statements
//! (a note library whose statements stand alone, a capture that is running or
//! is not, a list of links, a file lock guarding `()`), so the value a panic
//! left behind is still a value worth using, and recovering it is the honest
//! choice. A caller whose data could be left half-changed would need its own
//! answer; none does today, and one that did should say so where it locks.
//!
//! Lives in its own module rather than beside any one caller because it was
//! pasted into four modules and inlined in five more, and one copy
//! (`links.rs`) had drifted into dropping links on poison. Tauri-free, so
//! `whisper/` and `llm/` can use it without breaking their rule.

use std::sync::{Mutex, MutexGuard, PoisonError};

/// The guard, whether or not an earlier holder panicked with it.
pub fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_lock_poisoned_by_a_panic_still_hands_over_what_it_holds() {
        let shared = std::sync::Arc::new(Mutex::new(vec!["kept".to_string()]));
        let holder = std::sync::Arc::clone(&shared);
        let panicked = std::thread::spawn(move || {
            let mut guard = holder.lock().unwrap();
            guard.push("written before the panic".to_string());
            panic!("a holder dies with the guard");
        })
        .join();
        assert!(panicked.is_err());
        assert!(shared.is_poisoned(), "the setup has to poison it, or this proves nothing");
        let mut guard = lock(&shared);
        assert_eq!(*guard, ["kept", "written before the panic"]);
        guard.push("and it can still be written".to_string());
        drop(guard);
        assert_eq!(lock(&shared).len(), 3);
    }
}
