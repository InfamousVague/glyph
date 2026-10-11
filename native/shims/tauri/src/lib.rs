//! The two functions of `tauri::async_runtime` that `tauri/src-tauri/src/model_files.rs` names, and nothing
//! else of Tauri: this crate exists so that file is included unchanged (see Cargo.toml here).
//!
//! As in Tauri, one tokio runtime for the process, made on first use. Two workers, where Tauri takes one per
//! core: all that ever runs on it is one model download at a time.

pub mod async_runtime {
    use std::future::Future;
    use std::sync::OnceLock;

    pub use tokio::task::JoinHandle;

    fn runtime() -> &'static tokio::runtime::Runtime {
        static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
        RUNTIME.get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .thread_name("ghost-async")
                .enable_all()
                .build()
                .expect("the async runtime could not be started")
        })
    }

    /// Runs `work` on a thread where blocking is allowed; the handle is a future of its answer.
    pub fn spawn_blocking<F, R>(work: F) -> JoinHandle<R>
    where
        F: FnOnce() -> R + Send + 'static,
        R: Send + 'static,
    {
        runtime().spawn_blocking(work)
    }

    /// Runs `future` to its end on the runtime, blocking the calling thread (never one of the runtime's own).
    pub fn block_on<F: Future>(future: F) -> F::Output {
        runtime().block_on(future)
    }

    #[cfg(test)]
    mod tests {
        #[test]
        fn a_blocking_job_is_awaited_inside_block_on() {
            let answer = super::block_on(async { super::spawn_blocking(|| 6 * 7).await });
            assert_eq!(answer.ok(), Some(42));
        }
    }
}
