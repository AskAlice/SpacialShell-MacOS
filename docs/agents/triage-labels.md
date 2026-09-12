# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

## Category labels

Alongside the state label above, a ticket carries one category label:

| Role          | Label in our tracker | Meaning                     |
| ------------- | -------------------- | --------------------------- |
| `bug`         | `bug`                | Something isn't working     |
| `enhancement` | `enhancement`        | New feature or request      |

## Repo-specific notes

- `documentation` stands in for `enhancement` in the category slot when the deliverable is docs or
  media rather than code — the live-capture-media ticket, for instance.
- `wontfix` and the category labels pre-existed this triage setup; the five state labels were added
  for it.
- Tickets produced by `/to-tickets` are agent-ready by construction and are published straight to
  `ready-for-agent` — they do not pass through `needs-triage`. Triage is for requests that arrive
  from outside.
