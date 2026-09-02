package usagestats

import (
	"context"
	"math"
	"net/http"
	"testing"

	coreusage "github.com/router-for-me/CLIProxyAPI/v7/sdk/cliproxy/usage"
)

func TestRecordPromptCacheAccumulatesAndComputesRatio(t *testing.T) {
	RecordPromptCache("pc-1", 100, 800, 100)
	RecordPromptCache("pc-1", 0, 900, 100)

	u, ok := Get("pc-1")
	if !ok || u.PromptCache == nil {
		t.Fatalf("expected prompt cache stats, got %+v ok=%v", u, ok)
	}
	pc := u.PromptCache
	if pc.Requests != 2 || pc.InputTokens != 100 || pc.CacheReadTokens != 1700 || pc.CacheWriteTokens != 200 {
		t.Fatalf("unexpected counters: %+v", pc)
	}
	if math.Abs(pc.HitRatio-0.85) > 1e-9 {
		t.Fatalf("hit ratio = %v, want 0.85", pc.HitRatio)
	}
	if pc.UpdatedAt == 0 {
		t.Fatal("updated_at should be set")
	}
}

func TestPromptCacheHitRatioZeroDenominator(t *testing.T) {
	if got := promptCacheHitRatio(0, 0, 0); got != 0 {
		t.Fatalf("ratio = %v, want 0", got)
	}
}

func TestGetMergesHeaderSnapshotWithPromptCache(t *testing.T) {
	h := http.Header{}
	h.Set("anthropic-ratelimit-unified-5h-utilization", "0.25")
	RecordFromHeaders("pc-merge", h)
	RecordPromptCache("pc-merge", 10, 90, 0)

	u, ok := Get("pc-merge")
	if !ok {
		t.Fatal("expected usage")
	}
	if u.FiveHour == nil || u.FiveHour.Utilization != 0.25 {
		t.Fatalf("header snapshot lost: %+v", u)
	}
	if u.PromptCache == nil || u.PromptCache.CacheReadTokens != 90 {
		t.Fatalf("prompt cache missing: %+v", u.PromptCache)
	}

	// A later header snapshot must not wipe the cache counters, and the stored
	// header snapshot must not carry a stale PromptCache pointer.
	h.Set("anthropic-ratelimit-unified-5h-utilization", "0.5")
	RecordFromHeaders("pc-merge", h)
	mu.RLock()
	raw := store["pc-merge"]
	mu.RUnlock()
	if raw.PromptCache != nil {
		t.Fatal("stored header snapshot should not embed prompt cache")
	}
	u, _ = Get("pc-merge")
	if u.FiveHour.Utilization != 0.5 || u.PromptCache == nil || u.PromptCache.CacheReadTokens != 90 {
		t.Fatalf("merge after header refresh wrong: %+v pc=%+v", u, u.PromptCache)
	}
}

func TestPromptCachePluginFiltersRecords(t *testing.T) {
	p := promptCachePlugin{}
	ctx := context.Background()

	p.HandleUsage(ctx, coreusage.Record{AuthID: "pc-plugin", Failed: true, Detail: coreusage.Detail{InputTokens: 5}})
	p.HandleUsage(ctx, coreusage.Record{AuthID: "", Detail: coreusage.Detail{InputTokens: 5}})
	p.HandleUsage(ctx, coreusage.Record{AuthID: "pc-plugin", Detail: coreusage.Detail{OutputTokens: 5}})
	if _, ok := getPromptCache("pc-plugin"); ok {
		t.Fatal("failed, anonymous, or output-only records should be ignored")
	}

	// CachedTokens is used as the read count when no explicit cache fields exist.
	p.HandleUsage(ctx, coreusage.Record{AuthID: "pc-plugin", Detail: coreusage.Detail{InputTokens: 20, CachedTokens: 80}})
	pc, ok := getPromptCache("pc-plugin")
	if !ok || pc.Requests != 1 || pc.CacheReadTokens != 80 || pc.InputTokens != 20 {
		t.Fatalf("unexpected stats: %+v ok=%v", pc, ok)
	}

	// Claude mirrors cache writes into CachedTokens on a cold turn; that must not
	// be double-counted as a read.
	p.HandleUsage(ctx, coreusage.Record{AuthID: "pc-cold", Detail: coreusage.Detail{InputTokens: 10, CachedTokens: 500, CacheCreationTokens: 500}})
	cold, _ := getPromptCache("pc-cold")
	if cold.CacheReadTokens != 0 || cold.CacheWriteTokens != 500 || cold.HitRatio != 0 {
		t.Fatalf("cold turn miscounted: %+v", cold)
	}

	// The canonical breakdown wins when present (OpenAI subset semantics: cache
	// reads are part of InputTokens, not additional).
	subset := coreusage.Detail{InputTokens: 100, CacheReadTokens: 90, OutputTokens: 5}
	subset.TokenBreakdown = coreusage.NewSubsetTokenBreakdown(100, 90, 0, 5, 0, 105)
	p.HandleUsage(ctx, coreusage.Record{AuthID: "pc-subset", Detail: subset})
	sub, _ := getPromptCache("pc-subset")
	if sub.InputTokens != 10 || sub.CacheReadTokens != 90 || math.Abs(sub.HitRatio-0.9) > 1e-9 {
		t.Fatalf("subset breakdown miscounted: %+v", sub)
	}
}
