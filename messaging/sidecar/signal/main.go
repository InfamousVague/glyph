// Ghost Messaging's Signal helper (README.md, PROTOCOL.md). AGPL-3.0, as signalmeow, on which it is built.
//
// It links to the person's Signal account as a secondary device, as Signal Desktop does, and speaks JSON lines over
// standard input and output. Requests, each with an "id" its answer carries back:
//
//	{"id":1,"op":"status"}                                   → {"linked":bool,"connected":bool,"aci":"…","number":"…","name":"…"}
//	{"id":2,"op":"link","name":"Ghost Messaging"}            → null, then events "qr" (again every 45 s) and "linked" or "link_failed"
//	{"id":3,"op":"unlink"}                                   → null; everything forgotten
//	{"id":4,"op":"contacts"}                                 → [{"aci","name","number","avatar"}…]
//	{"id":5,"op":"groups"}                                   → [{"id","title","members","avatar"}…]
//	{"id":6,"op":"send","to":"…","text":"…","quote":{"ts":…,"author":"…"}} → {"ts":…}
//	{"id":7,"op":"send_media","to":"…","path":"…","mime":"…","name":"…","text":"…"} → {"ts":…}
//	{"id":8,"op":"read","to":"…","author":"…","ts":[…]}      → null
//	{"id":9,"op":"react","to":"…","author":"…","ts":…,"emoji":"👍","remove":false} → null
//	{"id":10,"op":"delete","to":"…","ts":…}                  → null
//	{"id":11,"op":"download","pointer":{…},"path":"…"}       → null once written
//
// Answers: {"id":1,"ok":true,"result":…} or {"id":1,"ok":false,"error":"…"}. Events, unasked, each with "ev": ready,
// qr, linked, link_failed, connected, disconnected, message, receipt, reaction, deleted, contacts, unlinked.
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
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/rs/zerolog"
	"go.mau.fi/util/dbutil"
	_ "go.mau.fi/util/dbutil/litestream"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"

	"go.mau.fi/mautrix-signal/pkg/libsignalgo"
	"go.mau.fi/mautrix-signal/pkg/signalmeow"
	"go.mau.fi/mautrix-signal/pkg/signalmeow/events"
	"go.mau.fi/mautrix-signal/pkg/signalmeow/protobuf/signalpb"
	"go.mau.fi/mautrix-signal/pkg/signalmeow/store"
	"go.mau.fi/mautrix-signal/pkg/signalmeow/types"
)

// stamps is a request's "ts": one message time, or a list of them.
type stamps []uint64

func (s *stamps) UnmarshalJSON(b []byte) error {
	b = bytes.TrimSpace(b)
	if len(b) > 0 && b[0] == '[' {
		var list []uint64
		if err := json.Unmarshal(b, &list); err != nil {
			return err
		}
		*s = list
		return nil
	}
	if string(b) == "null" {
		*s = nil
		return nil
	}
	var one uint64
	if err := json.Unmarshal(b, &one); err != nil {
		return err
	}
	*s = stamps{one}
	return nil
}

type quote struct {
	TS     uint64 `json:"ts"`
	Author string `json:"author"`
}

type request struct {
	ID      int64           `json:"id"`
	Op      string          `json:"op"`
	Name    string          `json:"name"`
	To      string          `json:"to"`
	Text    string          `json:"text"`
	Quote   *quote          `json:"quote"`
	Path    string          `json:"path"`
	Mime    string          `json:"mime"`
	Author  string          `json:"author"`
	TS      stamps          `json:"ts"`
	Emoji   string          `json:"emoji"`
	Remove  bool            `json:"remove"`
	Pointer json.RawMessage `json:"pointer"`
}

