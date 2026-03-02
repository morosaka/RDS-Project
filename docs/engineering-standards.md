# Engineering Standards for AI-Assisted Development

**Purpose:** This document codifies the practices that govern how AI agents (and human developers) work on RowData Studio. It operates across three domains -- Context, Intent, and Specification -- that together form the project's engineering scaffolding.

**Audience:** Any autonomous agent, planner agent, or human contributor. This document should be read at the start of any significant planning or architectural session. It is not auto-loaded per conversation; it is referenced on-demand.

---

## 1. Context Engineering

Context Engineering is the practice of structuring project information so that AI agents receive exactly the right knowledge at the right time, with minimal token cost.

### 1.1 Principles

**Cascading context model.** Claude Code auto-loads `CLAUDE.md` files from the working directory upward. Information should live at the most specific level where it's needed:

| Level | File | Loaded when | Contains |
|-------|------|-------------|----------|
| Project root | `CLAUDE.md` | Every conversation | Identity, build commands, module map, architecture principles (one-line each), domain context, critical constraints |
| Module | `modules/*/CLAUDE.md` | Working in that module | Module architecture, key types, testing framework, known bugs, domain-specific knowledge |
| Governance | `.claude/INTENT.md` | Design decisions | Values, trade-offs, decisional boundaries |
| Governance | `.claude/CONVENTIONS.md` | Writing code | File headers, naming, testing patterns, deprecation protocol |
| Governance | `.claude/AGENTS.md` | Multi-agent coordination | Session lifecycle, logging, safety, verification checkpoints |
| Specifications | `docs/specs/*.md` | Implementing specific features | Algorithms, constants, data models, source references |
| Architecture | `docs/architecture/*.md` | Understanding system design | Full architectural context, proposals, design rationale |

**Token economy.** Every token in an auto-loaded file is a tax on every conversation. The root `CLAUDE.md` must stay under 150 lines. Move anything that only matters in specific contexts to the appropriate sub-document.

**Single source of truth.** Each fact lives in exactly one file. Other files point to it. If a sync pipeline constant appears in `CLAUDE.md` and also in `docs/specs/sync-pipeline.md`, one of them is wrong -- eliminate the duplication.

**Deducibility rule.** Do not document information that an agent can discover in under 3 tool calls. Source tree listings, Package.swift contents, and test counts are deducible. Architecture rationale, timing model pitfalls, and calibrated algorithm constants are not.

**Freshness.** Documentation must be treated as code: when you change behavior, update the corresponding document in the same session. Stale documentation is worse than missing documentation because it creates confident, wrong agents.

### 1.2 File Maintenance Rules

- **Root CLAUDE.md:** Only the project owner (human) or an agent with explicit approval may modify it. Changes must be reviewed.
- **Module CLAUDE.md:** The agent working on that module may update it to reflect new findings, but must log the change in the session log.
- **Governance files (.claude/):** Require explicit human approval for any modification.
- **Spec files (docs/specs/):** May be updated when implementing the specified algorithm, to correct errors found during implementation. Corrections must be logged.
- **Architecture files (docs/architecture/):** Append-only during active development. Architectural decisions already made should not be edited without discussion.

### 1.3 Anti-Patterns

