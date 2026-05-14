# Changelog

All notable changes to this project are documented here. Format adapted from [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [SemVer](https://semver.org/).

## [unreleased]

### 🚀 Features

- *(jarvis/task)* Implement --jira merge for task list
- *(jarvis/doctor)* Per-integration enablement reasons
- *(jarvis/standup)* Cron-meet-cal helper for --join URL extraction
- *(jarvis/notify)* Email channel via mail / sendmail
- *(jarvis/ndjson-parity)* Add bats sanity test suite for NDJSON corpus
- *(jarvis/ndjson-parity)* Add Python oracle + ASCII baseline fixtures (01-05)
- *(jarvis/ndjson-parity)* Add remaining 45 fixtures + full golden corpus
- *(jarvis/ndjson-parity)* Add ndjson-contract.md documenting encoding rules
- *(jarvis/build)* Native helper build pipeline (Taskfile + scripts + skeletons)
- *(jarvis/native)* Protocol-version pin checker for native binaries
- *(jarvis/when)* Jarvis-when Python helper for natural-language datetime
- *(jarvis/cal)* Jarvis-cal Rust helper for ICS + gcalcli → NDJSON
- *(jarvis/state)* Jarvis-state Go helper for typed JSON store + frontmatter
- *(jarvis/native)* Clock.sh wrapper consolidates date helpers around jarvis-when
- *(jarvis/doctor)* --reap-focus-orphans flag (drains P3-design)
- *(jarvis/remind)* Dryrun <slug> subcommand (drains S1)
- *(setup)* Clift init --from PATH replaces clift import
- *(setup)* Drain init --from follow-ups (router, portability, namespace)
- *(setup)* Surface task-scoped vars caveats after init --from
- *(jarvis/calendar)* Applescript provider for Calendar.app via osascript
- *(version)* Bump/check/sync — close the release loop
- *(examples/bm)* Bookmark manager — small end-to-end clift example
- *(version)* List — enumerate available versions of the CLI

### 🐛 Bug Fixes

- *(jarvis/state)* Persistent --profile flag honored across all cmds
- *(jarvis/ndjson-parity)* Resolve fixture paths via examples/jarvis/ root
- *(jarvis/cache,calendar)* Drain T1-W2, T1-W3, T2-W2 from known-bugs
- *(jarvis/calendar)* AS-S4/S5 — warn on silent calendars-filter / extract_url_from drift

### 📚 Documentation

- *(jarvis)* Document .env vs config.toml boundary
- *(jarvis)* VHS tapes for the 9 jarvis cmds
- Rewrite Example + Error UX around bm; reference tj-smith47/jarvis

### 🧪 Testing

- *(jarvis/build)* TDD red — idempotent build + selective rebuild assertions
- *(jarvis/build)* Rewrite idempotent test against binary mtimes
- *(jarvis/ndjson-parity)* D2 cross-encoder gate (Python ↔ Rust ↔ Go)
- *(jarvis/native)* Pre-build binaries before HOME redirect
- *(bm)* 11 bats tests covering framework feature surface end-to-end
- *(tripwire)* Real-$HOME mutation guard
- Migrate 18 bats files to common_setup/common_teardown

### ⚙️ Miscellaneous Tasks

- Scrub phase / task-id markers from committed source
- *(jarvis)* Ignore python __pycache__/ + drop accidentally-committed .pyc
- Drop in-tree jarvis example (extracted to tj-smith47/jarvis)
- *(vhs)* Re-record demo gifs against current bm tapes
## [jarvis-p6] - 2026-04-27

### 🚀 Features

- *(jarvis/doctor)* --integrations-live flag (P6 T2)
- *(jarvis/brief)* Pluralize counts + secondary oncall in --short (P6 T3)

### 🐛 Bug Fixes

- *(jarvis/status)* Wire minutes_today through focus_stats_today_minutes (P6 T1)

### 📚 Documentation

- *(jarvis)* Add application-level CLAUDE.md (P6 T4)
- *(jarvis)* Explain jira stderr suppressions; rename status test (P6 T5)
## [jarvis-p5] - 2026-04-27

### 🚀 Features

- *(jarvis/cache)* TTL-based file cache for integration layer (P5 T1)
- *(jarvis/calendar)* Dispatcher + none provider with 300s cache (P5 T2)
- *(jarvis/calendar)* Gcalcli provider — TSV agenda → NDJSON (P5 T3)
- *(jarvis/calendar)* ICS provider (URL or file) + outlook-ics alias (P5 T4)
- *(jarvis/calendar)* Meeting URL extractor for zoom/meet/teams (P5 T5)
- *(jarvis/integrations)* Gh PR queries (review-requested + authored) (P5 T6)
- *(jarvis/integrations)* Jira in-flight + my-comments-since (P5 T7)
- *(jarvis/integrations)* Deploys.log tail (P5 T8)
- *(jarvis/integrations)* Oncall reader (config-only) (P5 T9)
- *(jarvis/status)* Real data + frozen --json golden fixture (P5 T10)
- *(jarvis/brief)* Real-data sections + --short snapshot (P5 T11)
- *(jarvis/standup)* Yesterday/today/blockers from real data (P5 T12)
- *(jarvis/standup)* --join opens next standup meeting (P5 T13)
- *(jarvis/doctor)* Integrations rollup — calendar/gh/jira/gcalcli (P5 T14)

### 🐛 Bug Fixes

- *(jarvis/cache)* Randomize tmp suffix to avoid same-PID collision (P5 T1 review)
- *(jarvis/cache)* Preserve trailing newline; calendar polish (P5 T1+T2 review)
- *(jarvis/calendar)* JSON-escape gcalcli titles + URLs; surface gcalcli stderr (P5 T3 review)
- *(jarvis/calendar)* ICS TZID skip, parameterized field regex, RFC 5545 unfolding (P5 T4 review)
- *(jarvis)* Drop set -e leak in cache lib; collapse status jira double-call; dedupe doctor jira probe (P5 final review)
## [jarvis-p4] - 2026-04-26

### 🚀 Features

- *(jarvis/remind)* Parsers for --in / --at / --repeat (P4 T1)
- *(jarvis/remind)* Pure next_trigger covering interval + anchored + DST seam (P4 T2)
- *(jarvis/remind)* Schema + delivery NDJSON + config_get profile arg (P4 T3)
- *(jarvis/notify)* Registry + local channel + shared shim helper (P4 T4)
- *(jarvis/notify)* Gotify channel (registered + profile-threaded) (P4 T5)
- *(jarvis/notify)* Slack channel (registered + profile-threaded) (P4 T6)
- *(jarvis/notify)* Dispatch fan-out via registry + profile-threaded (P4 T7)
- *(jarvis/remind)* Tick one-shot path with per-profile flock + delivery NDJSON (P4 T8)
- *(jarvis/remind)* Tick recurring + multi-profile (no env mutation) (P4 T9)
- *(jarvis/remind)* Rewrite remind to persist JSON (one-shot + recurring) (P4 T10)
- *(jarvis/remind)* List command + Taskfile schema for new flags (P4 T11 + T10 fix)
- *(jarvis/remind)* Cancel <slug> with did-you-mean (P4 T12)
- *(jarvis/remind)* Tick subcommand + e2e roundtrip (P4 T13)
- *(jarvis/remind)* Install/uninstall cron backend (P4 T14)
- *(jarvis/remind)* Systemd backend for install/uninstall (P4 T15)
- *(jarvis/doctor)* Surface reminder counts + scheduler install status (P4 T16)

### 🐛 Bug Fixes

- *(jarvis/remind)* Guard parse helpers against silent empty-result (P4 T1 cleanup)
## [jarvis-p3] - 2026-04-25

### 🚀 Features

- *(jarvis)* P3 — focus log + stats (NDJSON, EXIT trap, doctor orphan check)
## [jarvis-p2] - 2026-04-25

### 🚀 Features

- *(jarvis)* Add frontmatter lib (parse/emit/get/set/merge)
- *(jarvis/note)* Add resolver (slug/title/prefix/explicit kind)
- *(jarvis/note)* Add store + incremental index (create/append/archive)
- *(jarvis/note)* Ship daily/meeting/1on1/postmortem templates
- *(jarvis/note)* Wire default capture (create-or-append, --on, current routing)
- *(jarvis/note)* Add 'note new' explicit creator with template support
- *(jarvis/note)* Add 'note daily' with create-or-append matrix
- *(jarvis/note)* Add meeting + project template shortcuts
- *(jarvis/note)* Add 'note list' (grouped + --json/--yaml + filters)
- *(jarvis/note)* Add show + edit with current-fallback
- *(jarvis/note)* Add 'note search' (rg --json + index post-filter)
- *(jarvis/note)* Add tag +/- mutator and bidirectional link
- *(jarvis/note)* Add 'note archive' soft-delete + resolver archive-hide fix
- *(jarvis/note)* Add 'note current' active-note layer
- *(jarvis/note)* Dynamic positional + --on completers from .index.json
- *(jarvis/doctor)* Wire --rebuild-index to note_index_rebuild

### 🐛 Bug Fixes

- *(jarvis)* Frontmatter correctness — typed scalars, falsy values, body newline, override-only keys
- *(jarvis/note)* Unicode-consistent folding + tier-precedence tests
- *(jarvis/note)* Safe key injection path, fm_get array-vs-object, slug collision
- *(jarvis/note)* Surface --on ambiguity, tolerate create-race, use current_resolve
- *(jarvis/note)* Atomic-rename on note_store_new (real concurrent safety)
- *(flags/compile)* Pre-export .env values; go-task 3.x doesn't expose dotenv as vars
- *(completion)* Cache-aware task-path resolution unblocks pos2+
- *(jarvis/slug)* Reject 1-letter Jira project keys; assert stderr stream
- *(jarvis/store)* Slug guard, corrupt-record skip, jq-validate read, tmp-sidecar nullglob
- *(jarvis/lock,store,test)* Subshell isolation, seq-gap doc, env-var run_add
- *(log)* Unify log_info/log_success stream — all log_* go to stderr
- *(jarvis/task list)* Preserve nullglob, normalize null-project, pin --yaml/--jira

### 🚜 Refactor

- *(jarvis)* Shared standalone argv helper; drain note.add.sh inline parser

### 🧪 Testing

- *(jarvis/state)* Pin state_json_mutate --arg metachar safety invariant

### ⚙️ Miscellaneous Tasks

- *(jarvis)* Close P2 (note CRUD + frontmatter + current layer)
## [jarvis-p1] - 2026-04-20

### 🚀 Features

- *(completion)* Dispatch positional slots via clift_complete_<task>_pos<N>
- *(jarvis)* Add slug library (generate, jira-key, collide, prefix)
- *(jarvis)* Add task store — schema, CRUD, seq, list
- *(jarvis/task)* Persist add to tasks/<slug>.json with slug + seq
- *(jarvis/task)* List from store with filters and json/yaml output
- *(jarvis/task)* Done resolves slug prefix, shells jira move on JIRA-KEY
- *(jarvis/task)* Add remove with slug-prefix resolver and lock cleanup
- *(jarvis/task)* Add edit with per-field flag validation and jq mutate
- *(jarvis/task)* Dynamic positional completers for done/edit/remove

### 🐛 Bug Fixes

- *(jarvis/state)* Add atomic state_json_mutate, harden tmp-name against PID collisions
- *(jarvis/task)* List skips malformed JSON, honors NO_COLOR, dynamic width
- *(jarvis/task)* Don't exec jira so command_post override hook fires

### 🚜 Refactor

- *(jarvis/slug)* Sort ambiguous-match candidates alphabetically
- *(jarvis)* Cap slug length at 100 chars, validate before ensure_tree

### 📚 Documentation

- *(completion)* Narrow positional completer to pos1, flag pos2+ as known limitation

### 🧪 Testing

- *(jarvis/task)* Pin add/list/done/edit/remove round-trip

### ⚙️ Miscellaneous Tasks

- *(jarvis)* Close P1 (task CRUD + slug + positional completion)
## [jarvis-p0] - 2026-04-20

### 🚀 Features

- Initialize project skeleton with directory structure
- Add dependency checker for jq (hard) and gum (soft)
- Add themed logging system with 6 built-in themes and custom support
- Add prompt system with gum/read fallback and PROMPT=false support
- Add argument parser with flag, boolean, and positional support
- Add router with help redirect and command script dispatch
- Add help system with list and detail modes via jq
- Add log Taskfile wrapper with dedicated script
- Add templates for CLI bootstrap and command scaffolding
- Add command scaffolder with prompt-driven creation
- Add config commands for show, log-theme, and edit
- Add setup:cli task for bootstrapping new CLIs
- Add framework metadata file
- Complete framework with batteries, bug fixes, tests, and docs
- Add cfgd integration and version management system
- *(flags)* Add schema validator
- *(flags)* Add levenshtein distance helper
- *(flags)* Add error rendering helpers with did-you-mean
- *(flags)* Add precompilation cache builder
- *(flags)* Add argparser consuming precompiled tables
- *(wrapper)* Add standard-mode wrapper template
- *(router)* Integrate precompiled flag parser and dual-mode argv
- *(setup)* Add sentinel-based rc file helpers
- *(setup)* Add CLIFT_MODE branching and mode-switch scrubbing
- *(templates)* Add FLAGS stubs and CLIFT_* env var contract
- *(scaffold)* Validate names, one-script-per-task, refresh cache
- *(help)* Render flag sections from precompiled cache
- *(completion)* Add standard-mode completion generator
- *(flags)* Add env-var collision check and short-alias shadowing warning
- *(log)* Add LOG_CLR_* color scheme overrides, document Dracula + Catppuccin examples
- 12 bug fixes, bin/clift, examples/kube, 335 tests (224→335), 78% coverage
- VHS demos, coverage badge, test quality review (349 tests, 82% coverage)
- Clift import — wrap existing go-task tasks as clift commands
- *(kube example)* Replace cluster demo with restart — wraps kubectl
- *(flags)* Support flag aliases via 'aliases: [..]'
- *(flags)* Warn on use of deprecated: flags + mark in help
- *(cache)* Consolidate compile cache into index.json; add hidden: flags/commands
- *(flags)* Exclusive and required-together flag groups
- *(flags)* PERSISTENT_FLAGS at root Taskfile for cross-command flags
- *(flags)* Value validation via choices: and pattern: fields
- *(runtime)* Auto-load log helpers via prelude — no BASH_ENV
- *(flags)* Expose parsed flags via CLIFT_FLAGS assoc array (dash-preserving)
- *(runtime)* Override loader foundation (per-cmd + CLI-global tiers)
- *(overrides)* Help_list + help_detail slots with wrap/replace semantics
- *(overrides)* Version_print slot for --version / version subcommand
- *(overrides)* Log.sh slot via function shadowing (perf-motivated exception)
- *(overrides)* Command_pre and command_post slots (Task 3.5)
- *(log)* Clift_exit helper (Task 3.6)
- *(cache)* --no-cache flag + CLIFT_CACHE=rebuild|bypass (Task 4.1)
- *(cache)* Warn on unrecognized CLIFT_CACHE values
- *(wrapper)* --task:* passthrough for go-task runner flags (Task 4.3)
- *(wrapper)* Mycli watch <cmd> alias for --task:watch (Task 4.2)
- *(aliases)* Wire command aliases into dispatch, help, completion (Task 5.1)
- *(wrapper)* Rewrite `mycli help <cmd>` to `mycli <cmd> --help` (Task 6.0)
- *(help)* Completion install hint in --help footer (Task 5.4)
- *(setup)* Install shell completion during setup:cli (Task 5.3)
- *(completion)* Dynamic flag-value completers, convention-only (Task 5.5)
- *(aliases)* Nested-alias dispatch + framework-lib dogfood (Task 6.3)
- *(jarvis/state)* Add profile path resolver + dir-tree ensurer
- *(jarvis/state)* Add flock wrapper for JSON state writes
- *(jarvis/state)* Add atomic JSON read/write with jq validation
- *(jarvis/state)* Add TOML config loader via dasel
- *(jarvis)* Add doctor skeleton (profile + schema + binary probes)

### 🐛 Bug Fixes

- Resolve command help namespace issue by calling detail.sh directly
- Add shell quoting, set -euo pipefail in template, fix subcommand CLI_NAME
- Rename config:log-theme to config:theme (no dashes in task names)
- Revert deps.sh to simple hardcoded checks, keep .task-cli.yaml informational
- Address remaining spec gaps for release readiness
- *(flags)* Address validator review findings (colon task names, scalability, reserved names)
- Address review findings for tasks 11-14
- Address review findings for cache.sh
- *(parser)* Short-flag list accumulation + runtime comma splitting
- Replace GNU-only sed -i with portable temp-file-and-move
- Address review findings for parser.sh
- *(setup)* Preserve CLIFT_MODE during reconfigure when not explicitly given
- *(wrapper)* Handle -V at top level, fix empty-array expansion for bash < 4.4
- Guard remaining third empty-array expansion in wrapper for bash < 4.4
- Improve error messages — cluster layer, script paths, fallback debug log
- *(ux)* Mode-aware help footer, setup hints, wrapper jq check
- *(completion)* Standard-mode multi-level completion with space-separated subcommands
- Rc.sh preserves file permissions and prevents blank line accumulation
- Address code review findings — comment typo + empty-array guard
- Comprehensive audit — bugs, perf, portability, security, DRY, docs
- Eliminate hardcoded Taskfile globs, merge jq forks, document flag ordering
- *(ci)* Suppress SC2046 in cache.sh, remove redundant FRAMEWORK_DIR re-export in setup.sh
- --help for all commands, subcommand listing, Task stderr suppression
- Intercept --verbose/--quiet/--no-color in wrapper for all commands
- Gate module.yaml + CI workflow on opt-in flags, fix RC path portability
- Top-level --help lists groups, not every subcommand; +14 tests
- Add summaries to framework commands so --help renders detail
- Silence task runner output across demos + tests, ship hero demo
- *(flags)* Tighten group validation and error phrasing (review follow-up)
- *(flags)* Persistent -- terminator + review polish (C1/C2/I1/I3/minors/suggestions)
- *(flags)* Tighten value validation error phrasing + lock invariants (review follow-up)
- *(runtime)* Rename internal log symbols + lock shell-option semantics (review follow-up)
- *(runtime)* Enforce bash 4.2 floor + tighten CLIFT_FLAGS lifecycle (review follow-up)
- *(runtime)* Harden override loader — guards, validation, internal API (review follow-up)
- *(overrides)* Capture command_pre exit code via || (if ! negates $?)
- *(overrides)* Capture command_pre exit code on passthrough path too
- *(overrides)* Contain command_post via subshell (exit N escape)
- *(overrides)* Capture SIGINT/SIGTERM rc in post-hook (was 0)
- *(log)* Sync clift_exit references across scaffold + overrides docs
- *(cache)* Bypass short-circuit dispatches to go-task when cache absent
- *(flags)* Reject inline values on bool flags
- *(help)* Detail view merges globals.json so older CLIs see new globals
- *(wrapper)* Preserve --task:* flags through mycli watch re-exec
- *(aliases)* Reject duplicate alias across commands at compile time
- *(aliases)* Drop self-referential bare-namespace aliases from candidate sets
- *(completion)* Filter aliases of hidden commands
- *(aliases)* Drop alias-vs-command shadowed names from user_aliases
- *(router)* Expose persistent flags in CLIFT_FLAGS on passthrough path
- *(router,parser)* Stop leaking CLIFT_FLAGS_FILE on --help/--version
- *(runtime)* Rename _clift_user_rc to __CLIFT_USER_RC to dodge shadowing
- *(wrapper)* Hoist _complete dispatch above clift_ensure_cache
- *(compile)* Reject reserved top-level command/alias names
- *(wrapper)* Defer watch rewrite when index.json claims a 'watch' task
- *(runtime)* Surface suppressed command_post override failures at debug
- *(scripts)* Detect GNU date / gdate in benchmark.sh, fail loud on BSD date (S2)
- *(help)* Load the log-slot shadow in detail.sh / list.sh
- *(jarvis)* Probe dasel via subcommand, document flock eval suppression

### 💼 Other

- *(jarvis)* Replace kube with a personal-ops concierge CLI

### 🚜 Refactor

- Rename task-cli → clift
- *(tests)* Extract common_setup, create_test_cli, build_test_wrapper helpers
- Extract shared portable cache.sh, eliminate find -printf
- Single source of truth for framework globals in globals.json
- *(help)* Extract shared flag rendering into render_flags.sh
- Rename legacy → passthrough for commands without FLAGS
- *(help)* Convention polish — cat→read, hoist helper, idempotent _LIB_DIR
- *(overrides)* Hoist version_print default to shared location + router comment
- *(router)* Hoist overrides.sh source + extract pre-hook helper
- *(router)* Rename is_passthrough_no_cache to no_root_taskfile
- *(tests)* Extract _assert_rebuilt / _assert_not_rebuilt helpers
- *(cache,router)* Tighten post-review comments and fw_dir usage
- *(aliases)* Precompute user_aliases per task in index.json
- *(wrapper)* Cosmetic cleanups and root_cmds derivation
- *(aliases)* Collapse jq if-elif and stream-comma flatten
- *(completion,test)* Drop dead `// []` defaults and tighten alias regex
- *(wrapper)* Gate --no-cache scan behind argv-presence fast-path
- *(lib)* Standardize source-guard form across all sourced modules
- *(validate)* Collapse regex syntax check to a single subshell
- *(help)* Share alias-filter jq fragment across compile.sh and detail.sh
- *(tests)* Promote _setup_parity_cli to test_helper.bash (Pending #2)
- *(perf,dry)* Drain pre-push audit perf + dedup findings
- *(overrides)* Cache declare -F probe per slot (P6)
- *(jarvis)* Remove hidden debug command (replaced by doctor)

### 📚 Documentation

- Add guides for modes, flags, scripts, errors, cache, architecture
- Explain bash < 4.4 empty-array idiom in wrapper
- Rewrite for standard mode, fix all audit findings, fix CI shellcheck
- Remove migration language from scripts.md
- Show multi-language script extensions in README directory tree
- Show multi-language script extensions in README directory tree
- Center title, add ToC, reorganize README sections
- Center title/subtitle, add table of contents
- Reorder README — Features up, Modes after How It Works
- *(cli)* Surface list flags + go-task features in templates, docs, tests
- *(cli)* Fix template copy-paste footgun + sharpen go-task feature notes
- *(overrides)* Clarify log slot tier depth + defs-only contract; expand test symmetry
- *(overrides)* Timing recipe uses date +%s (bash 4.2 compatible)
- *(overrides)* Note user INT/TERM traps bypass post-hook rc capture
- *(log)* Clarify die vs clift_exit decision rule
- *(log)* Align example helper list with auto-loaded bullet
- *(cache)* Clarify flag > env precedence + unknown-value warning
- *(router)* Comment dual bypass guard
- Surface Phase 1-5 capabilities in README + doc index (Task 6.1)
- *(readme)* Trim Features list to meet 16-bullet ceiling (Task 6.1 follow-up)
- *(readme)* Split typed-flag bullet, add hidden commands, refine Features (Task 6.1 follow-up)
- *(readme)* Expand Shell Completions section, repair TOC, add cache cross-link (Task 6.1 follow-up)
- *(index)* Harmonize flag capability order, note hidden commands, tier precedence (Task 6.1 follow-up)
- *(readme)* Correct install-hint description to match unconditional render (Task 6.1 follow-up)
- *(flags)* Add dedicated Groups section + schema rows for group/exclusive/requires
- *(overrides)* Caveat command_pre/command_post on passthrough + abort example (I5/S5)
- Drain pre-push audit docs findings (DOC1-DOC10)
- *(demos)* Uplift VHS demos for Phase 1-6 UX; rework README layout

### ⚡ Performance

- *(errors)* Inline levenshtein, add >200 candidate bailout
- *(parser)* Pre-build bash lookup tables, eliminate per-flag jq forks
- *(compile)* Accumulate flags.json in memory, add temp file cleanup trap
- *(help)* Read from .clift/ cache instead of live task/yq calls
- *(parser)* Eliminate _clift_var_name subshell forks
- *(parser)* Batch defaults extraction into single jq call
- Skip duplicate cache check when wrapper already verified
- *(router)* Replace legacy-check jq call with string match
- *(wrapper)* O(1) task prefix lookup via associative arrays
- *(wrapper)* Eliminate subshell forks for IFS colon join
- *(compile)* Batch task-row extraction into single jq call
- *(compile)* Replace O(N²) flags_entries accumulation with temp file
- Defer version checks to compile-time, keep fast deps check in router
- *(help)* Batch jq calls in detail.sh
- *(wrapper)* Batch startup jq calls into single invocation
- *(cache)* Batch stat calls in clift_max_mtime
- *(compile)* Source validate.sh instead of forking bash per-Taskfile
- *(compile)* Combine merge + shadow_check into single jq call
- *(overrides)* Cache per-segment + global override-dir probes
- *(bench)* Attribute overhead per-stage, add cold-vs-warm comparison (Task 6.4)
- *(parser)* Pre-sort validation names in init jq batch, drop runtime sort fork

### 🧪 Testing

- Isolate HOME in test_helper.bash so setup.sh tests can't pollute real .bashrc
- Derive FRAMEWORK_DIR dynamically in per-file test setups
- Pin standard-mode argv quoting round-trip
- Add end-to-end standard mode smoke test
- *(overrides)* Lock CLIFT_TASK+CLIFT_FLAG visibility in command_pre
- *(overrides)* Wrap pattern + passthrough post + nested-tier negative
- *(log)* Cover clift_exit edge cases (empty msg + non-numeric code)
- *(cache)* Add precedence + concurrent + position + reserved-name coverage
- *(aliases)* Cover dispatch, help, completion, did-you-mean (Task 5.1)
- *(aliases)* Tighten assertions and cover edge cases
- *(integration)* Cobra-parity multi-feature seam (Task 6.2)
- *(integration)* Address 6.2 code-review findings (6.2 follow-up)
- *(integration)* Tighten latent assertions (6.2 follow-up)
- *(integration)* Add cobra-parity seam coverage for S3
- *(jarvis)* Add shared test helper + state lib dir

### ⚙️ Miscellaneous Tasks

- Re-record VHS demos — taller canvas, slower pacing, deeper help tour
- Add coverage job that publishes badge to badges branch
- *(flags)* Printf for deprecated warn, add list-flag dedup test
- *(cache)* Fix stale comment + replace sed -i in cache_index tests
- *(flags)* Annotate load-bearing subshells in regex-validation path
- *(review)* Drain minor branch-review findings (M2/M3/M7/M8/M9)