var (
	dir     string
	log     zerolog.Logger
	out     = json.NewEncoder(os.Stdout)
	outLock sync.Mutex

	mu        sync.Mutex
	db        *dbutil.Database
	container *store.Container
	cli       *signalmeow.Client
	connected bool
	stopLoops context.CancelFunc
	linking   context.CancelFunc
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
	flag.StringVar(&dir, "dir", "", "where the Signal store is kept")
	flag.Parse()
	if dir == "" {
		fmt.Fprintln(os.Stderr, "--dir is needed")
		os.Exit(2)
	}
	_ = os.MkdirAll(dir, 0o700)
	// signalmeow's and libsignal's log to standard error, for Ghost's developer log; never standard output.
	log = zerolog.New(os.Stderr).With().Timestamp().Logger().Level(zerolog.InfoLevel)
	signalmeow.SetLogger(log)
	// The QR address carries "&": kept as it is, not as \u0026.
	out.SetEscapeHTML(false)
	if err := openStore(); err != nil {
		log.Err(err).Msg("open store")
		fmt.Fprintln(os.Stderr, "the Signal store could not be opened:", err)
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
		go handle(r)
	}
	// Ghost closed its end: the app is quitting.
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

// --- the store ------------------------------------------------------------------------------------------------------

func dbPath() string { return filepath.Join(dir, "signal.db") }

func openStore() error {
	// The store holds the account's keys: readable by the person alone.
	if f, err := os.OpenFile(dbPath(), os.O_CREATE|os.O_RDWR, 0o600); err == nil {
		_ = f.Close()
	}
	raw, err := dbutil.NewWithDialect("file:"+dbPath()+"?_txlock=immediate", "sqlite3-fk-wal")
	if err != nil {
		return err
	}
	raw.Log = dbutil.ZeroLogger(log.With().Str("db_section", "main").Logger())
	c := store.NewStore(raw, dbutil.ZeroLogger(log.With().Str("db_section", "signalmeow").Logger()))
	if err := c.Upgrade(log.WithContext(context.Background())); err != nil {
		_ = raw.Close()
		return err
	}
	mu.Lock()
	db, container = raw, c
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
		if d.IsDeviceLoggedIn() {
			return d
		}
	}
	return nil
}

func bg() context.Context { return log.WithContext(context.Background()) }

// --- the connection -------------------------------------------------------------------------------------------------

// start connects [dev]'s client and follows its connection. Called with mu held.
func start(dev *store.Device) {
	c := signalmeow.NewClient(dev, log.With().Str("component", "signalmeow").Logger(), onEvent)
	// Ask the phone for its contacts (SendContactSyncRequest) once both sockets are up.
	c.SyncContactsOnConnect = true
	cli = c
	ctx, cancel := context.WithCancel(bg())
	stopLoops = cancel
	go connectLoop(ctx, c)
}

// connectLoop starts the receive loops, retrying with a growing wait as the bridge does, and turns their status into
// "connected" / "disconnected" / "unlinked".
func connectLoop(ctx context.Context, c *signalmeow.Client) {
	for retry := 0; ; retry++ {
		statuses, err := c.StartReceiveLoops(ctx)
		if err == nil {
			for s := range statuses {
				switch s.Event {
				case signalmeow.SignalConnectionEventConnected:
					setConnected(c, true)
				case signalmeow.SignalConnectionEventDisconnected, signalmeow.SignalConnectionEventError:
					setConnected(c, false)
				case signalmeow.SignalConnectionEventLoggedOut:
					go unlinked(c)
					return
				case signalmeow.SignalConnectionEventFatalError:
					log.Err(s.Err).Msg("fatal connection error")
					setConnected(c, false)
				}
			}
			return
		}
		log.Err(err).Msg("start receive loops")
		wait := min(time.Duration(2<<min(retry, 7))*time.Second, 150*time.Second)
		select {
		case <-time.After(wait):
		case <-ctx.Done():
			return
		}
	}
}

// isConnected is signalmeow's IsConnected, which panics before the sockets exist.
func isConnected(c *signalmeow.Client) (up bool) {
	defer func() {
		if recover() != nil {
			up = false
		}
	}()
	return c.AuthedWS != nil && c.UnauthedWS != nil && c.IsConnected()
}

