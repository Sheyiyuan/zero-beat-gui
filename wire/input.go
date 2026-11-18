package wire

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/sheyiyuan/zero-beat-core/player"
	"github.com/sheyiyuan/zero-beat-core/source"
	"github.com/sheyiyuan/zero-beat-core/store"
)

// Core converts an already-decoded reference for dispatch. JSON shape decoding
// alone is not business validation: the session must also check the registry,
// target capability, access rights and cancellation before calling the source.
func (v TrackRef) Core() (source.Ref, error) {
	if strings.TrimSpace(string(v.Source)) == "" || strings.TrimSpace(v.ExternalID) == "" {
		return source.Ref{}, fmt.Errorf("track reference requires source and external_id")
	}
	if v.Page < 1 {
		return source.Ref{}, fmt.Errorf("track reference page must be positive")
	}
	cid, err := strconv.ParseInt(string(v.CID), 10, 64)
	if err != nil || cid < 0 || strconv.FormatInt(cid, 10) != string(v.CID) {
		return source.Ref{}, fmt.Errorf("track reference cid must be a canonical nonnegative int64 string")
	}
	return source.Ref{Source: source.ID(v.Source), ExternalID: v.ExternalID, Page: v.Page, CID: cid}, nil
}
func (v BrowseRef) Core() (source.BrowseRef, error) {
	if strings.TrimSpace(string(v.Source)) == "" {
		return source.BrowseRef{}, fmt.Errorf("browse reference requires source")
	}
	switch source.BrowseKind(v.Kind) {
	case source.BrowseRadios:
		if v.ID != "" {
			return source.BrowseRef{}, fmt.Errorf("radios discovery must not include an id")
		}
	case source.BrowseArtist, source.BrowseUser, source.BrowseUserPrograms, source.BrowseRadio, source.BrowsePlaylist:
		if strings.TrimSpace(v.ID) == "" {
			return source.BrowseRef{}, fmt.Errorf("browse reference requires id")
		}
	default:
		return source.BrowseRef{}, fmt.Errorf("unsupported browse kind")
	}
	return source.BrowseRef{Source: source.ID(v.Source), Kind: source.BrowseKind(v.Kind), ID: v.ID}, nil
}
func (v Quality) Core() (source.Quality, error) {
	for _, q := range qualities {
		if string(v) == q.Name {
			return source.Quality(q.Core), nil
		}
	}
	return 0, fmt.Errorf("unsupported quality")
}
func (v PlaybackMode) Core() (player.Mode, error) {
	for _, m := range playbackModes {
		if string(v) == m.Name {
			return player.Mode(m.Core), nil
		}
	}
	return 0, fmt.Errorf("unsupported playback mode")
}
func (v Clip) Core() (store.Clip, error) {
	if v.StartMS < 0 || v.EndMS < 0 || v.StartMS > maxSafeInteger || v.EndMS > maxSafeInteger || (v.EndMS != 0 && v.EndMS <= v.StartMS) {
		return store.Clip{}, fmt.Errorf("clip requires nonnegative safe milliseconds and end > start, or end=0")
	}
	return store.Clip{StartMS: v.StartMS, EndMS: v.EndMS}, nil
}
