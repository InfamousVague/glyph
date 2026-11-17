// Ghost Messaging's WhatsApp helper (README.md, PROTOCOL.md). MPL-2.0, as whatsmeow, on which it is built.
//
// Matt, 2026-11-17: "enable whatsapp but warn the user that it's unsupported by whatsapp". It links to the person's
// WhatsApp account as a linked device, as WhatsApp Web does, and speaks JSON lines over standard input and output, in
// the same shape as the Signal helper (sidecar/signal). Requests, each with an "id" its answer carries back:
//
//	{"id":1,"op":"status"}                                    → {"linked","connected","jid","number","name"}
//	{"id":2,"op":"link","name":"Ghost Messaging"}             → null, then events "qr" (a new one every ~20 s) and "linked" or "link_failed"
//	{"id":3,"op":"pair_phone","phone":"+15550100"}            → {"code":"ABCD-EFGH"}: WhatsApp's "Link with phone number instead"
//	{"id":4,"op":"unlink"}                                    → null; everything forgotten
//	{"id":5,"op":"contacts"}                                  → [{"jid","name","number","avatar"}…]
//	{"id":6,"op":"groups"}                                    → [{"id","title","members","avatar"}…]
//	{"id":7,"op":"send","to":"…","text":"…","quote":{"id","author","text"}} → {"id":"<message id>","ts":…}
//	{"id":8,"op":"send_media","to":"…","path":"…","mime":"…","name":"…","text":"…"} → {"id","ts","pointer"}
//	{"id":9,"op":"read","to":"…","author":"…","ids":[…]}      → null
//	{"id":10,"op":"react","to":"…","author":"…","target":"…","emoji":"👍","remove":false} → null
//	{"id":11,"op":"delete","to":"…","target":"…"}             → null (your own message, for everyone)
//	{"id":12,"op":"download","pointer":{…},"path":"…"}        → null once written
//	{"id":13,"op":"who","jid":"…"}                            → {"jid","name","number","avatar"}
//	{"id":14,"op":"block","jid":"…","on":true}                → null
//	{"id":15,"op":"blocked"}                                  → [{"jid","name","number","avatar"}…]
//	{"id":16,"op":"group_info","to":"<group jid>"}            → the group in full
//
// Answers: {"id":1,"ok":true,"result":…} or {"id":1,"ok":false,"error":"…"}. Events, unasked, each with "ev": ready,
// qr, pair_code, linked, link_failed, connected, disconnected, message, history, receipt, reaction, deleted, contacts,
// name, group, unlinked.
package main

import (
	"bufio"
	"bytes"
	"cmp"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"github.com/rs/zerolog"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"

	"go.mau.fi/whatsmeow"
	waCompanionReg "go.mau.fi/whatsmeow/proto/waCompanionReg"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waHistorySync"
	"go.mau.fi/whatsmeow/proto/waWeb"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
)

// deviceName is what WhatsApp shows in the phone's Linked devices.
const deviceName = "Ghost Messaging"

type quote struct {
	ID     string `json:"id"`
	Author string `json:"author"`
	Text   string `json:"text"`
}

type request struct {
	ID      int64           `json:"id"`
	Op      string          `json:"op"`
	Name    string          `json:"name"`
	Phone   string          `json:"phone"`
	To      string          `json:"to"`
	Text    string          `json:"text"`
	Quote   *quote          `json:"quote"`
	Path    string          `json:"path"`
	Mime    string          `json:"mime"`
	Author  string          `json:"author"`
	IDs     []string        `json:"ids"`
	Target  string          `json:"target"`
	Emoji   string          `json:"emoji"`
	Remove  bool            `json:"remove"`
	Pointer json.RawMessage `json:"pointer"`
	JID     string          `json:"jid"`
	On      bool            `json:"on"`
}

var (
	dir     string
	log     zerolog.Logger
	out     = json.NewEncoder(os.Stdout)
	outLock sync.Mutex

	mu        sync.Mutex
	container *sqlstore.Container
	cli       *whatsmeow.Client
	connected bool
	linking   context.CancelFunc
	inflight  sync.WaitGroup
)

func say(v any) {
	outLock.Lock()
	defer outLock.Unlock()
	_ = out.Encode(v)
}

// event says [name] with [fields] beside "ev".
func event(name string, fields map[string]any) {
	m := map[string]any{"ev": name}
	for k, v := range fields {
		m[k] = v
	}
	say(m)
}

func main() {
	flag.StringVar(&dir, "dir", "", "where the WhatsApp store is kept")
	flag.Parse()
	if dir == "" {
		fmt.Fprintln(os.Stderr, "--dir is needed")
		os.Exit(2)
	}
	_ = os.MkdirAll(dir, 0o700)
	// whatsmeow's log goes to standard error (Ghost's developer log) and whatsapp.log beside the store; never stdout.
	log = zerolog.New(zerolog.MultiLevelWriter(os.Stderr, logFile())).With().Timestamp().Logger().Level(zerolog.InfoLevel)
	out.SetEscapeHTML(false)
	// The name WhatsApp shows for this device in Linked devices.
	store.SetOSInfo(deviceName, [3]uint32{0, 8, 0})
	store.DeviceProps.PlatformType = waCompanionReg.DeviceProps_DESKTOP.Enum()
	if err := openStore(); err != nil {
		log.Err(err).Msg("open store")
		fmt.Fprintln(os.Stderr, "the WhatsApp store could not be opened:", err)
		os.Exit(1)
	}
	if dev := firstDevice(); dev != nil {
		mu.Lock()
		start(dev)
		mu.Unlock()
	}
	mu.Lock()
	linked := cli != nil
	mu.Unlock()
	event("ready", map[string]any{"linked": linked})

	scan := bufio.NewScanner(os.Stdin)
	scan.Buffer(make([]byte, 1<<20), 8<<20)
	for scan.Scan() {
		r, err := parseRequest(scan.Bytes())
		if err != nil {
			continue
		}
		inflight.Add(1)
		go func() {
			defer inflight.Done()
			handle(r)
		}()
	}
	// Ghost closed its end: the app is quitting. What was asked is answered first, for a few seconds at most.
	waited := make(chan struct{})
	go func() {
		inflight.Wait()
		close(waited)
	}()
	select {
	case <-waited:
	case <-time.After(3 * time.Second):
	}
	mu.Lock()
	stop()
	mu.Unlock()
}

