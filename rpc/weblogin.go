package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/sheyiyuan/zero-beat-core/session"
	"github.com/sheyiyuan/zero-beat-core/source"
	"github.com/sheyiyuan/zero-beat-core/store"
)

const (
	webCookieMaxCount = 24
	webCookieMaxRunes = 2048
)

// webLoginProfile is the official browser login the GUI may finish on the
// same device. QR login stays available for a second device. Passwords are
// never accepted here: only session cookies the official page has already set.
type webLoginProfile struct {
	required string
	allowed  map[string]struct{}
}

func webLoginProfiles() map[string]webLoginProfile {
	return map[string]webLoginProfile{
		string(source.NetEase): {
			required: "MUSIC_U",
			allowed: cookieSet(
				"MUSIC_U", "MUSIC_A", "__csrf", "NMTID", "__remember_me",
				"os", "appver", "sDeviceId", "WNMCID", "WEVNSM",
			),
		},
		string(source.Bilibili): {
			required: "SESSDATA",
			allowed: cookieSet(
				"SESSDATA", "bili_jct", "DedeUserID", "DedeUserID__ckMd5",
				"sid", "buvid3", "buvid4", "b_nut",
			),
		},
	}
}

func cookieSet(names ...string) map[string]struct{} {
	out := make(map[string]struct{}, len(names))
	for _, name := range names {
		out[name] = struct{}{}
	}
	return out
}

// sanitizeWebCookies keeps only the session cookies the core already stores
// after a QR login. Unknown names, blank values and control characters are
// rejected without echoing the value.
func sanitizeWebCookies(id string, raw map[string]string) (map[string]string, error) {
	profile, ok := webLoginProfiles()[id]
	if !ok {
		return nil, fmt.Errorf("这个来源不能在本机页面登录")
	}
	if len(raw) == 0 {
		return nil, fmt.Errorf("官方页面还没有完成登录")
	}
	if len(raw) > webCookieMaxCount {
		return nil, fmt.Errorf("登录信息过长")
	}
	out := make(map[string]string, len(raw))
	for name, value := range raw {
		name = strings.TrimSpace(name)
		value = strings.TrimSpace(value)
		if name == "" || value == "" {
			continue
		}
		if _, allow := profile.allowed[name]; !allow {
			return nil, fmt.Errorf("登录信息包含不需要的字段")
		}
		if strings.ContainsAny(name, "\r\n;=,") || strings.ContainsAny(value, "\r\n;") {
			return nil, fmt.Errorf("登录信息格式无效")
		}
		if utf8.RuneCountInString(value) > webCookieMaxRunes {
			return nil, fmt.Errorf("登录信息过长")
		}
		out[name] = value
	}
	if out[profile.required] == "" {
		return nil, fmt.Errorf("官方页面还没有完成登录")
	}
	return out, nil
}

type webAccount interface {
	ID() source.ID
	Caps() source.Capability
	Session() map[string]string
	SetSession(map[string]string)
	Account(context.Context) (source.User, error)
}

func (c *clientConn) withLogin(fn func() (any, error)) (any, error) {
	c.srv.loginMu.Lock()
	defer c.srv.loginMu.Unlock()
	return fn()
}

func (c *clientConn) commitWebLogin(ctx context.Context, f *session.Features, id string, raw map[string]string) (map[string]any, error) {
	defer wipeCookies(raw)
	sources, err := f.SourceInfos(ctx)
	if err != nil {
		return nil, err
	}
	var src source.Source
	for _, item := range sources {
		if string(item.ID()) == id {
			src = item
			break
		}
	}
	if src == nil || !src.Caps().Has(source.CapAccount) {
		return nil, fmt.Errorf("这个来源不能在本机页面登录")
	}
	user, err := commitWebAccount(ctx, src, c.srv.sess.DataDir(), raw)
	if err != nil {
		return nil, err
	}
	c.notify("auth.changed", map[string]any{})
	c.notify("library.changed", map[string]any{})
	return map[string]any{"logged_in": user.LoggedIn, "name": user.Name}, nil
}

func commitWebAccount(ctx context.Context, src webAccount, dataDir string, raw map[string]string) (source.User, error) {
	cleaned, err := sanitizeWebCookies(string(src.ID()), raw)
	if err != nil {
		return source.User{}, err
	}
	defer wipeCookies(cleaned)
	if !src.Caps().Has(source.CapAccount) {
		return source.User{}, fmt.Errorf("这个来源不能在本机页面登录")
	}
	previous := src.Session()
	src.SetSession(cleaned)
	user, err := src.Account(ctx)
	if err != nil || !user.LoggedIn {
		src.SetSession(previous)
		return source.User{}, fmt.Errorf("官方页面的登录没有通过账号校验")
	}
	persisted := src.Session()
	if err := saveWebAccount(dataDir, string(src.ID()), persisted); err != nil {
		src.SetSession(previous)
		wipeCookies(persisted)
		return source.User{}, err
	}
	wipeCookies(persisted)
	return user, nil
}

func saveWebAccount(dataDir, id string, session map[string]string) error {
	if strings.TrimSpace(dataDir) == "" {
		return fmt.Errorf("没有可用的数据目录")
	}
	payload, err := json.Marshal(session)
	if err != nil {
		return fmt.Errorf("无法保存登录")
	}
	st, err := store.Open(filepath.Join(dataDir, "zero-beat.db"))
	if err != nil {
		return fmt.Errorf("无法保存登录")
	}
	defer st.Close()
	if err := st.SaveAccount(id, payload); err != nil {
		return fmt.Errorf("无法保存登录")
	}
	return nil
}

func wipeCookies(cookies map[string]string) {
	for key := range cookies {
		cookies[key] = ""
		delete(cookies, key)
	}
}
