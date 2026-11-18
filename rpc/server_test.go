package rpc

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"net"
	"sync"
	"testing"
	"time"

	"github.com/sheyiyuan/zero-beat-core/media"
	"github.com/sheyiyuan/zero-beat-core/player"
	"github.com/sheyiyuan/zero-beat-core/session"
	"github.com/sheyiyuan/zero-beat-core/source"
	"github.com/sheyiyuan/zero-beat-core/store"
)

const testToken = "00112233445566778899aabbccddeeff"

func TestStopForwardsToSessionWithoutClearingQueueOrClosing(t *testing.T) {
	fake := newFake()
	c := dial(t, startServer(t, fake))
	c.hello(t)
	res := c.call(t, 3, MethodStop, map[string]any{})
	if res["error"] != nil {
		t.Fatal(res["error"])
	}
	if fake.count("stop") != 1 || fake.count("clear") != 0 || fake.closed() {
		t.Fatalf("unexpected stop effects: %#v", fake.counts())
	}
}

func TestHelloShapeAndCapabilityFilter(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	if ip := srv.ln.Addr().(*net.TCPAddr).IP.String(); ip != "127.0.0.1" {
		t.Fatal(ip)
	}
	c := dial(t, srv)
	res := c.call(t, 1, MethodHello, map[string]any{
		"token":               testToken,
		"api":                 APIVersion,
		"repo":                RepoVersion,
		"client_version":      GUIVersion,
		"platform":            "linux",
		"engine_capabilities": []string{"clip", "downloads", "sync", "mpris", "tray", "loudnorm"},
	})
	result := object(t, res["result"])
	if int(result["api"].(float64)) != 1 || result["core_version"] != session.CoreVersion || result["gui_version"] != GUIVersion {
		t.Fatalf("%v", result)
	}
	caps := stringsOf(result["capabilities"])
	for _, want := range []string{"library", "search", "link", "player", "clip", "loudnorm"} {
		if !contains(caps, want) {
			t.Fatalf("missing %s in %v", want, caps)
		}
	}
	for _, banned := range []string{"downloads", "sync", "mpris", "tray"} {
		if contains(caps, banned) {
			t.Fatalf("advertised %s", banned)
		}
	}
	playerObj := object(t, result["player"])
	if playerObj["playback_id"] != nil || playerObj["play_when_ready"] != false {
		t.Fatalf("player %#v", playerObj)
	}
	snap := object(t, playerObj["snapshot"])
	if snap["state"] != "idle" || snap["mode"] != "list_loop" {
		t.Fatalf("snapshot %#v", snap)
	}
	if fake.count("play")+fake.count("search")+fake.count("songs") != 0 {
		t.Fatalf("hello touched playback calls: %#v", fake.counts())
	}
}

func TestHelloKeepsSourceNotice(t *testing.T) {
	fake := newFake()
	fake.sourceStatus = []session.SourceStatus{
		{ID: "bilibili", Name: "哔哩哔哩", Notice: "未登录，匿名访问部分内容受限", Capabilities: []string{"account", "search"}},
		{ID: "local", Name: "本机", Capabilities: []string{"search"}},
	}
	srv := startServer(t, fake)
	account := object(t, object(t, dial(t, srv).hello(t)["result"])["account"])
	bili := object(t, account["bilibili"])
	if bili["notice"] != "未登录，匿名访问部分内容受限" || bili["logged_in"] != false {
		t.Fatalf("bilibili %#v", bili)
	}
	if _, ok := account["local"]; ok {
		t.Fatalf("本机不应出现在账号摘要里: %#v", account)
	}
}

func TestBadTokenDoesNotTouchSession(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	c := dial(t, srv)
	res := c.call(t, 1, MethodHello, map[string]any{"token": "nope", "api": 1})
	errObj := object(t, res["error"])
	if int(errObj["code"].(float64)) != CodeUnauthorized {
		t.Fatal(errObj)
	}
	if fake.total() != 0 {
		t.Fatalf("session was touched: %#v", fake.counts())
	}
	assertClosed(t, c.conn)
}

