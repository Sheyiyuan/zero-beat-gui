package wire

import (
	"fmt"
	"github.com/sheyiyuan/zero-beat-core/app"
	"github.com/sheyiyuan/zero-beat-core/download"
	"github.com/sheyiyuan/zero-beat-core/lyrics"
	"github.com/sheyiyuan/zero-beat-core/media"
	"github.com/sheyiyuan/zero-beat-core/player"
	"github.com/sheyiyuan/zero-beat-core/session"
	"github.com/sheyiyuan/zero-beat-core/source"
	"github.com/sheyiyuan/zero-beat-core/store"
	coresync "github.com/sheyiyuan/zero-beat-core/sync"
	"reflect"
	"time"
)

type Fixture struct {
	Name  string `json:"name"`
	Type  string `json:"type"`
	Value any    `json:"value"`
}

func fixture(name string, value any) Fixture {
	return Fixture{name, reflect.TypeOf(value).Name(), value}
}
func Fixtures() []Fixture {
	now := time.Date(2026, 11, 17, 8, 9, 10, 123456789, time.FixedZone("UTC+8", 8*60*60))
	track := source.Track{Source: source.NetEase, ExternalID: "program:2066770638", Page: 0, CID: 9223372036854775807, Title: "夜间节目", Artist: "播客主播", Album: "电台", Duration: 245, Cover: "https://example.invalid/cover.jpg"}
	song := store.Song{Source: "bilibili", BVID: "BV1example", CID: 9223372036854775807, Title: "旧版歌曲", Artist: "UP 主", Duration: 123, AddedAt: now}
	candidate := source.Candidate{Track: track, Play: 9223372036854775807, VIP: true}
	ref := source.BrowseRef{Source: source.NetEase, Kind: source.BrowseRadio, ID: "9223372036854775807"}
	entry := source.BrowseEntry{Title: "四只烤翅", Subtitle: "播客电台", Ref: ref}
	playable := source.BrowseEntry{Title: track.Title, Subtitle: track.Artist, Track: &track}
	comment := source.Comment{ID: "9223372036854775807", Author: "听众", AuthorRef: source.BrowseRef{Source: source.NetEase, Kind: source.BrowseUser, ID: "32953014"}, Content: "好听\n第二行", Likes: 9223372036854775807, CreatedAt: now, ReplyCount: 2}
	stream := media.Stream{URL: "https://example.invalid/audio", Headers: map[string]string{"Referer": "https://www.bilibili.com/"}, Codec: "aac", DurationMS: 245123, ExpiresAt: now, Quality: "192k", ClipStartMS: 1234, ClipEndMS: 4321}
	binding := store.LyricBinding{Kind: store.BindingKindLRCLIB, LRCLIBID: 9223372036854775807, Title: "歌词", Duration: 123, OffsetMS: -456, BoundAt: now.Unix()}
	return []Fixture{
		fixture("download-task", DownloadTask{ID: 1, Song: FromSong(song), State: "running", Done: Decimal("1234"), Total: Decimal("5678")}),
		fixture("archive", Archive{Name: "20261118/deleted-playlists/example.json", Title: "归档歌单"}),
		fixture("work", Work{ID: "task-1", Action: "sync.now", State: "running"}),
		fixture("sync-conflict", SyncConflict{Index: 1, Entity: "playlist:1", Title: "歌单", Summary: "本地 2 首，远端 3 首", Both: true}),
		fixture("sync-conflicts", SyncConflictList{TxID: "tx-1", Entities: []SyncConflict{}}),
		fixture("login-qr", FromLoginQR(source.QRCode{Key: "session-key", URL: "https://example.invalid/qr"})),
		fixture("login-poll", FromLoginPoll(source.LoginStatus{Code: 86101, Message: "等待扫码"})),
		fixture("batch-failure", BatchFailure{SongID: "netease:1:1", Error: "权限不足"}),
		fixture("batch-result", FromBatch(session.BatchResult{Succeeded: []string{"netease:2:1"}, Failed: []session.BatchItem{{SongID: "netease:1:1", Error: "权限不足"}}})),
		fixture("gui-settings", FromGUISettings(session.GUISettings{Theme: "system", Palette: "zero-red", CloseAction: "background", Haptics: true})),
		fixture("clip", FromClip(store.Clip{StartMS: 1234, EndMS: 4321})),
		fixture("preferences", FromPreferences(app.Preferences{Volume: 0.8, AutoGain: true, Quality: source.QualityHigh, Mode: 2, LocalFirst: true, Mouse: true})),
		fixture("download", FromDownload(store.Download{SongID: "netease:program:2066770638:1", Path: "/music/episode.m4a", Size: 9223372036854775807, Codec: "aac", DurationMS: 245000, CreatedAt: now})),
		fixture("download-entry-missing-song", FromDownloadEntry(store.DownloadEntry{Download: store.Download{SongID: "deleted-song"}})),
		fixture("download-progress", FromDownloadProgress(download.Progress{Done: 9223372036854775807, Total: 9223372036854775807})),
		fixture("download-result", FromDownloadResult(app.DownloadResult{Song: song, Err: fmt.Errorf("secret URL")})),
		fixture("lyric-binding", FromLyricBinding(binding)),
		fixture("annotation", FromSongAnnotation(store.SongAnnotation{SongID: track.Key(), LyricOffsetMS: -456, CompDB: 1.25, ClipStartMS: 1234, ClipEndMS: 4321, LyricBind: &binding})),
		fixture("lyrics-result", FromLyricsResult(app.LyricsResult{Lines: []lyrics.Line{{StartMS: 1234, Text: "在路上"}}, OffsetMS: -456, OffsetKey: store.BindingPortable, Source: "LRCLIB", Bound: true, Binding: &binding, BindingKind: store.BindingPortable})),
		fixture("lyric-candidate", FromLyricCandidate(app.LyricCandidate{Kind: store.BindingKindLRCLIB, LRCLIBID: 9223372036854775807, Duration: 123, HasSynced: true, Known: true})),
		fixture("lyric-preview", FromLyricPreview(app.LyricPreview{Lines: []lyrics.Line{{Text: "歌词"}}, Label: "LRCLIB", Count: 1, Binding: binding})),
		fixture("merged-search", FromSearchResult(app.SearchResult{Candidates: []source.Candidate{candidate}, Pages: 3, Warn: fmt.Errorf("secret URL")})),
		fixture("library-scan", FromLibraryScan(app.LibraryScan{Playlist: store.Playlist{ID: "folder-1", Kind: store.PlaylistKindFolder, SyncExcluded: true}, Scanned: 4, Added: 2, Reused: 1, Missing: 1, Warnings: []string{"secret URL"}})),
		fixture("all-capabilities-and-future-bit", FromCapabilities(source.CapSearch|source.CapMultiPart|source.CapRemotePlaylists|source.CapOfficialLyrics|source.CapQualitySelect|source.CapLossless|source.CapDailyRecommendations|source.CapPlaylistWrite|source.CapAccount|source.CapComments|source.CapRelated|source.CapBrowse|source.Capability(1<<31))),
		fixture("source-summary", SourceInfo{SourceID(source.NetEase), "网易云", "网", FromCapabilities(source.CapAccount | source.CapBrowse), FromUser(source.User{ID: "32953014", Name: "听众", LoggedIn: true})}),
		fixture("user", FromUser(source.User{ID: "9223372036854775807", Name: "听众", Avatar: "https://example.invalid/avatar", LoggedIn: true})),
		fixture("program-ref", FromRef(track.Ref())), fixture("program-track", FromTrack(track)), fixture("legacy-song", FromSong(song)), fixture("zero-song-time", FromSong(store.Song{Source: "local", RemoteID: "file-1"})),
		fixture("candidate", FromCandidate(candidate)), fixture("search", FromSearchPage(source.SearchPage{Candidates: []source.Candidate{candidate}, Page: 1, Pages: 3})), fixture("related", FromRelated([]source.Candidate{candidate})), fixture("empty-related", FromRelated(nil)),
		fixture("local-only-playlist", FromPlaylist(store.Playlist{ID: "local-1", Title: "私藏", Kind: store.PlaylistKindLocal, Count: 3, SyncExcluded: true, CreatedAt: now.Unix()})),
		fixture("remote-playlist", FromRemotePlaylist(source.Playlist{ID: "netease-42", Source: source.NetEase, RemoteID: "42", Title: "收藏", Count: 7})),
		fixture("queue", FromQueue(store.QueueState{IDs: []string{track.Key()}, Index: 0, Position: 1234})), fixture("empty-queue", FromQueue(store.QueueState{Index: -1})),
		fixture("player", FromPlayer(player.State{Queue: []store.Song{song}, Index: 0, Current: &song, PlaybackState: media.StatePaused, Position: 1234567 * time.Microsecond, Duration: 123 * time.Second, Mode: player.ModeShuffle, Volume: 0.75, CompDB: -2.5, SongCompDB: 1.25, AutoGain: true, Muted: true, Awaiting: true, Request: 17, SleepUntil: now, Quality: source.QualityLossless})),
		fixture("idle-player", FromPlayer(player.State{Index: -1})),
		fixture("future-player", FromPlayer(player.State{PlaybackState: media.State(99), Mode: player.Mode(99), Quality: source.Quality(99)})),
		fixture("stream-info", FromStream(stream)), fixture("engine-stream", FromEngineStream(stream)), fixture("source-stream-duration", FromSourceStream(source.Stream{Duration: 245123456 * time.Microsecond})),
		fixture("lyric", FromLyricLine(lyrics.Line{StartMS: 1234, Text: "在路上", Translation: "On the road"})),
		fixture("radio-ref", *FromBrowseRef(ref)), fixture("radio-entry", FromBrowseEntry(entry)), fixture("program-entry", FromBrowseEntry(playable)),
		fixture("radio-page", FromBrowsePage(source.BrowsePage{Title: "四只烤翅", Description: "电台详情", Entries: []source.BrowseEntry{playable}, Page: 1, HasMore: true})),
		fixture("profiles", FromProfiles([]source.BrowseEntry{{Title: "主播", Ref: source.BrowseRef{Source: source.NetEase, Kind: source.BrowseUser, ID: "32953014"}}})),
		fixture("comment", FromComment(comment)), fixture("comments", FromComments(source.CommentPage{Comments: []source.Comment{comment}, Page: 1, Notice: "未登录预览"})), fixture("anonymous-comment", FromComment(source.Comment{ID: "0", Content: "未知作者"})),
		fixture("sync-config", FromSyncConfig(coresync.Config{Remote: "https://username:secret@example.invalid/owner/repo.git?access_token=secret#secret", Branch: "main", Auto: true})),
		fixture("sync-status", FromSyncStatus(coresync.Status{RequestedBackend: coresync.BackendAuto, ActualBackend: coresync.BackendGoGit, Configured: true, Remote: "https://username:secret@example.invalid/owner/repo.git", Branch: "main", Auto: true, LastSyncAt: now, LastError: "Bearer secret", Warnings: []string{"token=secret"}, Conflicts: 2, ConflictTx: "tx-42"})),
	}
}