func parseRequest(line []byte) (request, error) {
	var r request
	err := json.Unmarshal(line, &r)
	if err == nil && r.Op == "" {
		err = errors.New("no op")
	}
	return r, err
}

// answer is the line that answers request [id]: its result, or what went wrong.
func answer(id int64, result any, err error) map[string]any {
	if err != nil {
		return map[string]any{"id": id, "ok": false, "error": err.Error()}
	}
	return map[string]any{"id": id, "ok": true, "result": result}
}

func handle(r request) {
	result, err := do(r)
	say(answer(r.ID, result, err))
}

func bg() context.Context { return log.WithContext(context.Background()) }

// --- the store ------------------------------------------------------------------------------------------------------

func dbPath() string { return filepath.Join(dir, "whatsapp.db") }

func openStore() error {
	// The store holds the account's keys: readable by the person alone.
	if f, err := os.OpenFile(dbPath(), os.O_CREATE|os.O_RDWR, 0o600); err == nil {
		_ = f.Close()
	}
	c, err := sqlstore.New(bg(), "sqlite3", "file:"+dbPath()+"?_foreign_keys=on&_journal_mode=WAL&_busy_timeout=5000", waLog.Zerolog(log.With().Str("component", "store").Logger()))
	if err != nil {
		return err
	}
	mu.Lock()
	container = c
	mu.Unlock()
	return nil
}

func firstDevice() *store.Device {
	devs, err := container.GetAllDevices(bg())
	if err != nil {
		log.Err(err).Msg("load devices")
		return nil
	}
	for _, d := range devs {
		if d.ID != nil {
			return d
		}
	}
	return nil
}

// --- the connection -------------------------------------------------------------------------------------------------

func newClient(dev *store.Device) *whatsmeow.Client {
	c := whatsmeow.NewClient(dev, waLog.Zerolog(log.With().Str("component", "whatsmeow").Logger()))
	c.EnableAutoReconnect = true
	c.AutomaticMessageRerequestFromPhone = true
	c.AddEventHandler(func(evt any) { onEvent(c, evt) })
	return c
}

// start connects [dev]'s client. Called with mu held.
func start(dev *store.Device) {
	c := newClient(dev)
	cli = c
	go func() {
		if err := c.Connect(); err != nil {
			log.Err(err).Msg("connect")
		}
	}()
}

// stop disconnects the client, if any. Called with mu held.
func stop() {
	if linking != nil {
		linking()
		linking = nil
	}
	if cli == nil {
		return
	}
	cli.Disconnect()
	cli = nil
	connected = false
}

func setConnected(c *whatsmeow.Client, now bool) {
	mu.Lock()
	if cli != c || connected == now {
		mu.Unlock()
		return
	}
	connected = now
	mu.Unlock()
	if now {
		event("connected", nil)
	} else {
		event("disconnected", nil)
	}
}

// unlinked is WhatsApp removing this device: everything is forgotten and the app told.
func unlinked(c *whatsmeow.Client) {
	mu.Lock()
	if cli != c {
		mu.Unlock()
		return
	}
	mu.Unlock()
	if err := forget(); err != nil {
		log.Err(err).Msg("forget after unlink")
	}
	event("unlinked", nil)
}

// forget stops the client and wipes the store, then opens a fresh one.
func forget() error {
	mu.Lock()
	stop()
	c := container
	container = nil
	mu.Unlock()
	if c != nil {
		_ = c.Close()
	}
	for _, suffix := range []string{"", "-wal", "-shm"} {
		_ = os.Remove(dbPath() + suffix)
	}
	_ = os.RemoveAll(avatarDir())
	return openStore()
}

var errNotLinked = errors.New("not linked to WhatsApp")

func client() (*whatsmeow.Client, error) {
	mu.Lock()
	defer mu.Unlock()
	if cli == nil || cli.Store.ID == nil {
		return nil, errNotLinked
	}
	return cli, nil
}

// --- requests -------------------------------------------------------------------------------------------------------

