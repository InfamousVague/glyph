// Ghost.md's core in a browser (native/web, docs/WEB.md): the WebAssembly the phone's crypto, team documents and
// note names are built into, opened with as much of WASI as those files ask of it, and asked a command the way
// lib/core/native/ghost_worker.dart asks the phone's library over `dart:ffi`.
//
// Classic script, no modules: the worker takes it with importScripts, and tool/web_core_vectors.mjs reads it into
// Node to hold it to the web app's fixtures. It defines one global, GhostCoreWasm.
//
// What WASI is here: random bytes (crypto.getRandomValues, the generator the web app sealed with), the two
// clocks, no environment, and stderr to the console, where a panic says what it was. No file and no folder: the
// commands built in need none (native/web/src/lib.rs), and asking for one is the refusal a sandbox gives.
(function (scope) {
  'use strict';

  const ESUCCESS = 0;
  const EBADF = 8;
  const ENOSYS = 52;
  const ENOTCAPABLE = 76;

  function wasi(memory) {
    const view = () => new DataView(memory().buffer);
    const bytes = (ptr, len) => new Uint8Array(memory().buffer, ptr, len);
    let stderr = '';
    return {
      random_get(ptr, len) {
        // getRandomValues fills at most 65,536 bytes a call.
        for (let at = 0; at < len; at += 65536) scope.crypto.getRandomValues(bytes(ptr + at, Math.min(65536, len - at)));
        return ESUCCESS;
      },
      clock_time_get(id, _precision, out) {
        // 0 is the wall clock, the rest monotonic: nanoseconds, as WASI counts them.
        const ms = id === 0 ? Date.now() : scope.performance.now();
        view().setBigUint64(out, BigInt(Math.round(ms * 1e6)), true);
        return ESUCCESS;
      },
      environ_sizes_get(count, size) {
        view().setUint32(count, 0, true);
        view().setUint32(size, 0, true);
        return ESUCCESS;
      },
      environ_get() {
        return ESUCCESS;
      },
      fd_write(fd, iovs, count, written) {
        let total = 0;
        const text = new TextDecoder();
        for (let i = 0; i < count; i += 1) {
          const ptr = view().getUint32(iovs + i * 8, true);
          const len = view().getUint32(iovs + i * 8 + 4, true);
          if (fd === 1 || fd === 2) stderr += text.decode(bytes(ptr, len));
          total += len;
        }
        view().setUint32(written, total, true);
        const lines = stderr.split('\n');
        stderr = lines.pop();
        for (const line of lines) if (line) scope.console.error('[ghost core] ' + line);
        return fd === 1 || fd === 2 ? ESUCCESS : EBADF;
      },
      fd_prestat_get: () => EBADF,
      fd_prestat_dir_name: () => EBADF,
      fd_close: () => EBADF,
      fd_fdstat_get: () => EBADF,
      fd_filestat_get: () => EBADF,
      fd_read: () => EBADF,
      fd_sync: () => EBADF,
      path_open: () => ENOTCAPABLE,
      path_create_directory: () => ENOTCAPABLE,
      path_filestat_get: () => ENOTCAPABLE,
      path_rename: () => ENOTCAPABLE,
      path_unlink_file: () => ENOTCAPABLE,
      proc_exit(code) {
        throw new Error('Ghost.md\'s core exited with ' + code + '.');
      },
      sched_yield: () => ESUCCESS,
      _unknown: () => ENOSYS,
    };
  }

  // One instance of the core: `invoke(command, argsJson)` answers the JSON text native/src/ffi.rs answers,
  // `{"ok": …}` or `{"err": "…"}`. A trap (a panic: wasm32 has no unwinding) throws, and the instance is not to be
  // asked again; `GhostCoreWasm.open` makes another from the same compiled module.
  class Core {
    constructor(instance) {
      this.exports = instance.exports;
      this.memory = instance.exports.memory;
      this.encoder = new TextEncoder();
      this.decoder = new TextDecoder();
      // size_t is four bytes in wasm32: one slot for every answer's length, kept for the life of the instance.
      this.outLen = this.exports.ghost_alloc(4);
    }

    lend(bytes) {
      const ptr = this.exports.ghost_alloc(bytes.length);
      if (ptr === 0) throw new Error('no memory');
      // After the allocation: memory that grew has a new buffer.
      new Uint8Array(this.memory.buffer, ptr, bytes.length).set(bytes);
      return ptr;
    }

    invoke(command, argsJson) {
      const cmd = this.encoder.encode(command);
      const args = this.encoder.encode(argsJson || '');
      const cmdPtr = this.lend(cmd);
      const argsPtr = this.lend(args);
      try {
        const out = this.exports.ghost_invoke(cmdPtr, cmd.length, argsPtr, args.length, this.outLen);
        const len = new DataView(this.memory.buffer).getUint32(this.outLen, true);
        try {
          return this.decoder.decode(new Uint8Array(this.memory.buffer, out, len).slice());
        } finally {
          this.exports.ghost_free(out, len);
        }
      } finally {
        this.exports.ghost_free(cmdPtr, cmd.length);
        this.exports.ghost_free(argsPtr, args.length);
      }
    }
  }

  async function open(module) {
    let memory = null;
    const shim = wasi(() => memory);
    const imports = { wasi_snapshot_preview1: new Proxy(shim, { get: (all, name) => all[name] || all._unknown }) };
    const instance = await WebAssembly.instantiate(module, imports);
    memory = instance.exports.memory;
    if (instance.exports._initialize) instance.exports._initialize();
    return new Core(instance);
  }

  scope.GhostCoreWasm = { open, compile: (bytes) => WebAssembly.compile(bytes) };
})(typeof self !== 'undefined' ? self : globalThis);
