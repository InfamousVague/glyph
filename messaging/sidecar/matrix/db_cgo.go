//go:build cgo

package main

// With CGO (the phone's build, made with the NDK for Android's resolver) mautrix's own driver is linked in already
// (go.mau.fi/util/dbutil/litestream on mattn/go-sqlite3, as the Signal helper uses): the store uses it, and modernc's is
// left out rather than carried twice.

const sqliteDriver = "sqlite3-fk-wal"

func sqliteURI(path string) string {
	return "file:" + path + "?_txlock=immediate&_busy_timeout=5000"
}
