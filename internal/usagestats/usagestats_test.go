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

func TestExhaustedUntil(t *testing.T) {
	reset5h := int64(2_000_000_000)
	reset7d := int64(2_000_500_000)

	cases := []struct {
		name      string
		usage     Usage
		wantOK    bool
		wantReset int64
	}{
		{
			name:   "headroom",
			usage:  Usage{FiveHour: &Window{Utilization: 0.4, Status: "active"}},
			wantOK: false,
		},
		{
			name:      "five_hour full by utilization",
			usage:     Usage{FiveHour: &Window{Utilization: 1.0, Reset: reset5h}},
			wantOK:    true,
			wantReset: reset5h,
		},
		{
			name:      "status rejected",
			usage:     Usage{FiveHour: &Window{Utilization: 0.8, Status: "rejected", Reset: reset5h}},
			wantOK:    true,
			wantReset: reset5h,
		},
		{
			name: "both exhausted uses latest reset",
			usage: Usage{
				FiveHour: &Window{Utilization: 1.0, Reset: reset5h},
				SevenDay: &Window{Utilization: 1.2, Reset: reset7d},
			},
			wantOK:    true,
			wantReset: reset7d,
		},
		{
			name:   "near max is not exhausted",
			usage:  Usage{FiveHour: &Window{Utilization: 0.99, Status: "warning"}},
			wantOK: false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotReset, gotOK := tc.usage.ExhaustedUntil()
			if gotOK != tc.wantOK {
				t.Fatalf("ok = %v, want %v", gotOK, tc.wantOK)
			}
			if tc.wantOK && gotReset != tc.wantReset {
				t.Fatalf("reset = %d, want %d", gotReset, tc.wantReset)
			}
		})
	}
}

func TestRecordFromHeadersFiresExhaustionHook(t *testing.T) {
	t.Cleanup(func() { SetExhaustionHook(nil) })

	type call struct {
		authID    string
		resetUnix int64
	}
	got := make(chan call, 1)
	SetExhaustionHook(func(authID string, resetUnix int64) {
		got <- call{authID, resetUnix}
	})

	reset := int64(2_000_000_000)
	h := http.Header{}
	h.Set("anthropic-ratelimit-unified-5h-utilization", "1.0")
	h.Set("anthropic-ratelimit-unified-5h-reset", "2000000000")
	h.Set("anthropic-ratelimit-unified-5h-status", "rejected")
	RecordFromHeaders("hook-1", h)

	select {
	case c := <-got:
		if c.authID != "hook-1" || c.resetUnix != reset {
			t.Fatalf("hook call = %+v, want {hook-1 %d}", c, reset)
		}
	default:
		t.Fatal("expected exhaustion hook to fire")
	}
}

func TestRecordFromHeadersSkipsHookWhenHealthy(t *testing.T) {
	t.Cleanup(func() { SetExhaustionHook(nil) })

	fired := false
	SetExhaustionHook(func(string, int64) { fired = true })

	h := http.Header{}
	h.Set("anthropic-ratelimit-unified-5h-utilization", "0.5")
	h.Set("anthropic-ratelimit-unified-5h-status", "active")
	RecordFromHeaders("hook-2", h)

	if fired {
		t.Fatal("hook must not fire when the account still has headroom")
	}
}
