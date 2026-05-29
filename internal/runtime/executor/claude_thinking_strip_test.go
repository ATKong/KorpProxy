package executor

import (
	"testing"

	"github.com/tidwall/gjson"
)

func assertNoThinking(t *testing.T, out []byte) {
	t.Helper()
	gjson.GetBytes(out, "messages").ForEach(func(_, msg gjson.Result) bool {
		msg.Get("content").ForEach(func(_, blk gjson.Result) bool {
			if tpe := blk.Get("type").String(); tpe == "thinking" || tpe == "redacted_thinking" {
				t.Errorf("thinking block survived: %s", blk.Raw)
			}
			return true
		})
		return true
	})
}

// TestStripReplayedThinkingBlocks_RemovesThinkingPreservesRest verifies that
// cloaking drops replayed thinking/redacted_thinking blocks (which Anthropic would
// otherwise reject once the system prompt is swapped) while leaving text, tool_use,
// and user content intact and in order.
func TestStripReplayedThinkingBlocks_RemovesThinkingPreservesRest(t *testing.T) {
	body := []byte(`{"model":"claude-opus-4-8","messages":[` +
		`{"role":"user","content":[{"type":"text","text":"hello"}]},` +
		`{"role":"assistant","content":[` +
		`{"type":"thinking","signature":"SIG_A","thinking":"reasoning A"},` +
		`{"type":"text","text":"answer"},` +
		`{"type":"tool_use","id":"tool_1","name":"Bash","input":{"cmd":"ls"}}]},` +
		`{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool_1","content":"ok"}]},` +
		`{"role":"assistant","content":[` +
		`{"type":"redacted_thinking","data":"REDACTED_BLOB"},` +
		`{"type":"thinking","signature":"SIG_B","thinking":"reasoning B"},` +
		`{"type":"text","text":"done"}]}]}`)

	out := stripReplayedThinkingBlocks(body)

	assertNoThinking(t, out)

	if got := gjson.GetBytes(out, "messages.0.content.0.text").String(); got != "hello" {
		t.Errorf("user msg[0] altered: %q", got)
	}
	if got := gjson.GetBytes(out, "messages.2.content.0.tool_use_id").String(); got != "tool_1" {
		t.Errorf("tool_result msg[2] altered: %q", got)
	}

	m1 := gjson.GetBytes(out, "messages.1.content").Array()
	if len(m1) != 2 {
		t.Fatalf("msg[1] expected 2 blocks after strip, got %d", len(m1))
	}
	if m1[0].Get("type").String() != "text" || m1[0].Get("text").String() != "answer" {
		t.Errorf("msg[1] text block not preserved: %s", m1[0].Raw)
	}
	if m1[1].Get("type").String() != "tool_use" || m1[1].Get("name").String() != "Bash" {
		t.Errorf("msg[1] tool_use block not preserved: %s", m1[1].Raw)
	}

	m3 := gjson.GetBytes(out, "messages.3.content").Array()
	if len(m3) != 1 {
		t.Fatalf("msg[3] expected 1 block after strip, got %d", len(m3))
	}
	if m3[0].Get("type").String() != "text" || m3[0].Get("text").String() != "done" {
		t.Errorf("msg[3] text block not preserved: %s", m3[0].Raw)
	}
}

// TestStripReplayedThinkingBlocks_AllThinkingBecomesEmptyText ensures a message
// consisting solely of thinking blocks is rewritten to a single empty text block
// (rather than an empty content array, which Anthropic rejects).
func TestStripReplayedThinkingBlocks_AllThinkingBecomesEmptyText(t *testing.T) {
	body := []byte(`{"messages":[` +
		`{"role":"user","content":[{"type":"text","text":"hi"}]},` +
		`{"role":"assistant","content":[{"type":"thinking","signature":"S","thinking":"only thinking"}]}]}`)

	out := stripReplayedThinkingBlocks(body)

	c := gjson.GetBytes(out, "messages.1.content").Array()
	if len(c) != 1 {
		t.Fatalf("expected 1 placeholder block, got %d", len(c))
	}
	if c[0].Get("type").String() != "text" || c[0].Get("text").String() != "" {
		t.Errorf("expected empty text placeholder, got %s", c[0].Raw)
	}
}

// TestStripReplayedThinkingBlocks_NoThinkingIsNoOp verifies bodies without thinking
// blocks are returned unchanged.
func TestStripReplayedThinkingBlocks_NoThinkingIsNoOp(t *testing.T) {
	body := []byte(`{"messages":[` +
		`{"role":"user","content":[{"type":"text","text":"hi"}]},` +
		`{"role":"assistant","content":[{"type":"text","text":"hello"}]}]}`)

	out := stripReplayedThinkingBlocks(body)
	if string(out) != string(body) {
		t.Errorf("expected no-op, body changed:\n%s", string(out))
	}
}

// TestCheckSystemInstructions_StripsThinkingWhenCloaking is the integration guard:
// once the client system is swapped for the Claude Code prompt, replayed thinking
// blocks must be gone (otherwise Anthropic 400s the cloaked request).
func TestCheckSystemInstructions_StripsThinkingWhenCloaking(t *testing.T) {
	body := []byte(`{"model":"claude-opus-4-8",` +
		`"system":[{"type":"text","text":"You are a helpful third-party assistant."}],` +
		`"messages":[` +
		`{"role":"user","content":[{"type":"text","text":"hi"}]},` +
		`{"role":"assistant","content":[` +
		`{"type":"thinking","signature":"SIG","thinking":"prior reasoning"},` +
		`{"type":"text","text":"prior answer"}]},` +
		`{"role":"user","content":[{"type":"text","text":"continue"}]}]}`)

	out := checkSystemInstructionsWithSigningMode(body, false, true, true, "2.1.63", "cli", "")

	if got := gjson.GetBytes(out, "system.1.text").String(); got != "You are Claude Code, Anthropic's official CLI for Claude." {
		t.Errorf("system not cloaked, got system.1.text=%q", got)
	}
	assertNoThinking(t, out)
}
