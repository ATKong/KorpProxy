package helps

import (
	"net/http"
	"strconv"
	"testing"
	"time"
)

func TestClaudeRetryAfter(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)

	t.Run("retry-after seconds", func(t *testing.T) {
		h := http.Header{"Retry-After": {"42"}}
		got := ClaudeRetryAfter(http.StatusTooManyRequests, h, now)
		if got == nil || *got != 42*time.Second {
			t.Fatalf("got %v, want 42s", got)
		}
	})

	t.Run("retry-after http-date", func(t *testing.T) {
		when := now.Add(90 * time.Second).UTC().Format(http.TimeFormat)
		h := http.Header{"Retry-After": {when}}
		got := ClaudeRetryAfter(http.StatusTooManyRequests, h, now)
		// HTTP-date has second granularity; allow a small slack.
		if got == nil || *got < 89*time.Second || *got > 91*time.Second {
			t.Fatalf("got %v, want ~90s", got)
		}
	})

	t.Run("retry-after-ms", func(t *testing.T) {
		h := http.Header{"Retry-After-Ms": {"1500"}}
		got := ClaudeRetryAfter(http.StatusTooManyRequests, h, now)
		if got == nil || *got != 1500*time.Millisecond {
			t.Fatalf("got %v, want 1.5s", got)
		}
	})

	t.Run("unified reset fallback picks soonest future", func(t *testing.T) {
		h := http.Header{}
		h.Set("anthropic-ratelimit-unified-5h-reset", itoaInt64(now.Add(2*time.Minute).Unix()))
		h.Set("anthropic-ratelimit-unified-7d-reset", itoaInt64(now.Add(10*time.Minute).Unix()))
		got := ClaudeRetryAfter(http.StatusTooManyRequests, h, now)
		if got == nil || *got != 2*time.Minute {
			t.Fatalf("got %v, want 2m", got)
		}
	})

	t.Run("retry-after wins over reset headers", func(t *testing.T) {
		h := http.Header{}
		h.Set("Retry-After", "5")
		h.Set("anthropic-ratelimit-unified-5h-reset", itoaInt64(now.Add(time.Hour).Unix()))
		got := ClaudeRetryAfter(http.StatusTooManyRequests, h, now)
		if got == nil || *got != 5*time.Second {
			t.Fatalf("got %v, want 5s", got)
		}
	})

	t.Run("past reset is ignored", func(t *testing.T) {
		h := http.Header{}
		h.Set("anthropic-ratelimit-unified-5h-reset", itoaInt64(now.Add(-time.Minute).Unix()))
		if got := ClaudeRetryAfter(http.StatusTooManyRequests, h, now); got != nil {
			t.Fatalf("got %v, want nil for past reset", got)
		}
	})

	t.Run("529 overloaded is treated as rate limit", func(t *testing.T) {
		h := http.Header{"Retry-After": {"7"}}
		got := ClaudeRetryAfter(529, h, now)
		if got == nil || *got != 7*time.Second {
			t.Fatalf("got %v, want 7s", got)
		}
	})

	t.Run("non rate-limit status returns nil", func(t *testing.T) {
		h := http.Header{"Retry-After": {"30"}}
		if got := ClaudeRetryAfter(http.StatusInternalServerError, h, now); got != nil {
			t.Fatalf("got %v, want nil for 500", got)
		}
	})

	t.Run("no headers returns nil", func(t *testing.T) {
		if got := ClaudeRetryAfter(http.StatusTooManyRequests, http.Header{}, now); got != nil {
			t.Fatalf("got %v, want nil", got)
		}
	})

	t.Run("zero or negative retry-after returns nil", func(t *testing.T) {
		h := http.Header{"Retry-After": {"0"}}
		if got := ClaudeRetryAfter(http.StatusTooManyRequests, h, now); got != nil {
			t.Fatalf("got %v, want nil for zero", got)
		}
	})
}

func itoaInt64(v int64) string {
	return strconv.FormatInt(v, 10)
}