func do(r request) (any, error) {
	limit := 60 * time.Second
	if r.Op == "download" || r.Op == "send_media" {
		limit = 170 * time.Second
	}
	ctx, cancel := context.WithTimeout(bg(), limit)
	defer cancel()
	if r.Op != "status" {
		began := time.Now()
		log.Info().Str("op", r.Op).Int64("req", r.ID).Msg("asked")
		defer func() { log.Info().Str("op", r.Op).Int64("req", r.ID).Dur("took", time.Since(began)).Msg("answered") }()
	}
	switch r.Op {
	case "status":
		return status(), nil
	case "link":
		return nil, link(cmp.Or(r.Name, deviceName))
	case "pair_phone":
		code, err := pairPhone(ctx, r.Phone)
		if err != nil {
			return nil, err
		}
		return map[string]any{"code": code}, nil
	case "unlink":
		if c, err := client(); err == nil {
			if err := c.Logout(ctx); err != nil {
				log.Err(err).Msg("logout")
			}
		}
		return nil, forget()
	}
	c, err := client()
	if err != nil {
		return nil, err
	}
	switch r.Op {
	case "contacts":
		return contacts(ctx, c)
	case "who":
		jid, err := parseJID(r.JID)
		if err != nil {
			return nil, err
		}
		return who(ctx, c, jid, true), nil
	case "groups":
		return groups(ctx, c)
	case "group_info":
		jid, err := parseJID(r.To)
		if err != nil {
			return nil, err
		}
		return groupInfo(ctx, c, jid)
	case "block", "blocked":
		if r.Op == "blocked" {
			return blocked(ctx, c)
		}
		jid, err := parseJID(r.JID)
		if err != nil {
			return nil, err
		}
		action := events.BlocklistChangeActionUnblock
		if r.On {
			action = events.BlocklistChangeActionBlock
		}
		_, err = c.UpdateBlocklist(ctx, jid, action, "")
		return nil, err
	case "send":
		to, err := parseJID(r.To)
		if err != nil {
			return nil, err
		}
		msg := textMessage(r.Text, r.Quote)
		return sendAndSay(ctx, c, to, msg)
	case "send_media":
		to, err := parseJID(r.To)
		if err != nil {
			return nil, err
		}
		msg, ptr, err := upload(ctx, c, r.Path, r.Mime, r.Name, r.Text)
		if err != nil {
			return nil, err
		}
		res, err := sendAndSay(ctx, c, to, msg)
		if err != nil {
			return nil, err
		}
		res["pointer"] = ptr
		return res, nil
	case "read":
		chat, err := parseJID(r.To)
		if err != nil {
			return nil, err
		}
		if len(r.IDs) == 0 {
			return nil, nil
		}
		sender := chat
		if r.Author != "" {
			if sender, err = parseJID(r.Author); err != nil {
				return nil, err
			}
		}
		return nil, c.MarkRead(ctx, r.IDs, time.Now(), chat, sender)
	case "react":
		chat, err := parseJID(r.To)
		if err != nil {
			return nil, err
		}
		if r.Target == "" {
			return nil, errors.New("no target")
		}
		author := types.EmptyJID
		if r.Author != "" {
			if author, err = parseJID(r.Author); err != nil {
				return nil, err
			}
		}
		emoji := r.Emoji
		if r.Remove {
			emoji = ""
		}
		_, err = c.SendMessage(ctx, chat, c.BuildReaction(chat, author, r.Target, emoji))
		return nil, err
	case "delete":
		chat, err := parseJID(r.To)
		if err != nil {
			return nil, err
		}
		if r.Target == "" {
			return nil, errors.New("no target")
		}
		_, err = c.SendMessage(ctx, chat, c.BuildRevoke(chat, types.EmptyJID, r.Target))
		return nil, err
	case "download":
		msg, err := parsePointer(r.Pointer)
		if err != nil {
			return nil, err
		}
		return nil, download(ctx, c, msg, r.Path)
	}
	return nil, fmt.Errorf("unknown op %q", r.Op)
}

func status() map[string]any {
	mu.Lock()
	c, conn := cli, connected
	mu.Unlock()
	s := map[string]any{"linked": false, "connected": false, "jid": "", "number": "", "name": ""}
	if c == nil || c.Store.ID == nil {
		return s
	}
	s["linked"] = true
	s["connected"] = conn && c.IsConnected()
	s["jid"] = c.Store.ID.ToNonAD().String()
	s["number"] = "+" + c.Store.ID.User
	s["name"] = c.Store.PushName
	return s
}

// parseJID is a request's chat or person: a full JID ("…@s.whatsapp.net", "…@g.us", "…@lid"), or a phone number.
func parseJID(s string) (types.JID, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return types.EmptyJID, errors.New("no chat")
	}
	if !strings.Contains(s, "@") {
		digits := strings.Map(func(r rune) rune {
			if r >= '0' && r <= '9' {
				return r
			}
			return -1
		}, s)
		if len(digits) < 6 {
			return types.EmptyJID, fmt.Errorf("not a WhatsApp chat: %q", s)
		}
		return types.NewJID(digits, types.DefaultUserServer), nil
	}
	jid, err := types.ParseJID(s)
	if err != nil {
		return jid, fmt.Errorf("not a WhatsApp chat: %q", s)
	}
	return jid, nil
}

// textMessage is [text], as a reply to [q] where there is one.
func textMessage(text string, q *quote) *waE2E.Message {
	if q == nil || q.ID == "" {
		return &waE2E.Message{Conversation: proto.String(text)}
	}
	ctx := &waE2E.ContextInfo{StanzaID: proto.String(q.ID), QuotedMessage: &waE2E.Message{Conversation: proto.String(q.Text)}}
	if q.Author != "" {
		ctx.Participant = proto.String(q.Author)
	}
	return &waE2E.Message{ExtendedTextMessage: &waE2E.ExtendedTextMessage{Text: proto.String(text), ContextInfo: ctx}}
}

func sendAndSay(ctx context.Context, c *whatsmeow.Client, to types.JID, msg *waE2E.Message) (map[string]any, error) {
	resp, err := c.SendMessage(ctx, to, msg)
	if err != nil {
		if ctx.Err() != nil {
			return nil, fmt.Errorf("WhatsApp didn't take the message in time (%w)", err)
		}
		return nil, err
	}
	return map[string]any{"id": resp.ID, "ts": resp.Timestamp.UnixMilli()}, nil
}

// --- media ----------------------------------------------------------------------------------------------------------

// pointer is what a picture or file in a message is fetched again with: its kind and its WhatsApp message (with the
// key), as JSON. Thumbnails are left out: the file itself is fetched.
type pointer struct {
	Kind string          `json:"kind"`
	Msg  json.RawMessage `json:"msg"`
}

