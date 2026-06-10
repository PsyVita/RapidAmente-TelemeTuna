# 🐟 TelemeTuna v1.0

**TelemeTuna** is a self-contained telemetry platform for an electric race car. It catches live sensor data streamed from the car, cleans it up, stores it safely in a database, and draws it on live dashboards.

It is built almost entirely out of ready-made building blocks that run inside **Docker**. If you can copy a file and run a couple of commands in a terminal, you can run this project.

> **Old Repository:** https://github.com/PsyVita/car-telemetry-attempt

---

## 📑 Table of Contents

1. [What this project does](#-what-this-project-does)
2. [How it all fits together (the big picture)](#-how-it-all-fits-together-the-big-picture)
3. [What's inside the box (the services)](#-whats-inside-the-box-the-services)
4. [The data: what a "frame" looks like](#-the-data-what-a-frame-looks-like)
5. [The processing pipeline, step by step](#-the-processing-pipeline-step-by-step)
6. [Before you start (prerequisites)](#-before-you-start-prerequisites)
7. [Installation & first run](#-installation--first-run)
8. [How to feed data in](#-how-to-feed-data-in)
9. [Optional: running Node-RED locally for a direct serial connection](#-optional-running-node-red-locally-for-a-direct-serial-connection)
10. [The database tables](#-the-database-tables)
11. [The Grafana dashboard](#-the-grafana-dashboard)
12. [Project folder layout](#-project-folder-layout)
13. [Troubleshooting](#-troubleshooting)
14. [Glossary (plain-English definitions)](#-glossary-plain-english-definitions)

---

## 🎯 What this project does

An electric race car is covered in sensors. While it drives, those sensors constantly report things like:

- How fast the motor is spinning (**RPM**)
- How much electric current and voltage the motor is drawing (**amps / volts**)
- How much twisting force it is producing (**torque**)
- How hot the electronics and motor are (**IGBT temperature / motor temperature**)
- Which gear it is in (**Drive / Reverse / Neutral**)
- A set of warning and error flags (cooling pump on, regen braking active, faults, etc.)

On the car, a **sender ESP32** collects this data and radios it to a **receiver ESP32** in the pit. The receiver stamps each reading with a timestamp and publishes it over **MQTT** to this platform.

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
   On the car                In the pit              ┌──────────────────────────────────────────┐
                                                     │           DOCKER (one command)            │
  ┌──────────┐   radio    ┌──────────┐    MQTT       │                                           │
  │  Sender  │ ─────────▶ │ Receiver │ ────────────▶ │   ┌──────────┐      ┌──────────────────┐  │
  │  ESP32   │   (LoRa)   │  ESP32   │  (timestamped │   │ Mosquitto│─────▶│     Node-RED     │  │
  └──────────┘            └──────────┘    frames)    │   │  (MQTT)  │      │  (clean+convert) │  │
                                                     │   └──────────┘      └────────┬─────────┘  │
                          ┌──────────┐               │                              │            │
                          │ CSV file │ ──────────────┼──────────────────────────────┤            │
                          │ (replay) │               │                              ▼            │
                          └──────────┘               │                     ┌──────────────────┐  │
                                                     │                     │   PostgreSQL DB  │  │
                                                     │   ┌──────────┐      │ (stores readings)│  │
                                                     │   │  Flyway  │      └────────┬─────────┘  │
                                                     │   │ (sets up │               │            │
                                                     │   │  the DB) │               ▼            │
                                                     │   └──────────┘      ┌──────────────────┐  │
                                                     │                     │      Grafana     │  │
                                                     │                     │   (dashboards)   │  │
                                                     │                     └──────────────────┘  │
                                                     └──────────────────────────────────────────┘
```

**In words:** The sender ESP32 on the car radios each reading to the receiver ESP32, which timestamps it and publishes it to **Mosquitto** (the MQTT "post office"). **Node-RED** is the "brain" that picks the message up, cleans and converts it, and writes the result into **PostgreSQL**. **Grafana** reads from PostgreSQL to draw the charts. **Flyway** is a one-shot helper that builds the database tables the first time you start up. CSV files can be fed straight into Node-RED to replay old data through the very same pipeline.

---

## 📦 What's inside the box (the services)

When you start the project with Docker, five things run together. You don't install them one by one — Docker does it for you.

| Service | What it is | Where you reach it | Why it's here |
|---|---|---|---|
| **PostgreSQL** | The database | `localhost:5433` | Permanent storage for every reading |
| **Node-RED** | Visual data-flow tool | http://localhost:1881 | The "brain" — cleans, converts, heals, logs |
| **Grafana** | Dashboard tool | http://localhost:3001 | Live charts and gauges |
| **Mosquitto** | MQTT message broker | `localhost:1883` | Carries live data messages |
| **Flyway** | Database migration tool | *(runs once, then exits)* | Creates the tables automatically on first start |

> 💡 **Why these ports?** They are deliberately shifted (5433 instead of the usual 5432, 1881 instead of 1880, 3001 instead of 3000) so they don't collide with other software you might already have running.

---

## 🔢 The data: what a "frame" looks like

Each reading from the car is one line of comma-separated values, called a **frame**. The standard frame has **16 fields**: a timestamp (added by the receiver ESP32) followed by **15 data fields**, always in this order:

| # | Field | Meaning | Example raw value |
|---|-------|---------|-------------------|
| 0 | *(timestamp)* | When the reading was taken (added by the receiver ESP32) | `2024-01-01T00:00:00.600Z` |
| 1 | `rpm` | Motor speed (raw, -32767…32767) | `15000` |
| 2 | `amp` | Current (raw) | `-8000` |
| 3 | `volt` | Voltage (raw) | `19660` |
| 4 | `trq` | Torque (raw) | `12000` |
| 5 | `mode` | Gear: `D`rive, `R`everse, `N`eutral | `D` |
| 6 | `igbt_c` | IGBT temperature (raw sensor count) | `21357` |
| 7 | `mot_c` | Motor temperature (raw sensor count) | `11644` |
| 8 | `err` | Error bitmask (a number; each bit = one fault) | `0` |
| 9 | `warn` | Warning bitmask | `0` |
| 10 | `L_REGEN` | Regenerative braking active? (0/1) | `0` |
| 11 | `L_ERR` | Error light (0/1) | `0` |
| 12 | `L_WARN` | Warning light (0/1) | `0` |
| 13 | `L_OK` | "All OK" light (0/1) | `1` |
| 14 | `L_PUMP` | Cooling pump light (0/1) | `0` |
| 15 | `drive_ena` | Drive enabled? (0/1) | `1` |

Example standard frame:

```
2024-01-01T00:00:00.600Z,15000,-8000,19660,12000,D,21357,11644,0,0,0,0,0,1,0,1
```

### The 15-field fallback

If a frame arrives over MQTT with only the 15 data fields and **no timestamp** (for example from a test tool that doesn't stamp its output), the pipeline does not throw it away: it stamps the frame with the moment it arrived and writes a `warn` entry to the event log so you know the timestamp is approximate. This is a **safety fallback only** — the receiver ESP32 is expected to always provide the timestamp.

### Raw vs. Processed CSV

Both kinds of CSV import **expect a timestamp as the first column** (16 columns total):

- A **raw** CSV holds a timestamp + the 15 raw fields exactly as the car produced them (raw -32767…32767 numbers). It goes through the **full cleaning pipeline**.
- A **processed** CSV holds a timestamp + 15 fields that have *already been through* this program once (real-world units, true/false flags). It is parsed and written straight to the database **without** conversion or healing, so already-clean data isn't mangled twice.

Rows with a missing or unreadable timestamp are dropped and logged.

---

## ⚙️ The processing pipeline, step by step

Inside Node-RED there are three "tabs" (think of them as three pages of wiring):

- **Real-Time Imports** — the entry point for live data (the MQTT listener on topic `car_telemetry`).
- **CSV Imports** — the entry points for loading raw or processed files.
- **Background Flow** — the actual cleaning/conversion pipeline that live data and raw CSVs funnel into.

Live MQTT frames travel through the **Background Flow** starting at step 1. Raw CSV rows have their timestamp separated on the CSV Imports tab first, then join the pipeline directly at step 2 — keeping the original timestamps from the file:

1. **Strip Timestamp** *(live data)* — Separates the timestamp from the data. A 16-field frame keeps its own timestamp; a 15-field frame is stamped with its arrival time and a warning is logged (see fallback above). Any other field count drops the frame. (Raw CSV rows get the same treatment from the **Strip Timestamp** node on the CSV Imports tab before joining here.)
2. **Parse CSV** — Splits the line into its 15 fields and checks each one. If a frame has the wrong number of fields, a missing value, or text where a number should be, the **whole frame is dropped** and a frame-drop (`FD`) event is logged.
3. **Raw → Real Conversion** — Scales the raw -32767…32767 numbers into real units (raw ÷ 32767 × real-world maximum):
   - `rpm` → up to 5,500 RPM (rounded to a whole number)
   - `amp` → up to 212.1 A
   - `volt` → up to 200 V
   - `trq` → up to 125 Nm
   A raw value outside -32767…32767 becomes `null` and is logged (the Heal step will repair it).
4. **Map Mode** — Turns the gear letter into a number (`N`=0, `D`=1, `R`=2). Anything else becomes `null` and is logged.
5. **Temperature Conversion** — Converts the raw temperature counts into °C. IGBT temperature uses a precise 32-point lookup table with linear interpolation; motor temperature uses a straight-line formula (raw 11446 = 30 °C, raw 16000 = 100 °C). Out-of-range raw values become `null` and are logged.
6. **Heal** — The safety net for the continuous values (`rpm`, `amp`, `volt`, `trq`, `igbt_c`, `mot_c`, `mode`). If a converted value is impossible (out of a sensible range, missing, `null`, or `NaN`), it is replaced with the **last known-good value** for that field. Every healed field name is recorded in the row's `healed_fields` column *and* summarized in the event log, so you always know it happened.
7. **Flags** — Converts the 0/1 light signals (`L_REGEN`, `L_ERR`, `L_WARN`, `L_OK`, `L_PUMP`, `drive_ena`) into true/false. Anything that isn't exactly 0 or 1 becomes `null` (flags are **not** healed) and an `error` is logged.
8. **Validate Bitmasks** — Sanity-checks the `err` and `warn` numbers (they must be whole numbers 0–65535). Invalid values become `null` and an `error` is logged. The bitmask numbers are stored as-is; decoding into named faults happens later in Grafana.
9. **Build Parameters** — Packs all the clean values together, ready for the database.
10. **Car Telemetry Database** — Writes the finished row into the `telemetry_records` table. The `time` column is **unique**: if a row with the same timestamp already exists, the new row is silently skipped. This means accidentally replaying the same data (e.g. importing a CSV twice) can never create duplicates.

### What happens when something goes wrong

Every step can raise its hand. There are two ways problems are recorded:

- Each pipeline node has a second output that sends structured warnings to a **"Normalize Log Event"** node, which writes them to the `event_logs` table.
- A **crash** in any node is caught by a global **Catch** node and logged as `critical`.

This means **nothing fails silently** — if a reading looks odd, there's a matching entry in the log explaining why.

### Event log severity levels

| Level | When it's used |
|---|---|
| `warn` | A single value was out of bounds and was *healed* (replaced with the last good value), or a frame arrived without a timestamp and was stamped on arrival. |
| `error` | A value was wrong and **not** healed (flags, bitmasks), so it was set to null. |
| `FD` | "Frame Dropped" — the whole frame was thrown away (wrong field count, non-numeric data, bad timestamp). |
| `critical` | An unexpected code error happened (caught by the global safety net). |

### Built-in test generator (no hardware needed)

The Background Flow tab contains a **"FAKE Data Generator"** wired to a **"Test Injection Node"**. One click simulates a full driving cycle (idle → accelerate → cruise → coast → regen → stop) and then deliberately injects fault bitmasks, every flag combination, and corrupted values that exercise the healing system — pushing realistic data through the entire pipeline into the database. (Its frames carry no timestamp, so you will also see the 15-field fallback warnings in action.)

---

## ✅ Before you start (prerequisites)

You only need **two** things installed:

1. **Docker Desktop** — https://www.docker.com/products/docker-desktop/
   This bundles everything (`docker` and `docker compose`). Install it, open it once, and wait until it says it's running.
2. **Git** — https://git-scm.com/downloads (to download this project).
   *(Or just download the project as a ZIP from GitHub if you prefer.)*

That's it. You do **not** need to install PostgreSQL, Node-RED, Grafana, or Node.js separately — Docker provides them.

> The only optional extra is **Node.js + Node-RED**, and only if you want the advanced *local serial port* setup described in its own section below.

---

## 🚀 Installation & first run

### Step 1 — Download the project

```bash
git clone https://github.com/PsyVita/car-telemetry-attempt.git
cd car-telemetry-attempt
```

### Step 2 — Create your environment (`.env`) file

The project keeps passwords out of the code in a file called `.env`. A template is provided that you copy and rename.

```bash
cd infrastructure
cp .env.example .env
```

Now open `infrastructure/.env` in any text editor. It looks like this:

```dotenv
# PostgreSQL
POSTGRES_USER=user
POSTGRES_PASSWORD=password
POSTGRES_DB=telemetry

# Grafana
GRAFANA_ADMIN_USER=user
GRAFANA_ADMIN_PASSWORD=password
```

Change the values to whatever you like (especially the passwords). **Remember what you set** — you'll use:
- `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` to connect to the database.
- `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` to log in to Grafana.

> ⚠️ The `.env` file is intentionally **not** uploaded to GitHub (it's listed in `.gitignore`) because it holds your passwords. Only `.env.example` is shared. This is why you have to create your own `.env` the first time.

### Step 3 — Start everything

From the `infrastructure` folder:

```bash
docker compose up -d
```

The first time, this downloads the images and builds Node-RED, so it can take a few minutes. The `-d` means "run in the background."

**What happens automatically:**
- PostgreSQL starts and creates an empty database.
- **Flyway** runs once and builds all the tables (`telemetry_records`, `event_logs`, and the bitmask definition tables). Then it exits — that's normal, don't be alarmed that it "stopped."
- Node-RED, Grafana, and Mosquitto come up and stay running.

### Step 4 — Check that it's working

Open these in your browser:

- **Node-RED (the brain/editor):** http://localhost:1881
- **Grafana (dashboards):** http://localhost:3001 — log in with the Grafana user/password from your `.env`.

To peek directly at the database:

```bash
docker exec -it telemetry-postgresdb psql -U <YOUR_POSTGRES_USER> -d <YOUR_POSTGRES_DB> -c "SELECT count(*) FROM telemetry_records;"
```

(Replace the placeholders with what you put in `.env`.)

### Step 5 — Generate some test data (no hardware needed!)

You don't need a real car to see it work:

1. Open Node-RED at http://localhost:1881.
2. Go to the **Background Flow** tab.
3. Find the **"Test Injection Node"** (it's connected to the **"FAKE Data Generator"**) and click the little square button on its left edge.
4. Watch the generator's status bar step through the driving cycle and test phases while rows appear in Grafana.

### Useful Docker commands

```bash
docker compose ps          # see what's running
docker compose logs -f     # watch live logs from all services
docker compose logs flyway # check the database got set up
docker compose down        # stop everything (keeps your data)
docker compose down -v     # stop AND erase all stored data (start fresh)
```

---

## 📥 How to feed data in

### Option 1 — MQTT from the receiver ESP32 (the live path)

Node-RED is always listening on the MQTT topic **`car_telemetry`** (broker: Mosquitto, port `1883`).

The receiver ESP32 should publish each frame as plain text in the standard 16-field format — **timestamp first, then the 15 data fields**:

```
2024-01-01T00:00:00.600Z,15000,-8000,19660,12000,D,21357,11644,0,0,0,0,0,1,0,1
```

Anything published there flows straight into the pipeline. If the timestamp is ever missing (15 fields), the frame is still accepted and stamped with its arrival time, but a warning is logged — don't rely on this.

You can also test by hand from any machine with an MQTT client:

```bash
mosquitto_pub -h localhost -p 1883 -t car_telemetry \
  -m "2024-01-01T00:00:00.600Z,15000,-8000,19660,12000,D,21357,11644,0,0,0,0,0,1,0,1"
```

### Option 2 — CSV file import (replays and testing)

Great for replaying logged sessions. Remember: **both kinds of CSV need the timestamp column** (16 columns total).

1. Put your CSV file somewhere Node-RED can read it. In the Docker setup, the `nodered` folder is mounted inside the container at `/data`, so a file at `nodered/data/yourfile.csv` is seen by Node-RED as `/data/data/yourfile.csv`. *(Create the `nodered/data` folder if it doesn't exist — test CSVs are deliberately not committed to the repository.)*
2. In Node-RED, open the **CSV Imports** tab.
3. There are two starting points:
   - **Load Raw CSV** — for files with timestamp + 15 **raw** fields. These go through the full cleaning pipeline.
   - **Load Processed CSV** — for files with timestamp + 15 **already-processed** fields. These are written straight to the database.
4. Update the file path in the matching **"file in"** node (the comments next to them say *"Edit Path to Insert Your File"*).
5. Click the inject button to load and process the file. Blank lines are ignored; rows with bad timestamps or field counts are dropped and logged.

> 🔁 **Safe to re-run:** timestamps are unique in the database, so importing the same file twice simply skips the rows that are already stored — no duplicates.

---

## 🔌 Optional: running Node-RED locally for a direct serial connection

> **Most people can skip this section.** The normal live path is MQTT from the receiver ESP32 (Option 1 above). This section only matters if you want Node-RED to read a USB serial device (e.g. the LoRa receiver plugged straight into your laptop) **directly**, without MQTT.

### Why this is needed

Docker containers are sealed off from your computer's physical hardware. They **cannot directly access USB serial ports** (especially on macOS and Windows). So to use Node-RED's built-in serial-port nodes, you must run Node-RED **natively on your own machine** instead of in the container. The serial-port nodes you can see in the committed flow are disabled placeholders for exactly this purpose.

The plan is: **keep PostgreSQL, Grafana, Mosquitto, and Flyway running in Docker** (they don't need hardware access), but **turn off the Docker Node-RED** and run a local one in its place.

> 📝 The local flow (the wiring that includes the active serial-port nodes) is provided to you separately and is **not** committed to this repository. You'll import it into your local Node-RED in Step 5.

### Step 1 — Install Node.js (which includes npm)

Download the **LTS** version from https://nodejs.org and install it. Verify with:

```bash
node --version
npm --version
```

### Step 2 — Install Node-RED on your computer

```bash
npm install -g --unsafe-perm node-red
```

Test that it installed (stop it again with `Ctrl+C`):

```bash
node-red
```

This creates a settings folder in your home directory called **`~/.node-red`** — that's where your local Node-RED lives.

### Step 3 — Install the required add-on nodes (palette)

```bash
cd ~/.node-red
npm install node-red-node-serialport node-red-contrib-postgresql
```

- `node-red-node-serialport` — lets Node-RED read the USB serial port (the important one).
- `node-red-contrib-postgresql` — lets Node-RED write to the database.

*(Alternatively, install these from inside Node-RED via the menu ☰ → **Manage palette** → **Install**.)*

### Step 4 — Turn off the Docker Node-RED (so the two don't clash)

You don't want two Node-REDs both writing to the database. Stop just the container:

```bash
cd infrastructure
docker compose stop node-red
```

Leave everything else running. (`docker compose ps` should still show PostgreSQL, Mosquitto, and Grafana up, but not `telemetry-nodered`.)

### Step 5 — Start local Node-RED and import the flow

```bash
node-red
```

Open **http://localhost:1880** (note: **1880**, the local default — *not* 1881, which is the Docker one). Then import the provided local flow: menu ☰ → **Import** → paste the flow JSON → **Import**.

### Step 6 — Fix the database connection (the important change)

Inside Docker, Node-RED reaches the database using the name `postgresdb` on port `5432`. Your **local** Node-RED is outside Docker, so it must use the port Docker *published* to your computer: **`localhost:5433`**.

1. Double-click any **PostgreSQL** node (e.g. *"Car Telemetry Database"*), then click the pencil ✏️ next to its config to edit the **"Telemetry DB"** connection.
2. Set the fields to:

   | Field | Value |
   |---|---|
   | **Host** | `localhost` |
   | **Port** | `5433` |
   | **Database** | the `POSTGRES_DB` from your `.env` (e.g. `telemetry`) |
   | **User** | the `POSTGRES_USER` from your `.env` |
   | **Password** | the `POSTGRES_PASSWORD` from your `.env` |

3. Click **Update** / **Done**. This one connection config is shared by all the database nodes, so you only set it once.

> Always double-check the user, password, and database name match your own `.env`, or the writes will silently fail.

### Step 7 — Fix the CSV file paths (if you use CSV import)

The Docker paths like `/data/data/yourfile.csv` only exist *inside* the container. On your local machine, change the **"file in"** nodes on the **CSV Imports** tab to a real path on your computer, for example:

```
/Users/you/githubProjects/car-telemetry-attempt/nodered/data/yourfile.csv
```

### Step 8 — Configure the serial-port node

1. Double-click the **serial in** node, then edit its serial-port config.
2. Set the **Serial Port** to your actual device:
   - **macOS:** something like `/dev/cu.usbserial-0001` or `/dev/cu.usbmodemXXXX`
   - **Windows:** something like `COM5`
   - **Linux:** something like `/dev/ttyUSB0`
3. Set the **Baud Rate** to match your device (this project uses **38400** for the LoRa receiver).
4. Click **Update** / **Done** and then **Deploy** (top-right).

To find your serial port name:
- **macOS / Linux:** `ls /dev/cu.*` or `ls /dev/ttyUSB*`
- **Windows:** open Device Manager → "Ports (COM & LPT)".

### Step 9 — Deploy and verify

Click the red **Deploy** button. The serial node should turn green ("connected"). Live frames will now flow through the same pipeline into the Dockerized PostgreSQL, and Grafana (still on http://localhost:3001) will keep showing them.

### Quick recap of what changes for the local option

| Thing | Docker default | Local Node-RED value |
|---|---|---|
| Node-RED editor URL | http://localhost:1881 | http://localhost:1880 |
| Database **Host** | `postgresdb` | `localhost` |
| Database **Port** | `5432` | `5433` |
| CSV file path | `/data/data/...` | a real path on your disk |
| Serial port | (can't be used) | your real device, e.g. `/dev/cu.usbserial-0001` |
| Docker `node-red` service | running | **stopped** |

---

## 🗄️ The database tables

Flyway creates these automatically. You never write them by hand.

### `telemetry_records` — every cleaned reading

| Column | Type | Notes |
|---|---|---|
| `time` | timestamp | when the reading happened (from the receiver ESP32, or arrival time as fallback). **Unique** — a second row with the same timestamp is skipped on insert |
| `rpm`, `amp`, `volt`, `trq` | number | converted real-world values |
| `mode` | integer | 0=Neutral, 1=Drive, 2=Reverse |
| `err`, `warn` | integer | bitmask numbers (decoded via the definition tables) |
| `igbt_c`, `mot_c` | number | temperatures in °C |
| `l_regen`, `l_err`, `l_warn`, `l_ok`, `l_pump`, `drive_ena` | true/false | status lights |
| `healed_fields` | list of text | which fields (if any) had to be healed for this row |

### `event_logs` — the pipeline's diary

Every warning, error, frame drop, and crash from the pipeline lands here.

| Column | Type | Notes |
|---|---|---|
| `time` | timestamp | when it happened |
| `level` | text | `warn`, `error`, `FD`, `critical` |
| `node` | text | which pipeline step raised it |
| `message` | text | human-readable explanation |
| `fields` | list of text | which field names were involved (e.g. the healed fields) |

### `err_bit_definitions` & `warn_bit_definitions` — the fault dictionary

The `err` and `warn` columns are stored as plain numbers where each individual **bit** means a specific fault (for example, bit 7 of `err` = "IGBT-Temp. Max. Limit"). These two reference tables translate each bit (0–15) into a human-readable name and description, so Grafana can show "IGBT-Temp. Max. Limit" instead of a cryptic number.

---

## 📊 The Grafana dashboard

A pre-built dashboard is provisioned automatically — open Grafana at http://localhost:3001 and it's already there. It refreshes very fast (down to 300 ms) and shows, over your selected time window:

- **Live gauges & stats** — RPM, voltage, current, torque, motor & IGBT temperature, drive mode, and the six status lights, always showing the latest reading.
- **Time-series charts** — RPM, torque, voltage & current, and both temperatures over time.
- **Active Errors & Warnings** — the current `err`/`warn` bitmasks decoded into named faults using the definition tables.
- **Pipeline health** — the live `event_logs` feed plus counters for healed frames, errors, criticals, frame drops, and warnings.
- **Optional annotations** — overlays for car errors, car warnings, healed frames, frame drops, and program criticals can be toggled in the dashboard settings.

---

## 📁 Project folder layout

```
car-telemetry-attempt/
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
└── information/              ← this README & the author's process log
```

---

## 🛠️ Troubleshooting

**"Flyway exited / stopped" — is that broken?**
No. Flyway is supposed to run once, build the tables, and quit. Check it succeeded with `docker compose logs flyway`.

**No data is showing up in Grafana.**
- Did you actually feed data in? Try the **FAKE Data Generator** in Node-RED first.
- Is the receiver ESP32 publishing to the right place? Topic must be `car_telemetry`, broker port `1883`.
- Check the `event_logs` table — frames may have been dropped (`FD`) for being malformed.
- Confirm rows exist: `docker exec -it telemetry-postgresdb psql -U <USER> -d <DB> -c "SELECT count(*) FROM telemetry_records;"`

**Lots of "No timestamp in payload" warnings in the event log.**
Your data source is sending 15-field frames without the leading timestamp. The data is still stored (stamped on arrival), but the receiver ESP32 should be fixed to include the timestamp.

**My CSV rows are all being dropped.**
The CSV import expects a timestamp as the **first** column (16 columns total). A 15-column file without timestamps will be rejected with *"Bad field count"* — add a timestamp column first.

**I imported a CSV but the row count didn't go up (or went up less than expected).**
Rows whose timestamps already exist in `telemetry_records` are skipped on purpose (duplicate protection). If you're re-importing the same file, that's everything working as designed. Check `SELECT count(*)` before and after, and the event log for dropped (`FD`) rows.

**Node-RED can't connect to the database (local setup).**
You almost certainly still have the host/port set to `postgresdb:5432`. Locally it must be `localhost:5433`, with the user/password/database matching your `.env`. See [Step 6](#step-6--fix-the-database-connection-the-important-change).

**Port already in use.**
Something else on your machine is using 5433, 1881, 1883, or 3001. Stop that program, or change the published port in `infrastructure/docker-compose.yaml`.

**Can't log in to Grafana.**
Use the `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` from your `.env`. If you changed them *after* the first start, you may need `docker compose down -v` (this erases stored data) and start again.

**Serial port won't open (local setup).**
Double-check the exact device name (`ls /dev/cu.*` on macOS, Device Manager on Windows), make sure no other program (like the Arduino IDE) is already holding the port, and confirm the baud rate matches the device (38400).

---

## 📖 Glossary (plain-English definitions)

- **ESP32** — a small, cheap microcontroller board. This project uses two: a **sender** on the car and a **receiver** in the pit.
- **LoRa** — a long-range, low-power radio technology; how the sender ESP32 talks to the receiver ESP32.
- **Docker / container** — a way to package software so it runs the same on any computer, without you installing each piece by hand.
- **Docker Compose** — a tool that starts several containers together from one config file.
- **Node-RED** — a visual, drag-and-wire programming tool. Here it's the "brain" that cleans and routes the data.
- **MQTT / Mosquitto** — a lightweight messaging system for sending small messages (like sensor readings) around. Mosquitto is the specific "post office" (broker) used.
- **PostgreSQL (Postgres)** — the database that stores all the readings permanently.
- **Flyway** — a tool that builds/updates the database tables automatically and remembers which changes it already applied.
- **Grafana** — the tool that draws live charts and gauges from the database.
- **Serial port** — a USB connection your computer uses to talk to hardware like a radio receiver.
- **Baud rate** — the speed of a serial connection (e.g. 38400). Both sides must agree on it.
- **Raw value** — the unconverted number (-32767…32767) straight from the hardware, before it's turned into real units.
- **Healing** — replacing a clearly-broken reading with the last known-good value so one glitch doesn't ruin the data.
- **Bitmask** — a single number that secretly holds many yes/no flags, one per bit. The definition tables explain what each bit means.
- **Frame** — one complete reading: one line of comma-separated values (timestamp + 15 data fields).

---

*TelemeTuna v1.0 — built with Node-RED, PostgreSQL, Mosquitto, Grafana, and Flyway, all orchestrated by Docker.* 🐟