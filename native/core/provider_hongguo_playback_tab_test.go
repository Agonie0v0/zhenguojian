package core

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"

	"duanjuapp/native/core/sign6"
)

func TestHongguoTabPlaybackRequestAndExactEpisode(t *testing.T) {
	const videoID = "7705456646213864472"
	request, err := newHongguoTabPlaybackRequest(context.Background(), "api5-normal-sinfonlineb.fqnovel.com", "1234567890123456789", "2234567890123456789", videoID, time.Unix(1794371234, 123000000))
	if err != nil {
		t.Fatal(err)
	}
	if request.Method != http.MethodGet || request.Body != nil || request.URL.Path != "/reading/bookapi/video_tab/multi_video_model/v1/" {
		t.Fatalf("unexpected request: %s %s body=%v", request.Method, request.URL.Path, request.Body)
	}
	query := request.URL.Query()
	for key, want := range map[string]string{
		"video_id": videoID, "video_id_type": "0", "device_level": "1", "need_all_video_definition": "1",
		"need_mp4_align": "0", "use_os_player": "0", "video_platform": "1024", "source": "0",
		"version_code": "73932", "manifest_version_code": "73932", "update_version_code": "73932", "pv_player": "73932", "version_name": "7.3.9.32",
		"device_id": "1234567890123456789", "iid": "2234567890123456789",
	} {
		if query.Get(key) != want {
			t.Fatalf("query %s=%q, want %q", key, query.Get(key), want)
		}
	}
	if !query.Has("from_video_id") || query.Get("from_video_id") != "" || !strings.Contains(request.URL.RawQuery, "resolution=1280*2772") {
		t.Fatal("missing empty parameter or changed query encoding")
	}
	ts, _ := strconv.ParseInt(request.Header.Get("x-khronos"), 10, 64)
	if sign6.BranchOf(request.URL.String(), nil, ts) != 0 || request.Header.Get("x-ss-req-ticket") != query.Get("_rticket") {
		t.Fatal("signature is not bound to the final bodyless request")
	}
	for _, key := range []string{"x-gorgon", "x-helios", "x-medusa", "x-ladon", "x-argus"} {
		if request.Header.Get(key) == "" {
			t.Fatal("missing signature", key)
		}
	}
	if request.Header.Get("Content-Encoding") != "" || request.Header.Get("Content-Type") != "" || request.Header.Get("x-ss-stub") != "" {
		t.Fatal("bodyless GET carries POST headers")
	}
	model := map[string]any{"video_duration": "114.006", "video_list": []any{map[string]any{"main_url": "https://media.example/episode.mp4", "video_meta": map[string]any{"codec_type": "h264", "definition": "720p"}}}}
	encoded, _ := json.Marshal(model)
	for _, nested := range []bool{false, true} {
		for _, stringModel := range []bool{false, true} {
			value := any(model)
			if stringModel {
				value = string(encoded)
			}
			entries := map[string]any{videoID: map[string]any{"video_model": value}}
			data := any(entries)
			if nested {
				data = map[string]any{"video_model_data": entries}
			}
			body, _ := json.Marshal(map[string]any{"code": 0, "data": data})
			d := sourceFixtureDownloader(t, func(r *http.Request) (*http.Response, error) {
				return sourceFixtureResponse(r, 200, string(body)), nil
			})
			got, err := d.hongguoPlaybackResponse(request, videoID)
			if err != nil || mapString(got, "video_duration") != "114.006" {
				t.Fatalf("nested=%v string=%v: model=%v err=%v", nested, stringModel, got, err)
			}
			media, err := d.hongguoMediaFromModel(context.Background(), got)
			if err != nil || media.Duration != 114006*time.Millisecond || media.Quality != 720 {
				t.Fatalf("parsed media=%v err=%v", media, err)
			}
		}
	}
	for _, body := range []string{
		``, `invalid`, `{"code":110001,"data":{}}`,
		`{"code":0,"data":{"video_model_data":{"other":{"video_model":{"video_duration":114}}}}}`,
		`{"code":0,"data":{"video_model_data":{"7705456646213864472":{"video_model":"invalid"}}}}`,
	} {
		d := sourceFixtureDownloader(t, func(r *http.Request) (*http.Response, error) {
			return sourceFixtureResponse(r, 200, body), nil
		})
		if _, err := d.hongguoPlaybackResponse(request, videoID); err == nil {
			t.Fatalf("accepted invalid response: %s", body)
		}
	}
}

func TestHongguoTabPrecedesRememberedLegacyRoute(t *testing.T) {
	hongguoPlaybackPrefMu.Lock()
	previous, loaded := hongguoPlaybackPref, hongguoPlaybackPrefLoaded
	hongguoPlaybackPref = hongguoPlaybackPreference{Mode: hongguoPlaybackModeSignedRegistered, Host: "api5-normal-hl.fqnovel.com"}
	hongguoPlaybackPrefLoaded = true
	hongguoPlaybackPrefMu.Unlock()
	t.Cleanup(func() {
		hongguoPlaybackPrefMu.Lock()
		hongguoPlaybackPref, hongguoPlaybackPrefLoaded = previous, loaded
		hongguoPlaybackPrefMu.Unlock()
	})
	order := (&Downloader{}).hongguoPlaybackCandidateOrder()
	if len(order) < 3 || order[0].mode != hongguoPlaybackModeSignedTab || order[1].mode != hongguoPlaybackModeSignedTab || order[2].mode != hongguoPlaybackModeSignedRegistered {
		t.Fatalf("legacy preference bypasses current endpoint: %v", order)
	}
	seen := map[hongguoPlaybackCandidate]bool{}
	for _, candidate := range order {
		if seen[candidate] {
			t.Fatal("duplicate candidate", candidate)
		}
		seen[candidate] = true
	}
}
