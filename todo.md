# TimelessPhoenix TODO

## Pre-Launch (before podcast/Hex publish)

- [ ] **Publish to Hex** — Resolve all path/GitHub deps to Hex packages
- [x] **Trace waterfall view** — Already implemented in timeless_traces_dashboard (tree building, timing bars, service colors, span detail expansion)
- [x] **Alert management UI** — Create, edit, toggle, delete alerts + history with acknowledge/clear from the metrics dashboard alerts tab
- [ ] **Cross-signal linking** — Click metric time range → see traces/logs from that window. Click trace → see associated logs.

## Post-Launch Enhancements

- [ ] **Error grouping** — Cluster exceptions by type/message, show occurrence counts and trends
- [ ] **Slow query highlighting** — Surface Ecto queries exceeding threshold as a dedicated list/view
- [ ] **Dashboard presets** — Default "Phoenix Overview" tab: request rate, error rate, p99 latency, VM memory with zero config
- [ ] **Data export** — CSV/JSON export of metric ranges from the metrics dashboard