func pointerOf(kind string, m proto.Message) map[string]any {
	m = proto.Clone(m)
	switch v := m.(type) {
	case *waE2E.ImageMessage:
		v.JPEGThumbnail, v.ContextInfo = nil, nil
	case *waE2E.VideoMessage:
		v.JPEGThumbnail, v.ContextInfo = nil, nil
	case *waE2E.DocumentMessage:
		v.JPEGThumbnail, v.ContextInfo = nil, nil
	case *waE2E.AudioMessage:
		v.ContextInfo, v.Waveform = nil, nil
	case *waE2E.StickerMessage:
		v.PngThumbnail, v.ContextInfo = nil, nil
	}
	b, err := protojson.Marshal(m)
	if err != nil {
		return nil
	}
	return map[string]any{"kind": kind, "msg": json.RawMessage(b)}
}

// parsePointer takes back a pointer as an event gave it: a JSON object, or that object as a string.
func parsePointer(raw json.RawMessage) (whatsmeow.DownloadableMessage, error) {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || string(raw) == "null" {
		return nil, errors.New("no pointer")
	}
	if raw[0] == '"' {
		var s string
		if err := json.Unmarshal(raw, &s); err != nil {
			return nil, err
		}
		raw = []byte(s)
	}
	var p pointer
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("not a pointer: %w", err)
	}
	var m interface {
		proto.Message
		whatsmeow.DownloadableMessage
	}
	switch p.Kind {
	case "image":
		m = &waE2E.ImageMessage{}
	case "video":
		m = &waE2E.VideoMessage{}
	case "audio":
		m = &waE2E.AudioMessage{}
	case "document":
		m = &waE2E.DocumentMessage{}
	case "sticker":
		m = &waE2E.StickerMessage{}
	default:
		return nil, fmt.Errorf("not a pointer: kind %q", p.Kind)
	}
	if err := (protojson.UnmarshalOptions{DiscardUnknown: true}).Unmarshal(p.Msg, m); err != nil {
		return nil, fmt.Errorf("not a pointer: %w", err)
	}
	if len(m.GetMediaKey()) == 0 {
		return nil, errors.New("the attachment has no key")
	}
	return m, nil
}

func download(ctx context.Context, c *whatsmeow.Client, msg whatsmeow.DownloadableMessage, path string) error {
	if path == "" {
		return errors.New("no path")
	}
	data, err := c.Download(ctx, msg)
	if err != nil {
		return err
	}
	tmp := path + ".part"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// upload sends [path] to WhatsApp's media servers and makes the message that carries it.
func upload(ctx context.Context, c *whatsmeow.Client, path, mime, name, caption string) (*waE2E.Message, map[string]any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, err
	}
	if mime == "" || mime == "application/octet-stream" {
		mime = http.DetectContentType(data)
	}
	if name == "" {
		name = filepath.Base(path)
	}
	kind := mediaKind(mime)
	mt := map[string]whatsmeow.MediaType{"image": whatsmeow.MediaImage, "video": whatsmeow.MediaVideo, "audio": whatsmeow.MediaAudio, "document": whatsmeow.MediaDocument}[kind]
	up, err := c.Upload(ctx, data, mt)
	if err != nil {
		return nil, nil, err
	}
	var cap *string
	if caption != "" {
		cap = proto.String(caption)
	}
	msg := &waE2E.Message{}
	var part proto.Message
	switch kind {
	case "image":
		im := &waE2E.ImageMessage{URL: &up.URL, DirectPath: &up.DirectPath, MediaKey: up.MediaKey, Mimetype: &mime, FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: &up.FileLength, Caption: cap}
		if cfg, _, err := image.DecodeConfig(bytes.NewReader(data)); err == nil {
			im.Width, im.Height = proto.Uint32(uint32(cfg.Width)), proto.Uint32(uint32(cfg.Height))
		}
		msg.ImageMessage, part = im, im
	case "video":
		v := &waE2E.VideoMessage{URL: &up.URL, DirectPath: &up.DirectPath, MediaKey: up.MediaKey, Mimetype: &mime, FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: &up.FileLength, Caption: cap}
		msg.VideoMessage, part = v, v
	case "audio":
		a := &waE2E.AudioMessage{URL: &up.URL, DirectPath: &up.DirectPath, MediaKey: up.MediaKey, Mimetype: &mime, FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: &up.FileLength, PTT: proto.Bool(strings.Contains(mime, "ogg") || strings.Contains(mime, "mp4"))}
		msg.AudioMessage, part = a, a
	default:
		d := &waE2E.DocumentMessage{URL: &up.URL, DirectPath: &up.DirectPath, MediaKey: up.MediaKey, Mimetype: &mime, FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: &up.FileLength, FileName: &name, Title: &name, Caption: cap}
		msg.DocumentMessage, part = d, d
	}
	return msg, pointerOf(kind, part), nil
}

func mediaKind(mime string) string {
	switch {
	case strings.HasPrefix(mime, "image/") && mime != "image/webp":
		return "image"
	case strings.HasPrefix(mime, "video/"):
		return "video"
	case strings.HasPrefix(mime, "audio/"):
		return "audio"
	}
	return "document"
}

// --- linking --------------------------------------------------------------------------------------------------------

var (
	pairMu     sync.Mutex
	pairClient *whatsmeow.Client
	firstQR    chan struct{}
)

