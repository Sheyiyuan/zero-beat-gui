package rpc

import (
	"context"

	"github.com/sheyiyuan/zero-beat-core/player"
	"github.com/sheyiyuan/zero-beat-core/session"
	"github.com/sheyiyuan/zero-beat-core/store"
)

// Session 是 GUI 调用的会话门面。方法名与 zero-beat-core/session 对齐：
// 可取消的业务调用都带 context，快照和断线通知不进会话队列的等待。
type Session interface {
	DataDir() string
	Close() error
	SetEngine(session.Engine)

	Playlists(context.Context) ([]store.Playlist, string, error)
	Songs(context.Context, string, int, int) (session.SongPage, error)
	Search(context.Context, string, int, string) (session.SearchHit, error)
	OpenLink(context.Context, string) (session.LinkResult, error)

	Play(context.Context, session.PlayInput) (session.Accepted, error)
	Toggle(context.Context) (session.Accepted, error)
	Pause(context.Context) error
	Stop(context.Context) error
	Resume(context.Context) error
	Next(context.Context) (session.Accepted, error)
	Prev(context.Context) (session.Accepted, error)
	SeekMS(context.Context, int64) error
	SetVolume(context.Context, float64) error
	SetMode(context.Context, player.Mode) error
	Enqueue(context.Context, store.Song) (int, error)
	InsertNext(context.Context, store.Song) (int, error)
	RemoveAt(context.Context, int) error
	MoveAt(context.Context, int, int) error
	ClearUpcoming(context.Context) error

	Snapshot() session.Snapshot
	Subscribe() (<-chan struct{}, func())
	Sources(context.Context) ([]session.SourceStatus, error)
	OnEngineDisconnected()
}
