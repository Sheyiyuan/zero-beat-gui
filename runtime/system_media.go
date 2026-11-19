package runtime

import (
	"context"
	"github.com/sheyiyuan/zero-beat-core/player"
	"github.com/sheyiyuan/zero-beat-core/session"
	"github.com/sheyiyuan/zero-beat-core/sysmedia"
	"time"
)

// One adapter per native core; socket reconnection does not duplicate MPRIS.
func bindSystemMedia(sess *session.Session) (func(), error) {
	media, err := sysmedia.New()
	if err != nil {
		return nil, err
	}
	changes, unsubscribe := sess.Subscribe()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	publish := func() {
		v := sess.Snapshot().Player
		loop := sysmedia.LoopPlaylist
		if v.Mode == player.ModeLoopOne {
			loop = sysmedia.LoopTrack
		} else if v.Mode == player.ModeOrdered {
			loop = sysmedia.LoopNone
		}
		snapshot := sysmedia.Snapshot{Duration: v.Duration, Position: v.Position, State: v.PlaybackState, Volume: v.Volume, Muted: v.Muted, Shuffle: v.Mode == player.ModeShuffle, Loop: loop, CanNext: len(v.Queue) > 0 && (v.Mode != player.ModeOrdered || v.Index < len(v.Queue)-1), CanPrev: len(v.Queue) > 0 && (v.Mode != player.ModeOrdered || v.Index > 0)}
		if v.Current != nil {
			snapshot.TrackID = v.Current.ID
			snapshot.Title = v.Current.Title
			snapshot.Artist = v.Current.Artist
			snapshot.Album = v.Current.Album
			snapshot.Artwork = v.Current.Cover
		}
		media.Publish(snapshot)
	}
	publish()
	go func() {
		defer close(done)
		for {
			select {
			case <-ctx.Done():
				return
			case _, ok := <-changes:
				if !ok {
					return
				}
				publish()
			case command, ok := <-media.Commands():
				if !ok {
					return
				}
				call, stop := context.WithTimeout(ctx, 3*time.Second)
				v := sess.Snapshot().Player
				switch command.Kind {
				case sysmedia.CommandToggle:
					_, _ = sess.Toggle(call)
				case sysmedia.CommandPlay:
					_ = sess.Resume(call)
				case sysmedia.CommandPause:
					_ = sess.Pause(call)
				case sysmedia.CommandStop:
					_ = sess.Stop(call)
				case sysmedia.CommandNext:
					_, _ = sess.Next(call)
				case sysmedia.CommandPrevious:
					_, _ = sess.Prev(call)
				case sysmedia.CommandSeekTo:
					if v.Current != nil && v.Current.ID == command.TrackID {
						_ = sess.SeekMS(call, command.Position.Milliseconds())
					}
				case sysmedia.CommandSeekBy:
					_ = sess.SeekMS(call, (v.Position + command.Offset).Milliseconds())
				case sysmedia.CommandSetVolume:
					_ = sess.SetVolume(call, command.Volume)
				case sysmedia.CommandSetShuffle:
					if command.Shuffle {
						_ = sess.SetMode(call, player.ModeShuffle)
					} else if v.Mode == player.ModeShuffle {
						_ = sess.SetMode(call, player.ModeListLoop)
					}
				case sysmedia.CommandSetLoopStatus:
					mode := player.ModeListLoop
					if command.Loop == sysmedia.LoopNone {
						mode = player.ModeOrdered
					} else if command.Loop == sysmedia.LoopTrack {
						mode = player.ModeLoopOne
					}
					_ = sess.SetMode(call, mode)
				case sysmedia.CommandRestart:
					// 只回到 0，不改变 play/pause；与锁屏“从头播放”语义一致。
					_ = sess.SeekMS(call, 0)
				case sysmedia.CommandCycleMode:
					_ = sess.SetMode(call, v.Mode.Next())
				}
				stop()
			}
		}
	}()
	return func() { cancel(); unsubscribe(); media.Close(); <-done }, nil
}
