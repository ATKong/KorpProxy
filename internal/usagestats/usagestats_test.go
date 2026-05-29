package usagestats

import (
	"net/http"
	"testing"
	"time"
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

func TestRecordFromHeadersParsesCodex(t *testing.T) {
	now := time.Now().Unix()
	h := http.Header{}
	h.Set("x-codex-plan-type", "pro")
	h.Set("x-codex-primary-used-percent", "42")
	h.Set("x-codex-primary-window-minutes", "300")
	h.Set("x-codex-primary-reset-at", "1780097478")
	h.Set("x-codex-secondary-used-percent", "6.5")
	h.Set("x-codex-secondary-window-minutes", "10080")
	h.Set("x-codex-secondary-reset-after-seconds", "600")

	RecordFromHeaders("codex-1", h)
	u, ok := Get("codex-1")
	if !ok {
		t.Fatal("expected codex usage recorded")
	}
	// used-percent 42 → fraction 0.42 in the primary (5h) window.
	if u.FiveHour == nil || u.FiveHour.Utilization < 0.4199 || u.FiveHour.Utilization > 0.4201 {
		t.Fatalf("primary util = %+v, want 0.42", u.FiveHour)
	}
	// Absolute -reset-at is used verbatim.
	if u.FiveHour.Reset != 1780097478 {
		t.Fatalf("primary reset = %d, want 1780097478", u.FiveHour.Reset)
	}
	if u.SevenDay == nil || u.SevenDay.Utilization < 0.0649 || u.SevenDay.Utilization > 0.0651 {
		t.Fatalf("secondary util = %+v, want 0.065", u.SevenDay)
	}
	// No -reset-at on secondary → now + -reset-after-seconds (~600s).
	if u.SevenDay.Reset < now+595 || u.SevenDay.Reset > now+610 {
		t.Fatalf("secondary reset = %d, want ~now+600 (now=%d)", u.SevenDay.Reset, now)
	}
	if u.OverallStatus != "pro" {
		t.Fatalf("overall = %q, want pro", u.OverallStatus)
	}
}

// Anthropic headers take precedence when both somehow appear, and Codex headers
// alone never affect the Anthropic parse path.
func TestRecordFromHeadersAnthropicWinsOverCodex(t *testing.T) {
	h := http.Header{}
	h.Set("anthropic-ratelimit-unified-5h-utilization", "0.3")
	h.Set("x-codex-primary-used-percent", "99")
	RecordFromHeaders("mixed-1", h)
	u, ok := Get("mixed-1")
	if !ok || u.FiveHour == nil || u.FiveHour.Utilization != 0.3 {
		t.Fatalf("expected anthropic 0.3 to win, got %+v ok=%v", u, ok)
	}
}
