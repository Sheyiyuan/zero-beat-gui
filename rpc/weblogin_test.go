package rpc

import (
	"context"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sheyiyuan/zero-beat-core/source"
	"github.com/sheyiyuan/zero-beat-core/store"
)

func TestSanitizeWebCookiesKeepsOfficialSessionOnly(t *testing.T) {
	secret := "music-u-secret"
	got, err := sanitizeWebCookies(string(source.NetEase), map[string]string{
		" MUSIC_U ": secret,
		"__csrf":    "csrf-token",
	})
	if err != nil {
		t.Fatal(err)
	}
	if got["MUSIC_U"] != secret || got["__csrf"] != "csrf-token" {
		t.Fatalf("cookies = %#v", got)
	}
	if _, err := sanitizeWebCookies(string(source.NetEase), map[string]string{"MUSIC_U": secret, "password": "nope"}); err == nil || strings.Contains(err.Error(), secret) || strings.Contains(err.Error(), "nope") {
		t.Fatalf("unexpected error %v", err)
	}
	if _, err := sanitizeWebCookies(string(source.Bilibili), map[string]string{"MUSIC_U": secret}); err == nil {
		t.Fatal("bilibili accepted a netease cookie")
	}
	if _, err := sanitizeWebCookies("local", map[string]string{"SESSDATA": "x"}); err == nil {
		t.Fatal("local source accepted web login")
	}
	if _, err := sanitizeWebCookies(string(source.Bilibili), map[string]string{"SESSDATA": "a\nb"}); err == nil {
		t.Fatal("accepted a broken cookie")
	}
}

func TestCommitWebAccountValidatesThenPersists(t *testing.T) {
	dir := t.TempDir()
	src := &fakeWebAccount{id: source.NetEase, caps: source.CapAccount, name: "园"}
	secret := "music-u-secret"
	user, err := commitWebAccount(context.Background(), src, dir, map[string]string{"MUSIC_U": secret})
	if err != nil {
		t.Fatal(err)
	}
	if !user.LoggedIn || user.Name != "园" {
		t.Fatalf("user = %#v", user)
	}
	st, err := store.Open(filepath.Join(dir, "zero-beat.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	payload, err := st.LoadAccount(string(source.NetEase))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(payload), secret) {
		t.Fatalf("payload = %s", payload)
	}
	if len(src.session) == 0 || src.session["MUSIC_U"] != secret {
		t.Fatalf("memory session = %#v", src.session)
	}
}

func TestCommitWebAccountRollsBackWhenPlatformRejects(t *testing.T) {
	dir := t.TempDir()
	src := &fakeWebAccount{
		id:         source.Bilibili,
		caps:       source.CapAccount,
		session:    map[string]string{"SESSDATA": "old"},
		accountErr: errRejected,
	}
	_, err := commitWebAccount(context.Background(), src, dir, map[string]string{"SESSDATA": "new-secret"})
	if err == nil || strings.Contains(err.Error(), "new-secret") {
		t.Fatal(err)
	}
	if src.session["SESSDATA"] != "old" {
		t.Fatalf("session = %#v", src.session)
	}
	st, err := store.Open(filepath.Join(dir, "zero-beat.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	if _, err := st.LoadAccount(string(source.Bilibili)); err == nil {
		t.Fatal("rejected login was stored")
	}
}

var errRejected = errString("rejected")

type errString string

func (e errString) Error() string { return string(e) }

type fakeWebAccount struct {
	id         source.ID
	caps       source.Capability
	session    map[string]string
	name       string
	accountErr error
}

func (f *fakeWebAccount) ID() source.ID           { return f.id }
func (f *fakeWebAccount) Caps() source.Capability { return f.caps }
func (f *fakeWebAccount) Session() map[string]string {
	out := make(map[string]string, len(f.session))
	for k, v := range f.session {
		out[k] = v
	}
	return out
}
func (f *fakeWebAccount) SetSession(cookies map[string]string) {
	f.session = map[string]string{}
	for k, v := range cookies {
		f.session[k] = v
	}
}
func (f *fakeWebAccount) Account(context.Context) (source.User, error) {
	if f.accountErr != nil {
		return source.User{}, f.accountErr
	}
	return source.User{Name: f.name, LoggedIn: true}, nil
}