// link pairs a new device: QR codes ("qr", each a few tens of seconds, as WhatsApp Web shows them, about two minutes
// in all, then a new round), until the phone scans one ("linked") or it is given up ("link_failed").
func link(name string) error {
	mu.Lock()
	stop()
	ctx, cancel := context.WithCancel(bg())
	linking = cancel
	ct := container
	mu.Unlock()
	if ct == nil {
		cancel()
		return errors.New("the WhatsApp store is not open")
	}
	_ = name // WhatsApp shows the name set with store.SetOSInfo.
	ready := make(chan struct{})
	pairMu.Lock()
	firstQR = ready
	pairMu.Unlock()
	go func() {
		defer cancel()
		for round := 0; round < 4; round++ {
			done, failed := linkRound(ctx, ct, ready)
			if done || failed || ctx.Err() != nil {
				return
			}
		}
		event("link_failed", map[string]any{"error": "The QR code was not scanned in time"})
	}()
	return nil
}

// linkRound follows one QR channel: done once paired, failed once said so; neither means "start again".
func linkRound(ctx context.Context, ct *sqlstore.Container, ready chan struct{}) (done, failed bool) {
	c := newClient(ct.NewDevice())
	qr, err := c.GetQRChannel(ctx)
	if err != nil {
		event("link_failed", map[string]any{"error": err.Error()})
		return false, true
	}
	if err := c.Connect(); err != nil {
		event("link_failed", map[string]any{"error": "WhatsApp could not be reached (" + err.Error() + ")"})
		return false, true
	}
	pairMu.Lock()
	pairClient = c
	pairMu.Unlock()
	defer func() {
		pairMu.Lock()
		if pairClient == c {
			pairClient = nil
		}
		pairMu.Unlock()
	}()
	for item := range qr {
		switch item.Event {
		case whatsmeow.QRChannelEventCode:
			event("qr", map[string]any{"url": item.Code, "timeout": int(item.Timeout.Seconds())})
			select {
			case <-ready:
			default:
				close(ready)
			}
		case whatsmeow.QRChannelSuccess.Event:
			mu.Lock()
			linking = nil
			cli = c
			mu.Unlock()
			id := c.Store.ID
			if id == nil {
				event("link_failed", map[string]any{"error": "WhatsApp sent no account"})
				return false, true
			}
			event("linked", map[string]any{"jid": id.ToNonAD().String(), "number": "+" + id.User, "name": c.Store.PushName})
			return true, false
		case whatsmeow.QRChannelTimeout.Event:
			c.Disconnect()
			return false, false
		case whatsmeow.QRChannelEventError:
			c.Disconnect()
			event("link_failed", map[string]any{"error": "Linking did not finish (" + fmt.Sprint(item.Error) + ")"})
			return false, true
		case whatsmeow.QRChannelClientOutdated.Event:
			c.Disconnect()
			event("link_failed", map[string]any{"error": "WhatsApp refused this version of the helper as out of date."})
			return false, true
		default:
			if strings.HasPrefix(item.Event, "err") {
				c.Disconnect()
				event("link_failed", map[string]any{"error": "Linking did not finish (" + item.Event + ")"})
				return false, true
			}
		}
	}
	if ctx.Err() != nil {
		c.Disconnect()
		return false, true
	}
	return false, false
}

// pairPhone asks WhatsApp for an eight-letter code to type in on the phone (Linked devices › Link a device › Link with
// phone number instead), on the linking under way, starting one if none is.
func pairPhone(ctx context.Context, phone string) (string, error) {
	pairMu.Lock()
	c, ready := pairClient, firstQR
	pairMu.Unlock()
	if c == nil || ready == nil {
		if err := link(deviceName); err != nil {
			return "", err
		}
		pairMu.Lock()
		ready = firstQR
		pairMu.Unlock()
	}
	select {
	case <-ready:
	case <-ctx.Done():
		return "", errors.New("WhatsApp did not answer in time")
	}
	pairMu.Lock()
	c = pairClient
	pairMu.Unlock()
	if c == nil {
		return "", errors.New("linking is not under way")
	}
	code, err := c.PairPhone(ctx, phone, true, whatsmeow.PairClientChrome, "Chrome (Mac OS)")
	if err != nil {
		return "", err
	}
	event("pair_code", map[string]any{"code": code})
	return code, nil
}

// --- people and groups ----------------------------------------------------------------------------------------------

func avatarDir() string { return filepath.Join(dir, "avatars") }

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// number is a person's phone number, "+…", where their JID is one.
func number(jid types.JID) string {
	if jid.Server == types.DefaultUserServer && jid.User != "" {
		return "+" + jid.User
	}
	return ""
}

func infoName(i types.ContactInfo) string {
	return strings.TrimSpace(cmp.Or(i.FullName, i.FirstName, i.BusinessName, i.PushName))
}

// avatar is [jid]'s profile picture (a preview), kept beside the store; "" where there is none or it can't be had.
func avatar(ctx context.Context, c *whatsmeow.Client, jid types.JID) string {
	info, err := c.GetProfilePictureInfo(ctx, jid, &whatsmeow.GetProfilePictureParams{Preview: true})
	if err != nil || info == nil || info.URL == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(jid.String() + ":" + info.ID))
	p := filepath.Join(avatarDir(), hex.EncodeToString(sum[:12]))
	if _, err := os.Stat(p); err == nil {
		return p
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, info.URL, nil)
	if err != nil {
		return ""
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return ""
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil || len(data) == 0 {
		return ""
	}
	_ = os.MkdirAll(avatarDir(), 0o700)
	if os.WriteFile(p, data, 0o600) != nil {
		return ""
	}
	return p
}

// chatID is how the app knows a chat: a group's JID, or a person's phone-number JID (their hidden "@lid" one where
// WhatsApp gives no number), never a device's.
func chatID(c *whatsmeow.Client, jid types.JID) types.JID {
	jid = jid.ToNonAD()
	if jid.Server == types.HiddenUserServer && c != nil {
		if pn, err := c.Store.LIDs.GetPNForLID(bg(), jid); err == nil && !pn.IsEmpty() {
			return pn.ToNonAD()
		}
	}
	return jid
}

