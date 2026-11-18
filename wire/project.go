package wire

import (
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/sheyiyuan/zero-beat-core/app"
	"github.com/sheyiyuan/zero-beat-core/download"
	"github.com/sheyiyuan/zero-beat-core/lyrics"
	"github.com/sheyiyuan/zero-beat-core/media"
	"github.com/sheyiyuan/zero-beat-core/player"
	"github.com/sheyiyuan/zero-beat-core/source"
	"github.com/sheyiyuan/zero-beat-core/store"
	coresync "github.com/sheyiyuan/zero-beat-core/sync"
)

func decimal(v int64) Decimal { return Decimal(strconv.FormatInt(v, 10)) }
func timestamp(v time.Time) *Timestamp {
	if v.IsZero() {
		return nil
	}
	t := Timestamp(v.UTC().Truncate(time.Millisecond).Format("2006-01-02T15:04:05.000Z"))
	return &t
}
func unixTimestamp(v int64) *Timestamp {
	if v == 0 {
		return nil
	}
	return timestamp(time.Unix(v, 0))
}
func page(v int) int {
	if v <= 0 {
		return 1
	}
	return v
}
func items[A, B any](in []A, project func(A) B) []B {
	out := make([]B, len(in))
	for i, v := range in {
		out[i] = project(v)
	}
	return out
}

func FromRef(v source.Ref) TrackRef {
	return TrackRef{SourceID(v.Source), v.ExternalID, page(v.Page), decimal(v.CID)}
}
func FromTrack(v source.Track) Track {
	return Track{v.Key(), SourceID(v.Source), v.ExternalID, page(v.Page), decimal(v.CID), v.Title, v.Artist, v.Album, int64(v.Duration) * 1000, v.Cover}
}
func FromSong(v store.Song) Song {
	v = store.NormalizeSong(v)
	return Song{v.ID, SourceID(v.Source), v.ExternalID(), v.Page, decimal(v.CID), v.Title, v.Artist, v.Album, int64(v.Duration) * 1000, v.Cover, timestamp(v.AddedAt)}
}
func FromCandidate(v source.Candidate) Candidate {
	return Candidate{FromTrack(v.Track), decimal(v.Play), v.VIP}
}
func FromSearchPage(v source.SearchPage) SearchPage {
	return SearchPage{items(v.Candidates, FromCandidate), v.Page, v.Pages}
}
func FromRelated(v []source.Candidate) RelatedPage { return RelatedPage{items(v, FromCandidate)} }
func FromPlaylist(v store.Playlist) Playlist {
	return Playlist{v.ID, SourceID(v.Source), v.Title, PlaylistKind(v.Kind), v.RemoteID, v.Count, v.Frozen, v.SyncExcluded, v.RootPath, v.ScanStatus, v.ScanError != "", unixTimestamp(v.ScannedAt), unixTimestamp(v.CreatedAt)}
}
func FromRemotePlaylist(v source.Playlist) RemotePlaylist {
	return RemotePlaylist{v.ID, SourceID(v.Source), v.RemoteID, v.Title, v.Count}
}
func FromQueue(v store.QueueState) QueueSnapshot {
	return QueueSnapshot{append([]string{}, v.IDs...), v.Index, v.Position}
}
func FromPlayer(v player.State) PlaybackSnapshot {
	var current *Song
	if v.Current != nil {
		s := FromSong(*v.Current)
		current = &s
	}
	return PlaybackSnapshot{items(v.Queue, FromSong), v.Index, current, PlaybackStatus(enumInt(playbackStates, int(v.PlaybackState))), v.Position.Milliseconds(), v.Duration.Milliseconds(), PlaybackMode(enumInt(playbackModes, int(v.Mode))), v.Volume, v.CompDB, v.SongCompDB, v.AutoGain, v.Muted, v.Awaiting, v.Request, timestamp(v.SleepUntil), Quality(enumInt(qualities, int(v.Quality)))}
}
func FromStream(v media.Stream) StreamInfo {
	return StreamInfo{v.Codec, v.DurationMS, timestamp(v.ExpiresAt), v.Quality, v.ClipStartMS, v.ClipEndMS}
}
func FromEngineStream(v media.Stream) EngineStream {
	headers := make(map[string]string, len(v.Headers))
	for k, val := range v.Headers {
		headers[k] = val
	}
	return EngineStream{v.URL, headers, v.Codec, v.DurationMS, timestamp(v.ExpiresAt), v.Quality, v.ClipStartMS, v.ClipEndMS}
}
func FromSourceStream(v source.Stream) StreamInfo {
	return StreamInfo{v.Codec, v.Duration.Milliseconds(), timestamp(v.ExpiresAt), v.Quality, 0, 0}
}
func FromLyricLine(v lyrics.Line) LyricLine {
	return LyricLine{int64(v.StartMS), v.Text, v.Translation}
}
func FromBrowseRef(v source.BrowseRef) *BrowseRef {
	if v.Source == "" && v.Kind == "" && v.ID == "" {
		return nil
	}
	return &BrowseRef{SourceID(v.Source), BrowseKind(v.Kind), v.ID}
}
func FromBrowseEntry(v source.BrowseEntry) BrowseEntry {
	var track *Track
	if v.Track != nil {
		t := FromTrack(*v.Track)
		track = &t
	}
	return BrowseEntry{v.Title, v.Subtitle, FromBrowseRef(v.Ref), track}
}
func FromBrowsePage(v source.BrowsePage) BrowsePage {
	return BrowsePage{v.Title, v.Description, v.Cover, v.Notice, items(v.Entries, FromBrowseEntry), v.Page, v.HasMore}
}
func FromProfiles(v []source.BrowseEntry) ProfileList { return ProfileList{items(v, FromBrowseEntry)} }
func FromComment(v source.Comment) Comment {
	return Comment{v.ID, v.Author, FromBrowseRef(v.AuthorRef), v.Avatar, v.Content, decimal(v.Likes), timestamp(v.CreatedAt), v.ReplyCount}
}
func FromComments(v source.CommentPage) CommentPage {
	return CommentPage{items(v.Comments, FromComment), v.Page, v.HasMore, v.Notice}
}
func FromUser(v source.User) User { return User{v.ID, v.Name, v.Avatar, v.LoggedIn} }
func FromSource(v source.Source) SourceInfo {
	return SourceInfo{SourceID(v.ID()), v.Name(), v.Mark(), FromCapabilities(v.Caps()), FromUser(v.User())}
}
func FromCapabilities(v source.Capability) SourceCapabilities {
	names := []string{}
	var known source.Capability
	for _, c := range Capabilities {
		known |= c.Bit
		if v.Has(c.Bit) {
			names = append(names, c.Name)
		}
	}
	return SourceCapabilities{names, decimal(int64(v &^ known))}
}

