# Embedded vs external: the reconciliation plan (2026-08-09)

Status: PROPOSED — written overnight after the v0.5.0 downstream sweep, for
review before the modem fleet goes live. Nothing here is implemented yet.

## Thesis

The product family now has two legitimate deployment methodologies, and both
stay:

| | **Embedded** (timeless_phoenix's product) | **External** (timeless_stack's product) |
|---|---|---|
| Owner of each signal DB | the host BEAM process | one Rust server per signal (`timeless-*-api`) |
| Pitch | "no external infrastructure required" | production data plane, bounded admission, capability handshake |
| Storage engines | metrics `:rust` (pinned here) or `:libsql`; logs/traces Elixir block stores | timeless-libsql extension only, via the Rust owners |
| Right for | single-node apps, demos, small installs | the Stack, the modem fleet, anything multi-service |

The failure mode is not either methodology — it is a node where BOTH think
they own the same signal. That must become impossible **by construction**,
not by luck. Today it is worse than luck: `TimelessPhoenix.Supervisor`
actively *converts* an external host into an embedded one:

- `supervisor.ex:54-56,70-72` unconditionally `Application.put_env`s
  `:timeless_logs`/`:timeless_traces` `data_dir` (and more), ignoring any
  `owner: :external` the host configured.
- `supervisor.ex:132-142` (`ensure_app/1`) then `Application.stop` +
  `ensure_all_started` — deliberately bouncing the signal apps so its env
  wins. An external-owner host that adds TimelessPhoenix gets embedded
  writers pointed at TimelessPhoenix's data_dir. If that dir is (or ever
  becomes) Rust-owned: two writers.
- The installer's default HTTP ports (8428/9428/10428,
  `timeless_phoenix.install.ex:85-98`) are byte-identical to the Stack's
  production Rust server ports (`timeless_stack/config/config.exs`). On a
  Stack host, `--http` either EADDRINUSEs or steals the Rust ports.
- `<data_dir>/spans` here vs `/data/traces` on the Stack side: pointing both
  at one root silently yields two disjoint trace stores.
- OTel exporter + logger handler + dashboard reporter (`supervisor.ex:77-84,
  125`) mean a host that also ships to Rust APIs double-ingests.

## Phase 0 — Guardrails (small; before real data, ~half day)

1. **Respect the host's owner config; never bounce an external app.**
   `ensure_app/1` becomes conditional: if the host's app env (or the
   caller's `:timeless_logs`/`:timeless_traces` keywords) says
   `owner: :external`, TimelessPhoenix must NOT put_env data_dirs for that
   signal, NOT restart the app, and NOT start the corresponding embedded
   pieces — fail loudly if the caller's options are contradictory
   (e.g. explicit `data_dir` for a signal marked external). Same principle
   for metrics: thread an `owner:`/enable flag through the `:timeless`
   keyword so a host can run dashboards-only against an external plane.
2. **Refuse Rust-owned directories.** Before starting any embedded store,
   check the target dir for the external-owner markers the signal libraries
   already write (`_timeless_cutover` / owner tables from ReleaseStartup)
   and refuse with a message naming both owners. The libraries' own
   ambiguous-dual-store detection is the backstop; this makes the refusal
   happen at the TimelessPhoenix boundary with a better error.
3. **Change the installer's default ports** off 8428/9428/10428 (or default
   `--http` endpoints to *off* with docs). Breaking for new installs only;
   existing hosts configured explicit ports are unaffected.
4. **Repo hygiene per the git/dependency policy (2026-08-09):**
   - Track `mix.lock` (remove from .gitignore) — a library CAN commit its
     lock for CI reproducibility while consumers still resolve ranges.
   - Tighten ranges to the reconciled line: metrics `~> 6.3`, logs
     `~> 1.5.5`, traces `~> 1.4.5` (these bring the v0.5.0-validated
     libraries; `engine: :rust` still exists in 6.3.0 so the hardcode keeps
     working).
   - Start CHANGELOG.md; tag the current release (tags stopped at v1.5.8,
     versions ran to 1.5.18 untagged); add a CI workflow (`mix test` +
     format).

## Phase 1 — A real regression net (~half day)

The only test file never boots a store; every collision above is invisible
to `mix test`. Add:
- a boot test: full embedded tree in a tmp data_dir, write+query one metric,
  one log line, one span; assert directory layout (`metrics/`, `logs/`,
  `spans/`).
- an owner test: host env `owner: :external` for logs/traces → assert
  TimelessPhoenix starts NO embedded children for those signals, restarts
  nothing, and leaves app env untouched.
- a refusal test: data_dir seeded with external-owner markers → boot fails
  with the named error.

## Phase 2 — The embedded engine decision (discuss first)

`supervisor.ex:95` hardcodes `engine: :rust` for metrics. Options:

- **A (recommended): keep `:rust` pinned through 1.x.** Existing
  timeless_phoenix hosts have `rust_engine/` data; floating them onto
  metrics 6.3.0's `:libsql` default would hit the deliberate unmigrated-dir
  refusal at boot. Pinning preserves today's behavior on 6.3.x.
- **B: flip to `:libsql` in timeless_phoenix 2.0** with migration UX: a
  `mix timeless_phoenix.migrate` wrapper around
  `timeless_metrics.migrate_libsql`, upgrade docs, and the loud-refusal
  story documented. Do this AFTER A has soaked; it inherits the 1.3-2.4x
  message compression (logs) and the libSQL query wins.
- Note: embedded logs/traces have no libSQL runtime engine to flip — their
  Elixir block stores remain the embedded implementation (the Rust/libSQL
  path for those signals is external-only by design; the logs POC was
  explicitly not promoted on query-concurrency evidence).

## Phase 3 — Double-ingest and docs (~half day)

- Document the single-destination rule: a host uses TimelessPhoenix's OTel
  exporter/logger handler XOR ships to external Rust APIs — never both.
  Optionally add a config assertion.
- New doc: "Choosing embedded vs external" — the decision matrix above, the
  port map (embedded defaults vs Stack's 8428/9428/10428), the data_dir
  layout differences (`spans/` vs `traces/`), and the migration path from
  an embedded install to a Stack install (per signal: metrics has the
  verified offline migration; logs/traces have the
  ReleaseMigration/ReleaseStartup machinery validated on v0.5.0).
- Update `docs/production.md` / `architecture.md`, which currently describe
  only the embedded world.

## Non-goals

- Merging timeless_phoenix into the Stack (they serve different users).
- Renaming `<data_dir>/spans` (breaking, zero benefit; document instead).
- Publishing dashboards changes (none needed; loose ranges already admit
  the new libraries).

## Open questions for Mark

1. Phase 0.3 port change: pick new embedded defaults, or default HTTP off?
2. Phase 2: agree on A-then-B, or jump straight to B with the migration UX?
3. Does timeless_web (the only known consumer, pinned `~> 1.5`, locked
   1.5.18) get upgraded in the same pass as Phase 0, as the reference host?
