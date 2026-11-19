package rpc

import (
	"errors"
	"log"
	"net"
	"os"
	"sync"
	"syscall"
	"time"

	"github.com/sheyiyuan/zero-beat-core/session"
)

type accountBrief struct {
	LoggedIn bool   `json:"logged_in"`
	Name     string `json:"name"`
	Notice   string `json:"notice,omitempty"`
}

// Server is a local NDJSON JSON-RPC endpoint. One writer per connection.
type Server struct {
	sess      Session
	engine    *RemoteEngine
	token     string
	ln        net.Listener
	done      chan struct{}
	once      sync.Once
	subCancel func()

	mu         sync.Mutex
	shut       bool
	unauth     int
	control    *clientConn
	all        map[*clientConn]struct{}
	lastNotice string

	gateMu sync.RWMutex
	gate   chan struct{}

	// loginMu serializes QR polling and same-device web commit. A poll that
	// started earlier restores the previous cookie jar when it returns; web
	// commit must run only after that restore, then install the new session.
	loginMu sync.Mutex
}

func Serve(sess Session, engine *RemoteEngine, token string) (*Server, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	return serveListener(sess, engine, token, ln), nil
}

// ServeUnix keeps Android IPC outside the IP firewall. The socket belongs in
// the app's private data directory; token authentication still applies.
func ServeUnix(sess Session, engine *RemoteEngine, token, path string) (*Server, error) {
	if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSocket != 0 {
		conn, dialErr := net.DialTimeout("unix", path, time.Second)
		if dialErr == nil {
			_ = conn.Close()
			return nil, errBusy
		}
		// Recover a socket left by a killed process, never an active listener,
		// regular file or a path we cannot access.
		if errors.Is(dialErr, syscall.ECONNREFUSED) {
			if err := os.Remove(path); err != nil {
				return nil, err
			}
		}
	}
	ln, err := net.Listen("unix", path)
	if err != nil {
		return nil, err
	}
	if err := os.Chmod(path, 0600); err != nil {
		_ = ln.Close()
		return nil, err
	}
	return serveListener(sess, engine, token, ln), nil
}

func serveListener(sess Session, engine *RemoteEngine, token string, ln net.Listener) *Server {
	s := &Server{
		sess:   sess,
		engine: engine,
		token:  token,
		ln:     ln,
		done:   make(chan struct{}),
		all:    map[*clientConn]struct{}{},
	}
	updates, cancel := sess.Subscribe()
	s.subCancel = cancel
	go s.forwardSnapshots(updates)
	if owner, ok := sess.(featureSession); ok {
		go s.forwardFeatures(owner.Features())
	}
	go s.accept()
	return s
}

func (s *Server) Port() int {
	if addr, ok := s.ln.Addr().(*net.TCPAddr); ok {
		return addr.Port
	}
	return 0
}

func (s *Server) SocketPath() string {
	if addr, ok := s.ln.Addr().(*net.UnixAddr); ok {
		return addr.Name
	}
	return ""
}

func (s *Server) Shutdown() {
	s.once.Do(func() {
		close(s.done)
		if s.subCancel != nil {
			s.subCancel()
		}
		_ = s.ln.Close()
		s.mu.Lock()
		s.shut = true
		conns := make([]*clientConn, 0, len(s.all))
		for c := range s.all {
			conns = append(conns, c)
		}
		s.mu.Unlock()
		for _, c := range conns {
			c.close()
		}
		if s.engine != nil {
			s.engine.Shutdown()
		}
	})
}

func (s *Server) accept() {
	for {
		conn, err := s.ln.Accept()
		if err != nil {
			return
		}
		if tcp, ok := conn.(*net.TCPConn); ok {
			_ = tcp.SetNoDelay(true)
			_ = tcp.SetKeepAlive(true)
		}
		if !s.track(conn) {
			_ = conn.Close()
		}
	}
}

func (s *Server) track(conn net.Conn) bool {
	s.mu.Lock()
	if s.shut || s.unauth >= MaxPendingHello {
		s.mu.Unlock()
		return false
	}
	s.unauth++
	c := newClientConn(s, conn)
	s.all[c] = struct{}{}
	s.mu.Unlock()
	go c.serve()
	return true
}

func (s *Server) promote(c *clientConn) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.shut || c.slot != slotUnauth {
		return errClosed
	}
	if s.control != nil {
		return errBusy
	}
	if s.unauth > 0 {
		s.unauth--
	}
	c.slot = slotControl
	s.control = c
	return nil
}

func (s *Server) release(c *clientConn) {
	s.mu.Lock()
	control := false
	switch c.slot {
	case slotUnauth:
		if s.unauth > 0 {
			s.unauth--
		}
	case slotControl:
		if s.control == c {
			control = true
		}
	}
	c.slot = slotNone
	delete(s.all, c)
	engine := s.engine
	sess := s.sess
	s.mu.Unlock()
	if control {
		if engine != nil {
			engine.detach(c)
		}
		go func() {
			sess.OnEngineDisconnected()
			s.mu.Lock()
			if s.control == c {
				s.control = nil
			}
			s.mu.Unlock()
		}()
	}
}

