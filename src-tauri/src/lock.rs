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

use std::sync::{Mutex, MutexGuard, PoisonError, TryLockError};

/// The guard, whether or not an earlier holder panicked with it.
pub fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

/// The guard if nobody else holds it, poisoned or not, and `None` while
/// somebody does. For the locks a caller refuses rather than waits on: a
/// meeting's write-up and a recording's refine pass both want small.en, and
/// the second to arrive says "busy" instead of loading it twice
/// (`guards::try_write_up`). The same poison rule as `lock`, for the same
/// reason: a pass that panicked with the guard must not make every later pass
/// answer "busy" for the life of the process.
pub fn try_lock<T>(mutex: &Mutex<T>) -> Option<MutexGuard<'_, T>> {
    match mutex.try_lock() {
        Ok(guard) => Some(guard),
        Err(TryLockError::Poisoned(poisoned)) => Some(poisoned.into_inner()),
        Err(TryLockError::WouldBlock) => None,
    }
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

    #[test]
    fn a_try_answers_none_only_while_somebody_else_holds_the_lock() {
        let shared = std::sync::Arc::new(Mutex::new(0));
        let held = try_lock(&shared).expect("nobody holds it");
        assert!(try_lock(&shared).is_none(), "held by this thread");
        drop(held);
        assert!(try_lock(&shared).is_some());
        // Poisoned by a panic, and still handed over rather than refused.
        let holder = std::sync::Arc::clone(&shared);
        let _ = std::thread::spawn(move || {
            let _guard = holder.lock().unwrap();
            panic!("dies with the guard");
        })
        .join();
        assert!(shared.is_poisoned());
        assert!(try_lock(&shared).is_some(), "poison is recovered, not obeyed");
    }
}
