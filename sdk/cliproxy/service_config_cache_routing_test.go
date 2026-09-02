package cliproxy

import (
	"testing"

	coreauth "github.com/router-for-me/CLIProxyAPI/v7/sdk/cliproxy/auth"
)

func TestClaudeCacheRoutingRisk(t *testing.T) {
	claudeAuths := []*coreauth.Auth{
		{ID: "a", Provider: "claude"},
		{ID: "b", Provider: "Claude"},
		{ID: "c", Provider: "claude", Disabled: true},
		{ID: "d", Provider: "codex"},
		nil,
	}

	tests := []struct {
		name      string
		state     routingRuntimeState
		auths     []*coreauth.Auth
		wantCount int
		wantRisk  bool
	}{
		{name: "round-robin two claude", state: routingRuntimeState{strategy: "round-robin"}, auths: claudeAuths, wantCount: 2, wantRisk: true},
		{name: "weighted two claude", state: routingRuntimeState{strategy: "weighted-round-robin"}, auths: claudeAuths, wantCount: 2, wantRisk: true},
		{name: "session affinity on", state: routingRuntimeState{strategy: "round-robin", sessionAffinity: true}, auths: claudeAuths, wantRisk: false},
		{name: "fill-first", state: routingRuntimeState{strategy: "fill-first"}, auths: claudeAuths, wantRisk: false},
		{name: "single claude", state: routingRuntimeState{strategy: "round-robin"}, auths: claudeAuths[:1], wantCount: 1, wantRisk: false},
		{name: "no auths", state: routingRuntimeState{strategy: "round-robin"}, auths: nil, wantRisk: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			count, risky := claudeCacheRoutingRisk(tt.state, tt.auths)
			if risky != tt.wantRisk {
				t.Fatalf("risky = %v, want %v", risky, tt.wantRisk)
			}
			if risky && count != tt.wantCount {
				t.Fatalf("count = %d, want %d", count, tt.wantCount)
			}
		})
	}
}