func person(ctx context.Context, c *whatsmeow.Client, jid types.JID, pic bool) map[string]any {
	jid = chatID(c, jid)
	info, _ := c.Store.Contacts.GetContact(ctx, jid)
	a := ""
	if pic {
		a = avatar(ctx, c, jid)
	}
	return map[string]any{"jid": jid.String(), "name": infoName(info), "number": number(jid), "avatar": nullable(a)}
}

func contacts(ctx context.Context, c *whatsmeow.Client) ([]map[string]any, error) {
	all, err := c.Store.Contacts.GetAllContacts(ctx)
	if err != nil {
		return nil, err
	}
	own := c.Store.ID.ToNonAD()
	seen := map[string]bool{}
	list := make([]map[string]any, 0, len(all))
	for jid, info := range all {
		jid = chatID(c, jid)
		if jid.User == own.User || jid.Server == types.GroupServer || jid.Server == types.BroadcastServer || seen[jid.String()] {
			continue
		}
		// Only the people in the phone's address book, not everyone met in a group.
		if info.FullName == "" && info.FirstName == "" {
			continue
		}
		seen[jid.String()] = true
		list = append(list, map[string]any{"jid": jid.String(), "name": infoName(info), "number": number(jid), "avatar": nil})
	}
	sort.Slice(list, func(i, j int) bool { return fmt.Sprint(list[i]["name"]) < fmt.Sprint(list[j]["name"]) })
	return list, nil
}

func who(ctx context.Context, c *whatsmeow.Client, jid types.JID, pic bool) map[string]any {
	return person(ctx, c, jid, pic)
}

func blocked(ctx context.Context, c *whatsmeow.Client) ([]map[string]any, error) {
	bl, err := c.GetBlocklist(ctx, "")
	if err != nil {
		return nil, err
	}
	list := make([]map[string]any, 0, len(bl.Items))
	for _, it := range bl.Items {
		jid := it.PN
		if jid.IsEmpty() {
			jid = it.LID
		}
		if jid.IsEmpty() {
			continue
		}
		list = append(list, person(ctx, c, jid, false))
	}
	return list, nil
}

func describeGroup(ctx context.Context, c *whatsmeow.Client, g *types.GroupInfo, pic bool) map[string]any {
	members := make([]string, 0, len(g.Participants))
	for _, p := range g.Participants {
		jid := p.PhoneNumber
		if jid.IsEmpty() {
			jid = p.JID
		}
		members = append(members, chatID(c, jid).String())
	}
	a := ""
	if pic {
		a = avatar(ctx, c, g.JID)
	}
	return map[string]any{"id": g.JID.String(), "title": g.Name, "members": members, "avatar": nullable(a)}
}

func groups(ctx context.Context, c *whatsmeow.Client) ([]map[string]any, error) {
	gs, err := c.GetJoinedGroups(ctx)
	if err != nil {
		return nil, err
	}
	list := make([]map[string]any, 0, len(gs))
	for _, g := range gs {
		list = append(list, describeGroup(ctx, c, g, false))
	}
	return list, nil
}

func groupInfo(ctx context.Context, c *whatsmeow.Client, jid types.JID) (map[string]any, error) {
	g, err := c.GetGroupInfo(ctx, jid)
	if err != nil {
		return nil, err
	}
	m := describeGroup(ctx, c, g, true)
	own := c.Store.ID.ToNonAD()
	ownLID := c.Store.LID.ToNonAD()
	people := make([]map[string]any, 0, len(g.Participants))
	admin := false
	for _, p := range g.Participants {
		jid := p.PhoneNumber
		if jid.IsEmpty() {
			jid = p.JID
		}
		me := jid.User == own.User || (p.LID.User != "" && p.LID.User == ownLID.User) || p.JID.User == ownLID.User
		if me && (p.IsAdmin || p.IsSuperAdmin) {
			admin = true
		}
		pm := person(ctx, c, jid, false)
		if pm["name"] == "" {
			pm["name"] = p.DisplayName
		}
		pm["admin"], pm["owner"], pm["me"] = p.IsAdmin || p.IsSuperAdmin, p.IsSuperAdmin, me
		people = append(people, pm)
	}
	m["description"] = g.Topic
	m["timer"] = 0
	if g.IsEphemeral {
		m["timer"] = g.DisappearingTimer
	}
	m["people"] = people
	m["admin"] = admin
	m["edit_info"] = map[bool]string{true: "admins", false: "members"}[g.IsLocked]
	m["add_members"] = "members"
	if g.MemberAddMode == types.GroupMemberAddModeAdmin {
		m["add_members"] = "admins"
	}
	m["announcements_only"] = g.IsAnnounce
	return m, nil
}

// --- events ---------------------------------------------------------------------------------------------------------

var (
	announcedMu sync.Mutex
	announced   = map[string]bool{}
)

// once is true the first time [key] is asked about this run.
func once(key string) bool {
	announcedMu.Lock()
	defer announcedMu.Unlock()
	if announced[key] {
		return false
	}
	announced[key] = true
	return true
}

