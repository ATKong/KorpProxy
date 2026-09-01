package executor

import (
	"testing"

	"github.com/tidwall/gjson"
)

func TestDropTrailingClaudeAssistantPrefill_ThinkingActive(t *testing.T) {
	payload := []byte(`{"thinking":{"type":"adaptive","display":"summarized"},"messages":[` +
		`{"role":"user","content":[{"type":"text","text":"hi"}]},` +
		`{"role":"assistant","content":[{"type":"text","text":"I","cache_control":{"type":"ephemeral"}}]}` +
		`]}`)

	out, discardedText, dropped := dropTrailingClaudeAssistantPrefill(payload, false)
	if !dropped {
		t.Fatalf("trailing assistant prefill should be dropped when thinking is active")
	}
	if !discardedText {
		t.Fatalf("dropped prefill carried text, so discardedText should be true")
	}
	messages := gjson.GetBytes(out, "messages").Array()
	if len(messages) != 1 {
		t.Fatalf("messages length = %d, want 1; body=%s", len(messages), out)
	}
	if got := messages[0].Get("role").String(); got != "user" {
		t.Fatalf("last role = %q, want user; body=%s", got, out)
	}
}

func TestDropTrailingClaudeAssistantPrefill_KeepsPrefillWithoutThinking(t *testing.T) {
	payload := []byte(`{"messages":[` +
		`{"role":"user","content":"return json"},` +
		`{"role":"assistant","content":"{"}` +
		`]}`)

	out, _, dropped := dropTrailingClaudeAssistantPrefill(payload, false)
	if dropped {
		t.Fatalf("a real prefill must survive on an upstream that accepts it; body=%s", out)
	}
	if len(gjson.GetBytes(out, "messages").Array()) != 2 {
		t.Fatalf("messages should be untouched; body=%s", out)
	}
}

func TestDropTrailingClaudeAssistantPrefill_AnthropicDropsRealPrefillWithoutThinking(t *testing.T) {
	payload := []byte(`{"messages":[` +
		`{"role":"user","content":"Finish this sentence with one word."},` +
		`{"role":"assistant","content":"The capital of France is"}` +
		`]}`)

	out, discardedText, dropped := dropTrailingClaudeAssistantPrefill(payload, true)
	if !dropped {
		t.Fatalf("Anthropic rejects every prefill, so forwarding it would 400; body=%s", out)
	}
	if !discardedText {
		t.Fatalf("dropped prefill carried text, so discardedText should be true")
	}
	messages := gjson.GetBytes(out, "messages").Array()
	if len(messages) != 1 || messages[0].Get("role").String() != "user" {
		t.Fatalf("conversation should end on the user turn; body=%s", out)
	}
}

func TestDropTrailingClaudeAssistantPrefill_EmptyPrefillWithoutThinking(t *testing.T) {
	payload := []byte(`{"messages":[` +
		`{"role":"user","content":"hi"},` +
		`{"role":"assistant","content":[{"type":"text","text":"  "}]}` +
		`]}`)

	out, discardedText, dropped := dropTrailingClaudeAssistantPrefill(payload, false)
	if !dropped {
		t.Fatalf("whitespace-only prefill should be dropped regardless of thinking; body=%s", out)
	}
	if discardedText {
		t.Fatalf("a blank prefill discards no text")
	}
	if len(gjson.GetBytes(out, "messages").Array()) != 1 {
		t.Fatalf("messages length = %d, want 1; body=%s", len(gjson.GetBytes(out, "messages").Array()), out)
	}
}

func TestDropTrailingClaudeAssistantPrefill_DropsThinkingAndTextTurnOnAnthropic(t *testing.T) {
	// A trailing assistant turn with thinking + text is still a prefill: Anthropic
	// rejects thinking blocks in the final message, and the signature sanitizer
	// would strip them after this pass, recreating the text-only shape it removes.
	payload := []byte(`{"thinking":{"type":"enabled","budget_tokens":1024},"messages":[` +
		`{"role":"user","content":"hi"},` +
		`{"role":"assistant","content":[{"type":"thinking","thinking":"…","signature":"sig"},{"type":"text","text":"partial"}]}` +
		`]}`)

	out, discardedText, dropped := dropTrailingClaudeAssistantPrefill(payload, true)
	if !dropped {
		t.Fatalf("trailing thinking+text turn must be dropped for a prefill-rejecting upstream; body=%s", out)
	}
	if !discardedText {
		t.Fatalf("dropped turn carried text, so discardedText should be true")
	}
	if len(gjson.GetBytes(out, "messages").Array()) != 1 {
		t.Fatalf("messages length = %d, want 1; body=%s", len(gjson.GetBytes(out, "messages").Array()), out)
	}
}

