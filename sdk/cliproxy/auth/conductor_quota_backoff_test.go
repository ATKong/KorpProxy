package auth

import (
	"context"
	"testing"
	"time"

	"github.com/router-for-me/CLIProxyAPI/v7/internal/registry"
)

// markQuotaAndReadNextRetry registers a single Claude auth, marks a 429 with the
// given RetryAfter (nil = none), and returns how far in the future the resulting
// per-model cooldown lands.
func markQuotaAndReadNextRetry(t *testing.T, authID string, retryAfter *time.Duration) time.Duration {
	t.Helper()
	const model = "claude-sonnet-4-6"
	reg := registry.GetGlobalRegistry()
	reg.RegisterClient(authID, "claude", []*registry.ModelInfo{{ID: model, Type: "claude"}})
	t.Cleanup(func() { reg.UnregisterClient(authID) })

	m := NewManager(nil, &RoundRobinSelector{}, nil)
	if _, err := m.Register(context.Background(), &Auth{ID: authID, Provider: "claude", Metadata: map[string]any{"k": "v"}}); err != nil {
		t.Fatalf("register: %v", err)
	}

	before := time.Now()
	m.MarkResult(context.Background(), Result{
		AuthID:     authID,
		Provider:   "claude",
		Model:      model,
		Success:    false,
		Error:      &Error{HTTPStatus: 429, Message: "quota"},
		RetryAfter: retryAfter,
	})

	auth, ok := m.GetByID(authID)
	if !ok || auth == nil {
		t.Fatalf("auth not found after MarkResult")
	}
	state := auth.ModelStates[model]
	if state == nil || state.NextRetryAfter.IsZero() {
		t.Fatalf("expected a cooldown to be set, got %+v", state)
	}
	return state.NextRetryAfter.Sub(before)
}

func TestMarkResult429_HonorsProviderRetryAfterVerbatim(t *testing.T) {
	// A real 2-hour reset (e.g. Anthropic weekly window) must be honored, not capped.
	want := 2 * time.Hour
	got := markQuotaAndReadNextRetry(t, "claude-ra-1", &want)
	if got < want-2*time.Second || got > want+2*time.Second {
		t.Fatalf("cooldown = %v, want ~%v (provider hint must be verbatim)", got, want)
	}
}

func TestMarkResult429_SyntheticFallbackIsCapped(t *testing.T) {
	// No provider hint: the synthetic fallback must never exceed the small cap,
	// so a missing header can't cause a multi-minute blackout.
	got := markQuotaAndReadNextRetry(t, "claude-ra-2", nil)
	if got > quotaSyntheticBackoffMax+2*time.Second {
		t.Fatalf("synthetic cooldown = %v, want <= %v", got, quotaSyntheticBackoffMax)
	}
}

func TestMarkResult429_SyntheticFallbackCappedAtHighBackoffLevel(t *testing.T) {
	const model = "claude-sonnet-4-6"
	const authID = "claude-ra-3"
	reg := registry.GetGlobalRegistry()
	reg.RegisterClient(authID, "claude", []*registry.ModelInfo{{ID: model, Type: "claude"}})
	t.Cleanup(func() { reg.UnregisterClient(authID) })

	m := NewManager(nil, &RoundRobinSelector{}, nil)
	// Seed a high backoff level so the raw exponential would blow past the cap.
	if _, err := m.Register(context.Background(), &Auth{
		ID:       authID,
		Provider: "claude",
		Metadata: map[string]any{"k": "v"},
		ModelStates: map[string]*ModelState{
			model: {Quota: QuotaState{BackoffLevel: 20}},
		},
	}); err != nil {
		t.Fatalf("register: %v", err)
	}

	before := time.Now()
	m.MarkResult(context.Background(), Result{
		AuthID:   authID,
		Provider: "claude",
		Model:    model,
		Success:  false,
		Error:    &Error{HTTPStatus: 429, Message: "quota"},
	})

	auth, _ := m.GetByID(authID)
	state := auth.ModelStates[model]
	got := state.NextRetryAfter.Sub(before)
	if got > quotaSyntheticBackoffMax+2*time.Second {
		t.Fatalf("synthetic cooldown at high backoff = %v, want <= %v", got, quotaSyntheticBackoffMax)
	}
}
