// Package runtime is the in-process core started by ZeroStart.
//
// Desktop leaves an empty data_dir so session.Open can use config.DataDir.
// Android passes the sandbox directory and lock false. A second Start does not
// open another database. Stop is idempotent.
package runtime

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"github.com/sheyiyuan/zero-beat-core/session"
	"github.com/sheyiyuan/zero-beat-gui/rpc"
)

var urlPattern = regexp.MustCompile(`(?i)https?://\S+`)

func redact(s string) string { return urlPattern.ReplaceAllString(s, "[url]") }

type coreSession struct {
	*session.Session
	once       sync.Once
	closeErr   error
	mediaClose func()
}

func (c *coreSession) Close() error {
	c.once.Do(func() {
		if c.mediaClose != nil {
			c.mediaClose()
		}
		if c.Session != nil {
			c.closeErr = c.Session.Close()
		}
	})
	return c.closeErr
}

type running struct {
	srv    *rpc.Server
	sess   *coreSession
	engine *rpc.RemoteEngine
}

var (
	stateMu sync.Mutex
	current *running
)

type startConfig struct {
	DataDir  string `json:"data_dir"`
	Platform string `json:"platform"`
	Lock     *bool  `json:"lock"`
}

// Start opens one session and the local RPC server. The returned JSON is
// the ZeroStart payload. The token exists only in this process.
func Start(configJSON string) string {
	var cfg startConfig
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil || strings.TrimSpace(cfg.Platform) == "" {
		return failJSON("invalid_config", "启动配置无效", 0)
	}
	if cfg.Platform == "android" && strings.TrimSpace(cfg.DataDir) == "" {
		return failJSON("invalid_config", "Android 必须提供数据目录", 0)
	}

	stateMu.Lock()
	defer stateMu.Unlock()
	if current != nil {
		return failJSON("already_running", "另一个 zero-beat 已在运行", os.Getpid())
	}

	var closers []func()
	ok := false
	defer func() {
		if ok {
			return
		}
		for i := len(closers) - 1; i >= 0; i-- {
			closers[i]()
		}
	}()

	token, err := newToken()
	if err != nil {
		log.Printf("runtime: token: %s", redact(err.Error()))
		return failJSON("start_failed", "核心启动失败", 0)
	}
	engine := rpc.NewRemoteEngine()
	closers = append(closers, engine.Shutdown)
	// Empty DataDir on desktop is intentional: session uses config.DataDir.
	// Android always passes the sandbox path and does not consult UserConfigDir here.
	sess, err := session.Open(context.Background(), session.OpenOptions{
		DataDir:  cfg.DataDir,
		Platform: cfg.Platform,
		Lock:     cfg.Lock,
		Engine:   engine,
	})
	if err != nil {
		return failOpen(err)
	}
	wrapped := &coreSession{Session: sess}
	wrapped.SetEngine(engine)
	closers = append(closers, func() { _ = wrapped.Close() })

	var srv *rpc.Server
	if cfg.Platform == "android" {
		srv, err = rpc.ServeUnix(wrapped, engine, token, filepath.Join(sess.DataDir(), "core.sock"))
	} else {
		srv, err = rpc.Serve(wrapped, engine, token)
	}
	if err != nil {
		log.Printf("runtime: listen: %s", redact(err.Error()))
		return failJSON("start_failed", "核心启动失败", 0)
	}
	closers = append(closers, srv.Shutdown)
	if cfg.Platform == "linux" {
		if closeMedia, err := bindSystemMedia(sess); err == nil {
			wrapped.mediaClose = closeMedia
		} else {
			log.Printf("runtime: system media: %s", redact(err.Error()))
		}
	}
	current = &running{srv: srv, sess: wrapped, engine: engine}
	ok = true
	return okJSON(srv.Port(), srv.SocketPath(), token)
}

// Stop closes the transport and the session. A second call does nothing.
func Stop() {
	stateMu.Lock()
	defer stateMu.Unlock()
	if current == nil {
		return
	}
	current.srv.Shutdown()
	_ = current.sess.Close()
	current.engine.Shutdown()
	current = nil
}

func newToken() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

func failOpen(err error) string {
	var running *session.AlreadyRunningError
	if errors.As(err, &running) || errors.Is(err, session.ErrAlreadyRunning) {
		pid := 0
		if running != nil {
			pid = running.PID
		}
		return failJSON("already_running", "另一个 zero-beat 已在运行", pid)
	}
	log.Printf("runtime: open: %s", redact(err.Error()))
	return failJSON("start_failed", "核心启动失败", 0)
}

func okJSON(port int, socketPath, token string) string {
	body, _ := json.Marshal(struct {
		OK         bool   `json:"ok"`
		Port       int    `json:"port"`
		SocketPath string `json:"socket_path,omitempty"`
		Token      string `json:"token"`
		API        int    `json:"api"`
		Repo       int    `json:"repo"`
		Version    string `json:"version"`
	}{true, port, socketPath, token, rpc.APIVersion, rpc.RepoVersion, rpc.GUIVersion})
	return string(body)
}

func failJSON(code, message string, pid int) string {
	body, _ := json.Marshal(struct {
		OK      bool   `json:"ok"`
		Code    string `json:"code"`
		Message string `json:"message"`
		PID     int    `json:"pid,omitempty"`
	}{false, code, message, pid})
	return string(body)
}