func setConnected(c *signalmeow.Client, now bool) {
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

// stop disconnects the client, if any. Called with mu held.
func stop() {
	if linking != nil {
		linking()
		linking = nil
	}
	if cli == nil {
		return
	}
	if stopLoops != nil {
		stopLoops()
		stopLoops = nil
	}
	if err := cli.StopReceiveLoops(); err != nil {
		log.Debug().Err(err).Msg("stop receive loops")
	}
	cli = nil
	connected = false
}

// unlinked is Signal removing this device: everything is forgotten and the app told.
func unlinked(c *signalmeow.Client) {
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
	raw := db
	db, container = nil, nil
	mu.Unlock()
	if raw != nil {
		_ = raw.Close()
	}
	for _, suffix := range []string{"", "-wal", "-shm"} {
		_ = os.Remove(dbPath() + suffix)
	}
	_ = os.RemoveAll(avatarDir())
	return openStore()
}

var errNotLinked = errors.New("not linked to Signal")

func client() (*signalmeow.Client, error) {
	mu.Lock()
	defer mu.Unlock()
	if cli == nil || !cli.IsLoggedIn() {
		return nil, errNotLinked
	}
	return cli, nil
}

// --- requests -------------------------------------------------------------------------------------------------------

func do(r request) (any, error) {
	ctx, cancel := context.WithTimeout(bg(), 90*time.Second)
	defer cancel()
	switch r.Op {
	case "status":
		return status(ctx), nil
	case "link":
		return nil, link(cmp.Or(r.Name, "Ghost Messaging"))
	case "unlink":
		if c, err := client(); err == nil {
			if err := c.Unlink(ctx); err != nil {
				log.Err(err).Msg("unlink")
			}
		}
		return nil, forget()
	case "contacts":
		c, err := client()
		if err != nil {
			return nil, err
		}
		return contacts(ctx, c)
	case "groups":
		c, err := client()
		if err != nil {
			return nil, err
		}
		return groups(ctx, c)
	case "send":
		c, err := client()
		if err != nil {
			return nil, err
		}
		ts := now()
		dm := &signalpb.DataMessage{Timestamp: proto.Uint64(ts), Body: proto.String(r.Text)}
		if r.Quote != nil && r.Quote.TS != 0 {
			author, err := uuid.Parse(r.Quote.Author)
			if err != nil {
				return nil, fmt.Errorf("quote author: %w", err)
			}
			dm.Quote = &signalpb.DataMessage_Quote{
				Id: proto.Uint64(r.Quote.TS), AuthorAciBinary: author[:], Type: signalpb.DataMessage_Quote_NORMAL.Enum(),
			}
		}
		if err := send(ctx, c, r.To, dm); err != nil {
			return nil, err
		}
		return map[string]any{"ts": ts}, nil
	case "send_media":
		c, err := client()
		if err != nil {
			return nil, err
		}
		att, err := upload(ctx, c, r.Path, r.Mime, r.Name)
		if err != nil {
			return nil, err
		}
		ts := now()
		dm := &signalpb.DataMessage{Timestamp: proto.Uint64(ts), Attachments: []*signalpb.AttachmentPointer{att}}
		if r.Text != "" {
			dm.Body = proto.String(r.Text)
		}
		if err := send(ctx, c, r.To, dm); err != nil {
			return nil, err
		}
		return map[string]any{"ts": ts}, nil
	case "read":
		c, err := client()
		if err != nil {
			return nil, err
		}
		author, err := libsignalgo.ServiceIDFromString(cmp.Or(r.Author, r.To))
		if err != nil {
			return nil, fmt.Errorf("author: %w", err)
		}
		if len(r.TS) == 0 || author.UUID == c.Store.ACI {
			return nil, nil
		}
		res := c.SendMessage(ctx, author, signalmeow.ReadReceptMessageForTimestamps(r.TS))
		return nil, resultErr(res)
	case "react":
		c, err := client()
		if err != nil {
			return nil, err
		}
		author, err := uuid.Parse(r.Author)
		if err != nil {
			return nil, fmt.Errorf("author: %w", err)
		}
		if len(r.TS) == 0 {
			return nil, errors.New("no ts")
		}
		return nil, send(ctx, c, r.To, &signalpb.DataMessage{
			Timestamp:               proto.Uint64(now()),
			RequiredProtocolVersion: proto.Uint32(uint32(signalpb.DataMessage_REACTIONS)),
			Reaction: &signalpb.DataMessage_Reaction{
				Emoji:                 proto.String(r.Emoji),
				Remove:                proto.Bool(r.Remove),
				TargetAuthorAciBinary: author[:],
				TargetSentTimestamp:   proto.Uint64(r.TS[0]),
			},
		})
	case "delete":
		c, err := client()
		if err != nil {
			return nil, err
		}
		if len(r.TS) == 0 {
			return nil, errors.New("no ts")
		}
		return nil, send(ctx, c, r.To, &signalpb.DataMessage{
			Timestamp: proto.Uint64(now()),
			Delete:    &signalpb.DataMessage_Delete{TargetSentTimestamp: proto.Uint64(r.TS[0])},
		})
	case "download":
		ptr, err := parsePointer(r.Pointer)
		if err != nil {
			return nil, err
		}
		return nil, download(ctx, ptr, r.Path)
	}
	return nil, fmt.Errorf("unknown op %q", r.Op)
}

func now() uint64 { return uint64(time.Now().UnixMilli()) }

func status(ctx context.Context) map[string]any {
	mu.Lock()
	c, conn := cli, connected
	mu.Unlock()
	s := map[string]any{"linked": false, "connected": false, "aci": "", "number": "", "name": ""}
	if c == nil || !c.IsLoggedIn() {
		return s
	}
	s["linked"] = true
	s["connected"] = conn && isConnected(c)
	s["aci"] = c.Store.ACI.String()
	s["number"] = c.Store.Number
	s["name"] = ownName(ctx, c)
	return s
}

func ownName(ctx context.Context, c *signalmeow.Client) string {
	if ar := c.Store.AccountRecord; ar != nil {
		if n := strings.TrimSpace(ar.GetGivenName() + " " + ar.GetFamilyName()); n != "" {
			return n
		}
	}
	if rc, err := c.Store.RecipientStore.LoadAndUpdateRecipient(ctx, c.Store.ACI, uuid.Nil, nil); err == nil && rc != nil {
		return rc.Profile.Name
	}
	return ""
}

// parseChat is a request's "to": a group id (44 characters of base64), or a person's service id.
func parseChat(to string) (libsignalgo.ServiceID, types.GroupIdentifier, error) {
	if len(to) == 44 {
		return libsignalgo.ServiceID{}, types.GroupIdentifier(to), nil
	}
	sid, err := libsignalgo.ServiceIDFromString(to)
	if err != nil {
		return sid, "", fmt.Errorf("not a Signal chat: %q", to)
	}
	return sid, "", nil
}

func send(ctx context.Context, c *signalmeow.Client, to string, dm *signalpb.DataMessage) error {
	user, group, err := parseChat(to)
	if err != nil {
		return err
	}
	content := signalmeow.WrapDataMessage(dm)
	if group != "" {
		res, err := c.SendGroupMessage(ctx, group, content)
		if err != nil {
			return err
		}
		if len(res.SuccessfullySentTo) == 0 && len(res.FailedToSendTo) > 0 {
			return fmt.Errorf("not sent to anyone in the group: %w", res.FailedToSendTo[0].Error)
		}
		return nil
	}
	return resultErr(c.SendMessage(ctx, user, content))
}

func resultErr(res signalmeow.SendMessageResult) error {
	if res.WasSuccessful {
		return nil
	}
	if res.Error != nil {
		return res.Error
	}
	return errors.New("Signal did not take the message")
}

func upload(ctx context.Context, c *signalmeow.Client, path, mime, name string) (*signalpb.AttachmentPointer, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if mime == "" || mime == "application/octet-stream" {
		mime = http.DetectContentType(data)
	}
	if name == "" {
		name = filepath.Base(path)
	}
	att, err := c.UploadAttachment(ctx, data)
	if err != nil {
		return nil, err
	}
	att.ContentType = proto.String(mime)
	att.FileName = proto.String(name)
	if strings.HasPrefix(mime, "image/") {
		if cfg, _, err := image.DecodeConfig(bytes.NewReader(data)); err == nil {
			att.Width, att.Height = proto.Uint32(uint32(cfg.Width)), proto.Uint32(uint32(cfg.Height))
		}
	}
	return att, nil
}

// parsePointer takes back an attachment pointer as an event gave it: a JSON object, or that object as a string.
func parsePointer(raw json.RawMessage) (*signalpb.AttachmentPointer, error) {
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
	var ptr signalpb.AttachmentPointer
	if err := (protojson.UnmarshalOptions{DiscardUnknown: true}).Unmarshal(raw, &ptr); err != nil {
		return nil, fmt.Errorf("not an attachment pointer: %w", err)
	}
	if len(ptr.GetKey()) == 0 {
		return nil, errors.New("the attachment has no key")
	}
	return &ptr, nil
}

func download(ctx context.Context, ptr *signalpb.AttachmentPointer, path string) error {
	if path == "" {
		return errors.New("no path")
	}
	tmp := path + ".part"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	_, err = signalmeow.DownloadAttachmentWithPointer(ctx, ptr, nil, f)
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = os.Rename(tmp, path)
	}
	if err != nil {
		_ = os.Remove(tmp)
	}
	return err
}