func (s *Server) publish(snap session.Snapshot) bool {
	view, err := playerJSON(snap)
	if err != nil {
		log.Printf("rpc: snapshot: %s", redact(err.Error()))
		return false
	}
	s.mu.Lock()
	c := s.control
	sendNotice := snap.Notice != "" && snap.Notice != s.lastNotice
	if sendNotice {
		s.lastNotice = snap.Notice
	}
	level := snap.NoticeLevel
	text := snap.Notice
	s.mu.Unlock()
	if c == nil {
		return true
	}
	if sendNotice && !c.notify(EventNotice, map[string]any{"text": text, "level": level}) {
		return false
	}
	return c.notify(EventPlayerState, view)
}

func (s *Server) forwardSnapshots(ch <-chan struct{}) {
	if ch == nil {
		return
	}
	for {
		select {
		case <-s.done:
			return
		case _, ok := <-ch:
			if !ok {
				return
			}
			s.publish(s.sess.Snapshot())
		}
	}
}

func (c *clientConn) handleHello(frame []byte) {
	msg, err := parseInbound(frame)
	if err != nil || msg.Method != MethodHello || !msg.HasID {
		if err == nil && msg.HasID {
			_ = c.replyFlush(msg.ID, nil, errBody(CodeUnauthorized, "鉴权失败", nil))
		}
		return
	}
	if msg.JSONRPC != Version || msg.ID%2 == 0 {
		_ = c.replyFlush(msg.ID, nil, errBody(CodeInvalidRequest, "请求无效", nil))
		return
	}
	var p struct {
		Token              string   `json:"token"`
		API                int      `json:"api"`
		Repo               int      `json:"repo"`
		ClientVersion      string   `json:"client_version"`
		Platform           string   `json:"platform"`
		EngineCapabilities []string `json:"engine_capabilities"`
	}
	if decodeErr := decodeParams(msg.Params, &p); decodeErr != nil || !tokenEqual(p.Token, c.srv.token) {
		_ = c.replyFlush(msg.ID, nil, errBody(CodeUnauthorized, "鉴权失败", nil))
		return
	}
	if p.API != APIVersion {
		_ = c.replyFlush(msg.ID, nil, errBody(CodeVersion, "需要升级客户端", map[string]any{"api": APIVersion}))
		return
	}
	if promoteErr := c.srv.promote(c); promoteErr != nil {
		_ = c.replyFlush(msg.ID, nil, errBody(CodeUnavailable, "已有一个控制连接", nil))
		return
	}
	if c.srv.engine != nil {
		c.srv.engine.attach(c)
		c.srv.engine.SetCapabilities(p.EngineCapabilities)
	}
	_ = c.conn.SetReadDeadline(time.Time{})
	result, resultErr := c.helloResult(p.EngineCapabilities)
	if resultErr != nil {
		log.Printf("rpc: hello: %s", redact(resultErr.Error()))
		_ = c.replyFlush(msg.ID, nil, errBody(CodeInternal, "内部错误", nil))
		return
	}
	c.authed = true
	c.reply(msg.ID, result, nil)
}

func (c *clientConn) helloResult(caps []string) (any, error) {
	_, hasFeatures := c.srv.sess.(featureSession)
	player, err := playerJSON(c.srv.sess.Snapshot())
	if err != nil {
		return nil, err
	}
	accounts := map[string]accountBrief{
		"bilibili": {LoggedIn: false, Name: ""},
		"netease":  {LoggedIn: false, Name: ""},
	}
	sources, srcErr := c.srv.sess.Sources(c.ctx)
	if srcErr != nil {
		return nil, srcErr
	}
	for _, src := range sources {
		if !accountSource(src) {
			continue
		}
		accounts[src.ID] = accountBrief{LoggedIn: src.LoggedIn, Name: src.UserName, Notice: src.Notice}
	}
	return struct {
		API          int                     `json:"api"`
		Repo         int                     `json:"repo"`
		CoreVersion  string                  `json:"core_version"`
		GUIVersion   string                  `json:"gui_version"`
		DataDir      string                  `json:"data_dir"`
		Capabilities []string                `json:"capabilities"`
		Account      map[string]accountBrief `json:"account"`
		Player       any                     `json:"player"`
	}{
		API:          APIVersion,
		Repo:         RepoVersion,
		CoreVersion:  session.CoreVersion,
		GUIVersion:   GUIVersion,
		DataDir:      c.srv.sess.DataDir(),
		Capabilities: implementedCapabilities(caps, hasFeatures),
		Account:      accounts,
		Player:       player,
	}, nil
}

func accountSource(src session.SourceStatus) bool {
	if src.ID == "bilibili" || src.ID == "netease" {
		return true
	}
	for _, name := range src.Capabilities {
		if name == "account" {
			return true
		}
	}
	return false
}