// PublicRemote strips credentials and query/fragment; an invalid URL-like value
// is omitted rather than risking accidental secret disclosure. SCP-style remotes
// use only user@host:path, with no password component.
func PublicRemote(v string) string {
	v = strings.TrimSpace(v)
	if strings.Contains(v, "://") {
		u, err := url.Parse(v)
		if err != nil || u.Hostname() == "" {
			return ""
		}
		u.User = nil
		u.RawQuery = ""
		u.ForceQuery = false
		u.Fragment = ""
		return u.String()
	}
	if strings.ContainsAny(v, "?#\r\n") {
		return ""
	}
	if at := strings.IndexByte(v, '@'); at >= 0 && strings.Contains(v[:at], ":") {
		return ""
	}
	return v
}
func backend(v coresync.Backend) SyncBackend {
	if v == "" {
		return SyncBackend(coresync.BackendAuto)
	}
	return SyncBackend(v)
}
func FromSyncConfig(v coresync.Config) SyncConfig {
	return SyncConfig{backend(v.Backend), PublicRemote(v.Remote), v.Branch, v.Auto, v.SyncAccounts}
}
func FromSyncStatus(v coresync.Status) SyncStatus {
	return SyncStatus{backend(v.RequestedBackend), backend(v.ActualBackend), v.Configured, PublicRemote(v.Remote), v.Branch, v.Auto, v.SyncAccounts, v.KeyCached, v.KeyMatchesRepo, v.KeyVersion, timestamp(v.LastSyncAt), v.LastError != "", v.KeyIssue != "", v.ConflictTx, v.Conflicts, len(v.Warnings)}
}

func enumInt(values []IntValue, v int) string {
	for _, p := range values {
		if p.Core == v {
			return p.Name
		}
	}
	return "unknown:" + strconv.Itoa(v)
}

type IntValue struct {
	Core int
	Name string
}