// --- linking --------------------------------------------------------------------------------------------------------

// link provisions this device: a QR address ("qr", a fresh one every 45 seconds as Signal Desktop does, for 15
// minutes), then, once Signal on the phone scans it, the device is kept and connected ("linked").
func link(name string) error {
	mu.Lock()
	stop()
	ctx, cancel := context.WithCancel(bg())
	linking = cancel
	c := container
	mu.Unlock()
	if c == nil {
		cancel()
		return errors.New("the Signal store is not open")
	}
	go func() {
		defer cancel()
		for round := 0; round < 20; round++ {
			roundCtx, roundCancel := context.WithCancel(ctx)
			ch := signalmeow.PerformProvisioning(roundCtx, c, name, false)
			done, failed := provisionRound(ctx, ch)
			roundCancel()
			if done || failed {
				return
			}
			if ctx.Err() != nil {
				return
			}
		}
		event("link_failed", map[string]any{"error": "The QR code was not scanned in time"})
	}()
	return nil
}

// provisionRound follows one provisioning socket: done once linked, failed once said so; neither means "new QR".
func provisionRound(ctx context.Context, ch chan signalmeow.ProvisioningResponse) (done, failed bool) {
	timer := time.NewTimer(45 * time.Second)
	defer timer.Stop()
	for {
		select {
		case resp, ok := <-ch:
			if !ok {
				return false, false
			}
			if resp.Err != nil {
				if ctx.Err() != nil {
					return false, true
				}
				event("link_failed", map[string]any{"error": linkWhy(resp.Err)})
				return false, true
			}
			switch resp.State {
			case signalmeow.StateProvisioningURLReceived:
				event("qr", map[string]any{"url": resp.ProvisioningURL})
			case signalmeow.StateProvisioningDataReceived:
				data := resp.ProvisioningData
				if data == nil || data.ACI == uuid.Nil {
					event("link_failed", map[string]any{"error": "Signal sent no account"})
					return false, true
				}
				linked(data)
				return true, false
			}
		case <-timer.C:
			// Still waiting for the scan: the phone may be scanning this one. Give the socket time to finish if it has
			// the data already, else start again with a new code.
			select {
			case resp, ok := <-ch:
				if ok && resp.State == signalmeow.StateProvisioningDataReceived && resp.ProvisioningData != nil {
					linked(resp.ProvisioningData)
					return true, false
				}
			default:
			}
			return false, false
		case <-ctx.Done():
			return false, true
		}
	}
}

