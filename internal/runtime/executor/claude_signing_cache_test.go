package executor

import (
	"regexp"
	"testing"

	"github.com/tidwall/gjson"
)

var (
	cchValuePattern       = regexp.MustCompile(`cch=[0-9a-f]{5};`)
	buildFingerprintValue = regexp.MustCompile(`cc_version=(\d+\.\d+\.\d+)\.[0-9a-f]{3};`)
)

// The billing header in system[0] carries a per-turn build fingerprint (derived
// from the latest user message, like real Claude Code) and a per-body cch. This
// guards that those are the only bytes that vary between turns, so the cacheable
// prefix (remaining system blocks, tools, breakpoint positions) stays byte-identical
// across consecutive turns of the same conversation.
func TestSigningKeepsCacheablePrefixStable(t *testing.T) {
	build := func(lastUser string) []byte {
		payload := []byte(`{
			"model": "claude-sonnet-4-5",
			"system": [{"type": "text", "text": "You are a helpful coding agent for project Foo."}],
			"tools": [
				{"name": "read", "description": "Read a file", "input_schema": {"type": "object"}},
				{"name": "write", "description": "Write a file", "input_schema": {"type": "object"}}
			],
			"messages": [
				{"role": "user", "content": "first question"},
				{"role": "assistant", "content": "first answer"},
				{"role": "user", "content": "` + lastUser + `"}
			]
		}`)
		payload = checkSystemInstructionsWithSigningMode(payload, false, true, true, "2.1.251", "cli", "")
		payload = ensureCacheControl(payload)
		signed, err := signAnthropicMessagesBody(payload)
		if err != nil {
			t.Fatalf("sign: %v", err)
		}
		return signed
	}

	a := build("second question")
	b := build("a different second question")

	headerA := gjson.GetBytes(a, "system.0.text").String()
	headerB := gjson.GetBytes(b, "system.0.text").String()
	if !cchValuePattern.MatchString(headerA) || !cchValuePattern.MatchString(headerB) {
		t.Fatalf("billing header not signed: %q / %q", headerA, headerB)
	}
	stable := func(h string) string {
		h = cchValuePattern.ReplaceAllString(h, "")
		return buildFingerprintValue.ReplaceAllString(h, "cc_version=$1;")
	}
	if stable(headerA) != stable(headerB) {
		t.Fatalf("billing header differs beyond cch/build fingerprint: %q vs %q", headerA, headerB)
	}

	sysA := gjson.GetBytes(a, "system").Array()
	sysB := gjson.GetBytes(b, "system").Array()
	if len(sysA) != len(sysB) || len(sysA) < 2 {
		t.Fatalf("system block count mismatch: %d vs %d", len(sysA), len(sysB))
	}
	for i := 1; i < len(sysA); i++ {
		if sysA[i].Raw != sysB[i].Raw {
			t.Fatalf("system[%d] differs between turns:\n%s\n%s", i, sysA[i].Raw, sysB[i].Raw)
		}
	}
	if gjson.GetBytes(a, "tools").Raw != gjson.GetBytes(b, "tools").Raw {
		t.Fatal("tools differ between turns")
	}

	// Breakpoint positions must match between turns, wherever ensureCacheControl put them.
	positions := func(p []byte) []string {
		var out []string
		for _, section := range []string{"tools", "system"} {
			gjson.GetBytes(p, section).ForEach(func(idx, item gjson.Result) bool {
				if item.Get("cache_control").Exists() {
					out = append(out, section+"."+idx.String())
				}
				return true
			})
		}
		return out
	}
	posA, posB := positions(a), positions(b)
	if len(posA) == 0 || len(posA) != len(posB) {
		t.Fatalf("breakpoint positions differ: %v vs %v", posA, posB)
	}
	for i := range posA {
		if posA[i] != posB[i] {
			t.Fatalf("breakpoint positions differ: %v vs %v", posA, posB)
		}
	}
	if gjson.GetBytes(a, "system.0.cache_control").Exists() {
		t.Fatal("billing header block must not carry cache_control")
	}
	if n := countCacheControls(a); n > 4 {
		t.Fatalf("too many cache_control blocks: %d", n)
	}
}