func TestAPIMismatchIsFatal(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	c := dial(t, srv)
	res := c.call(t, 1, MethodHello, map[string]any{"token": testToken, "api": 99})
	errObj := object(t, res["error"])
	if int(errObj["code"].(float64)) != CodeVersion {
		t.Fatal(errObj)
	}
	data := object(t, errObj["data"])
	if int(data["api"].(float64)) != APIVersion {
		t.Fatal(data)
	}
	if fake.total() != 0 {
		t.Fatalf("version mismatch touched session: %#v", fake.counts())
	}
	assertClosed(t, c.conn)
}

func TestHelloFrameLimitAndAuthenticatedLimit(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	early := dial(t, srv)
	blob := make([]byte, MaxHelloFrame+1)
	for i := range blob {
		blob[i] = 'a'
	}
	early.conn.SetWriteDeadline(time.Now().Add(time.Second))
	_, _ = early.conn.Write(append(blob, '\n'))
	assertClosed(t, early.conn)
	if fake.total() != 0 {
		t.Fatal(fake.counts())
	}

	c := dial(t, srv)
	c.hello(t)
	keyword := stringsRepeat("词", MaxHelloFrame)
	res := c.call(t, 11, MethodSearch, map[string]any{"keyword": keyword, "page": 1, "source": ""})
	if res["error"] != nil {
		t.Fatal(res["error"])
	}
	if fake.count("search") != 1 {
		t.Fatalf("search not accepted: %#v", fake.counts())
	}
	huge := make([]byte, MaxFrame+8)
	for i := range huge {
		huge[i] = 'b'
	}
	c.conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
	_, _ = c.conn.Write(append(huge, '\n'))
	assertClosed(t, c.conn)
}

