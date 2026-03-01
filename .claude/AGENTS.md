# Multi-Agent Protocols

## Session Lifecycle

### Session Start

1. Root CLAUDE.md is auto-loaded (project essentials)
2. Module CLAUDE.md is auto-loaded if working in a module directory
3. Read `.claude/INTENT.md` if making design decisions or trade-off calls
4. Read `.claude/CONVENTIONS.md` if writing or reviewing code
5. Check `git status` -- verify working tree is clean before starting
6. Read recent session logs in `.claude/session-logs/` for continuity

### During Session

- Mark tasks in TodoWrite as you work
- Run `swift build` after every file modification to catch errors early
- Run `swift test` in affected modules after completing a logical unit of work
- Update file headers (version + revision history) on every file touched

### Session End

1. `swift build` in all affected modules (verify no compilation errors)
2. `swift test` in all affected modules (verify no test regressions)
3. Update file headers for all changed files
4. Write session log to `.claude/session-logs/`
5. Commit if instructed (follow conventional commit format from CONVENTIONS.md)

## Session Logging

### Log File Naming

```
.claude/session-logs/YYYY-MM-DD_HHMM_description.md
```

Example: `2026-03-01_1430_create-session-document-model.md`

### Log Structure

```markdown
---
date: YYYY-MM-DD HH:MM
scope: [module name or feature area]
status: [completed | partial | blocked]
---

## Summary
[2-3 sentences: what was accomplished]

## Changes
- [file1.swift]: [what changed and why]
- [file2.swift]: [what changed and why]

## Decisions Made
- [Decision]: [Rationale, with reference to INTENT.md value if applicable]

## Open Questions
- [Question that needs human input before next session]

## Next Steps
- [Concrete action items for the next session to pick up]

## Test Results
- Module X: [N tests passed, M failed]
- Build status: [clean | warnings | errors]
```

### Log Retention
- Logs are committed to git alongside code changes
- Old logs (>30 days) may be archived or summarized at human discretion
- Never delete logs -- they are the project's memory

## Multi-Agent Safety

### File Ownership
- The Planner agent assigns non-overlapping file scopes to sub-agents
- A sub-agent must not modify files outside its assigned scope
- Shared files (CLAUDE.md, Package.swift) require Planner coordination

### Conflict Prevention
- Each sub-agent works on a separate feature branch when possible
- Never modify CLAUDE.md or `.claude/` files without Planner approval
- Run `swift build` after every file modification
- If a test fails that was passing before your changes, **stop and report**
- Do not "fix" failing tests by weakening assertions

### Planner Agent Responsibilities
1. Read all pending session logs before dispatching work
2. Verify git working tree is clean before starting
3. Assign non-overlapping file scopes to sub-agents
4. Validate sub-agent work before marking complete
5. Write integration session log with combined results
6. Ensure no two sub-agents touch the same file

## Verification Checkpoints

### Before Any Code Change
- [ ] Read the file being modified (Read tool, not assumptions)
- [ ] Check if the file's directory has a CLAUDE.md with local conventions
- [ ] Verify the change aligns with INTENT.md values and trade-off hierarchies
- [ ] Confirm the change is within your assigned scope

### After Code Changes
- [ ] `swift build` succeeds with no new warnings
- [ ] `swift test` passes in affected module
- [ ] File header version incremented with revision history entry
- [ ] All new public types have at least one test
- [ ] All new public types conform to Sendable

### Before Commit
- [ ] All verification checkpoints pass
- [ ] Session log written to `.claude/session-logs/`
- [ ] Commit message follows conventional format (see CONVENTIONS.md)
- [ ] No secrets, test data, or personal information in staged files
- [ ] Only explicitly requested files are staged (no `git add -A`)

## Progress Tracking

### For Multi-Step Tasks
Use TodoWrite to maintain a structured task list. Rules:
- Create the list at task start with all known steps
- Mark exactly one task as `in_progress` at a time
- Mark tasks `completed` immediately when done (don't batch)
- Add discovered sub-tasks as they emerge
- If blocked, keep the task as `in_progress` and note the blocker

### For Extended Implementations (multi-session)
Reference the plan file created during planning phase. Each session should:
1. Read the plan to understand overall progress
2. Identify which phase/step to work on next
3. Complete the step and verify
4. Update session log with what was accomplished
5. Note deviations from plan with rationale
