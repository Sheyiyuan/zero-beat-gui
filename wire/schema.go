package wire

import (
	"github.com/sheyiyuan/zero-beat-core/source"
	"github.com/sheyiyuan/zero-beat-core/store"
	coresync "github.com/sheyiyuan/zero-beat-core/sync"
	"reflect"
)

// Types is the allowlist. New core fields never become wire-visible implicitly.
// Adding an exported DTO here generates the Dart model and schema manifest.
var Types = []reflect.Type{
	reflect.TypeFor[Archive](), reflect.TypeFor[LoginQR](), reflect.TypeFor[LoginPoll](), reflect.TypeFor[BatchFailure](), reflect.TypeFor[BatchResult](), reflect.TypeFor[GUISettings](), reflect.TypeFor[DownloadTask](), reflect.TypeFor[Work](), reflect.TypeFor[SyncConflict](), reflect.TypeFor[SyncConflictList](),
	reflect.TypeFor[Clip](), reflect.TypeFor[Preferences](), reflect.TypeFor[Download](), reflect.TypeFor[DownloadEntry](), reflect.TypeFor[DownloadProgress](), reflect.TypeFor[DownloadResult](), reflect.TypeFor[LyricBinding](), reflect.TypeFor[SongAnnotation](), reflect.TypeFor[LyricsResult](), reflect.TypeFor[LyricCandidate](), reflect.TypeFor[LyricPreview](), reflect.TypeFor[SearchResult](), reflect.TypeFor[LibraryScan](),
	reflect.TypeFor[SourceCapabilities](), reflect.TypeFor[SourceInfo](), reflect.TypeFor[User](),
	reflect.TypeFor[TrackRef](), reflect.TypeFor[Track](), reflect.TypeFor[Song](), reflect.TypeFor[Candidate](), reflect.TypeFor[SearchPage](), reflect.TypeFor[RelatedPage](),
	reflect.TypeFor[Playlist](), reflect.TypeFor[RemotePlaylist](), reflect.TypeFor[QueueSnapshot](), reflect.TypeFor[PlaybackSnapshot](), reflect.TypeFor[StreamInfo](), reflect.TypeFor[EngineStream](), reflect.TypeFor[LyricLine](),
	reflect.TypeFor[BrowseRef](), reflect.TypeFor[BrowseEntry](), reflect.TypeFor[BrowsePage](), reflect.TypeFor[ProfileList](), reflect.TypeFor[Comment](), reflect.TypeFor[CommentPage](), reflect.TypeFor[SyncConfig](), reflect.TypeFor[SyncStatus](),
}

type Enum struct {
	Name   string
	Values []string
}

func intNames(in []IntValue) []string {
	out := make([]string, len(in))
	for i, v := range in {
		out[i] = v.Name
	}
	return out
}

var Enums = []Enum{
	{"BindingKind", []string{store.BindingKindSource, store.BindingKindLRCLIB, store.BindingKindLocalFile, store.BindingKindLocalSong}},
	{"BindingScope", []string{string(store.BindingAuto), string(store.BindingPortable), string(store.BindingLocal)}},
	{"SourceID", []string{string(source.Bilibili), string(source.NetEase), string(source.Local)}},
	{"BrowseKind", []string{string(source.BrowseArtist), string(source.BrowseUser), string(source.BrowseUserPrograms), string(source.BrowseRadio), string(source.BrowseRadios), string(source.BrowsePlaylist)}},
	{"PlaylistKind", []string{store.PlaylistKindRemote, store.PlaylistKindLocal, store.PlaylistKindMixin, store.PlaylistKindFolder}},
	{"PlaybackStatus", intNames(playbackStates)}, {"PlaybackMode", intNames(playbackModes)}, {"Quality", intNames(qualities)},
	{"SyncBackend", []string{string(coresync.BackendAuto), string(coresync.BackendCLI), string(coresync.BackendGoGit)}},
}