func TestDropTrailingClaudeAssistantPrefill_KeepsThinkingAndTextTurnWhenPrefillUsable(t *testing.T) {
	payload := []byte(`{"messages":[` +
		`{"role":"user","content":"hi"},` +
		`{"role":"assistant","content":[{"type":"thinking","thinking":"…","signature":"sig"},{"type":"text","text":"partial"}]}` +
		`]}`)

	out, _, dropped := dropTrailingClaudeAssistantPrefill(payload, false)
	if dropped {
		t.Fatalf("an upstream that accepts prefill keeps a text-carrying turn when thinking is off; body=%s", out)
	}
}

func TestDropTrailingClaudeAssistantPrefill_DropsThinkingOnlyTurn(t *testing.T) {
	payload := []byte(`{"thinking":{"type":"adaptive"},"messages":[` +
		`{"role":"user","content":"hi"},` +
		`{"role":"assistant","content":[{"type":"thinking","thinking":"…","signature":"sig"}]}` +
		`]}`)

	out, discardedText, dropped := dropTrailingClaudeAssistantPrefill(payload, true)
	if !dropped {
		t.Fatalf("a trailing thinking-only turn is inert and must be dropped; body=%s", out)
	}
	if discardedText {
		t.Fatalf("a thinking-only turn discards no text")
	}
}

func TestDropTrailingClaudeAssistantPrefill_KeepsToolUseTurn(t *testing.T) {
	payload := []byte(`{"thinking":{"type":"adaptive"},"messages":[` +
		`{"role":"user","content":"hi"},` +
		`{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Read","input":{}}]}` +
		`]}`)

	out, _, dropped := dropTrailingClaudeAssistantPrefill(payload, true)
	if dropped {
		t.Fatalf("assistant turn carrying tool_use must be preserved; body=%s", out)
	}
}

func TestDropTrailingClaudeAssistantPrefill_NoopOnMalformedBody(t *testing.T) {
	for _, payload := range [][]byte{
		[]byte(`{`),
		[]byte(`{}`),
		[]byte(`{"messages":"nope"}`),
		[]byte(`{"messages":[]}`),
	} {
		out, _, dropped := dropTrailingClaudeAssistantPrefill(payload, true)
		if dropped || string(out) != string(payload) {
			t.Fatalf("malformed body %s must pass through untouched, got dropped=%v body=%s", payload, dropped, out)
		}
	}
}

func TestDropTrailingClaudeAssistantPrefill_DropsConsecutivePrefills(t *testing.T) {
	payload := []byte(`{"thinking":{"type":"adaptive"},"messages":[` +
		`{"role":"user","content":"hi"},` +
		`{"role":"assistant","content":[{"type":"text","text":"I"}]},` +
		`{"role":"assistant","content":[{"type":"text","text":"I'll"}]}` +
		`]}`)

	out, discardedText, dropped := dropTrailingClaudeAssistantPrefill(payload, true)
	if !dropped {
		t.Fatalf("consecutive trailing prefills should be dropped; body=%s", out)
	}
	if !discardedText {
		t.Fatalf("dropped prefills carried text, so discardedText should be true")
	}
	messages := gjson.GetBytes(out, "messages").Array()
	if len(messages) != 1 || messages[0].Get("role").String() != "user" {
		t.Fatalf("conversation should end on the user turn; body=%s", out)
	}
}

func TestDropTrailingClaudeAssistantPrefill_KeepsSoleAssistantMessage(t *testing.T) {
	payload := []byte(`{"thinking":{"type":"adaptive"},"messages":[{"role":"assistant","content":[{"type":"text","text":"I"}]}]}`)

	out, _, dropped := dropTrailingClaudeAssistantPrefill(payload, true)
	if dropped {
		t.Fatalf("stripping the only message would leave an empty conversation; body=%s", out)
	}
}

func TestDropTrailingClaudeAssistantPrefill_NoopWhenEndingOnUser(t *testing.T) {
	payload := []byte(`{"thinking":{"type":"adaptive"},"messages":[` +
		`{"role":"assistant","content":[{"type":"text","text":"done"}]},` +
		`{"role":"user","content":"thanks"}` +
		`]}`)

	out, _, dropped := dropTrailingClaudeAssistantPrefill(payload, true)
	if dropped {
		t.Fatalf("a conversation already ending on a user turn must be untouched; body=%s", out)
	}
}