func linked(data *store.DeviceData) {
	mu.Lock()
	c := container
	mu.Unlock()
	dev, err := c.DeviceByACI(bg(), data.ACI)
	if err != nil || dev == nil {
		event("link_failed", map[string]any{"error": fmt.Sprintf("the new device was not kept (%v)", err)})
		return
	}
	mu.Lock()
	linking = nil
	start(dev)
	mu.Unlock()
	event("linked", map[string]any{"aci": data.ACI.String(), "number": data.Number})
}

func linkWhy(err error) string {
	var le signalmeow.DeviceLinkError
	if errors.As(err, &le) {
		switch le.StatusCode {
		case http.StatusConflict:
			return "Signal turned the link down: this app lacks something your other devices need. Try again later."
		case http.StatusLengthRequired:
			return "Your Signal account has as many linked devices as it may. Remove one in Signal and try again."
		case http.StatusForbidden:
			return "The QR code was not valid or was used already. Try again."
		case http.StatusTooManyRequests:
			return "Signal asked to wait a few minutes before linking again."
		}
	}
	return "Linking did not finish (" + err.Error() + ")"
}

// --- contacts and groups --------------------------------------------------------------------------------------------

func avatarDir() string { return filepath.Join(dir, "avatars") }

// keepAvatar writes [data] under a name from [key] and says where; an empty string if there is nothing.
func keepAvatar(key string, data []byte) string {
	if len(data) == 0 {
		return ""
	}
	_ = os.MkdirAll(avatarDir(), 0o700)
	sum := sha256.Sum256([]byte(key))
	p := filepath.Join(avatarDir(), hex.EncodeToString(sum[:12]))
	if err := os.WriteFile(p, data, 0o600); err != nil {
		return ""
	}
	return p
}