// CoreTypes are fingerprinted in schema.json. New/removed/changed core fields
// invalidate generator -check, forcing a deliberate projection decision.
var CoreTypes = []reflect.Type{
	reflect.TypeFor[store.Clip](), reflect.TypeFor[app.Preferences](), reflect.TypeFor[store.Download](), reflect.TypeFor[store.DownloadEntry](), reflect.TypeFor[download.Progress](), reflect.TypeFor[app.DownloadResult](), reflect.TypeFor[store.LyricBinding](), reflect.TypeFor[store.SongAnnotation](), reflect.TypeFor[app.LyricsResult](), reflect.TypeFor[app.LyricCandidate](), reflect.TypeFor[app.LyricPreview](), reflect.TypeFor[app.SearchResult](), reflect.TypeFor[app.LibraryScan](),
	reflect.TypeFor[source.Ref](), reflect.TypeFor[source.Track](), reflect.TypeFor[source.Candidate](), reflect.TypeFor[source.Comment](), reflect.TypeFor[source.CommentPage](), reflect.TypeFor[source.SearchPage](), reflect.TypeFor[source.Playlist](), reflect.TypeFor[source.User](), reflect.TypeFor[source.Stream](), reflect.TypeFor[source.BrowseRef](), reflect.TypeFor[source.BrowseEntry](), reflect.TypeFor[source.BrowsePage](), reflect.TypeFor[store.Song](), reflect.TypeFor[store.Playlist](), reflect.TypeFor[store.QueueState](), reflect.TypeFor[player.State](), reflect.TypeFor[media.Stream](), reflect.TypeFor[lyrics.Line](), reflect.TypeFor[coresync.Config](), reflect.TypeFor[coresync.Status](),
}
