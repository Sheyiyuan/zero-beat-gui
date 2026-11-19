package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/sheyiyuan/zero-beat-core/app"
	"github.com/sheyiyuan/zero-beat-core/session"
	"github.com/sheyiyuan/zero-beat-core/source"
	"github.com/sheyiyuan/zero-beat-core/store"
	"github.com/sheyiyuan/zero-beat-gui/wire"
)

type featureSession interface{ Features() *session.Features }
type featureError struct{ error }

func projectList[A, B any](list []A, fn func(A) B) []B {
	out := make([]B, 0, len(list))
	for _, v := range list {
		out = append(out, fn(v))
	}
	return out
}
func (c *clientConn) featureDispatch(ctx context.Context, method string, raw json.RawMessage) (any, error) {
	owner, ok := c.srv.sess.(featureSession)
	if !ok {
		return nil, errMethod
	}
	f := owner.Features()
	var p struct {
		Subdirs  int    `json:"subdirs"`
		FD       int    `json:"fd"`
		URI      string `json:"uri"`
		Name     string `json:"name"`
		LRC      string `json:"lrc"`
		Duration int    `json:"duration"`

		TaskID      int                 `json:"task_id"`
		Force       bool                `json:"force"`
		Sync        session.SyncInput   `json:"sync"`
		TxID        string              `json:"tx_id"`
		Index       int                 `json:"index"`
		Side        string              `json:"side"`
		ID          string              `json:"id"`
		Source      string              `json:"source"`
		Key         string              `json:"key"`
		Cookies     map[string]string   `json:"cookies"`
		Page        int                 `json:"page"`
		Ref         wire.TrackRef       `json:"ref"`
		BrowseRef   wire.BrowseRef      `json:"browse_ref"`
		AuthorsOnly bool                `json:"authors_only"`
		Song        wire.Song           `json:"song"`
		Songs       []wire.Song         `json:"songs"`
		PlaylistID  string              `json:"playlist_id"`
		Title       string              `json:"title"`
		Kind        string              `json:"kind"`
		LocalOnly   bool                `json:"local_only"`
		Refs        []string            `json:"refs"`
		Path        string              `json:"path"`
		Action      string              `json:"action"`
		Target      string              `json:"target"`
		Query       string              `json:"query"`
		Filter      string              `json:"filter"`
		Remote      wire.RemotePlaylist `json:"remote"`
		Write       bool                `json:"write"`
		Refresh     bool                `json:"refresh"`
		Text        string              `json:"text"`
		Candidate   wire.LyricCandidate `json:"candidate"`
		Scope       string              `json:"scope"`
		OffsetMS    int                 `json:"offset_ms"`
		Value       float64             `json:"value"`
		Settings    wire.GUISettings    `json:"settings"`
		Clip        wire.Clip           `json:"clip"`
		PositionMS  int64               `json:"position_ms"`
	}
	if err := decodeParams(raw, &p); err != nil {
		return nil, errParams
	}
	result, err := func() (any, error) {
		switch method {
		case "library.resource.begin":
			v, err := f.ResourceBegin(ctx, p.ID, p.URI, p.Title, p.Subdirs)
			return map[string]any{"token": v}, err
		case "library.resource.lyrics":
			return empty(f.ResourceLyrics(ctx, p.Key, p.Name, p.FD))
		case "library.resource.inspect":
			return empty(f.ResourceInspect(ctx, p.Key, p.URI, p.Name, p.LRC, p.FD, p.Duration))
		case "library.resource.cancel":
			return empty(f.ResourceCancel(ctx, p.Key))
		case "library.resource.skip":
			return empty(f.ResourceSkip(ctx, p.Key, p.Name))
		case "library.resource.commit":
			v, err := f.ResourceCommit(ctx, p.Key)
			return wire.FromLibraryScan(v), err
		case "library.resource.unavailable":
			return empty(f.ResourceUnavailable(ctx, p.ID))
		case "download.list":
			v, err := f.Downloads(ctx)
			return map[string]any{"entries": projectList(v, wire.FromDownloadEntry)}, err
		case "download.tasks":
			v, err := f.DownloadTasks(ctx)
			return map[string]any{"tasks": projectList(v, wire.FromDownloadTask)}, err
		case "download.add":
			songs := make([]store.Song, 0, len(p.Songs))
			for _, v := range p.Songs {
				song, err := songFromWire(v)
				if err != nil {
					return nil, errParams
				}
				songs = append(songs, song)
			}
			v, err := f.DownloadSelection(ctx, session.Selection{PlaylistID: p.PlaylistID, Songs: songs}, p.Force)
			return wire.FromBatch(v), err
		case "download.action":
			return empty(f.DownloadAction(ctx, p.Action, p.TaskID, p.ID))
		case "library.batch.start", "download.batch.start":
			songs := make([]store.Song, 0, len(p.Songs))
			for _, v := range p.Songs {
				song, err := songFromWire(v)
				if err != nil {
					return nil, errParams
				}
				songs = append(songs, song)
			}
			action := p.Action
			if method == "download.batch.start" {
				action = "download"
			}
			v, err := f.StartBatch(ctx, action, p.Target, session.Selection{PlaylistID: p.PlaylistID, Songs: songs}, p.Force)
			return wire.FromWork(v), err
		case "tasks.batch_result":
			v, err := f.BatchWork(ctx, p.ID)
			return map[string]any{"task": wire.FromWork(v.Task), "result": wire.FromBatch(v.Result)}, err
		case "tasks.retry_batch":
			v, err := f.RetryBatch(ctx, p.ID)
			return wire.FromWork(v), err
		case "sync.choices":
			v, err := f.ConflictChoices(ctx, p.TxID)
			return map[string]any{"choices": v}, err
		case "library.folder.start":
			v, err := f.StartFolder(ctx, p.Action, p.ID, p.Path)
			return wire.FromWork(v), err
		case "tasks.folder_result":
			v, err := f.FolderResult(ctx, p.ID)
			return wire.FromLibraryScan(v), err
		case "tasks.list":
			v, err := f.Work(ctx)
			return map[string]any{"tasks": projectList(v, wire.FromWork)}, err
		case "tasks.cancel":
			return empty(f.CancelWork(ctx, p.ID))
		case "sync.archives":
			v, err := f.Archives(ctx)
			return map[string]any{"archives": projectList(v, wire.FromArchive)}, err
		case "sync.archive":
			v, err := f.ArchiveText(ctx, p.Name)
			return map[string]any{"text": v}, err
		case "sync.status":
			v, err := f.SyncStatus(ctx)
			return wire.FromSyncStatus(v), err
		case "sync.action":
			v, err := f.SyncAction(ctx, p.Action, p.Sync)
			return wire.FromWork(v), err
		case "sync.conflicts":
			v, err := f.SyncConflicts(ctx)
			return wire.FromSyncConflicts(v), err
		case "sync.version":
			v, err := f.ConflictVersion(ctx, p.TxID, p.Index, p.Side)
			return map[string]any{"text": v}, err
		case "auth.accounts":
			if p.Refresh {
				if _, err := f.Accounts(ctx, true); err != nil {
					return nil, err
				}
			}
			all, err := f.SourceInfos(ctx)
			return map[string]any{"sources": projectList(all, wire.FromSource)}, err
		case "auth.qr.start":
			v, err := f.StartLogin(ctx, p.Source)
			return wire.FromLoginQR(v), err
		case "auth.qr.poll":
			return c.withLogin(func() (any, error) {
				v, err := f.PollLogin(ctx, p.Source, p.Key)
				return wire.FromLoginPoll(v), err
			})
		case "auth.qr.cancel":
			return empty(f.CancelLogin(ctx, p.Source, p.Key))
		case "auth.web.commit":
			return c.withLogin(func() (any, error) {
				return c.commitWebLogin(ctx, f, p.Source, p.Cookies)
			})
		case "auth.logout":
			return c.withLogin(func() (any, error) {
				return empty(f.Logout(ctx, p.Source))
			})
		case "content.comments", "content.related", "browse.profiles":
			ref, err := p.Ref.Core()
			if err != nil {
				return nil, errParams
			}
			if method == "content.comments" {
				v, err := f.Comments(ctx, ref, p.Page)
				return wire.FromComments(v), err
			}
			if method == "content.related" {
				v, err := f.Related(ctx, ref)
				return wire.FromRelated(v), err
			}
			v, err := f.Profiles(ctx, ref, p.AuthorsOnly)
			return wire.FromProfiles(v), err
		case "browse.roots":
			v, err := f.Roots(ctx)
			return wire.FromProfiles(v), err
		case "browse.page":
			ref, err := p.BrowseRef.Core()
			if err != nil {
				return nil, errParams
			}
			v, err := f.Browse(ctx, ref, p.Page)
			return wire.FromBrowsePage(v), err
		case "browse.parse":
			ref, err := source.ParseBrowseTarget(p.Text)
			return map[string]any{"ref": wire.FromBrowseRef(ref)}, err
		case "library.create":
			v, err := f.CreatePlaylist(ctx, session.PlaylistEdit{Title: p.Title, Kind: p.Kind, LocalOnly: p.LocalOnly, Refs: p.Refs})
			return wire.FromPlaylist(v), err
		case "library.rename", "library.delete", "library.unlock", "library.refresh", "library.refs.set":
			action := map[string]string{"library.rename": "rename", "library.delete": "delete", "library.unlock": "unlock", "library.refresh": "refresh", "library.refs.set": "refs"}[method]
			_, err := f.EditPlaylist(ctx, action, session.PlaylistEdit{ID: p.ID, Title: p.Title, Refs: p.Refs})
			return empty(err)
		case "library.refs":
			v, err := f.MixinRefs(ctx, p.ID)
			return map[string]any{"playlists": projectList(v, wire.FromPlaylist)}, err
		case "library.remote":
			v, err := f.RemotePlaylists(ctx, p.Source, p.Write)
			return map[string]any{"playlists": projectList(v, wire.FromRemotePlaylist)}, err
		case "library.import_remote":
			v, err := f.ImportPlaylist(ctx, source.Playlist{ID: p.Remote.ID, Source: source.ID(p.Remote.Source), RemoteID: p.Remote.RemoteID, Title: p.Remote.Title, Count: p.Remote.Count})
			return wire.FromPlaylist(v), err
		case "library.folder":
			v, err := f.Folder(ctx, p.Action, p.ID, p.Path)
			return wire.FromLibraryScan(v), err
		case "search.local":
			v, err := f.LocalSearch(ctx, p.Query, p.PlaylistID)
			return map[string]any{"songs": projectList(v, wire.FromSong)}, err
		case "library.batch":
			songs := make([]store.Song, 0, len(p.Songs))
			for _, v := range p.Songs {
				song, err := songFromWire(v)
				if err != nil {
					return nil, err
				}
				songs = append(songs, song)
			}
			v, err := f.Batch(ctx, p.Action, p.Target, session.Selection{PlaylistID: p.PlaylistID, Songs: songs})
			return wire.FromBatch(v), err
		case "lyrics.get", "lyrics.candidates", "lyrics.preview", "lyrics.bind":
			song, err := songFromWire(p.Song)
			if err != nil {
				return nil, err
			}
			switch method {
			case "lyrics.get":
				v, err := f.Lyrics(ctx, song)
				return wire.FromLyricsResult(v), err
			case "lyrics.candidates":
				v, err := f.LyricCandidates(ctx, song, p.Query, p.Filter)
				return map[string]any{"candidates": projectList(v, wire.FromLyricCandidate)}, err
			default:
				cand, err := lyricCandidate(p.Candidate)
				if err != nil {
					return nil, errParams
				}
				if method == "lyrics.preview" {
					v, err := f.PreviewLyrics(ctx, song, cand)
					return wire.FromLyricPreview(v), err
				}
				return empty(f.BindLyrics(ctx, song, cand))
			}
		case "lyrics.unbind":
			return empty(f.UnbindLyrics(ctx, p.ID))
		case "lyrics.offset":
			return empty(f.LyricOffset(ctx, p.ID, store.BindingScope(p.Scope), p.OffsetMS))
		case "settings.get":
			v, err := f.Preferences(ctx)
			return wire.FromPreferences(v), err
		case "settings.set":
			return empty(f.PlaybackSetting(ctx, p.Key, p.Value))
		case "settings.gui.get":
			v, err := f.GUISettings(ctx)
			return wire.FromGUISettings(v), err
		case "settings.gui.set":
			return empty(f.SaveGUISettings(ctx, p.Settings.Core()))
		case "player.clip.get":
			v, err := f.Clip(ctx, p.ID)
			return wire.FromClip(v), err
		case "player.clip.begin":
			token, clip, err := f.BeginClip(ctx, p.ID)
			return map[string]any{"token": token, "clip": wire.FromClip(clip)}, err
		case "player.clip.edit":
			clip, err := p.Clip.Core()
			if err != nil && p.Action == "save" {
				return nil, errParams
			}
			return empty(f.EditClip(ctx, p.ID, p.Action, clip, p.PositionMS, p.Key))
		default:
			return nil, errMethod
		}
	}()
	if err != nil && err != errMethod && err != errParams {
		return nil, featureError{err}
	}
	return result, err
}
func lyricCandidate(v wire.LyricCandidate) (app.LyricCandidate, error) {
	cid, err := strconv.ParseInt(string(v.CID), 10, 64)
	if err != nil {
		return app.LyricCandidate{}, err
	}
	lid, err := strconv.ParseInt(string(v.LRCLIBID), 10, 64)
	if err != nil {
		return app.LyricCandidate{}, err
	}
	if cid < 0 || lid < 0 || v.DurationMS < 0 {
		return app.LyricCandidate{}, fmt.Errorf("歌词来源无效")
	}
	return app.LyricCandidate{Kind: string(v.Kind), Source: source.ID(v.Source), ExternalID: v.ExternalID, Page: v.Page, CID: cid, LRCLIBID: lid, Path: v.Path, SongID: v.SongID, Title: v.Title, Artist: v.Artist, Duration: int(v.DurationMS / 1000), HasSynced: v.HasSynced, Known: v.Known, Mark: v.Mark}, nil
}
func (s *Server) forwardFeatures(f *session.Features) {
	events, cancel := f.Subscribe()
	defer cancel()
	for {
		select {
		case <-s.done:
			return
		case kind, ok := <-events:
			if !ok {
				return
			}
			s.mu.Lock()
			c := s.control
			s.mu.Unlock()
			if c != nil {
				c.notify(kind, map[string]any{})
			}
		}
	}
}
