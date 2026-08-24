# Changelog

This changelog starts at 2.0.0; earlier releases are recorded by git
tags (through v1.5.8; 1.5.9–1.5.18 shipped untagged).

## 2.0.3 (2026-08-24)

**Requires `timeless_metrics >= 6.6.6`.** Every `timeless_metrics` release
from 6.2.3 through 6.6.5 carries a release-migration path that can hang and
silently lose data on upgrade: cold validation resolved one
`timeless_series` probe per series with predicates that cannot be pushed
down, making validation O(series²) and unbounded on a high-cardinality
store, and the half-built candidate ran the production `:compact` and
`:retention` timers, so any copy taking longer than an hour had raw points
older than the retention window pruned out of it mid-migration. A real
1,000,997-series store lost 2,419,903 points that way.

The previous constraint (`~> 6.4`) permitted the entire affected range.
Upgrade directly to 6.6.6; the fixed migration runs from the version you
upgrade *to*, so landing on 6.6.6 is the fix. Those versions are retired on
Hex.

## 2.0.1 (2026-08-09)

**`TimelessPhoenix.doctor/1`** — post-upgrade verification for a live
node (run from `bin/my_app remote`): confirms each signal is configured
AND running on the libSQL engine, the extension capability handshake
holds (version + data ABI), legacy stores were converted with rollback
material retained (and errors loudly if a legacy store exists without a
conversion marker), and reports data presence. Prints a report and
returns `{verdict, report}` with `:ok` | `:warn` | `:error`.

## 2.0.0 (2026-08-09)

**The libSQL release.** All three embedded signals now run on in-process
engines over the timeless-libsql v0.5.0 extension (metrics 6.4, logs
1.7, traces 1.6): one SQLite file per signal, dashboard reads stay
in-process (no HTTP hop), rich log messages get CLP codec-8 template
compression, and embedded hosts share ONE on-disk format with the Rust
services — graduating to a Rust-owned deployment is stop-one-owner /
start-the-other, never a data migration.

### Breaking

- **`:http` is removed.** The embedded Elixir engines no longer serve
  signal HTTP APIs; passing `:http` raises with guidance. Run the
  `timeless-metrics-api` / `timeless-logs-api` / `timeless-traces-api`
  services from the timeless-libsql release bundle against the same data
  directories instead.
- **`engine: :rust` is no longer hard-coded for metrics.** Metrics uses
  its library default (libSQL). Existing hosts convert automatically on
  first boot — see below. Pass `timeless: [engine: :rust]` to pin the
  deprecated engine explicitly.

### Upgrade path for existing hosts — automatic

On first boot after upgrading, each signal detects its legacy store
(metrics `rust_engine/`, logs/traces block stores) and runs the
journaled, digest-verified conversion automatically, blocking startup
until verified and activated. Sources are retained for rollback;
restarts never re-convert. Set `auto_migrate: false` per signal to get
a strict refusal instead. The legacy engines are deprecated for removal
in roughly three months (~2026-11).

### Changed

- External ownership is respected: a signal whose host config or
  overrides declare `owner: :external` is no longer env-clobbered or
  stop/restarted into embedded mode — TimelessPhoenix starts nothing
  for it (previously it force-converted external hosts into embedded
  writers).
- Logs and traces load the extension shipped with the metrics package's
  precompiled natives; no separate extension install is needed.
- `mix.lock` is now tracked.