func keptAvatar(key string) string {
	sum := sha256.Sum256([]byte(key))
	p := filepath.Join(avatarDir(), hex.EncodeToString(sum[:12]))
	if _, err := os.Stat(p); err == nil {
		return p
	}
	return ""
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func recipientName(r *types.Recipient) string {
	if r == nil {
		return ""
	}
	return strings.TrimSpace(cmp.Or(r.Nickname, r.ContactName, r.Profile.Name))
}

func contact(ctx context.Context, c *signalmeow.Client, r *types.Recipient) map[string]any {
	avatar := ""
	if len(r.ContactAvatar.Image) > 0 {
		key := "contact:" + r.ACI.String() + ":" + r.ContactAvatar.Hash
		if avatar = keptAvatar(key); avatar == "" {
			avatar = keepAvatar(key, r.ContactAvatar.Image)
		}
	} else if r.Profile.AvatarPath != "" && c != nil && ctx != nil {
		key := "profile:" + r.Profile.AvatarPath
		if avatar = keptAvatar(key); avatar == "" {
			if data, err := c.DownloadUserAvatar(ctx, r.Profile.AvatarPath, r.Profile.Key); err == nil {
				avatar = keepAvatar(key, data)
			}
		}
	}
	return map[string]any{"aci": r.ACI.String(), "name": recipientName(r), "number": r.E164, "avatar": nullable(avatar)}
}

func contacts(ctx context.Context, c *signalmeow.Client) ([]map[string]any, error) {
	all, err := c.Store.RecipientStore.LoadAllContacts(ctx)
	if err != nil {
		return nil, err
	}
	list := make([]map[string]any, 0, len(all))
	for _, r := range all {
		if r.ACI == uuid.Nil || r.ACI == c.Store.ACI {
			continue
		}
		list = append(list, contact(ctx, c, r))
	}
	return list, nil
}

func groups(ctx context.Context, c *signalmeow.Client) ([]map[string]any, error) {
	mu.Lock()
	d := db
	mu.Unlock()
	if d == nil {
		return nil, errNotLinked
	}
	rows, err := d.Query(ctx, `SELECT group_identifier FROM signalmeow_groups WHERE account_id=$1`, c.Store.ACI)
	if err != nil {
		return nil, err
	}
	var ids []string
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	_ = rows.Close()
	list := make([]map[string]any, 0, len(ids))
	for _, id := range ids {
		g, _, err := c.RetrieveGroupByID(ctx, types.GroupIdentifier(id), 0)
		if err != nil || g == nil {
			log.Debug().Err(err).Str("group", id).Msg("group not fetched")
			continue
		}
		members := make([]string, 0, len(g.Members))
		for _, m := range g.Members {
			members = append(members, m.ACI.String())
		}
		avatar := ""
		if g.AvatarPath != "" {
			key := "group:" + g.AvatarPath
			if avatar = keptAvatar(key); avatar == "" {
				if data, err := c.DownloadGroupAvatar(ctx, g.AvatarPath, g.GroupMasterKey); err == nil {
					avatar = keepAvatar(key, data)
				}
			}
		}
		list = append(list, map[string]any{"id": id, "title": g.Title, "members": members, "avatar": nullable(avatar)})
	}
	return list, nil
}

// senderName is a sender's name from what the store knows, without asking Signal.
func senderName(c *signalmeow.Client, aci uuid.UUID) string {
	if aci == uuid.Nil {
		return ""
	}
	ctx, cancel := context.WithTimeout(bg(), 5*time.Second)
	defer cancel()
	r, err := c.Store.RecipientStore.LoadAndUpdateRecipient(ctx, aci, uuid.Nil, nil)
	if err != nil {
		return ""
	}
	return recipientName(r)
}

// --- events ---------------------------------------------------------------------------------------------------------

func onEvent(raw events.SignalEvent) bool {
	mu.Lock()
	c := cli
	mu.Unlock()
	switch evt := raw.(type) {
	case *events.ChatEvent:
		if c != nil {
			chatEvent(c, evt)
		}
	case *events.Receipt:
		kind := ""
		switch evt.Content.GetType() {
		case signalpb.ReceiptMessage_DELIVERY:
			kind = "delivered"
		case signalpb.ReceiptMessage_READ:
			kind = "read"
		}
		if kind != "" {
			event("receipt", map[string]any{"chat": evt.Sender.String(), "ts": nonNil(evt.Content.GetTimestamp()), "kind": kind})
		}
	case *events.ContactList:
		if c == nil {
			break
		}
		list := make([]map[string]any, 0, len(evt.Contacts))
		for _, r := range evt.Contacts {
			if r.ACI != uuid.Nil && r.ACI != c.Store.ACI {
				// No avatar downloads here: this is the receive loop.
				list = append(list, contact(nil, nil, r))
			}
		}
		event("contacts", map[string]any{"list": list})
	case *events.LoggedOut:
		if c != nil {
			go unlinked(c)
		}
	case *events.DecryptionError:
		log.Warn().Err(evt.Err).Stringer("sender", evt.Sender).Uint64("ts", evt.Timestamp).Msg("message not decrypted")
	}
	return true
}

func nonNil(ts []uint64) []uint64 {
	if ts == nil {
		return []uint64{}
	}
	return ts
}

func chatEvent(c *signalmeow.Client, evt *events.ChatEvent) {
	dm, ok := evt.Event.(*signalpb.DataMessage)
	if !ok {
		return
	}
	group := dm.GetGroupV2() != nil
	chat := evt.Info.ChatID
	sender := evt.Info.Sender
	switch {
	case dm.Reaction != nil:
		target, _ := signalmeow.ParseStringOrBinaryUUID(dm.Reaction.GetTargetAuthorAci(), dm.Reaction.GetTargetAuthorAciBinary())
		event("reaction", map[string]any{
			"chat": chat, "from": sender.String(), "target_ts": dm.Reaction.GetTargetSentTimestamp(),
			"target_author": target.String(), "emoji": dm.Reaction.GetEmoji(), "remove": dm.Reaction.GetRemove(),
		})
	case dm.Delete != nil:
		event("deleted", map[string]any{"chat": chat, "target_ts": dm.Delete.GetTargetSentTimestamp()})
	case dm.Body != nil || len(dm.Attachments) > 0 || dm.Sticker != nil:
		event("message", message(c, chat, group, sender, dm))
	}
}

func message(c *signalmeow.Client, chat string, group bool, sender uuid.UUID, dm *signalpb.DataMessage) map[string]any {
	atts := dm.GetAttachments()
	if st := dm.GetSticker(); st != nil && st.GetData() != nil {
		atts = append(atts, st.GetData())
	}
	media := make([]map[string]any, 0, len(atts))
	for _, a := range atts {
		if m := mediaOf(a); m != nil {
			media = append(media, m)
		}
	}
	m := map[string]any{
		"chat": chat, "group": group, "from": sender.String(), "name": senderName(c, sender),
		"mine": sender == c.Store.ACI, "ts": dm.GetTimestamp(), "text": dm.GetBody(), "media": media,
	}
	if q := dm.GetQuote(); q != nil {
		author, _ := signalmeow.ParseStringOrBinaryUUID(q.GetAuthorAci(), q.GetAuthorAciBinary())
		m["quote"] = map[string]any{"ts": q.GetId(), "author": author.String(), "text": q.GetText()}
	}
	return m
}

func mediaOf(a *signalpb.AttachmentPointer) map[string]any {
	ptr, err := protojson.Marshal(a)
	if err != nil {
		return nil
	}
	return map[string]any{
		"pointer": json.RawMessage(ptr), "mime": a.GetContentType(), "name": a.GetFileName(), "size": a.GetSize(),
		"width": a.GetWidth(), "height": a.GetHeight(),
	}
}
