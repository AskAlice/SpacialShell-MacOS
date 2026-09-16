# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone. This
repo is `AskAlice/SpacialShell-MacOS`. It was previously `AskAlice/alice-material`; GitHub
redirects the old name, but do not write it — a redirected blob URL is not worth betting a PR's
images on.

## Repo-specific rules a ticket must carry

These are not optional extras — a ticket written without them produces work that cannot be merged
here. See `AGENTS.md` for the full statement of both.

- **The repo is private**, so media in issue and PR bodies must be linked as
  `https://github.com/AskAlice/SpacialShell-MacOS/blob/<branch>/docs/media/<file>?raw=true`, pointed at
  the PR's own branch. Never `raw.githubusercontent.com` (proxied anonymously, renders broken),
  never `data:` URIs (stripped by the sanitizer), never `?token=…` links (they expire).
- **Every PR needs inline UI screenshots and an animation**, including bug fixes, one-line tweaks,
  refactors and config defaults. The test is "is the affected thing visible?", never "is this a
  feature?". Where there is no visible surface, the observable effect stands in: a `spacialctl`
  transcript, a passing `swift test` run, a before/after of the tiling. Tickets should say so, so
  it is not discovered at review time.

## Conversation tracking

Nothing the user raises lives only in the conversation. Agreed with the user on 2026-09-14.

**What gets an issue:** every bug the user reports, every feature or design proposal, every rule or
invariant they state, and every bug you discover while working. A decision that changes a spec is a
comment on the issue it belongs to (plus the spec edit), not a new issue. A question becomes an issue
only once the user wants the work done.

**When:** in the same reply the thing comes up, including work you are fixing right now; the PR closes
it. Before ending a reply, check whether anything new was raised and file or update it.

**Keeping it current:** the body is always the current summary: the user's words quoted verbatim
under **Reported**, then cause, decisions, repro and acceptance criteria. Each new detail is a dated
comment, and the body is revised to match. Search open issues first (`gh issue list --search`) and
update rather than duplicate.

**No confirmation before filing.** End every reply that touches the tracker with
`Tracked: #n (new), #m (updated)`.

**Hierarchy:**

| Level | Representation |
|---|---|
| Milestone | GitHub milestone named after the M-series (`M2 — shell UI`, `M3a — trustworthy core`, …); its description states the goal |
| Epic | issue labelled `epic`, in a milestone: one outcome |
| Story | issue labelled `story`, "As a … I want … so that …" plus acceptance criteria; sub-issue of an epic |
| Task | issue labelled `task`: non-user-facing work (investigation, PR media, harness, docs); sub-issue of a story or epic |
| Bug | `bug`, sub-issue of the story or epic whose behaviour it breaks; directly in the milestone if none fits |

Link children with **GitHub sub-issues** (`gh api --method POST repos/AskAlice/SpacialShell-MacOS/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`, db id from `gh api repos/AskAlice/SpacialShell-MacOS/issues/<n> --jq .id`). Record ordering constraints with native dependencies (see Wayfinding → Blocking). Issue types are not available on this personal repo; the labels carry the level. Wayfinder maps stay as they are: `#26` is M4's planning epic.

**Labels for the user's own reports:** `ready-for-agent` when fully specified; `needs-info` when the cause is
unknown or design questions are open. `needs-triage` is only for requests from outside (see
`triage-labels.md`). Every issue also carries one category label: `bug`, `enhancement` or `documentation`.

**Working a milestone:** when several tickets in the current milestone are independent (no open
`blocked_by` between them, disjoint files or modules), hand them to parallel subagents, one ticket
each, in isolated worktrees, instead of working them one by one. Keep coupled tickets, and anything
touching the same files, sequential.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
