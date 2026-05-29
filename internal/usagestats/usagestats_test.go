package usagestats

import (
	"net/http"
	"testing"
)

func TestRecordFromHeadersParsesUnified(t *testing.T) {
	h := http.Header{}
	h.Set("anthropic-ratelimit-unified-5h-utilization", "0.58")
	h.Set("anthropic-ratelimit-unified-5h-reset", "1714579200")
	h.Set("anthropic-ratelimit-unified-5h-status", "active")
	h.Set("anthropic-ratelimit-unified-7d-utilization", "0.14")
	h.Set("anthropic-ratelimit-unified-status", "allowed")
	h.Set("anthropic-ratelimit-unified-representative-claim", "five_hour")

	RecordFromHeaders("auth-1", h)
	u, ok := Get("auth-1")
	if !ok {
		t.Fatal("expected usage recorded")
	}
	if u.FiveHour == nil || u.FiveHour.Utilization != 0.58 {
		t.Fatalf("5h util = %+v", u.FiveHour)
	}
	if u.FiveHour.Reset != 1714579200 {
		t.Fatalf("5h reset = %d", u.FiveHour.Reset)
	}
	if u.FiveHour.Status != "active" {
		t.Fatalf("5h status = %q", u.FiveHour.Status)
	}
	if u.SevenDay == nil || u.SevenDay.Utilization != 0.14 {
		t.Fatalf("7d util = %+v", u.SevenDay)
	}
	if u.OverallStatus != "allowed" {
		t.Fatalf("overall = %q", u.OverallStatus)
	}
	if u.RepresentativeClaim != "five_hour" {
		t.Fatalf("claim = %q", u.RepresentativeClaim)
	}
}

func TestRecordFromHeadersIgnoresNonUnified(t *testing.T) {
	h := http.Header{}
	h.Set("content-type", "application/json")
	RecordFromHeaders("auth-2", h)
	if _, ok := Get("auth-2"); ok {
		t.Fatal("expected no usage for non-unified headers")
	}
}

func TestParseWindowAltSpelling(t *testing.T) {
	h := http.Header{}
	h.Set("anthropic-ratelimit-unified-five_hour-utilization", "0.9")
	RecordFromHeaders("auth-3", h)
	u, ok := Get("auth-3")
	if !ok || u.FiveHour == nil || u.FiveHour.Utilization != 0.9 {
		t.Fatalf("alt spelling not parsed: %+v ok=%v", u, ok)
	}
}

func TestRecordFromHeadersEmptyAuthID(t *testing.T) {
	h := http.Header{}
	h.Set("anthropic-ratelimit-unified-5h-utilization", "0.5")
	RecordFromHeaders("", h)
	if _, ok := Get(""); ok {
		t.Fatal("expected no usage stored for empty auth id")
	}
}