func onEvent(c *whatsmeow.Client, raw any) {
	switch evt := raw.(type) {
	case *events.Connected:
		setConnected(c, true)
	case *events.Disconnected, *events.KeepAliveTimeout:
		setConnected(c, false)
	case *events.StreamReplaced:
		log.Warn().Msg("another copy of this device connected")
		setConnected(c, false)
	case *events.TemporaryBan:
		log.Warn().Str("ban", evt.String()).Msg("temporarily banned")
		event("banned", map[string]any{"error": evt.String()})
	case *events.LoggedOut:
		go unlinked(c)
	case *events.Message:
		message(c, evt, false)
	case *events.HistorySync:
		history(c, evt.Data)
	case *events.Receipt:
		kind := ""
		switch evt.Type {
		case types.ReceiptTypeDelivered:
			kind = "delivered"
		case types.ReceiptTypeRead, types.ReceiptTypePlayed:
			kind = "read"
		}
		if kind != "" && !evt.IsFromMe {
			ids := evt.MessageIDs
			if ids == nil {
				ids = []string{}
			}
			event("receipt", map[string]any{"chat": chatID(c, evt.Chat).String(), "from": chatID(c, evt.Sender).String(), "ids": ids, "kind": kind})
		}
	case *events.PushName:
		event("name", map[string]any{"jid": chatID(c, evt.JID).String(), "name": evt.NewPushName, "number": number(chatID(c, evt.JID)), "avatar": nil})
	case *events.Contact:
		if evt.Action != nil {
			jid := chatID(c, evt.JID)
			name := strings.TrimSpace(cmp.Or(evt.Action.GetFullName(), evt.Action.GetFirstName()))
			if name != "" {
				event("contacts", map[string]any{"list": []map[string]any{{"jid": jid.String(), "name": name, "number": number(jid), "avatar": nil}}})
			}
		}
	case *events.GroupInfo:
		announceGroup(c, evt.JID, true)
	case *events.JoinedGroup:
		event("group", describeGroup(bg(), c, &evt.GroupInfo, false))
	case *events.UndecryptableMessage:
		log.Warn().Str("chat", evt.Info.Chat.String()).Msg("message not decrypted")
	}
}

// announceGroup says a "group" event for [jid], once a run (again when it changed), off the event loop.
func announceGroup(c *whatsmeow.Client, jid types.JID, changed bool) {
	key := "group:" + jid.String()
	if changed {
		announcedMu.Lock()
		delete(announced, key)
		announcedMu.Unlock()
	}
	if !once(key) {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(bg(), 30*time.Second)
		defer cancel()
		g, err := c.GetGroupInfo(ctx, jid)
		if err != nil {
			announcedMu.Lock()
			delete(announced, key)
			announcedMu.Unlock()
			return
		}
		event("group", describeGroup(ctx, c, g, true))
	}()
}

// message turns a message WhatsApp sent this device into the app's event: a message, a reaction or a delete.
func message(c *whatsmeow.Client, evt *events.Message, past bool) {
	m := messageMap(c, evt, past)
	if m == nil {
		return
	}
	ev := m["ev"].(string)
	delete(m, "ev")
	if ev == "message" && evt.Info.IsGroup && !past {
		announceGroup(c, evt.Info.Chat, false)
	}
	event(ev, m)
}

// messageMap is a WhatsApp message as the app's event fields, with "ev" naming which; nil for what the app doesn't
// show (protocol chatter, status updates, polls and the like).
func messageMap(c *whatsmeow.Client, evt *events.Message, past bool) map[string]any {
	info := evt.Info
	if info.Chat.Server == types.BroadcastServer || info.Chat.Server == types.NewsletterServer {
		return nil
	}
	msg := evt.Message
	if msg == nil {
		return nil
	}
	chat := chatID(c, info.Chat).String()
	from := chatID(c, info.Sender).String()
	if info.IsFromMe {
		from = chatID(c, *c.Store.ID).String()
	}
	if r := msg.GetReactionMessage(); r != nil {
		return map[string]any{
			"ev": "reaction", "chat": chat, "from": from, "target_id": r.GetKey().GetID(),
			"target_mine": r.GetKey().GetFromMe(), "emoji": r.GetText(), "remove": r.GetText() == "",
		}
	}
	if p := msg.GetProtocolMessage(); p != nil {
		if p.GetType() == waE2E.ProtocolMessage_REVOKE {
			return map[string]any{"ev": "deleted", "chat": chat, "target_id": p.GetKey().GetID()}
		}
		return nil
	}
	text, media, ctxInfo := content(msg)
	if text == "" && len(media) == 0 {
		return nil
	}
	if evt.IsEdit {
		// An edit is said as an edit of the message it changes.
		return map[string]any{"ev": "edited", "chat": chat, "target_id": info.ID, "text": text}
	}
	name := info.PushName
	if ci, err := c.Store.Contacts.GetContact(bg(), chatID(c, info.Sender)); err == nil && infoName(ci) != "" {
		name = infoName(ci)
	}
	if info.IsFromMe {
		name = ""
	}
	m := map[string]any{
		"ev": "message", "chat": chat, "group": info.IsGroup, "id": info.ID, "from": from, "name": name,
		"mine": info.IsFromMe, "ts": info.Timestamp.UnixMilli(), "text": text, "media": media,
	}
	if past {
		m["history"] = true
	}
	if ctxInfo != nil && ctxInfo.GetStanzaID() != "" {
		author := ""
		if p := ctxInfo.GetParticipant(); p != "" {
			if j, err := types.ParseJID(p); err == nil {
				author = chatID(c, j).String()
			}
		} else if !info.IsGroup {
			author = chat
		}
		qt, _, _ := content(ctxInfo.GetQuotedMessage())
		m["quote"] = map[string]any{"id": ctxInfo.GetStanzaID(), "author": author, "text": qt}
	}
	return m
}

