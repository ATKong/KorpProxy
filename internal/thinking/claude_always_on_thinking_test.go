package thinking_test

import (
	"testing"

	"github.com/router-for-me/CLIProxyAPI/v7/internal/registry"
	"github.com/router-for-me/CLIProxyAPI/v7/internal/thinking"
	_ "github.com/router-for-me/CLIProxyAPI/v7/internal/thinking/provider/claude"
	"github.com/tidwall/gjson"
)

// Opus 5.5 rejects thinking.type=disabled with a 400. Callers that ask to turn
// thinking off must be mapped to the lowest effort level instead.
func TestClaudeAlwaysOnThinkingDisableMapsToLowestEffort(t *testing.T) {
	reg := registry.GetGlobalRegistry()
	clientID := "test-claude-always-on-thinking"
	reg.RegisterClient(clientID, "claude", registry.GetClaudeModels())
	t.Cleanup(func() { reg.UnregisterClient(clientID) })

	cases := []struct {
		name string
		body string
	}{
		{name: "disabled type", body: `{"model":"claude-opus-5-5","messages":[{"role":"user","content":"hi"}],"thinking":{"type":"disabled"}}`},
		{name: "zero budget", body: `{"model":"claude-opus-5-5","messages":[{"role":"user","content":"hi"}],"thinking":{"type":"enabled","budget_tokens":0}}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			out, err := thinking.ApplyThinking([]byte(tc.body), "claude-opus-5-5", "claude", "claude", "claude")
			if err != nil {
				t.Fatalf("ApplyThinking returned error: %v", err)
			}
			if got := gjson.GetBytes(out, "thinking.type").String(); got != "adaptive" {
				t.Fatalf("thinking.type = %q, want adaptive: %s", got, out)
			}
			if got := gjson.GetBytes(out, "output_config.effort").String(); got != "low" {
				t.Fatalf("output_config.effort = %q, want low: %s", got, out)
			}
			if gjson.GetBytes(out, "thinking.budget_tokens").Exists() {
				t.Fatalf("budget_tokens must not be sent for adaptive thinking: %s", out)
			}
		})
	}
}

// Opus 5 still accepts thinking.type=disabled, so the fallback must not touch it.
func TestClaudeDisableableThinkingStaysDisabled(t *testing.T) {
	reg := registry.GetGlobalRegistry()
	clientID := "test-claude-disableable-thinking"
	reg.RegisterClient(clientID, "claude", registry.GetClaudeModels())
	t.Cleanup(func() { reg.UnregisterClient(clientID) })

	body := []byte(`{"model":"claude-opus-5","messages":[{"role":"user","content":"hi"}],"thinking":{"type":"disabled"}}`)
	out, err := thinking.ApplyThinking(body, "claude-opus-5", "claude", "claude", "claude")
	if err != nil {
		t.Fatalf("ApplyThinking returned error: %v", err)
	}
	if got := gjson.GetBytes(out, "thinking.type").String(); got != "disabled" {
		t.Fatalf("thinking.type = %q, want disabled: %s", got, out)
	}
}
