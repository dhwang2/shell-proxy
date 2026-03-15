# Archive Rule — Auto-record after app/ changes

After completing a bugfix or feature update that modifies files under `app/`, automatically append records to both archive files before the conversation ends. Do NOT skip this step.

## When to trigger

- A bug in `app/` code was located and fixed.
- A feature or behavior under `app/` was added, changed, or removed.
- Menu, spinner, or module logic under `app/modules/` was updated.

## What to record

### 1. Checklist (`docs/dev/checklist.md`)

Append a new task entry under section `2.0`, after the last entry:

```markdown
- [x] **u-2-{N} {type}: {concise title} ({YYYY-MM-DD})**
  - [x] {what was done, one line per sub-item}
  - [x] Re-validated with `bash -n <file>` and bundle rebuild on target server.
```

- `{N}` = next sequential number after the last `u-2-*` entry.
- `{type}` = `bugfix`, `fix`, `refactor`, `feat`, `enhancement`, `update`, etc.
- Keep sub-items concise — one line each, no filler.

### 2. Workflow (`docs/dev/workflow.md`)

Append a matching execution record at the end:

```markdown
##### u-2-{N} {type}: {concise title} ({YYYY-MM-DD})
> **Target**: {one-sentence goal}

- **Investigation** (bugfix only):
  1. {details}

- **Fixes** / **Changes**:
  1. {what was changed and why}

- **Verification**:
  - {how the fix was confirmed}

- **Commit**: `{short SHA}` — `{commit message first line}`
```

- Omit the **Investigation** section for non-bugfix entries.
- Include **Commit** only after the commit is created.

## Rules

- Checklist and workflow entries must use the **same** `u-2-{N}` number, title, and date.
- English only. Title Case for titles, lowercase for body text.
- Do NOT add "Version Information" or "Main Modified Files" headers in the checklist — only in workflow.
- Follow the archiving guidelines in `docs/dev/checklist.md` §0.0.
- Place the new entry **after** the last existing entry (never before).
- Keep descriptions concise; avoid file-path lists or version info blocks.
- If the change is trivial (typo fix, comment-only), skip archiving.
