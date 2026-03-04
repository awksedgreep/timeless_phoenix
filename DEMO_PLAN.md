# TimelessPhoenix Demo Plan

**Target**: Short, focused demo (~5-7 min total) showing install-to-dashboard flow.
**Recording**: asciinema for terminal, Cmd-Shift-5 for screen, Keynote for assembly + talking head.

---

## Slide Deck Outline

| # | Slide | Content | Recording? |
|---|-------|---------|------------|
| 1 | **Title** | TimelessPhoenix — Persistent Observability for Phoenix | — |
| 2 | **The Problem** | LiveDashboard loses everything on restart. No logs, no traces, no history. You need Grafana/Datadog/etc. for that — until now. | — |
| 3 | **Overview** | One dep, one child_spec, one router macro → persistent metrics + logs + traces. Compression stats (~11x metrics, ~12x logs, ~10x traces). Zero external infra. | — |
| 4 | **Install** | asciinema recording of project creation + igniter install | terminal recording |
| 5 | **Dashboard** | Screen recording of dashboard walkthrough (metrics, logs, traces) | screen recording |
| 6 | **Performance** | Compression ratios, disk usage, overhead numbers. Optional: asciinema of perf test. | optional recording |
| 7 | **Wrap-up / Links** | Hex link, GitHub, "try it in 60 seconds" call to action | — |

---

## Recording 1: Install (asciinema)

Pre-flight (do before hitting record):
```bash
# Make sure mix, elixir, sqlite3 are available
elixir --version
mix local.hex --if-missing --force
mix archive.install hex phx_new --force
```

### Script

```bash
# Start asciinema recording
asciinema rec demo_install.cast

# 1. Create a fresh Phoenix project with SQLite
mix phx.new demo_app --database sqlite3 --no-mailer
cd demo_app
mix deps.get

# 2. Add TimelessPhoenix dependency (not on Hex yet)
# Add to mix.exs deps:
#   {:timeless_phoenix, github: "awksedgreep/timeless_phoenix"}
# And igniter
#   {:igniter, "~> 0.6", only: [:dev]}
mix deps.get

# 3. Run the igniter installer
mix timeless_phoenix.install

# 4. Generate demo traffic
mix timeless_phoenix.gen_demo

# 5. Start the app
mix phx.server

# (let it run ~15-20 seconds so traffic populates, then Ctrl-C)
# End asciinema recording: Ctrl-D or `exit`
```

### Talking Points for This Slide
- "One command to install — the igniter handles supervision tree, router, and OpenTelemetry config"
- "gen_demo gives us realistic traffic: HTTP requests, DB queries, background jobs, errors"
- "That's it. Three commands after `phx.new` and we have full observability"

---

## Recording 2: Dashboard (screen recording via Cmd-Shift-5)

Start the app first (off-camera or from the same asciinema session):
```bash
cd demo_app
mix phx.server
```

Open browser to `http://localhost:4000/dashboard`.

### Walkthrough Script

1. **Home tab** — point out that charts show *historical* data, not just since boot
2. **Timeless tab** (metrics) — show metric series list, click into a chart, zoom a time range, mention compression stats
3. **Logs tab** — filter by level (show errors from demo traffic), search by message substring, show metadata
4. **Traces tab** — find a trace, open waterfall view, show span details and attributes
5. *(optional)* Refresh or restart the app → show data persists

### Talking Points for This Slide
- "Everything you see here survives restarts — it's stored in compressed SQLite + Gorilla/Zstd/OpenZL"
- "No Prometheus, no Loki, no Jaeger — it's all in-process"
- "Filter, search, zoom — it's a real observability stack, not a toy"

---

## Recording 3 (Optional): Performance Test (asciinema)

```bash
asciinema rec demo_perf.cast

# Show storage stats after traffic has been running
du -sh priv/observability/
du -sh priv/observability/metrics/
du -sh priv/observability/logs/
du -sh priv/observability/spans/

# If you have a bench script or can show compression ratios via iex:
iex -S mix <<'EOF'
TimelessMetrics.stats(:tp_default_timeless) |> IO.inspect(label: "Metrics Stats")
EOF
```

---

## Things You Might Forget (Checklist)

- [ ] Clean terminal (white or dark theme, large font for readability)
- [ ] Set terminal to ~100 cols x 30 rows for asciinema
- [ ] Close notifications / Do Not Disturb
- [ ] Pre-install deps so `mix deps.get` is fast (or at least has cached downloads)
- [ ] Have `sqlite3` installed (`brew install sqlite`)
- [ ] Delete any previous `demo_app/` directory before recording
- [ ] Browser zoom level appropriate for screen recording
- [ ] Test the full flow once before recording
- [ ] For the dashboard recording, let demo traffic run for 30-60 seconds first so there's interesting data

---

## Keynote Assembly

1. Title slide
2. Problem slide (static)
3. Overview slide (static — bullet points or simple diagram)
4. Install slide → embed asciinema replay (or converted mp4) with talking head overlay
5. Dashboard slide → embed screen recording with talking head overlay
6. Performance slide → static stats or embed perf recording
7. Wrap-up slide with links

### Converting asciinema to video for Keynote

```bash
# Option A: agg (asciinema gif generator) → then convert gif to mp4
# Install: cargo install --git https://github.com/asciinema/agg
agg demo_install.cast demo_install.gif --font-size 16
ffmpeg -i demo_install.gif -movflags faststart -pix_fmt yuv420p demo_install.mp4

# Option B: Record terminal directly with Cmd-Shift-5 while replaying
asciinema play demo_install.cast
```