// content is a message's words, its pictures and files, and its context (what it replies to).
func content(msg *waE2E.Message) (string, []map[string]any, *waE2E.ContextInfo) {
	if msg == nil {
		return "", nil, nil
	}
	media := []map[string]any{}
	add := func(kind string, m proto.Message, mime, name string, size uint64, w, h uint32) {
		if p := pointerOf(kind, m); p != nil {
			media = append(media, map[string]any{"pointer": p, "mime": mime, "name": name, "size": size, "width": w, "height": h})
		}
	}
	switch {
	case msg.GetConversation() != "":
		return msg.GetConversation(), media, nil
	case msg.GetExtendedTextMessage() != nil:
		e := msg.GetExtendedTextMessage()
		return e.GetText(), media, e.GetContextInfo()
	case msg.GetImageMessage() != nil:
		im := msg.GetImageMessage()
		add("image", im, im.GetMimetype(), "", im.GetFileLength(), im.GetWidth(), im.GetHeight())
		return im.GetCaption(), media, im.GetContextInfo()
	case msg.GetVideoMessage() != nil:
		v := msg.GetVideoMessage()
		add("video", v, v.GetMimetype(), "", v.GetFileLength(), v.GetWidth(), v.GetHeight())
		return v.GetCaption(), media, v.GetContextInfo()
	case msg.GetAudioMessage() != nil:
		a := msg.GetAudioMessage()
		add("audio", a, a.GetMimetype(), "", a.GetFileLength(), 0, 0)
		return "", media, a.GetContextInfo()
	case msg.GetDocumentMessage() != nil:
		d := msg.GetDocumentMessage()
		add("document", d, d.GetMimetype(), d.GetFileName(), d.GetFileLength(), 0, 0)
		return d.GetCaption(), media, d.GetContextInfo()
	case msg.GetStickerMessage() != nil:
		s := msg.GetStickerMessage()
		add("sticker", s, cmp.Or(s.GetMimetype(), "image/webp"), "", s.GetFileLength(), s.GetWidth(), s.GetHeight())
		return "", media, s.GetContextInfo()
	case msg.GetLocationMessage() != nil:
		l := msg.GetLocationMessage()
		return fmt.Sprintf("📍 %s https://maps.google.com/?q=%f,%f", l.GetName(), l.GetDegreesLatitude(), l.GetDegreesLongitude()), media, l.GetContextInfo()
	case msg.GetContactMessage() != nil:
		return "👤 " + msg.GetContactMessage().GetDisplayName(), media, msg.GetContactMessage().GetContextInfo()
	}
	return "", media, nil
}

// history turns a history sync (what WhatsApp gives a newly linked device: recent chats and their messages, and
// later more) into one "history" event a chat: its name, unread count and messages, oldest first.
func history(c *whatsmeow.Client, h *waHistorySync.HistorySync) {
	if h == nil {
		return
	}
	for _, pn := range h.GetPushnames() {
		if j, err := types.ParseJID(pn.GetID()); err == nil && pn.GetPushname() != "" {
			_, _, _ = c.Store.Contacts.PutPushName(bg(), j, pn.GetPushname())
			jid := chatID(c, j)
			event("name", map[string]any{"jid": jid.String(), "name": pn.GetPushname(), "number": number(jid), "avatar": nil})
		}
	}
	for _, conv := range h.GetConversations() {
		if m := conversation(c, conv); m != nil {
			event("history", m)
		}
	}
}

func conversation(c *whatsmeow.Client, conv *waHistorySync.Conversation) map[string]any {
	jid, err := types.ParseJID(conv.GetID())
	if err != nil || jid.Server == types.BroadcastServer || jid.Server == types.NewsletterServer {
		return nil
	}
	msgs := make([]map[string]any, 0, len(conv.GetMessages()))
	for _, hm := range conv.GetMessages() {
		web := hm.GetMessage()
		if web == nil {
			continue
		}
		evt, err := c.ParseWebMessage(jid, web)
		if err != nil {
			continue
		}
		m := messageMap(c, evt, true)
		if m == nil || m["ev"] != "message" {
			continue
		}
		delete(m, "ev")
		if r := reactionsOf(c, web); len(r) > 0 {
			m["reactions"] = r
		}
		msgs = append(msgs, m)
	}
	sort.Slice(msgs, func(i, j int) bool { return msgs[i]["ts"].(int64) < msgs[j]["ts"].(int64) })
	chat := chatID(c, jid)
	if pn := conv.GetPnJID(); pn != "" && chat.Server == types.HiddenUserServer {
		if p, err := types.ParseJID(pn); err == nil {
			chat = p.ToNonAD()
		}
	}
	return map[string]any{
		"chat": chat.String(), "group": jid.Server == types.GroupServer, "name": cmp.Or(conv.GetName(), conv.GetDisplayName()),
		"unread": conv.GetUnreadCount(), "last": int64(conv.GetLastMsgTimestamp()) * 1000, "messages": msgs,
	}
}

// reactionsOf is a past message's reactions, who → emoji ("me" for this account's own).
func reactionsOf(c *whatsmeow.Client, web *waWeb.WebMessageInfo) map[string]string {
	out := map[string]string{}
	for _, r := range web.GetReactions() {
		if r.GetText() == "" {
			continue
		}
		who := ""
		k := r.GetKey()
		switch {
		case k.GetFromMe():
			who = chatID(c, *c.Store.ID).String()
		case k.GetParticipant() != "":
			if j, err := types.ParseJID(k.GetParticipant()); err == nil {
				who = chatID(c, j).String()
			}
		default:
			if j, err := types.ParseJID(k.GetRemoteJID()); err == nil {
				who = chatID(c, j).String()
			}
		}
		if who != "" {
			out[who] = r.GetText()
		}
	}
	return out
}

// --- the log file ---------------------------------------------------------------------------------------------------

// logFile is whatsapp.log in the store's folder, begun afresh past a megabyte; standard error alone where it can't open.
func logFile() *os.File {
	path := filepath.Join(dir, "whatsapp.log")
	if st, err := os.Stat(path); err == nil && st.Size() > 1<<20 {
		_ = os.Remove(path)
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return os.Stderr
	}
	return f
}