- Repeating the tech stack in both `CLAUDE.md` and a design document (deducible from `Package.swift`)
- Embedding code examples in `CLAUDE.md` when the code exists in the actual source files
- Using CLAUDE.md as a changelog (that's what git history and session logs are for)
- Documenting aspirational features as if they exist ("the app supports X" when X is not yet built)
- Leaving stale test counts or module status descriptions (these drift first and mislead most)

---

## 2. Intent Engineering

Intent Engineering encodes organizational purpose into infrastructure that AI agents can act against. It sits above Context Engineering the way strategy sits above tactics.

### 2.1 Principles

**Explicit value hierarchy.** When an agent faces a trade-off, it must know which value wins. The hierarchy in `.claude/INTENT.md` is not a suggestion -- it is a binding constraint:

1. Correctness > Performance > API Elegance > Code Brevity
2. Working code > Beautiful code > Documented code
3. Test coverage > Feature completeness > Polish
4. Existing patterns > New patterns > External patterns
5. User safety (data integrity) > User convenience

**Decisional autonomy tiers.** Not every action needs human approval, and not every action should proceed without it. The three tiers (MAY / MUST-ASK / MUST-NEVER) create a clear boundary that enables autonomous work within safe limits. An agent that never asks is dangerous. An agent that asks about everything is useless. The tiers calibrate the balance.

**Scope discipline.** Build exactly what is requested. Do not add configuration points "in case we need them later." Do not prepare abstractions for post-MVP features. Do not refactor surrounding code while fixing a bug. Every addition has a maintenance cost; only pay it when there is a present need.

**Quality as a non-negotiable.** Quality standards (file headers, test coverage, Sendable conformance, source references for algorithms) are not aspirational -- they are acceptance criteria. Code that lacks them is incomplete, regardless of whether it compiles and passes tests.

### 2.2 Decision Records

When an agent makes a significant design decision (choosing between approaches, interpreting an ambiguous requirement, resolving a trade-off), it should record the decision in the session log using this format:

```text
**Decision:** [What was decided]
**Alternatives considered:** [What else was possible]
**Rationale:** [Why this choice, referencing INTENT.md values if applicable]
**Reversibility:** [Easy/Moderate/Hard to change later]
```

This creates an audit trail that helps future agents (and humans) understand why the codebase is shaped the way it is, not just what it contains.

### 2.3 Anti-Patterns

- Over-engineering "for the future" (violates simplicity value, costs maintenance now)
- Silently making architectural decisions without recording them (next agent will re-debate)
- Treating code conventions as optional when under time pressure (technical debt accrues faster than you think)
- Adding dependencies without approval (each dependency is a long-term commitment)
- Reducing test coverage "temporarily" (temporary reductions tend to become permanent)

---

## 3. Specification Engineering

Specification Engineering is the practice of writing documents that autonomous agents can execute against over extended time horizons without rework. It operates above Context and Intent: it ensures that everything we write is something an agent can act on.

### 3.1 Principles

**Executable precision.** A specification is only useful if an agent can read it and produce working code without asking clarifying questions. This means:

- Every algorithm includes all constants with their calibrated values
- Every data model includes all fields with their types
- Every pipeline specifies the order of operations and why it matters
- Every constraint includes the rationale (so the agent doesn't "optimize it away")

**Source traceability.** Every algorithm and constant must cite its source: the RDL file it was ported from, the paper it references, or the experiment that calibrated it. When an agent encounters a constant like `THRESHOLD = 0.15`, it must be able to trace it back to `services/sync/SignMatchStrategy.ts` and the real-world rowing data that validated it.

**Completeness over brevity.** In governance documents (INTENT.md, CONVENTIONS.md), brevity matters because they're loaded frequently. In spec files, completeness matters because they're loaded rarely and must be self-contained when loaded. An agent reading `sync-pipeline.md` should not need to also read the Kickoff Report.

**Verification built in.** Every spec should imply how to verify that the implementation is correct. Algorithm specs include expected outputs for known inputs. Data model specs include invariants. Pipeline specs include intermediate checkpoints where values can be validated.

### 3.2 Specification Anatomy

A well-formed specification contains:

1. **Status and provenance** -- Is this a canonical spec or a proposal? Where did it come from?
2. **Input and output** -- What goes in, what comes out, with types
3. **Algorithm** -- Step by step, with all constants and their calibrated values
4. **Constants table** -- Named, valued, with units and source reference
5. **Data models** -- Swift structs with all fields, types, and Codable/Sendable conformance
6. **Verification criteria** -- How to know the implementation is correct
7. **Source reference** -- RDL file path, paper citation, or experimental evidence

### 3.3 Session Protocol for Extended Work

When a Planner Agent dispatches sub-agents for multi-session implementation:

**Before dispatching:**

1. Read all pending session logs in `.claude/session-logs/`
2. Verify git working tree is clean
3. Identify the current phase in the implementation plan
4. Assign non-overlapping file scopes to sub-agents
5. Provide each sub-agent with: the relevant spec file(s), its file scope, and the verification criteria

**During each sub-agent session:**

1. Read assigned spec file(s) and module CLAUDE.md
2. Read CONVENTIONS.md before writing code
3. Read INTENT.md before making any design decision
4. Implement, building after every file change
5. Test after completing each logical unit
6. Write session log before ending

**After all sub-agents complete:**

1. Planner reads all session logs
2. Runs integration build and tests across all affected modules
3. Checks for file ownership violations (did sub-agents stay in scope?)
4. Writes integration session log
5. Identifies next phase

### 3.4 Progress Tracking

**Session logs** (`.claude/session-logs/`) are the project's institutional memory across agent sessions. They answer:

- What was done in each session?
- What decisions were made, and why?
- What is blocked or needs human input?
- What should the next session pick up?

**Plan files** (`/Users/[user]/.claude/plans/`) are generated during planning phases and describe the full implementation strategy. Session logs track progress against the plan.

**TodoWrite** tracks intra-session task progress. It is ephemeral (resets per conversation) and is for the agent's own organization, not for cross-session continuity.

### 3.5 Anti-Patterns

- Specifications that describe "what" without "how" (useless for autonomous execution)
- Specs that embed calibrated constants without source references (next agent might "improve" them)
- Plans that assign overlapping file scopes to different agents (guaranteed merge conflicts)
- Sessions that skip the session log (breaks continuity for the next agent)
- Implementing first, documenting later (the spec should precede the code, not follow it)
- Leaving verification criteria implicit ("it should work" is not a criterion)

---

## 4. Cross-Cutting Practices

### 4.1 The Hierarchy

```text
Specification (what to build, how, verified)
    |
    +-- Intent (why, trade-offs, boundaries)
            |
            +-- Context (where, with what, navigating the codebase)
```

Intent governs Context: the value hierarchy determines what goes in CLAUDE.md (critical constraints that affect correctness and data integrity go in; convenience features don't).

Specification governs Intent: when a spec says "complementary filter alpha = 0.999", the Intent value of "correctness > performance" means you do NOT change that constant for performance without re-validating on real data, even if profiling suggests it would be faster.

### 4.2 Document Lifecycle

| Phase | What happens |
|-------|-------------|
| **Planning** | Create or update spec in `docs/specs/` with algorithm, constants, models, verification criteria |
| **Implementation** | Read spec. Write code. If spec has errors, correct the spec AND log the correction |
| **Verification** | Run tests, check against spec's verification criteria, update session log |
| **Maintenance** | When changing behavior, update the spec in the same commit. Never let code and spec diverge |

### 4.3 When to Update What

| Event | Update |
|-------|--------|
| New module created | Root CLAUDE.md (module map), new module CLAUDE.md |
| New algorithm implemented | `docs/specs/` (new or existing spec file) |
| Convention changed | `.claude/CONVENTIONS.md` |
| New trade-off principle discovered | `.claude/INTENT.md` (requires human approval) |
| Bug found in production data | Module CLAUDE.md (camera-specific notes, known issues) |
| Session completed | `.claude/session-logs/` (always) |
| Factual error found in any doc | Fix immediately, log in session |

### 4.4 Quality Gates

Before any code is considered complete:

- [ ] Compiles cleanly (`swift build`, no warnings)
- [ ] Tests pass (`swift test` in affected module)
- [ ] File headers updated (version incremented, revision history entry)
- [ ] New public types have tests
- [ ] New public types conform to Sendable
- [ ] Algorithm implementations cite their source
- [ ] Session log written
- [ ] No TODOs, stubs, or fatalError() in production code

These gates apply to every session, every agent, every change. They are not optional.