func TestHelloTimeout(t *testing.T) {
	t.Parallel()
	fake := newFake()
	srv := startServer(t, fake)
	conn, err := net.Dial("tcp", srv.ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	start := time.Now()
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	_, err = conn.Read(make([]byte, 1))
	if err == nil {
		t.Fatal("expected close")
	}
	if time.Since(start) < 2*time.Second {
		t.Fatalf("closed too fast: %v", time.Since(start))
	}
	if fake.total() != 0 {
		t.Fatal(fake.counts())
	}
}

func TestUnauthenticatedConnectionLimit(t *testing.T) {
	srv := startServer(t, newFake())
	var held []net.Conn
	for i := 0; i < MaxPendingHello; i++ {
		c, err := net.Dial("tcp", srv.ln.Addr().String())
		if err != nil {
			t.Fatal(err)
		}
		held = append(held, c)
	}
	defer func() {
		for _, c := range held {
			c.Close()
		}
	}()
	extra, err := net.Dial("tcp", srv.ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer extra.Close()
	_ = extra.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	_, err = extra.Read(make([]byte, 1))
	if err == nil || isTimeout(err) {
		t.Fatalf("ninth connection was not rejected: %v", err)
	}
	_ = held[0].SetReadDeadline(time.Now().Add(200 * time.Millisecond))
	_, err = held[0].Read(make([]byte, 1))
	if !isTimeout(err) {
		t.Fatalf("first connection closed: %v", err)
	}
}

func TestSingleAuthenticatedConnection(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	first := dial(t, srv)
	first.hello(t)
	second := dial(t, srv)
	res := second.call(t, 1, MethodHello, map[string]any{"token": testToken, "api": 1})
	if res["error"] == nil {
		t.Fatal("second hello accepted")
	}
	assertClosed(t, second.conn)
	if fake.count("snapshot") != 1 {
		t.Fatalf("second hello touched snapshot: %#v", fake.counts())
	}
	state := first.call(t, 3, MethodPlayerState, map[string]any{})
	if state["error"] != nil {
		t.Fatal(state)
	}
	first.conn.Close()
	waitDisc(t, fake)
	third := dial(t, srv)
	third.hello(t)
	if fake.count("snapshot") != 3 {
		t.Fatalf("reconnect snapshot: %#v", fake.counts())
	}
}

func TestBidirectionalLoadDoesNotDeadlock(t *testing.T) {
	srv, engine := startServerEngine(t, newFake())
	c := dial(t, srv)
	c.hello(t)
	done := make(chan struct{})
	go func() {
		defer close(done)
		msg := c.read(t)
		if msg["method"] != MethodEngineLoad {
			t.Errorf("method %v", msg["method"])
		}
		params := object(t, msg["params"])
		c.write(t, map[string]any{
			"jsonrpc": Version,
			"method":  EventEnginePlaying,
			"params": map[string]any{
				"playback_id": params["playback_id"], "seq": 4, "state": "playing",
				"position_ms": 16000, "duration_ms": 245000,
			},
		})
		c.write(t, map[string]any{
			"jsonrpc": Version,
			"id":      msg["id"],
			"result":  map[string]any{"accepted": true, "playback_id": params["playback_id"]},
		})
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	err := engine.Load(ctx, "pb_01", media.Stream{URL: "https://cdn.example/a", Codec: "aac", DurationMS: 245000}, 15*time.Second, session.PlayIntent{})
	if err != nil {
		t.Fatal(err)
	}
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("peer did not finish")
	}
	deadline := time.Now().Add(time.Second)
	for engine.State() != media.StatePlaying {
		if time.Now().After(deadline) {
			t.Fatalf("state %v", engine.State())
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func TestCancelDoesNotCancelEngineCall(t *testing.T) {
	fake := newFake()
	fake.blockSearch = true
	srv, engine := startServerEngine(t, fake)
	c := dial(t, srv)
	c.hello(t)
	c.write(t, map[string]any{
		"jsonrpc": Version, "id": 11, "method": MethodSearch,
		"params": map[string]any{"keyword": "示例", "page": 1},
	})
	loadDone := make(chan error, 1)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		loadDone <- engine.Load(ctx, "pb_01", media.Stream{URL: "https://cdn.example/a"}, 0, session.PlayIntent{PlayWhenReady: true})
	}()
	loadMsg := c.read(t)
	if loadMsg["method"] != MethodEngineLoad {
		t.Fatal(loadMsg)
	}
	c.write(t, map[string]any{
		"jsonrpc": Version, "id": 13, "method": MethodCancel,
		"params": map[string]any{"rpc_id": loadMsg["id"]},
	})
	cancelRes := c.read(t)
	if cancelRes["error"] != nil {
		t.Fatal(cancelRes)
	}
	c.write(t, map[string]any{
		"jsonrpc": Version, "id": loadMsg["id"],
		"result": map[string]any{"accepted": true, "playback_id": "pb_01"},
	})
	if err := <-loadDone; err != nil {
		t.Fatal(err)
	}
	c.write(t, map[string]any{
		"jsonrpc": Version, "id": 15, "method": MethodCancel,
		"params": map[string]any{"rpc_id": 11},
	})
	var search map[string]any
	for i := 0; i < 2; i++ {
		msg := c.read(t)
		if msg["id"] == float64(11) {
			search = msg
		}
	}
	if search == nil {
		t.Fatal("missing search response")
	}
	errObj := object(t, search["error"])
	if int(errObj["code"].(float64)) != CodeCancelled {
		t.Fatal(search)
	}
}

func TestMethodTimeoutCancelsContext(t *testing.T) {
	t.Parallel()
	fake := newFake()
	fake.blockPause = true
	srv := startServer(t, fake)
	c := dial(t, srv)
	c.hello(t)
	start := time.Now()
	res := c.call(t, 5, MethodPause, map[string]any{})
	if time.Since(start) < 2*time.Second {
		t.Fatalf("returned too fast: %v", time.Since(start))
	}
	errObj := object(t, res["error"])
	if int(errObj["code"].(float64)) != CodeCancelled {
		t.Fatal(res)
	}
	if !errors.Is(fake.pauseErr(), context.DeadlineExceeded) {
		t.Fatal(fake.pauseErr())
	}
}

func TestOutboundQueueOverflowClosesConnection(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	c := dial(t, srv)
	c.hello(t)
	srv.gateMu.Lock()
	srv.gate = make(chan struct{})
	srv.gateMu.Unlock()
	snap := fake.Snapshot()
	failed := false
	for i := 0; i < ReliableQueue+2; i++ {
		if !srv.publish(snap) {
			failed = true
			break
		}
	}
	if !failed {
		t.Fatal("queue accepted more than its reliable capacity")
	}
	assertClosed(t, c.conn)
	waitDisc(t, fake)
}

func TestDisconnectFailsInflightAndReconnectIsFresh(t *testing.T) {
	fake := newFake()
	srv, engine := startServerEngine(t, fake)
	c := dial(t, srv)
	c.hello(t)
	errCh := make(chan error, 1)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		errCh <- engine.Load(ctx, "pb_old", media.Stream{URL: "https://cdn.example/old"}, 0, session.PlayIntent{})
	}()
	if msg := c.read(t); msg["method"] != MethodEngineLoad {
		t.Fatal(msg)
	}
	c.conn.Close()
	if err := <-errCh; err == nil {
		t.Fatal("load survived disconnect")
	}
	waitDisc(t, fake)
	fake.setPlayback("pb_new")
	next := dial(t, srv)
	res := next.hello(t)
	playerObj := object(t, object(t, res["result"])["player"])
	if playerObj["playback_id"] != "pb_new" {
		t.Fatalf("stale snapshot %#v", playerObj)
	}
	_ = next.conn.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
	buf := make([]byte, 1)
	if _, err := next.r.Read(buf); err == nil {
		t.Fatal("reconnected peer received a replayed frame")
	}
}

func TestVolumeCacheAppliedOnNextLoad(t *testing.T) {
	srv, engine := startServerEngine(t, newFake())
	c := dial(t, srv)
	c.hello(t)
	ctx := context.Background()
	if err := engine.SetVolume(ctx, "", 0.25); err != nil {
		t.Fatal(err)
	}
	if err := engine.SetCompensationDB(ctx, "", -3); err != nil {
		t.Fatal(err)
	}
	if err := engine.SetAutoGain(ctx, "", true); err != nil {
		t.Fatal(err)
	}
	got := make(chan map[string]any, 1)
	go func() {
		msg := c.read(t)
		got <- msg
		c.write(t, map[string]any{
			"jsonrpc": Version,
			"id":      msg["id"],
			"result":  map[string]any{"accepted": true, "playback_id": "pb_01"},
		})
	}()
	if err := engine.Load(ctx, "pb_01", media.Stream{URL: "https://cdn.example/a", Headers: map[string]string{"Referer": "https://www.bilibili.com/"}}, time.Second, session.PlayIntent{PlayWhenReady: false}); err != nil {
		t.Fatal(err)
	}
	msg := <-got
	if msg["method"] != MethodEngineLoad {
		t.Fatalf("sent %v before load", msg["method"])
	}
	params := object(t, msg["params"])
	if params["volume"].(float64) != 0.25 || params["comp_db"].(float64) != -3 || params["auto_gain"] != true || params["play_when_ready"] != false {
		t.Fatalf("%v", params)
	}
	if params["start_at_ms"].(float64) != 1000 {
		t.Fatal(params["start_at_ms"])
	}
}

func TestStalePlaybackFromPeer(t *testing.T) {
	srv, engine := startServerEngine(t, newFake())
	c := dial(t, srv)
	c.hello(t)
	go func() {
		msg := c.read(t)
		c.write(t, map[string]any{
			"jsonrpc": Version,
			"id":      msg["id"],
			"error": map[string]any{
				"code": CodeStalePlayback, "message": "播放代次已过期",
				"data": map[string]any{"reason": "stale_playback"},
			},
		})
	}()
	err := engine.Load(context.Background(), "pb_01", media.Stream{URL: "https://cdn.example/a"}, 0, session.PlayIntent{})
	if !errors.Is(err, session.ErrStalePlayback) {
		t.Fatal(err)
	}
	if err := engine.Pause(context.Background(), "other"); err != nil && !errors.Is(err, session.ErrStalePlayback) && !errors.Is(err, errNoPlayback) {
		t.Fatal(err)
	}
}

func TestPlayAcceptsWithoutWaitingForAudio(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	c := dial(t, srv)
	c.hello(t)
	start := time.Now()
	res := c.call(t, 9, MethodPlay, map[string]any{"song_id": "bilibili:BV1demo:1", "queue_index": -1, "start_at_ms": 0})
	if time.Since(start) > time.Second {
		t.Fatal("play waited")
	}
	result := object(t, res["result"])
	if int(result["request_id"].(float64)) != 4 || result["started"] != true {
		t.Fatal(result)
	}
}

func TestLibrarySearchAndLinkShapes(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	c := dial(t, srv)
	c.hello(t)
	songs := object(t, c.call(t, 3, MethodSongs, map[string]any{"playlist_id": "local-default", "offset": 0, "limit": 50})["result"])
	list := songs["songs"].([]any)
	song := object(t, list[0])
	if song["id"] != "bilibili:BV1demo:1" || song["duration_ms"].(float64) != 245000 {
		t.Fatal(song)
	}
	if len(song["title"].(string)) < 20 {
		t.Fatal(song["title"])
	}
	search := object(t, c.call(t, 5, MethodSearch, map[string]any{"keyword": "示例", "page": 1, "source": ""})["result"])
	if search["has_warning"] != true || search["warning"] != "部分音源搜索失败：哔哩哔哩" {
		t.Fatal(search)
	}
	link := object(t, c.call(t, 7, MethodOpenLink, map[string]any{"text": "https://www.bilibili.com/video/BV1GJ411x7h7?p=2"})["result"])
	if link["kind"] != "track" || link["matched"] != true {
		t.Fatal(link)
	}
	ref := object(t, link["ref"])
	if ref["external_id"] != "BV1GJ411x7h7" || ref["page"].(float64) != 2 {
		t.Fatal(ref)
	}
}

func TestQuitWritesResponseThenStops(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	c := dial(t, srv)
	c.hello(t)
	res := c.call(t, 21, MethodQuit, map[string]any{})
	if res["result"] == nil {
		t.Fatal(res)
	}
	if !fake.closed() {
		t.Fatal("session was not closed before the response")
	}
	assertClosed(t, c.conn)
	conn, err := net.DialTimeout("tcp", srv.ln.Addr().String(), 300*time.Millisecond)
	if err == nil {
		conn.Close()
		t.Fatal("listener still accepted")
	}
}

func TestRejectsEvenRequestID(t *testing.T) {
	fake := newFake()
	srv := startServer(t, fake)
	c := dial(t, srv)
	c.hello(t)
	res := c.call(t, 2, MethodPlay, map[string]any{"song_id": "x", "queue_index": -1})
	errObj := object(t, res["error"])
	if int(errObj["code"].(float64)) != CodeInvalidRequest {
		t.Fatal(res)
	}
	if fake.count("play") != 0 {
		t.Fatal("even id dispatched")
	}
}

type lineConn struct {
	conn net.Conn
	r    *bufio.Reader
}

func startServer(t *testing.T, fake *fakeSession) *Server {
	t.Helper()
	srv, _ := startServerEngine(t, fake)
	return srv
}

func startServerEngine(t *testing.T, fake *fakeSession) (*Server, *RemoteEngine) {
	t.Helper()
	engine := NewRemoteEngine()
	srv, err := Serve(fake, engine, testToken)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(srv.Shutdown)
	return srv, engine
}

func dial(t *testing.T, srv *Server) *lineConn {
	t.Helper()
	conn, err := net.Dial("tcp", srv.ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return &lineConn{conn: conn, r: bufio.NewReader(conn)}
}

func (c *lineConn) hello(t *testing.T) map[string]any {
	t.Helper()
	return c.call(t, 1, MethodHello, map[string]any{
		"token": testToken, "api": APIVersion, "repo": RepoVersion,
		"client_version": GUIVersion, "platform": "linux",
		"engine_capabilities": []string{"clip"},
	})
}

func (c *lineConn) call(t *testing.T, id int, method string, params any) map[string]any {
	t.Helper()
	c.write(t, map[string]any{"jsonrpc": Version, "id": id, "method": method, "params": params})
	return c.read(t)
}

func (c *lineConn) write(t *testing.T, v any) {
	t.Helper()
	body, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	_ = c.conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
	if _, err := c.conn.Write(append(body, '\n')); err != nil {
		t.Fatal(err)
	}
}

func (c *lineConn) read(t *testing.T) map[string]any {
	t.Helper()
	_ = c.conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	line, err := c.r.ReadBytes('\n')
	if err != nil {
		t.Fatal(err)
	}
	var msg map[string]any
	if err := json.Unmarshal(line, &msg); err != nil {
		t.Fatalf("%s: %v", line, err)
	}
	return msg
}

func object(t *testing.T, v any) map[string]any {
	t.Helper()
	m, ok := v.(map[string]any)
	if !ok {
		t.Fatalf("not object: %#v", v)
	}
	return m
}

func stringsOf(v any) []string {
	raw, _ := v.([]any)
	out := make([]string, 0, len(raw))
	for _, item := range raw {
		out = append(out, item.(string))
	}
	return out
}

func contains(list []string, want string) bool {
	for _, item := range list {
		if item == want {
			return true
		}
	}
	return false
}

func assertClosed(t *testing.T, conn net.Conn) {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(time.Second))
	_, err := conn.Read(make([]byte, 1))
	if err == nil {
		t.Fatal("connection stayed open")
	}
}

func isTimeout(err error) bool {
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
}

func waitDisc(t *testing.T, fake *fakeSession) {
	t.Helper()
	select {
	case <-fake.disc:
	case <-time.After(time.Second):
		t.Fatal("OnEngineDisconnected was not called")
	}
}

func stringsRepeat(s string, n int) string {
	out := make([]byte, 0, len(s)*n)
	for i := 0; i < n; i++ {
		out = append(out, s...)
	}
	return string(out)
}

type fakeSession struct {
	disconnectGate <-chan struct{}
	mu             sync.Mutex
	calls          map[string]int
	snap           session.Snapshot
	blockSearch    bool
	blockPause     bool
	paused         error
	isClosed       bool
	disc           chan struct{}
	sourceStatus   []session.SourceStatus
}

func newFake() *fakeSession {
	return &fakeSession{
		calls: map[string]int{},
		disc:  make(chan struct{}, 1),
		snap: session.Snapshot{
			Player: player.State{
				Queue:         []store.Song{},
				Volume:        0.8,
				Mode:          player.ModeListLoop,
				Quality:       source.QualityAuto,
				PlaybackState: media.StateIdle,
			},
		},
	}
}

func (f *fakeSession) bump(name string) {
	f.mu.Lock()
	f.calls[name]++
	f.mu.Unlock()
}

func (f *fakeSession) count(name string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls[name]
}

func (f *fakeSession) total() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, v := range f.calls {
		n += v
	}
	return n
}

func (f *fakeSession) counts() map[string]int {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := map[string]int{}
	for k, v := range f.calls {
		out[k] = v
	}
	return out
}

func (f *fakeSession) DataDir() string { f.bump("datadir"); return "/tmp/zero-beat" }
func (f *fakeSession) Close() error {
	f.bump("close")
	f.mu.Lock()
	f.isClosed = true
	f.mu.Unlock()
	return nil
}
func (f *fakeSession) closed() bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.isClosed
}
func (f *fakeSession) SetEngine(session.Engine) { f.bump("setengine") }
func (f *fakeSession) Playlists(context.Context) ([]store.Playlist, string, error) {
	f.bump("playlists")
	return []store.Playlist{}, "", nil
}
func (f *fakeSession) Songs(_ context.Context, id string, offset, limit int) (session.SongPage, error) {
	f.bump("songs")
	song := store.NormalizeSong(store.Song{
		Source: "bilibili", RemoteID: "BV1demo", Page: 1,
		Title: "很长很长的示例标题用来检查单行省略时仍然保留完整语义", Artist: "示例作者",
		Duration: 245, AddedAt: time.Date(2026, 11, 1, 12, 0, 0, 0, time.UTC),
	})
	return session.SongPage{Songs: []store.Song{song}, Total: 1, Offset: offset, Limit: limit}, nil
}
func (f *fakeSession) Search(ctx context.Context, keyword string, page int, sourceID string) (session.SearchHit, error) {
	f.bump("search")
	if f.blockSearch {
		<-ctx.Done()
		return session.SearchHit{}, ctx.Err()
	}
	return session.SearchHit{
		Pages:   2,
		Warning: "部分音源搜索失败：哔哩哔哩",
		Candidates: []source.Candidate{{
			Track: source.Track{Source: source.NetEase, ExternalID: "186016", Page: 1, Title: "示例", Artist: "示例作者", Duration: 180},
		}},
	}, nil
}
func (f *fakeSession) OpenLink(context.Context, string) (session.LinkResult, error) {
	f.bump("link")
	return session.LinkResult{
		Matched: true, Kind: session.LinkTrack,
		Ref:  source.Ref{Source: source.Bilibili, ExternalID: "BV1GJ411x7h7", Page: 2},
		Song: store.Song{Source: "bilibili", RemoteID: "BV1GJ411x7h7", Page: 2},
	}, nil
}
func (f *fakeSession) Play(context.Context, session.PlayInput) (session.Accepted, error) {
	f.bump("play")
	return session.Accepted{RequestID: 4, Started: true}, nil
}
func (f *fakeSession) Toggle(context.Context) (session.Accepted, error) {
	f.bump("toggle")
	return session.Accepted{RequestID: 1, Started: true}, nil
}
func (f *fakeSession) Pause(ctx context.Context) error {
	f.bump("pause")
	if f.blockPause {
		<-ctx.Done()
		f.mu.Lock()
		f.paused = ctx.Err()
		f.mu.Unlock()
		return ctx.Err()
	}
	return nil
}
func (f *fakeSession) pauseErr() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.paused
}
func (f *fakeSession) Resume(context.Context) error { f.bump("resume"); return nil }
func (f *fakeSession) Stop(context.Context) error   { f.bump("stop"); return nil }
func (f *fakeSession) Next(context.Context) (session.Accepted, error) {
	f.bump("next")
	return session.Accepted{}, nil
}
func (f *fakeSession) Prev(context.Context) (session.Accepted, error) {
	f.bump("prev")
	return session.Accepted{}, nil
}
func (f *fakeSession) SeekMS(context.Context, int64) error { f.bump("seek"); return nil }
func (f *fakeSession) SetVolume(context.Context, float64) error {
	f.bump("volume")
	return nil
}
func (f *fakeSession) SetMode(context.Context, player.Mode) error { f.bump("mode"); return nil }
func (f *fakeSession) Enqueue(context.Context, store.Song) (int, error) {
	f.bump("enqueue")
	return 1, nil
}
func (f *fakeSession) InsertNext(context.Context, store.Song) (int, error) {
	f.bump("insert")
	return 1, nil
}
func (f *fakeSession) RemoveAt(context.Context, int) error { f.bump("remove"); return nil }
func (f *fakeSession) MoveAt(context.Context, int, int) error {
	f.bump("move")
	return nil
}
func (f *fakeSession) ClearUpcoming(context.Context) error { f.bump("clear"); return nil }
func (f *fakeSession) Snapshot() session.Snapshot {
	f.bump("snapshot")
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.snap
}
func (f *fakeSession) setPlayback(id string) {
	f.mu.Lock()
	f.snap.PlaybackID = id
	f.mu.Unlock()
}
func (f *fakeSession) Subscribe() (<-chan struct{}, func()) {
	ch := make(chan struct{})
	var once sync.Once
	return ch, func() { once.Do(func() { close(ch) }) }
}
func (f *fakeSession) Sources(context.Context) ([]session.SourceStatus, error) {
	f.bump("sources")
	return f.sourceStatus, nil
}
func (f *fakeSession) OnEngineDisconnected() {
	f.bump("disconnect")
	if f.disconnectGate != nil {
		<-f.disconnectGate
	}
	select {
	case f.disc <- struct{}{}:
	default:
	}
}

var _ Session = (*fakeSession)(nil)

func TestReconnectWaitsForDisconnectCleanup(t *testing.T) {
	gate := make(chan struct{})
	fake := newFake()
	fake.disconnectGate = gate
	old := &clientConn{slot: slotControl}
	srv := &Server{sess: fake, control: old, all: map[*clientConn]struct{}{old: {}}}
	srv.release(old)
	// A new owner cannot attach while the old Session is persisting state.
	next := &clientConn{slot: slotUnauth}
	if err := srv.promote(next); !errors.Is(err, errBusy) {
		close(gate)
		t.Fatalf("accepted new owner before disconnect cleanup: %v", err)
	}
	close(gate)
	waitDisc(t, fake)
	deadline := time.Now().Add(time.Second)
	for {
		srv.mu.Lock()
		released := srv.control == nil
		srv.mu.Unlock()
		if released {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("old owner was not released")
		}
		time.Sleep(time.Millisecond)
	}
	if err := srv.promote(next); err != nil {
		t.Fatalf("reconnect after cleanup: %v", err)
	}
}
