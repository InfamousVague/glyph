//go:build !cgo

package main

// Without CGO (the computers' builds) the encrypted chats' key store is modernc.org/sqlite, SQLite in pure Go.

import _ "modernc.org/sqlite"

const sqliteDriver = "sqlite"

func sqliteURI(path string) string {
	return "file:" + path + "?_pragma=foreign_keys(1)&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)&_pragma=busy_timeout(5000)&_txlock=immediate"
}
