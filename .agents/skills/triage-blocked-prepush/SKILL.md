---
name: triage-blocked-prepush
description: Use when `git push` is blocked by a pre-push hook that runs a full test suite (Flutter `flutter test` in this repo), when pushes keep failing back-to-back, when tests fail only in the full-suite run but pass when their file is run alone, or when a fresh commit's own new tests fail the gate.
---

# Triage a Blocked pre-push Gate

## Overview

A blocked push is **not** a hook problem. The gate is doing its job; your job is to classify each failing case into exactly one bucket and fix it at the root. The gate can also **lie** — verify the gate before trusting the block.

**Never** `--no-verify`, weaken expected values, or delete a test to get green.

## Step 0 — Reproduce and list

Run the gate command yourself (`cd app && flutter test`). The hook prints a copy-pasteable failing list; take it verbatim.

## Step 1 — Classify every failure (exactly one bucket)

| Bucket | Signature | Root fix |
|---|---|---|
| **A. Stale assertion after a UI refactor** | Finder throws `No element` / a `findsNothing` breaks; the asserted surface was removed or renamed by the refactor | Re-point the finder/key at the **equivalent new surface**. Do **not** edit the asserted contract values (colors, sizes, thresolds) to force a pass |
| **B. Real production defect captured by a NEW test** | The failing assertion lives in a test file **created or edited in the commit you are pushing**, and it encodes intended behavior that production code violates | Fix **production code** at the source. Keep the new assertion byte-for-byte — a freshly added test that fails is the gate working, not a test bug. Never relax or rewrite the new expected value to green it |
| **C. Gate artifact / cross-test state pollution** | Passes alone, fails in the full run (or only under parallelism `-j`) | Find the shared singleton / global cache / temp file / prefs that leaks between files. Confirm with a single-file run |
| **D. Gate status logic bug** | Tests are all green but the hook still exits 1 | Fix the hook's **status extraction** (see Step 2) |
| **E. Push dies *after* a green gate** | The hook prints its success line, then `git push` exits **141** (SIGPIPE) or hangs, often with `Connection to <github-ip> closed by remote host`. Trivial/short hooks push fine | **Not a hook bug** — the gate's runtime idles out the SSH connection git opened first. Fix the *connection*, not the hook (see Trap 3) |

**Bucket A vs B is the trap.** Do not assume "the refactor broke the tests"; one new test can be the only thing catching a real regression. Check whether the production code or the test is the newer artifact, and whether the asserted behavior matches the product's stated semantics.

## Step 2 — The gate can lie (two traps)

**Trap 1: pipeline status.** A hook that does `set -o pipefail; if ! flutter test | tee log; then fail; fi` judges the **whole pipeline**, so a `tee` hiccup reports failure on a green suite. Extract only the test command's status:

```bash
set +e
flutter test 2>&1 | tee "$LOG_FILE"
TEST_STATUS=${PIPESTATUS[0]}   # the flutter test exit code, not tee's
set -e
[ "$TEST_STATUS" -eq 0 ] || fail_with_list
```

Make the hook report the failing list (`sed -n '/Failing tests:/,$p' | tail -n +2`) plus the log path instead of a bare exit 1.

**Repairing the status logic is NOT weakening the gate.** These are opposite actions:

| Action | Verdict |
|---|---|
| Fix `PIPESTATUS[0]` so a green suite stops reporting failure | **Repair** — required, the gate is lying |
| Delete/skip checks, add `\|\| true`, or `--no-verify` | **Bypass** — forbidden |

If you find yourself thinking "never touch the hook", you are about to leave a lying gate in place. Distinguish the gate's *truthfulness* (fixable bug) from its *checks* (sacred).

**Trap 2: dirty tree ≠ HEAD.** The hook tests the **working tree**, but `git push` ships **HEAD**. If they differ, a green run does not describe what you are pushing. Before claiming success, make the tested tree equal HEAD.

**Trap 3: a long gate can kill the push *after* it passes (exit 141 / hang).** For a push, git connects to the remote **first**, then runs `pre-push` (the hook is fed the remote's ref list). That SSH connection then sits **idle for the whole hook run**. With no keepalives (`ssh -G github.com` shows `serveraliveinterval 0`), the remote drops the idle connection (GitHub: ~10 min), and when the hook returns git sends the pack over a dead socket → **SIGPIPE, exit 141** (or a stall).

Diagnose it (fast, no suite needed): a hook that only `sleep 700` before `git lfs pre-push "$@"` reproduces 141 and prints `Connection to <ip> closed by remote host`. Confirm with `ssh -G github.com | grep -i serveraliveinterval`.

Fix the **connection**, not the hook: send keepalives.
```bash
ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=20 git@github.com   # verify
GIT_SSH_COMMAND="ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=20" git push origin main
```
Then persist it in `~/.ssh/config` under the host (or repo-local `git config core.sshCommand`) so future pushes need no prefix. Do **not** "fix" this by deleting/short-circuiting the gate — a 2-minute hook is normal; the missing keepalive is the bug.

## Step 3 — Verify

1. Failing files alone → green.
2. Full suite → green, on a tree that equals HEAD.
3. `lsp_diagnostics` clean on changed files; run analyze/lint if the repo has it.

## Red Flags — STOP

- Reaching for `--no-verify`, deleting the hook, or `exit 0` in it

- Editing an expected color/size/count to make a stale assertion pass

- "All 41 are just stale tests" without checking each one for bucket B

- Treating a failing **brand-new** test as "the test must be wrong" — that is bucket B; fix the code

- Refusing to repair the hook's status logic under a blanket "never touch the hook" — that leaves a lying gate

- Fixing tests while the gate's status logic is still broken (you will not see real results)

- Trusting a green run from a dirty tree as proof the pushed commit is green

- Calling exit 141 / a post-gate hang a "hook problem" and touching the hook — it's the SSH connection idling out (bucket E)

- Committing on the user's behalf (this repo: `不得自行 git commit`)

## Common Mistakes

| Mistake | Reality |
|---|---|
| "The hook is the bug, remove it" | The hook is a quality gate; the bug is the code/tests it caught |
| "Refactor moved the UI, so update all expectations" | Cheaper to mis-encode than fix; check bucket B first |
| "It passed when I ran that file alone, so it's flaky" | Consistent pass-alone/fail-together = deterministic state pollution, not flake |
| "CI-less local hook, so bypassing is harmless" | Bypassing ships the regression the gate exists to stop |

## Repo-specific anchors

- Gate source of truth: `tools/git-hooks/pre-push` (tracked), installed to `.git/hooks/` by `tools/install_git_hooks.sh`. A fresh clone must run the installer once, or there is no gate at all.
- This repo's `~/.ssh/config` now carries `ServerAliveInterval 30` / `ServerAliveCountMax 20` for `Host github.com` — added after a 10:38-min gate dropped the idle connection and killed an already-green push. Bucket E therefore shows up only on machines **without** that keepalive (fresh clone, another machine, or if the lines were removed). Check with `ssh -G github.com | grep -i serveraliveinterval`; expect `30`, and a bare `0` means bucket E is live again.
- Wallpaper/legibility tests read ink colors and card glass by refactored widget keys — the classic bucket A surface.
- `AppClock`-driven cross-day tests and audio-session singletons are the usual bucket C leakers.
