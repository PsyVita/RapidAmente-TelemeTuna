# 🐟 TelemeTuna v1.0

**TelemeTuna** is a self-contained telemetry platform for the **RapidAmente** electric race car. It catches live sensor data streamed from the car, cleans it up, stores it safely in a database, and draws it on live dashboards.

It is built almost entirely out of ready-made building blocks that run inside **Docker**. If you can copy a file and run a couple of commands in a terminal, you can run this project.

> **Repository:** https://github.com/PsyVita/RapidAmente-TelemeTuna

---

## 📑 Table of Contents

1. [What this project does](#-what-this-project-does)
2. [How it all fits together (the big picture)](#-how-it-all-fits-together-the-big-picture)
3. [Deployment: cloud first, local optional](#-deployment-cloud-first-local-optional)
4. [What's inside the box (the services)](#-whats-inside-the-box-the-services)
5. [The data: what a "frame" looks like](#-the-data-what-a-frame-looks-like)
6. [Timestamps: who stamps, and why](#-timestamps-who-stamps-and-why)
7. [The processing pipeline, step by step](#-the-processing-pipeline-step-by-step)
8. [Before you start (prerequisites)](#-before-you-start-prerequisites)
9. [Installation & first run](#-installation--first-run)
10. [How to feed data in](#-how-to-feed-data-in)
11. [Optional: running Node-RED locally for a direct serial connection](#-optional-running-node-red-locally-for-a-direct-serial-connection)
12. [The database tables](#-the-database-tables)
13. [The Grafana dashboard](#-the-grafana-dashboard)
14. [Team access: watching together](#-team-access-watching-together)
15. [Design decisions & concerns — the exhaustive FAQ](#-design-decisions--concerns--the-exhaustive-faq)
16. [Project folder layout](#-project-folder-layout)
17. [Troubleshooting](#-troubleshooting)
18. [Glossary (plain-English definitions)](#-glossary-plain-english-definitions)

---

## 🎯 What this project does

An electric race car is covered in sensors. While it drives, those sensors constantly report things like:

- How fast the motor is spinning (**RPM**)
- How much electric current and voltage the motor is drawing (**amps / volts**)
- How much twisting force it is producing (**torque**)
- How hot the electronics and motor are (**IGBT temperature / motor temperature**)
- Which gear it is in (**Drive / Reverse / Neutral**)
- A set of warning and error flags (cooling pump on, regen braking active, faults, etc.)

On the car, a **sender ESP32** collects this data and radios it to a **receiver ESP32** using **LoRa**. The receiver publishes each reading over **MQTT** to this platform, where it is timestamped on arrival (see [Timestamps](#-timestamps-who-stamps-and-why) for why that's the right call).

That raw data is messy. It arrives as long strings of numbers, sometimes with missing values, sometimes corrupted, and the numbers are in a "raw" computer format (-32767 to 32767) instead of real-world units.

**TelemeTuna does four things:**

1. **Ingests** the data — accepts it live from the receiver ESP32 over MQTT, or from a CSV file for replays and testing.
2. **Cleans & converts it** — turns raw numbers into real units (RPM, °C, amps…), repairs ("heals") corrupted readings using the last known-good value, and drops anything hopelessly broken.
3. **Stores it** — saves every reading in a PostgreSQL database, plus a separate log of every warning/error that happened along the way.
4. **Visualizes it** — shows it all on live Grafana dashboards.

Everything is logged, so you can always trace *why* a value looks the way it does.

---

## 🧩 How it all fits together (the big picture)

```
   On the car                                ┌─────────────────────────────────────────────┐
                                             │      CLOUD SERVER (or local PC) — DOCKER     │
  ┌──────────┐   radio    ┌──────────┐ MQTT  │                                              │
  │  Sender  │ ─────────▶ │ Receiver │ ────▶ │   ┌──────────┐      ┌──────────────────┐     │
  │  ESP32   │   (LoRa)   │  ESP32   │ WiFi  │   │ Mosquitto│─────▶│     Node-RED     │     │
  └──────────┘            └──────────┘       │   │  (MQTT)  │      │ (stamp+clean+    │     │
                                             │   └──────────┘      │  convert+heal)   │     │
                          ┌──────────┐       │                     └────────┬─────────┘     │
                          │ CSV file │ ──────┼──────────────────────────────┤               │
                          │ (replay) │       │                              ▼               │
                          └──────────┘       │                     ┌──────────────────┐     │
                                             │   ┌──────────┐      │   PostgreSQL DB  │     │
                                             │   │  Flyway  │      │ (stores readings)│     │
                                             │   │ (builds  │      └────────┬─────────┘     │
                                             │   │  tables) │               │               │
                                             │   └──────────┘      ┌────────┴─────────┐     │
                                             │                     ▼                  ▼     │
                                             │                 ┌─────────┐      ┌─────────┐ │
                                             │                 │ Grafana │      │ pgAdmin │ │
                                             │                 │ (charts)│      │ (browse)│ │
                                             │                 └─────────┘      └─────────┘ │
                                             └─────────────────────────────────────────────┘
                                                       ▲ team watches from anywhere ▲
```

**In words:** The sender ESP32 on the car radios each reading to the receiver ESP32, which publishes it to **Mosquitto** (the MQTT "post office"). **Node-RED** is the "brain" that picks the message up, stamps it with the arrival time, cleans and converts it, and writes the result into **PostgreSQL**. **Grafana** reads from PostgreSQL to draw the charts, and **pgAdmin** lets you inspect the raw tables by hand. **Flyway** is a one-shot helper that builds the database tables the first time you start up. CSV files can be fed straight into Node-RED to replay old data through the very same pipeline.

---

## ☁️ Deployment: cloud first, local optional

The same Docker setup runs anywhere. Pick the deployment that fits you:

### Option A — Everything on a cloud server *(how the RapidAmente team runs it)*

The **whole platform** — Mosquitto, Node-RED, PostgreSQL, Grafana, pgAdmin — runs on one cloud VM. The receiver ESP32 publishes to the **cloud server's public IP**, and the whole team watches the dashboards from anywhere, no shared network needed:

```
http://<cloud-public-ip>:3001   ← Grafana       http://<cloud-public-ip>:1881  ← Node-RED
http://<cloud-public-ip>:5051   ← pgAdmin       <cloud-public-ip>:1883         ← MQTT (ESP32 publishes here)
```

**Cloud checklist:**

1. Create a small VM (any provider — 1–2 GB RAM is plenty), install Docker, clone the repo, follow the normal [installation steps](#-installation--first-run).
2. **Change every default password in `.env` first** — a public IP is visible to the whole world within hours, not just to the team.
3. In the cloud firewall / security group, open only what's needed: `1883` (so the ESP32 can publish), `3001`, `1881`, `5051` (ideally allow-listed to the team's IPs). **Keep `5433` closed** — nothing outside Docker needs the database directly.
4. The receiver ESP32 just needs any internet-connected Wi-Fi (a phone hotspot at the track works) and the broker address set to the cloud IP.
5. Turn on your provider's automatic disk snapshots — it's a one-checkbox backup of everything.

### Option B — Everything on one local PC

The classic setup: run the stack on a laptop, open everything at `localhost`. Best for development, testing, and tracks with zero connectivity. Teammates on the **same network** can still watch (see [Team access](#-team-access-watching-together)).

### Option C — Hybrid

Local stack on the pit laptop, but the Mosquitto broker in the cloud (point Node-RED's MQTT node and the ESP32 at the cloud broker). Useful when the dashboard machine sits behind a strict network but the car still needs a reachable broker.

---

## 📦 What's inside the box (the services)

When you start the project with Docker, six things run together. You don't install them one by one — Docker does it for you.

| Service | What it is | Where you reach it | Why it's here |
|---|---|---|---|
| **PostgreSQL** | The database | `localhost:5433` | Permanent storage for every reading |
| **Node-RED** | Visual data-flow tool | http://localhost:1881 | The "brain" — stamps, cleans, converts, heals, logs |
| **Grafana** | Dashboard tool | http://localhost:3001 | Live charts and gauges |
| **Mosquitto** | MQTT message broker | `localhost:1883` | Carries live data messages |
| **Flyway** | Database migration tool | *(runs once, then exits)* | Creates the tables automatically on first start |
| **pgAdmin** | Database admin UI | http://localhost:5051 | Browse and query the stored data by hand |

> 💡 **Why these ports?** They are deliberately shifted (5433 instead of the usual 5432, 1881 instead of 1880, 3001 instead of 3000, 5051 instead of the usual 5050) so they don't collide with other software you might already have running. On a cloud deployment, replace `localhost` with the server's public IP.

---

## 🔢 The data: what a "frame" looks like

Each reading from the car is one line of comma-separated values, called a **frame**. A live frame from the car has **15 data fields**, always in this order:

| # | Field | Meaning | Example raw value |
|---|-------|---------|-------------------|
| 1 | `rpm` | Motor speed (raw, -32767…32767) | `15000` |
| 2 | `amp` | Current (raw) | `-8000` |
| 3 | `volt` | Voltage (raw) | `19660` |
| 4 | `trq` | Torque (raw) | `12000` |
| 5 | `mode` | Gear: `D`rive, `R`everse, `N`eutral | `D` |
| 6 | `igbt_c` | IGBT temperature (raw sensor count) | `21357` |
| 7 | `mot_c` | Motor temperature (raw sensor count) | `11644` |
| 8 | `err` | Error bitmask (a number; each bit = one fault) | `0` |
| 9 | `warn` | Warning bitmask | `0` |
| 10 | `L_REGEN` | Regenerative braking active? | `0` |
| 11 | `L_ERR` | Error light (0/1) | `0` |
| 12 | `L_WARN` | Warning light (0/1) | `0` |
| 13 | `L_OK` | "All OK" light (0/1) | `1` |
| 14 | `L_PUMP` | Cooling pump light (0/1) | `0` |
| 15 | `drive_ena` | Drive enabled? (0/1) | `1` |

Example live frame (15 fields — TelemeTuna stamps it on arrival):

```
15000,-8000,19660,12000,D,21357,11644,0,0,0,0,0,1,0,1
```

A **16-field** variant with a leading ISO timestamp is also accepted (and is **required** for CSV imports):

```
2024-01-01T00:00:00.600Z,15000,-8000,19660,12000,D,21357,11644,0,0,0,0,0,1,0,1
```

Negative values are normal: negative `amp`/`trq` means the car is **regenerating** — charging the battery while braking.

---

## ⏱️ Timestamps: who stamps, and why

This was a deliberate design decision, documented inside the Node-RED flow itself ("Note to Future Developer"):

**Current decision: the ESP32 sends no timestamps. Node-RED stamps each frame the moment it arrives.**

**Why arrival-stamping is accurate here:** MQTT only guarantees delivery between the *broker and the computer*. It does **not** buffer messages on the ESP32 side — if the ESP32 loses its connection, data generated while offline is simply lost, never queued. So every message that reaches the platform was sent in real time, arrival intervals mirror real intervals, and arrival timestamps do **not** condense or distort the graphs.

**The 16-field path is the future-proofing.** If the team ever adds ESP32-side queuing (so disconnects don't lose data), two changes must come **together**: (1) the firmware buffers readings during disconnects and flushes them on reconnect, and (2) the ESP32 attaches a real timestamp to each reading at measurement time (RTC module or NTP sync). Without sender timestamps, a flushed backlog would arrive in seconds and be plotted as one cluster at the reconnect moment. The pipeline already accepts the 16-field format, so that upgrade needs **zero Node-RED changes**.

**Rules as implemented:**

| Frame arrives with | What happens |
|---|---|
| 15 fields (live MQTT) | Stamped silently with arrival time — the normal case |
| 16 fields, valid timestamp | The provided timestamp is used (CSV replays; future ESP32 firmware) |
| 16 fields, broken/blank timestamp | Frame dropped, logged as `FD` |
| Any other field count | Frame dropped, logged as `FD` |
| CSV import with 15 fields | Rejected — CSV files **must** include the timestamp column |

---

## ⚙️ The processing pipeline, step by step

Inside Node-RED there are three "tabs" (think of them as three pages of wiring):

- **Real-Time Imports** — the entry point for live data (the MQTT listener on topic `car_telemetry`, QoS 2).
- **CSV Imports** — the entry points for loading raw or processed files (timestamp column required; it's stripped here, then raw rows join the pipeline below).
- **Background Flow** — the cleaning/conversion pipeline that live data and raw CSVs funnel into.

Every raw frame passes through these stations, in order:

1. **Strip Timestamp** — Separates time from data. A 16-field frame keeps its own timestamp; a 15-field frame is stamped with arrival time (silently — this is the normal live case). Any other field count drops the frame (`FD`).
2. **Parse CSV** — Splits the line into its 15 fields and checks each one: right count, gear present, every other field a real number. Any failure drops the **whole frame** (`FD`) — at this stage the structure isn't trusted yet, so no repairs are attempted.
3. **Raw → Real Conversion** — Scales raw -32767…32767 into real units via `real = raw ÷ 32767 × max`:
   - `rpm` → max 5,500 RPM (rounded to a whole number — sensor precision doesn't justify decimals)
   - `amp` → max 212.1 A · `volt` → max 200 V · `trq` → max 125 Nm (1 decimal each)
   - A raw value outside ±32767 didn't come from the hardware → becomes `null` + `warn` logged (the Heal step will repair it).
4. **Map Mode** — `N`→0, `D`→1, `R`→2. Anything else → `null` + `warn` (healable — the car can't teleport between gears in 300 ms).
5. **Temperature Conversion** — raw counts → °C:
   - **IGBT:** 32-point manufacturer lookup table (raw 16308 = −30 °C … raw 28480 = +125 °C) with straight-line interpolation between neighboring points.
   - **Motor:** linear sensor, two-point fit: `temp = 30 + (raw − 11446) × 70 ÷ 4554` (valid raw range 10000–20000).
   - Out-of-range raw values → `null` + `warn`, healable.
6. **Heal** — The safety net for the seven continuous values. Keeps a per-field snapshot of the last known-good value and checks each new value against a plausibility range: rpm ±6000, amp ±250, volt ±250, trq ±150, temps −40…200 °C, mode 0–2. Valid → keep & update snapshot. Invalid/missing/null → **replace with the snapshot value** and record the field name. Every healed row carries its `healed_fields` list into the database **and** a summary into the event log — repairs are never silent.
7. **Flags** — The six 0/1 lights become true/false. Anything that isn't exactly 0 or 1 → `null` + `error` logged. **Flags are never healed** — copying yesterday's "no error" over a corrupted error light could hide a real fault.
8. **Validate Bitmasks** — `err` and `warn` must be whole numbers 0–65535 (what 16 bits can hold). Invalid → `null` + `error`. The numbers are stored as-is; decoding into fault names happens in Grafana at display time.
9. **Build Parameters** — Packs timestamp, converted values, flags, bitmasks, and the healed-fields list into one ordered row.
10. **Car Telemetry Database** — Inserts into `telemetry_records` with `ON CONFLICT (time) DO NOTHING`: the `time` column is unique, so replaying the same data can never create duplicates.

### What happens when something goes wrong

- Every station has a **second output** that sends structured complaints to a **"Normalize Log Event"** node → the `event_logs` table.
- A global **Catch node** per tab grabs unexpected crashes in any station and logs them as `critical` — the pipeline keeps running for the next frame.
- **Deliberate exception:** the Catch nodes do *not* watch "Normalize Log Event" or "Log Database" themselves. If the database is down, a caught log-write failure would generate another log write, which fails, which generates another… an infinite loop. Excluding the logging chain breaks that loop (the trade-off: log writes that fail when the DB is down are lost — see the FAQ).

### Event log severity levels

| Level | When it's used |
|---|---|
| `warn` | A value was out of bounds and was *healed* (replaced with the last good value) |
| `error` | A value was wrong and **not** healed (flags, bitmasks) — stored as null |
| `FD` | "Frame Dropped" — the whole frame was unusable and discarded |
| `critical` | An unexpected code error happened (caught by the safety net) |

### Built-in test generator (no hardware needed)

The Background Flow tab contains a **"FAKE Data Generator"** wired to a **"Test Injection Node"**. One click simulates a full driving cycle (idle → accelerate → cruise → coast → regen → stop) and then deliberately exercises **every defence in the pipeline**, phase by phase: fault bitmask combinations (FAULTS), every status-light combination (FLAGS), corrupted values that trigger healing (HEAL), malformed frames that get dropped whole — wrong field counts, non-numeric values, bad timestamps (DROPS) — and finally simulated code errors that land in the log as `critical` (CRITICAL). After one run, every panel on both dashboard tabs has something to show.

---

## ✅ Before you start (prerequisites)

You only need **two** things installed (on your PC or on the cloud VM):

1. **Docker Desktop** (or Docker Engine on a Linux server) — https://www.docker.com/products/docker-desktop/
2. **Git** — https://git-scm.com/downloads (or download the project as a ZIP from GitHub).

That's it. PostgreSQL, Node-RED, Grafana, Mosquitto, Flyway, and pgAdmin all come inside the project.

> The only optional extra is **Node.js + Node-RED**, and only for the advanced *local serial port* setup described in its own section below.

---

## 🚀 Installation & first run

### Step 1 — Download the project

```bash
git clone https://github.com/PsyVita/RapidAmente-TelemeTuna.git
cd RapidAmente-TelemeTuna
```

### Step 2 — Create your environment (`.env`) file

```bash
cd infrastructure
cp .env.example .env
```

Open `infrastructure/.env` in any text editor and set your own values:

```dotenv
# PostgreSQL
POSTGRES_USER=user
POSTGRES_PASSWORD=password
POSTGRES_DB=telemetry

# Grafana
GRAFANA_ADMIN_USER=user
GRAFANA_ADMIN_PASSWORD=password

# pgAdmin
PGADMIN_EMAIL=admin@admin.com
PGADMIN_PASSWORD=password
```

**Remember what you set** — you'll use:
- `POSTGRES_*` to connect to the database (Node-RED and pgAdmin use them automatically).
- `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` to log in to Grafana.
- `PGADMIN_EMAIL` / `PGADMIN_PASSWORD` to log in to pgAdmin (the email just needs to *look* like an email).

> ⚠️ The `.env` file is intentionally **not** uploaded to GitHub (it's in `.gitignore`) because it holds your passwords. On a cloud deployment, treat strong passwords here as mandatory, not optional.

### Step 3 — Start everything

```bash
docker compose up -d
```

First start takes a few minutes (downloads + builds). What happens automatically: PostgreSQL starts → Flyway builds all tables and exits (that's normal!) → Node-RED, Grafana, Mosquitto, and pgAdmin come up and stay running.

### Step 4 — Check that it's working

| What | Address | Login |
|---|---|---|
| Node-RED | http://localhost:1881 | none |
| Grafana | http://localhost:3001 | Grafana user/password from `.env` |
| pgAdmin | http://localhost:5051 | pgAdmin email/password from `.env` |

> 🐘 **First time in pgAdmin:** register the database once. Right-click *Servers* → *Register* → *Server*, any name, and under *Connection* set **Host** = `postgresdb`, **Port** = `5432`, plus the `POSTGRES_*` values from `.env`. Tick **Save password**. (It must be `postgresdb:5432`, *not* `localhost:5433` — pgAdmin lives *inside* the Docker network with the database.)

Command-line peek at the database:

```bash
docker exec -it telemetry-postgresdb psql -U <YOUR_POSTGRES_USER> -d <YOUR_POSTGRES_DB> -c "SELECT count(*) FROM telemetry_records;"
```

### Step 5 — Generate test data (no car needed!)

1. Open Node-RED → **Background Flow** tab.
2. Click the square button on the **Test Injection Node** (wired to the **FAKE Data Generator**).
3. Watch the status bar under the node step through the phases while both Grafana tabs fill with data.

### Useful Docker commands

```bash
docker compose ps          # see what's running
docker compose logs -f     # watch live logs from all services
docker compose logs flyway # check the database got set up
docker compose down        # stop everything (keeps your data)
docker compose down -v     # stop AND erase all stored data (be careful!)
```

---

## 📥 How to feed data in

### Way 1 — Live MQTT (the racing setup)

Node-RED is always listening on MQTT topic **`car_telemetry`**. The receiver ESP32 publishes each 15-field frame there — cloud deployment: to the cloud server's IP on port 1883; local: to the PC's IP. Frames flow straight into the pipeline, stamped on arrival. Nothing to click.

Test it by hand from any machine with an MQTT client:

```bash
mosquitto_pub -h <server-ip> -p 1883 -t car_telemetry \
  -m "15000,-8000,19660,12000,D,21357,11644,0,0,0,0,0,1,0,1"
```

### Way 2 — CSV file import (replays and testing)

Both CSV types **require a timestamp as the first column** (16 columns total):

- **Raw CSV** — timestamp + 15 raw fields → full cleaning pipeline (keeps the file's original timestamps).
- **Processed CSV** — timestamp + 15 already-cleaned fields (data that went through TelemeTuna before) → written straight to the database, no double-cleaning.

**How to:**

1. Put the file in `nodered/data/` — Node-RED sees it as `/data/data/yourfile.csv`.
2. Open the **CSV Imports** tab in Node-RED.
3. Edit the file path in the matching **file-in** node (comment: "Edit Path to Insert Your File").
4. Click the inject button on **Load Raw CSV** or **Load Processed CSV**.

Blank lines are ignored; rows with bad timestamps or field counts are dropped and logged. 🔁 **Safe to re-run:** duplicate timestamps are skipped, so importing the same file twice never duplicates data.

### Way 3 — Direct serial (advanced, local only)

See the [dedicated section below](#-optional-running-node-red-locally-for-a-direct-serial-connection) — only needed when the LoRa receiver is plugged into the computer by USB and you want to skip MQTT entirely.

---

## 🔌 Optional: running Node-RED locally for a direct serial connection

> **Most users skip this.** Docker containers cannot access USB serial ports, so reading the receiver directly requires Node-RED to run natively on your machine. The serial-port nodes visible in the committed flow are disabled placeholders; the active local flow is provided separately and not committed.

1. Install Node.js (LTS) from https://nodejs.org, then Node-RED: `npm install -g --unsafe-perm node-red`
2. Install the add-ons: `cd ~/.node-red && npm install node-red-node-serialport node-red-contrib-postgresql`
3. Stop the Docker Node-RED so the two don't clash: `docker compose stop node-red` (leave everything else running).
4. Start local Node-RED → http://localhost:**1880** (the local default — not 1881) and import the provided local flow.
5. **Fix the database connection** — the important change: local Node-RED is *outside* Docker, so the PostgreSQL config must be **Host `localhost`, Port `5433`** (not `postgresdb:5432`), with the user/password/database from your `.env`. One shared config covers all database nodes.
6. Fix CSV paths (if used) to real paths on your disk.
7. Configure the serial node: your device (macOS `/dev/cu.usbserial-…`, Windows `COM5`, Linux `/dev/ttyUSB0`), baud **38400**, then Deploy. The node should turn green.

| Thing | Docker default | Local Node-RED value |
|---|---|---|
| Editor URL | http://localhost:1881 | http://localhost:1880 |
| DB host/port | `postgresdb` / `5432` | `localhost` / `5433` |
| CSV path | `/data/data/...` | real path on disk |
| Serial port | (unusable) | your device |
| Docker node-red | running | **stopped** |

---

## 🗄️ The database tables

Flyway creates these automatically from the migration files (V1–V4). You never write them by hand.

### `telemetry_records` — every cleaned reading

| Column | Type | Notes |
|---|---|---|
| `time` | timestamp | when the reading happened. **Unique** — a second row with the same timestamp is skipped on insert (V4) |
| `rpm`, `amp`, `volt`, `trq` | number | converted real-world values |
| `mode` | integer | 0=Neutral, 1=Drive, 2=Reverse |
| `err`, `warn` | integer | bitmask numbers (decoded in Grafana via the definition tables) |
| `igbt_c`, `mot_c` | number | temperatures in °C |
| `l_regen`, `l_err`, `l_warn`, `l_ok`, `l_pump`, `drive_ena` | true/false | status lights (null = was corrupted, never healed) |
| `healed_fields` | list of text | which fields (if any) were repaired for this row |

### `event_logs` — the pipeline's diary

| Column | Type | Notes |
|---|---|---|
| `time` | timestamp | when it happened |
| `level` | text | `warn`, `error`, `FD`, `critical` |
| `node` | text | which pipeline station raised it |
| `message` | text | human-readable explanation |
| `fields` | list of text | involved field names (e.g. the healed fields) |

### `err_bit_definitions` & `warn_bit_definitions` — the fault dictionary

`err` and `warn` are stored as plain numbers where each **bit** means one specific fault (bit 7 of `err` = "IGBT-Temp. Max. Limit"). These tables map all 16 + 16 bits to names and descriptions straight from the motor controller's manual, so Grafana can show readable fault names instead of cryptic numbers.

---

## 📊 The Grafana dashboard

A pre-built dashboard — the **EV TelemeTuna Dashboard** — is provisioned automatically. It refreshes very fast (down to 300 ms) and is organized into **two tabs**:

### Tab 1 — Car Live Dashboard

- **Live gauges & stats** — RPM, voltage, current, torque, motor & IGBT temperature, drive mode, and the six status lights.
- **Time-series charts** — RPM, torque, voltage & current, and both temperatures over time.
- **Active Errors & Warnings** — the latest `err`/`warn` bitmasks decoded into named faults. When a frame exists and no fault bits are set, it shows a friendly **"No active faults — All systems normal"** row, so an empty table is never ambiguous.

### Tab 2 — TelemeTuna Pipeline Health

- **Connection** — a true live indicator: shows **Connected <๏)))>< ∿∿∿** (blue) if *anything* arrived within the last second — including dropped frames, because malformed-but-arriving data still proves the radio link is alive — and **Disconnected <×)))>< ···** otherwise. Unlike everything else, this panel always checks against *right now*, regardless of the time picker.
- **Event Logs** — the live `event_logs` feed (time, level, node, message, affected fields).
- **Counters** — healed frames, errors, criticals, frame drops, warnings, and **Total Null Count** (how many flag/bitmask values had to be stored as unknown in the window).
- **Healed Fields** — every reading that needed repair and exactly which fields were patched.

### One rule to remember: everything follows the time picker

**Every** panel except Connection — including the live gauges and status lights — shows data from the **currently selected time range** only. The "live" panels simply display the most recent reading *inside that window*:

- Watching live? Keep the default *Last 15 minutes* and the gauges behave like real-time instruments.
- A gauge showing **"-" / grey** means *no reading in the selected window* — either the data stopped (check the Connection panel) or you're looking at the wrong time range.
- Replaying an old CSV? Set the time picker to cover the file's dates and the **whole dashboard** — gauges included — replays that moment in history.
- The counters count only within the window: "Heal Count: 3" means 3 healed frames *in the selected range*, not all-time. Zooming into a chart shrinks the counters, because zooming *is* changing the time range.

**Optional annotations** — overlays for car errors, car warnings, healed frames, frame drops, and program criticals can be toggled in the dashboard settings.

---

## 👥 Team access: watching together

**Cloud deployment (Option A):** nothing extra to do — everyone opens the cloud IP addresses from anywhere.

**Local deployment (Option B):** the stack runs on one computer; anyone on the **same network (same subnet)** replaces `localhost` with the host computer's IP on that network (`ipconfig` on Windows, `ifconfig` on macOS/Linux): `http://<host-ip>:3001` (Grafana), `:1881` (Node-RED), `:5051` (pgAdmin). Gotchas: same Wi-Fi/hotspot required (a phone on 5G can't see a laptop on Wi-Fi), and the host's firewall must allow those ports. Each service still asks for its own login.

---

## 🤔 Design decisions & concerns — the exhaustive FAQ

**Why does Node-RED stamp timestamps instead of the car?**
The ESP32 has no wall clock, and MQTT never queues data on the ESP32 side — anything that arrives was sent in real time, so arrival timestamps are accurate. The flow contains a "Note to Future Developer" explaining exactly what must change (firmware buffering **plus** sender timestamps, together) if offline buffering is ever added. See [Timestamps](#-timestamps-who-stamps-and-why).

**If the radio drops, is data lost?** Yes — readings generated while the link is down are gone (the ESP32 doesn't buffer). The dashboard shows an honest gap, and the Connection panel shows Disconnected. This is a known, accepted trade-off; fixing it requires the firmware upgrade described above.

**Why are some bad values healed, others nulled, others dropped?** Three deliberate tiers. *Continuous physics* (rpm, amp, volt, trq, temps, mode) changes smoothly, so the previous value is an excellent 300-ms-old estimate → **heal**. *Discrete signals* (flags, fault bitmasks) can genuinely change between frames — copying an old "no fault" over a corrupted value could hide a real fault → **null + error log**, never guessed. *Structurally broken frames* (wrong field count, text where numbers belong) can't be trusted at all → **dropped whole + FD log**. In one sentence: interpolate physics, never interpolate alarms.

**Can healing hide real problems?** No — every healed row stores the repaired field names in `telemetry_records.healed_fields`, *and* logs a summary, *and* can be overlaid on charts via the Healed Frames annotation. A long streak of the same healed field is itself diagnostic (failing sensor or wiring).

**Why is `time` unique / why are duplicates silently skipped?** So that re-importing a CSV, replaying a session, or any reconnect hiccup can never double-count data (`ON CONFLICT (time) DO NOTHING`, migration V4). The cost: two genuinely different readings with identical timestamps would collide — at one frame per ~300 ms with millisecond stamps, that doesn't happen in practice.

**What happens if the database goes down?** Telemetry inserts fail and those readings are lost (there's no buffering between Node-RED and PostgreSQL). Importantly, the Catch nodes deliberately do **not** watch the logging chain ("Normalize Log Event" → "Log Database") — if they did, a failed log write would trigger another log write, forever. The loop is broken by design; the trade-off is that errors occurring *while the DB is down* go unrecorded. In Docker, `restart: unless-stopped` brings PostgreSQL back automatically.

**What happens if the broker (Mosquitto) goes down?** The ESP32's publishes go nowhere (lost), and Node-RED's MQTT node shows disconnected, reconnecting automatically. Same honest-gap behavior.

**Why does the Connection panel count dropped frames as "connected"?** Because it answers "is the radio link alive?", not "is the data good?". A malformed frame that arrives still proves the link works — the data quality story is told by the FD counter next to it.

**Why is fault decoding done in Grafana instead of Node-RED?** The raw bitmask number is stored; Grafana joins it against the definition tables at display time (`err & (1 << bit)`). Storage stays compact, and fault names/descriptions can be corrected later without touching historical data.

**Why do CSVs require timestamps when live frames don't?** A CSV is *historical* data — stamping it with import time would be a lie, planting old readings at today's date. Live frames are *present* data — arrival time is the truth. Different tenses, different rules.

**Why is the processed-CSV path separate?** Processed files already contain real units and true/false flags. Sending them through conversion again would scale already-scaled numbers (and "heal" perfectly fine values). The processed path parses and inserts only.

**Why drop a frame for one bad field at the parse stage, but heal one bad field later?** Before parsing succeeds, the program can't know *which* field is which — a 14-field frame might be missing any field. After parsing, identity is certain and surgical repair is safe.

**Why QoS 2 with a persistent session on the MQTT subscription?** Maximum delivery guarantee between broker and platform: nothing the broker accepted is lost, even if Node-RED restarts. The queue-flush clumping concern doesn't apply because the broker→platform link is on the same machine (or same datacenter) and essentially never backlogs; the fragile link (car→receiver) has no queue at all.

**Why PostgreSQL and not TimescaleDB?** Considered (see `information/processDocumentation.md`). The project runs in sessions, not continuously; plain PostgreSQL with a time index handles this scale comfortably with one less moving part.

**Why Flyway instead of writing tables by hand or an ORM (Prisma)?** Versioned migrations (V1–V4) run once each, in order, automatically, with history tracked in the database itself — and Flyway runs as a throwaway container, nothing to install.

**Why is Flyway "exited" in `docker compose ps`?** That's its design: run migrations, quit. Check it succeeded with `docker compose logs flyway`.

**Why the shifted ports (5433/1881/3001/5051)?** To avoid colliding with default installs of the same tools on your machine. Inside the Docker network, services still talk on standard ports (e.g. `postgresdb:5432`).

**Is it safe to click "Test Injection" twice?** Yes — a new run kills the previous one (the generator clears its interval timer first). Timestamps are current-time so the runs just append.

**Can two people import CSVs or run the generator at once?** Yes, but their rows interleave in the database by timestamp; the unique-time rule resolves any exact collisions by keeping the first arrival.

**What's protected when someone runs `docker compose down -v`?** Nothing, by default — it erases all volumes (database included). Mitigations the team uses/recommends: marking the database volume `external: true` (compose then refuses to delete it), a scheduled `pg_dump` backup container writing to a plain folder, cloud disk snapshots, and restricting who has SSH access on the cloud box in the first place.

**Is the data sent by the car encrypted or authenticated?** No — LoRa frames and MQTT (port 1883, `allow_anonymous true`) are plaintext. On a cloud deployment, anyone who finds the broker could publish fake frames. Acceptable for a race-team prototype; the hardening path is MQTT username/password + TLS (port 8883) on Mosquitto, both supported by ESP32 and Node-RED.

**How fast can data arrive?** The pipeline is event-driven; the FAKE generator pushes a frame every 300 ms comfortably, and Grafana's minimum refresh is 300 ms. The practical ceiling is far above the car's transmit rate.

**What's the storage footprint?** One row ≈ a few hundred bytes. A 2-hour session at 300 ms ≈ 24,000 rows ≈ a few MB. Years of racing fit in single-digit GB.

---

## 📁 Project folder layout

```
RapidAmente-TelemeTuna/
├── README.md                 ← you are here
├── infrastructure/
│   ├── docker-compose.yaml   ← defines all the services
│   ├── .env.example          ← template for your secrets (copy to .env)
│   └── .env                  ← YOUR secrets (you create this; not on GitHub)
├── database/
│   └── migrations/           ← SQL files Flyway runs to build the tables
│       ├── V1__init.sql              (telemetry_records)
│       ├── V2__add_event_logs.sql    (event_logs)
│       ├── V3__add_bitmask_definitions.sql
│       └── V4__unique_timestamp.sql  (no duplicate timestamps)
├── nodered/
│   ├── Dockerfile            ← builds Node-RED with the extra nodes baked in
│   ├── flows.json            ← the data-flow wiring (the whole pipeline)
│   └── data/                 ← put your CSV files here (not committed)
├── mosquitto/
│   └── config/mosquitto.conf ← MQTT broker settings
├── grafana/
│   └── provisioning/         ← pre-built dashboard & database connection
└── information/              ← the author's process log
```

---

## 🛠️ Troubleshooting

**"Flyway exited / stopped" — is that broken?**
No. Flyway runs once, builds the tables, and quits. Check with `docker compose logs flyway`.

**No data is showing up in Grafana.**
- Check the **Connection panel** (Pipeline Health tab) first — Disconnected means nothing is arriving at all.
- Did you feed data in? Try the **FAKE Data Generator**.
- Check `event_logs` — frames may have been dropped (`FD`) for being malformed.
- Confirm rows exist: `docker exec -it telemetry-postgresdb psql -U <USER> -d <DB> -c "SELECT count(*) FROM telemetry_records;"`

**Connection says Disconnected but the car is sending.**
Wrong broker address on the ESP32 (must be the cloud/host IP, port 1883), wrong topic (must be `car_telemetry`), or port 1883 blocked by the firewall / security group.

**Charts say "No data" after a CSV replay.**
The dashboard is looking at *Last 15 minutes* — set an absolute time range covering the file's dates.

**My CSV rows are all being dropped.**
CSV import requires a timestamp as the **first** column (16 columns total). A 15-column file is rejected with *"Bad field count"*.

**CSV import added no rows (or fewer than expected).**
Those timestamps already exist — duplicate protection working as designed.

**Heal/error counters look too low (or too high).**
They count only within the selected time range — widen or narrow the time picker.

**Node-RED can't connect to the database (local setup).**
You still have `postgresdb:5432` configured. Locally it must be `localhost:5433` with credentials matching your `.env`.

**Teammates can't open the dashboards.**
Cloud: use the cloud public IP; check ports 3001/1881/5051 in the cloud firewall. Local: host's LAN IP (not `localhost`), same subnet, host firewall open.

**Port already in use.**
Something else owns 5433, 1881, 1883, 3001, or 5051 — stop it or change the published port in `infrastructure/docker-compose.yaml`.

**Can't log in to Grafana / pgAdmin.**
Use the values from `.env`. If you changed them *after* first start, `docker compose down -v` (erases data!) and restart, or change them in the running app.

**Serial port won't open (local setup).**
Check the exact device name (`ls /dev/cu.*` on macOS, Device Manager on Windows), make sure no other program holds the port, baud = 38400.

---

## 📖 Glossary (plain-English definitions)

- **ESP32** — a small, cheap microcontroller board with built-in Wi-Fi. This project uses two: a **sender** on the car and a **receiver** that publishes to MQTT.
- **LoRa** — long-range, low-power radio; how the sender talks to the receiver.
- **Docker / container** — packages software so it runs the same on any computer, no manual installs.
- **Docker Compose** — starts several containers together from one config file.
- **Node-RED** — a visual, drag-and-wire programming tool; here it's the pipeline "brain".
- **MQTT / Mosquitto** — a lightweight publish/subscribe messaging system; Mosquitto is the broker ("post office").
- **QoS (MQTT)** — delivery guarantee level between broker and subscriber; this project subscribes at QoS 2 (strongest).
- **PostgreSQL (Postgres)** — the database storing all readings permanently.
- **Flyway** — applies versioned SQL migrations automatically, once each.
- **Grafana** — draws the live charts and gauges from the database.
- **pgAdmin** — a web interface for browsing the PostgreSQL database by hand.
- **Serial port / baud rate** — USB link to hardware and its speed (38400 here).
- **Raw value** — the unconverted -32767…32767 number from the hardware.
- **Healing** — replacing a clearly-broken reading with the last known-good value, with full disclosure in the data and logs.
- **Bitmask** — one number holding up to 16 yes/no fault switches, one per bit.
- **Frame** — one complete reading: 15 comma-separated data fields (16 with a leading timestamp).
- **FD** — "frame dropped": the log level for discarded frames.

---

*Thanks for reading — feel free to try it out. If anything's wrong with the tuna, or should you have any inquiries, please feel free to contact me on Instagram: [praery.in.april](https://www.instagram.com/praery.in.april)* 🐟

⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣿⡇⠛⠛⠿⡿⡟⠻⣻⣿⠛⠛⠟⠛⠛⠛⠃⠙⠛⣛
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠛⠁⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠀⣴⣶⣿⣿⣿⡏⠘⠟⠀⠀⠀⣼⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠘⢿⣿⣿⣿⡇⠠⡶⢠⠰⢸⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡯⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡠⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠂⠀⡙⣿⣿⢳⢰⡇⠀⠀⠈⠛⠛
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⢻⠿⠃⠀⠀⠀⠀⠀⣀⣾⣿⣿⣿⣿⣧⣈⣀⣀⣀⡀⠀⠀⠀⠀⠀⠀⠠⡱⢬⠉⠀⠈⣷⢔⠄⠀⢀⠀
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠇⠀⡘⠀⠀⠀⣠⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣄⡀⠀⠀⠀⠀⠈⡈⢁⡰⠀⠸⠀⠀⠀⣤⠀
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⠀⠀⣼⠀⢀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦⣀⠀⠀⠀⠈⠐⠯⠁⠁⠀⡁⣷⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡷⠀⣾⡏⢀⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦⠀⠀⠀⠀⠀⠀⠀⠀⠄⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⠟⡛⠃⠀⠀⠀⣿⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡆⠀⠈⠀⡀⠀⠀⠀⠀⡿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⡟⣴⠒⢠⣴⣿⡆⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠂⠀⠀⡇⣿⣿
⢂⠀⠀⠀⠀⠀⠀⢀⡿⠀⢸⣿⣿⡇⣿⣿⣿⣯⡉⠻⠿⢿⣿⢿⣿⣿⣿⣿⣿⣿⡿⣿⣿⣿⢿⣿⣿⢟⠀⣤⣶⡆⠀⡄⠀⠀⠀⡇⣿⣿
⢸⣄⠀⠀⠀⠀⠀⠈⠃⠀⠘⠿⠿⠁⣿⣿⣿⣿⣷⣤⣄⣀⠀⠁⢸⣿⣿⠛⠋⠉⠉⢀⣀⣜⣶⣶⡧⠊⠀⢳⣿⡇⠘⣸⠀⡄⠀⠘⣿⣿
⢸⣿⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣽⣇⡈⠉⠉⠉⠁⠀⠠⣴⣾⣿⣿⣧⠀⠀⠈⠉⠉⠙⠛⠋⢁⡤⠀⠘⢿⠇⠀⠻⠀⡇⠀⠀⣿⣿
⣘⣿⣾⣧⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡟⣿⣿⣶⣤⣤⣶⣾⣿⣿⣿⣿⣿⣿⣷⠙⣦⣄⣀⣀⢀⢶⣾⣿⠀⠀⠀⠀⠀⠀⠀⠇⠀⠀⣻⡿
⠿⣿⣭⡙⢷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠘⢻⣿⣿⣿⣿⣿⣿⣿⡿⣿⣿⣿⣿⣿⣧⣌⢿⣿⣿⣿⣿⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠘⠐⣿⣗
⠀⠉⢻⣿⣦⣙⢿⣦⣀⡀⠀⠀⠀⠀⢠⣴⣝⠿⣟⣿⣿⣯⠙⠁⠈⠙⠛⠉⠁⠋⣿⣿⣿⣿⠿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣛
⡀⣀⠘⣿⣿⣿⣿⣿⣿⣿⣿⣶⣶⠶⠂⣿⣿⣿⣿⣿⣿⣿⣦⣤⣤⣀⠀⠀⠀⢀⣿⣿⣿⣇⣴⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⢀⠀⢠⡄⣿
⣿⣷⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠈⣛⣿⣿⣿⡿⣿⣿⣿⢿⢻⣿⣻⣶⣿⣿⢿⣿⣿⡟⠀⠀⠀⠀⠤⠠⠀⠜⠀⠀⠀⠆⠤⠤⠟
⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠛⣁⣤⠀⠀⠀⠑⠙⢻⣿⣧⣀⣉⣈⡉⠳⠃⢀⣀⠈⠀⢺⠟⠁⠀⠀⠀⠀⠀⠐⢶⠀⣄⠀⠀⠀⢰⣶⣶⣶
⣿⣿⠿⠿⠟⠛⠛⠃⣀⣀⣾⣿⣿⣆⠀⠀⠀⠀⠀⡸⣿⠎⠫⠉⡛⢷⡶⢿⠟⠀⢀⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⠀⠀⠀⢺⣿⣿⣿
⣭⣤⣶⣶⣶⣶⣖⣿⠻⣷⣝⠻⣿⣿⣷⣄⠀⠀⠀⠀⢻⣧⡀⠀⠀⠀⠀⠀⠀⠀⠊⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠂⠻⢿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣬⢷⡌⠻⣦⠙⢿⣿⣿⣶⡀⠀⠀⠀⠘⢿⣷⣶⣶⠶⠶⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣷⠆⢀⣤⠉⣽⣾⢶⣄⠍⢻
⣿⣿⣿⣿⣿⣿⣿⣿⡞⢿⣄⠈⠳⣄⠙⣿⡿⣿⣶⣄⠀⠀⠀⠈⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢴⣏⣿⠿⢃⣴⣿⣿⣗⢻⣿⣿⣟⡛⠀
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣾⣿⣷⣦⣄⠱⠶⣶⣤⣌⠙⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣦⡿⠉⢠⣾⣿⣿⣿⢌⣇⢻⣿⣿⣿⣷
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣤⡙⠻⠿⠶⣧⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⡏⠁⣀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