var playbackStates = []IntValue{{int(media.StateIdle), "idle"}, {int(media.StateBuffering), "buffering"}, {int(media.StatePlaying), "playing"}, {int(media.StatePaused), "paused"}, {int(media.StateEnded), "ended"}, {int(media.StateFailed), "failed"}}
var playbackModes = []IntValue{{int(player.ModeListLoop), "list_loop"}, {int(player.ModeLoopOne), "loop_one"}, {int(player.ModeShuffle), "shuffle"}, {int(player.ModeOrdered), "ordered"}}
var qualities = []IntValue{{int(source.QualityAuto), "auto"}, {int(source.QualityHigh), "high"}, {int(source.QualityLossless), "lossless"}}

type CapabilityValue struct {
	Bit  source.Capability
	Name string
}

var Capabilities = []CapabilityValue{
	{source.CapSearch, "search"}, {source.CapMultiPart, "multi_part"}, {source.CapRemotePlaylists, "remote_playlists"}, {source.CapOfficialLyrics, "official_lyrics"}, {source.CapQualitySelect, "quality_select"}, {source.CapLossless, "lossless"}, {source.CapDailyRecommendations, "daily_recommendations"}, {source.CapPlaylistWrite, "playlist_write"}, {source.CapAccount, "account"}, {source.CapComments, "comments"}, {source.CapRelated, "related"}, {source.CapBrowse, "browse"},
}

func FromClip(v store.Clip) Clip { return Clip{v.StartMS, v.EndMS} }
func FromPreferences(v app.Preferences) Preferences {
	return Preferences{v.Volume, v.CompDB, v.AutoGain, Quality(enumInt(qualities, int(v.Quality))), PlaybackMode(enumInt(playbackModes, v.Mode)), v.PlayingPlaylist, v.LocalFirst, v.Mouse}
}
func FromDownload(v store.Download) Download {
	return Download{v.SongID, v.Path, decimal(v.Size), v.Codec, v.DurationMS, timestamp(v.CreatedAt)}
}
func FromDownloadEntry(v store.DownloadEntry) DownloadEntry {
	var s *Song
	if v.Song.ID != "" || v.Song.ExternalID() != "" {
		projected := FromSong(v.Song)
		s = &projected
	}
	return DownloadEntry{FromDownload(v.Download), s}
}
func FromDownloadProgress(v download.Progress) DownloadProgress {
	return DownloadProgress{decimal(v.Done), decimal(v.Total)}
}
func FromDownloadResult(v app.DownloadResult) DownloadResult {
	return DownloadResult{FromSong(v.Song), v.Path, decimal(v.Size), v.Err != nil}
}
func FromLyricBinding(v store.LyricBinding) LyricBinding {
	return LyricBinding{BindingKind(v.Kind), SourceID(v.Source), v.ExternalID, v.Page, decimal(v.CID), decimal(v.LRCLIBID), v.Path, v.SongID, v.Title, v.Artist, int64(v.Duration) * 1000, int64(v.OffsetMS), unixTimestamp(v.BoundAt)}
}
func lyricBinding(v *store.LyricBinding) *LyricBinding {
	if v == nil {
		return nil
	}
	b := FromLyricBinding(*v)
	return &b
}
func FromSongAnnotation(v store.SongAnnotation) SongAnnotation {
	return SongAnnotation{v.SongID, int64(v.LyricOffsetMS), v.CompDB, v.ClipStartMS, v.ClipEndMS, lyricBinding(v.LyricBind)}
}
func FromLyricsResult(v app.LyricsResult) LyricsResult {
	return LyricsResult{items(v.Lines, FromLyricLine), int64(v.OffsetMS), BindingScope(v.OffsetKey), v.Source, v.Bound, v.Degraded, v.Warning != "", lyricBinding(v.Binding), BindingScope(v.BindingKind)}
}
func FromLyricCandidate(v app.LyricCandidate) LyricCandidate {
	return LyricCandidate{BindingKind(v.Kind), SourceID(v.Source), v.ExternalID, v.Page, decimal(v.CID), decimal(v.LRCLIBID), v.Path, v.SongID, v.Title, v.Artist, int64(v.Duration) * 1000, v.HasSynced, v.Known, v.Mark}
}
func FromLyricPreview(v app.LyricPreview) LyricPreview {
	return LyricPreview{items(v.Lines, FromLyricLine), v.Label, v.Count, FromLyricBinding(v.Binding)}
}
func FromSearchResult(v app.SearchResult) SearchResult {
	return SearchResult{items(v.Candidates, FromCandidate), v.Pages, v.Warn != nil}
}
func FromLibraryScan(v app.LibraryScan) LibraryScan {
	return LibraryScan{FromPlaylist(v.Playlist), v.Subdirs, v.Scanned, v.Added, v.Reused, v.Missing, len(v.Warnings)}
}
