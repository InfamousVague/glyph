//go:build cgo

package main

// With CGO (the phone's build, made with the NDK for Android's resolver) the encrypted chats' key store is SQLite
// through mattn/go-sqlite3, as the WhatsApp helper's is.

import _ "github.com/mattn/go-sqlite3"

const sqliteDriver = "sqlite3"

func sqliteURI(path string) string {
	return "file:" + path + "?_foreign_keys=on&_journal_mode=WAL&_busy_timeout=5000&_txlock=immediate"
}
