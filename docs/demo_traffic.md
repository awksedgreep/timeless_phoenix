# Demo Traffic Generator

TimelessPhoenix includes an Igniter task that generates a demo traffic module for populating your dashboards with realistic data.

## Usage

```bash
mix timeless_phoenix.gen_demo
```

This creates two things:

1. **`lib/<app>/demo_traffic.ex`** -- a GenServer that simulates application activity
2. **Supervision tree entries** -- a `Task.Supervisor` and the `DemoTraffic` module added to your application

The generator requires [Igniter](https://hex.pm/packages/igniter). If Igniter isn't installed, you'll see an error with instructions.

## What it generates

The DemoTraffic GenServer spawns 3-6 random activities every 2 seconds:

### Simulated HTTP requests

- Random methods (GET, POST, PUT, DELETE)
- Random paths (/users, /orders, /products, /api/health, /search)
- Realistic status codes (mostly 200s, some 201, 301, 404)
- Random durations (5-150ms)
- Creates OpenTelemetry spans with HTTP attributes
- Emits telemetry events and Logger info messages

### Database queries

- Random tables (users, orders, products, sessions, events)
- Random durations (1-50ms)
- Creates OTel spans with `db.system` and `db.sql.table` attributes
- Emits Ecto-style telemetry events
- Logger debug messages

### Background jobs

- Job types: send_email, process_payment, generate_report, sync_inventory
- Random durations (50-500ms)
- Creates OTel spans with `job.type` attributes
- Logger info messages for start and completion

### Cache operations

- 75% hits, 25% misses
- Random keys (user:123, product:456, session:abc, config:main)
- Creates OTel spans with `cache.key` and `cache.hit` attributes
- Logger debug messages

### Warnings (every 10 seconds)

Random warnings:
- "Connection pool running low"
- "Slow query detected"
- "Rate limit approaching"
- "Memory usage elevated"

### Errors (every 24 seconds)

Random errors:
- "Connection timeout to external API"
- "Failed to process webhook"
- "Database deadlock detected"

## What shows up in the dashboard

After starting the demo traffic:

- **Metrics page** -- Request counts, durations, DB query times, job durations
- **Logs page** -- A mix of debug, info, warning, and error entries with structured metadata
- **Traces page** -- Spans from simulated requests, DB queries, jobs, and cache operations

## Removing the demo

When you no longer need demo data:

1. Delete `lib/<app>/demo_traffic.ex`
2. Remove `<App>.DemoTraffic` and `{Task.Supervisor, name: <App>.DemoTaskSupervisor}` from your supervision tree
