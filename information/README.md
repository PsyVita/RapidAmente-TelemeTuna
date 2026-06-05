# 🚗 Car Telemetry Platform

A self-contained system that takes live data coming off an electric race car, cleans it up, stores it safely in a database, and draws it on live dashboards.

It is built almost entirely out of ready-made building blocks that run inside **Docker**, so you do not need to be a programmer to get it running. If you can copy a file and run a couple of commands in a terminal, you can run this project.

> **Repository:** https://github.com/PsyVita/car-telemetry-attempt

---

## 📑 Table of Contents

1. [What this project does](#-what-this-project-does)
2. [How it all fits together (the big picture)](#-how-it-all-fits-together-the-big-picture)
3. [What's inside the box (the services)](#-whats-inside-the-box-the-services)
4. [The data: what a "frame" looks like](#-the-data-what-a-frame-looks-like)
5. [The processing pipeline, step by step](#-the-processing-pipeline-step-by-step)
6. [Before you start (prerequisites)](#-before-you-start-prerequisites)
7. [Installation & first run (the easy path with Docker)](#-installation--first-run-the-easy-path-with-docker)
8. [How to feed data in](#-how-to-feed-data-in)
9. [Running Node-RED locally for the Serial Port option](#-running-node-red-locally-for-the-serial-port-option)
10. [The database tables](#-the-database-tables)
11. [Project folder layout](#-project-folder-layout)
12. [Troubleshooting](#-troubleshooting)
13. [Glossary (plain-English definitions)](#-glossary-plain-english-definitions)

---

## 🎯 What this project does

An electric car is covered in sensors. While it drives, those sensors constantly report things like:

- How fast the motor is spinning (**RPM**)
- How much electric current and voltage the motor is drawing (**amps / volts**)
- How much twisting force it is producing (**torque**)
- How hot the electronics and motor are (**IGBT temperature / motor temperature**)
- Which gear it is in (**Drive / Reverse / Neutral**)
- A set of warning and error flags (battery pump on, regen braking active, faults, etc.)

That raw data is messy. It arrives as long strings of numbers, sometimes with missing values, sometimes corrupted, and the numbers are in a "raw" computer format (0–32767) instead of real-world units.

**This platform does four things:**

1. **Ingests** the data — accepts it from a radio/serial link, from an MQTT message, or from a CSV file.
2. **Cleans & converts it** — turns raw numbers into real units (RPM, °C, amps…), repairs ("heals") corrupted readings using the last known-good value, and drops anything hopelessly broken.
3. **Stores it** — saves every reading in a PostgreSQL database, plus a separate log of every warning/error that happened along the way.
4. **Visualizes it** — shows it all on live Grafana dashboards.

Everything is logged, so you can always trace *why* a value looks the way it does.

---

## 🧩 How it all fits together (the big picture)

```
                                    ┌──────────────────────────────────────────┐
   Car sensors                      │            DOCKER (one command)           │
        │                           │                                            │
        ▼                           │   ┌──────────┐      ┌──────────────────┐   │
  Radio / LoRa                      │   │ Mosquitto│─────▶│     Node-RED     │   │
   receiver                         │   │  (MQTT)  │      │  (clean+convert) │   │
        │                           │   └──────────┘      └────────┬─────────┘   │
        │   3 ways in               │        ▲                     │             │
        ├─────────────────────────▶ │        │                     ▼             │
        │  (A) MQTT message          │       │            ┌──────────────────┐   │
        │  (B) CSV file              │        │            │   PostgreSQL DB  │   │
        │  (C) Serial port*          │        │            │ (stores readings)│   │
        │                           │        │            └────────┬─────────┘   │
        ▼                           │        │                     │             │
  serial-bridge.py ─────────────────┼────────┘                     ▼             │
  (turns serial into MQTT)          │                     ┌──────────────────┐   │
                                    │   ┌──────────┐      │      Grafana      │   │
                                    │   │  Flyway  │      │   (dashboards)    │   │
                                    │   │ (sets up │      └──────────────────┘   │
                                    │   │  the DB) │                              │
                                    │   └──────────┘                              │
                                    └──────────────────────────────────────────┘

  * The Serial Port option (C) needs Node-RED running on your own
    computer instead of in Docker — see its own section below.
```

**In words:** Data comes in three ways. It always ends up flowing into **Node-RED**, which is the "brain" that cleans and converts it. Node-RED writes the clean data into **PostgreSQL**, and **Grafana** reads from PostgreSQL to draw the charts. **Mosquitto** is the messaging post office for live data, and **Flyway** is a one-shot helper that builds the database tables the first time you start up.

---

## 📦 What's inside the box (the services)

When you start the project with Docker, six things run together. You don't install them one by one — Docker does it for you.

| Service | What it is | Where you reach it | Why it's here |
|---|---|---|---|
| **PostgreSQL** | The database | `localhost:5433` | Permanent storage for every reading |
| **Node-RED** | Visual data-flow tool | http://localhost:1881 | The "brain" — cleans, converts, heals, logs |
| **Grafana** | Dashboard tool | http://localhost:3001 | Live charts and gauges |
| **Mosquitto** | MQTT message broker | `localhost:1883` | Carries live data messages |
| **Flyway** | Database migration tool | *(runs once, then exits)* | Creates the tables automatically on first start |
| **serial-bridge** | A small Python helper *(optional, run by hand)* | — | Reads a USB serial port and forwards it to MQTT |

> 💡 **Why these ports?** They are deliberately shifted (5433 instead of the usual 5432, 1881 instead of 1880, 3001 instead of 3000) so they don't collide with other software you might already have running.

---

## 🔢 The data: what a "frame" looks like

Each reading from the car is one line of comma-separated values, called a **frame**. A frame has **15 fields**, always in this order:

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
| 10 | `L_REGEN` | Regenerative braking active? (0/1) | `0` |
| 11 | `L_ERR` | Error light (0/1) | `0` |
| 12 | `L_WARN` | Warning light (0/1) | `0` |
| 13 | `L_OK` | "All OK" light (0/1) | `1` |
| 14 | `L_PUMP` | Cooling pump light (0/1) | `0` |
| 15 | `drive_ena` | Drive enabled? (0/1) | `1` |

Example raw frame:

```
15000,-8000,19660,12000,D,21357,11644,0,0,0,0,0,1,0,1
```

### Raw vs. Processed CSV

- A **raw** CSV has exactly these 15 fields (no date in front).
- A **processed** CSV has **16 fields**, because the very first field is a timestamp (e.g. `2024-01-01T00:00:00.600Z`). These are files that have *already been through* this program once and exported with a time column.

Node-RED automatically figures out which kind it's looking at: 15 fields → it stamps the arrival time itself; 16 fields → it uses the timestamp already in the file.

---

## ⚙️ The processing pipeline, step by step

Inside Node-RED there are three "tabs" (think of them as three pages of wiring):

- **Real-Time Imports** — the entry point for live data (MQTT or serial).
- **CSV Imports** — the entry point for loading data from files.
- **Background Flow** — the actual cleaning/conversion pipeline that everything funnels into.

Whatever the source, every frame travels through the **Background Flow** in this order:

1. **Strip Timestamp** — Separates the date from the data. If the frame already has a timestamp it keeps it; if not, it assigns one (the first message gets the real clock time, and each following message is spaced +300 ms apart so the timeline stays even).
2. **Parse CSV** — Splits the line into its 15 fields and checks each one. If a frame has the wrong number of fields or contains text where a number should be, the **whole frame is dropped** and a warning is logged.
3. **Raw → Real Conversion** — Converts the raw 0–32767 numbers into real units:
   - `rpm` → up to 5500 RPM
   - `amp` → up to 212.1 A
   - `volt` → up to 200 V
   - `trq` → up to 125 Nm
4. **Map Mode** — Turns the gear letter into a number (`N`=0, `D`=1, `R`=2).
5. **Temperature Conversion** — Converts the raw temperature counts into °C. IGBT temperature uses a precise 32-point lookup table; motor temperature uses a straight-line formula.
6. **Heal** — The safety net. If a converted value is impossible (out of a sensible range, missing, or `NaN`), it is replaced with the **last known-good value** for that field. Every healed field is recorded so you know it happened.
7. **Flags** — Converts the 0/1 light signals into true/false.
8. **Validate Bitmasks** — Sanity-checks the `err` and `warn` numbers (they must be whole numbers 0–65535).
9. **Build Parameters** — Packs all the clean values together, ready for the database.
10. **Car Telemetry Database** — Writes the finished row into the `telemetry_records` table.

### What happens when something goes wrong

Every step can raise its hand. There are two ways problems are recorded:

- A **warning** (e.g. one value was out of range and got healed) is sent to a **"Normalize Log Event"** node, then written to the `event_logs` table.
- A **crash** in any node is caught by a global **Catch** node and also logged as `critical`.

This means **nothing fails silently** — if a reading looks odd, there's a matching entry in the log explaining why.

### The healing/logging severity levels

| Level | When it's used |
|---|---|
| `warn` | A single value was out of bounds and was *healed* (replaced with the last good value). |
| `error` | A value was wrong and **not** healed, so it was set to null / the frame dropped. |
| `critical` | An unexpected code error happened (caught by the safety net). |

---

## ✅ Before you start (prerequisites)

You only need **two** things installed for the normal (Docker) path:

1. **Docker Desktop** — https://www.docker.com/products/docker-desktop/
   This bundles everything (`docker` and `docker compose`). Install it, open it once, and wait until it says it's running.
2. **Git** — https://git-scm.com/downloads (to download this project).
   *(Or just download the project as a ZIP from GitHub if you prefer.)*

That's it. You do **not** need to install PostgreSQL, Node-RED, Grafana, or Node.js separately for the basic setup — Docker provides them.

> Extra tools you only need for the optional advanced paths are listed in their own sections:
> - **Python 3** — only for the `serial-bridge` helper.
> - **Node.js + Node-RED** — only for the *local* Serial Port option.

---

## 🚀 Installation & first run (the easy path with Docker)

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
3. Find the **"Test Injection Node"** (it's connected to a **"FAKE Data Generator"**) and click the little square button on its left edge.
4. It will simulate a full driving cycle (idle → accelerate → cruise → coast → regen → stop), pushing realistic data through the whole pipeline and into the database.
5. Watch the rows appear in Grafana or query the database again.

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

There are three ways to get data into the system. The first two work with the standard Docker setup. The third (direct serial port) needs the special local setup described in the next section.

### Option 1 — MQTT (recommended for live data)

Node-RED is always listening for MQTT messages on the topic **`car_telemetry`**. Anything published there (a 15-field raw frame, or a 16-field frame with a leading timestamp) flows straight into the pipeline.

If your hardware speaks over a USB **serial** cable, use the included **`serial-bridge`** helper to forward serial → MQTT. Because Docker containers cannot see your computer's physical USB ports, this little Python script does the hand-off:

```bash
cd serial-bridge
pip install -r requirements.txt

# Point it at your device and run it:
SERIAL_PORT=/dev/cu.usbserial-0001 BAUD_RATE=38400 python3 bridge.py
```

It reads each line off the serial port, stamps it with the arrival time, and publishes it to Mosquitto, where the Dockerized Node-RED picks it up. Everything is configurable with environment variables (`SERIAL_PORT`, `BAUD_RATE`, `MQTT_HOST`, `MQTT_PORT`, `MQTT_TOPIC`, …) so you never edit the script itself.

### Option 2 — CSV file import

Great for replaying logs or testing.

1. Put your CSV file somewhere Node-RED can read it. In the Docker setup, the `nodered` folder is mounted inside the container at `/data`, so a file at `nodered/data/yourfile.csv` is seen by Node-RED as `/data/data/yourfile.csv`.
2. In Node-RED, open the **CSV Imports** tab.
3. There are two starting points:
   - **Load Raw CSV** — for files with the 15 raw fields.
   - **Load Processed CSV** — for files that already have a timestamp + 15 fields (16 total).
4. Update the file path in the matching **"file in"** node (the comments next to them say *"Edit Path to Insert Your File"*).
5. Click the inject button to load and process the file.

Two sample files are included to try this out: `nodered/data/test_raw.csv` and `nodered/data/test_processed.csv`.

### Option 3 — Direct Serial Port (needs local Node-RED → see below)

If you want Node-RED to read the USB serial port **directly** (without the Python bridge), Node-RED has to run on your own computer rather than inside Docker. That's the next section.

---

## 🔌 Running Node-RED locally for the Serial Port option

### Why this is needed

Docker containers are sealed off from your computer's physical hardware. They **cannot directly access USB serial ports** (this is especially true on macOS and Windows). So if you want to use Node-RED's built-in **serial-port nodes** to talk straight to the device, you must run Node-RED **natively on your own machine** instead of in the container.

> You have two choices for serial input. Pick one:
> - **Easy:** keep the Dockerized Node-RED and use the Python `serial-bridge` (Option 1 above). Nothing in this section is needed.
> - **Direct:** run Node-RED locally as described here, and use its serial-port nodes directly.

The plan is: **keep PostgreSQL, Grafana, Mosquitto, and Flyway running in Docker** (they don't need hardware access), but **turn off the Docker Node-RED** and run a local one in its place.

> 📝 The local flow (the wiring that includes the serial-port nodes) is provided to you separately and is **not** committed to this repository. You'll import it into your local Node-RED in Step 5.

### Step 1 — Install Node.js (which includes npm)

Node-RED runs on Node.js.

- Download the **LTS** version from https://nodejs.org and install it.
- Verify it worked by opening a terminal and running:

```bash
node --version
npm --version
```

Both should print a version number.

### Step 2 — Install Node-RED on your computer

```bash
npm install -g --unsafe-perm node-red
```

Test that it installed (you can stop it again with `Ctrl+C` right after):

```bash
node-red
```

This creates a settings folder in your home directory called **`~/.node-red`** — that's where your local Node-RED lives.

### Step 3 — Install the required add-on nodes (palette)

This project uses three add-on node packages. Install them into your local Node-RED folder:

```bash
cd ~/.node-red
npm install node-red-node-serialport node-red-contrib-postgresql @flowfuse/node-red-dashboard
```

- `node-red-node-serialport` — lets Node-RED read the USB serial port (the important one for this option).
- `node-red-contrib-postgresql` — lets Node-RED write to the database.
- `@flowfuse/node-red-dashboard` — the dashboard widgets.

*(Alternatively you can install these from inside Node-RED via the menu ☰ → **Manage palette** → **Install**.)*

### Step 4 — Turn off the Docker Node-RED (so the two don't clash)

You don't want two Node-REDs both writing to the database. Stop just the container:

```bash
cd infrastructure
docker compose stop node-red
```

Leave everything else running. (To confirm, `docker compose ps` should still show PostgreSQL, Mosquitto, Grafana up, but not `telemetry-nodered`.)

> If you'd rather it never start again, you can comment out the whole `node-red:` service block in `infrastructure/docker-compose.yaml`. Stopping it is enough for normal use.

### Step 5 — Start local Node-RED and import the flow

```bash
node-red
```

Open **http://localhost:1880** in your browser (note: **1880**, the local default — *not* 1881, which was the Docker one).

Then import the provided local flow: menu ☰ → **Import** → paste the flow JSON → **Import**.

### Step 6 — Fix the database connection (the important change)

This is the step most people miss. Inside Docker, Node-RED reached the database using the name `postgresdb` on port `5432`. But your **local** Node-RED is outside Docker, so it must reach the database through the port that Docker *published* to your computer: **`localhost:5433`**.

1. In Node-RED, double-click any **PostgreSQL** node (e.g. *"Car Telemetry Database"*), then click the pencil ✏️ next to its config to edit the **"Telemetry DB"** connection.
2. Set the fields to:

   | Field | Value |
   |---|---|
   | **Host** | `localhost` |
   | **Port** | `5433` |
   | **Database** | the `POSTGRES_DB` from your `.env` (e.g. `telemetry`) |
   | **User** | the `POSTGRES_USER` from your `.env` |
   | **Password** | the `POSTGRES_PASSWORD` from your `.env` |

3. Click **Update** / **Done**. This one connection config is shared by all the database nodes, so you only set it once.

> The local flow that was provided is already pointing at `localhost:5433` — but **always double-check** that the user, password, and database name match what you put in your own `.env`, or the writes will silently fail.

### Step 7 — Fix the CSV file paths (if you use CSV import)

The Docker paths like `/data/data/test_raw.csv` only exist *inside* the container. On your local machine, change the **"file in"** nodes on the **CSV Imports** tab to a real path on your computer, for example:

```
/Users/you/githubProjects/car-telemetry-attempt/nodered/data/test_raw.csv
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
| `time` | timestamp | when the reading happened |
| `rpm`, `amp`, `volt`, `trq` | number | converted real-world values |
| `mode` | integer | 0=Neutral, 1=Drive, 2=Reverse |
| `err`, `warn` | integer | bitmask numbers (decoded via the definition tables) |
| `igbt_c`, `mot_c` | number | temperatures in °C |
| `l_regen`, `l_err`, `l_warn`, `l_ok`, `l_pump`, `drive_ena` | true/false | status lights |
| `healed_fields` | list of text | which fields (if any) had to be healed for this row |

### `event_logs` — the pipeline's diary

Every warning, error, and crash from the pipeline lands here.

| Column | Type | Notes |
|---|---|---|
| `time` | timestamp | when it happened |
| `level` | text | `warn`, `error`, `critical`, … |
| `node` | text | which step raised it |
| `message` | text | human-readable explanation |
| `fields` | list of text | which field names were involved |

### `err_bit_definitions` & `warn_bit_definitions` — the fault dictionary

The `err` and `warn` columns are stored as plain numbers where each individual **bit** means a specific fault (for example, bit 7 of `err` = "IGBT temperature max limit"). These two reference tables translate each bit into a human-readable name and description, so Grafana can show "IGBT-Temp. Max. Limit" instead of a cryptic number.

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
│       └── V3__add_bitmask_definitions.sql
├── nodered/
│   ├── Dockerfile            ← builds Node-RED with the extra nodes baked in
│   ├── flows.json            ← the Dockerized data-flow wiring
│   └── data/                 ← sample CSVs (test_raw.csv, test_processed.csv)
├── mosquitto/
│   └── config/mosquitto.conf ← MQTT broker settings
├── grafana/
│   └── provisioning/         ← pre-built dashboards & database connection
├── serial-bridge/
│   ├── bridge.py             ← serial → MQTT helper (Python)
│   └── requirements.txt
└── information/              ← author's design notes & process log
```

---

## 🛠️ Troubleshooting

**"Flyway exited / stopped" — is that broken?**
No. Flyway is supposed to run once, build the tables, and quit. Check it succeeded with `docker compose logs flyway`.

**No data is showing up in Grafana.**
- Did you actually feed data in? Try the **FAKE Data Generator** in Node-RED first.
- Check the `event_logs` table — frames may have been dropped for being malformed.
- Confirm rows exist: `docker exec -it telemetry-postgresdb psql -U <USER> -d <DB> -c "SELECT count(*) FROM telemetry_records;"`

**Node-RED can't connect to the database (local setup).**
You almost certainly still have the host/port set to `postgresdb:5432`. Locally it must be `localhost:5433`, with the user/password/database matching your `.env`. See [Step 6](#step-6--fix-the-database-connection-the-important-change).

**Port already in use.**
Something else on your machine is using 5433, 1881, 1883, or 3001. Stop that program, or change the published port in `infrastructure/docker-compose.yaml`.

**Can't log in to Grafana.**
Use the `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` from your `.env`. If you changed them *after* the first start, you may need `docker compose down -v` (this erases stored data) and start again.

**Serial port won't open (local setup).**
Double-check the exact device name (`ls /dev/cu.*` on macOS, Device Manager on Windows), make sure no other program (like the Python bridge or Arduino IDE) is already holding the port, and confirm the baud rate matches the device.

---

## 📖 Glossary (plain-English definitions)

- **Docker / container** — a way to package software so it runs the same on any computer, without you installing each piece by hand.
- **Docker Compose** — a tool that starts several containers together from one config file.
- **Node-RED** — a visual, drag-and-wire programming tool. Here it's the "brain" that cleans and routes the data.
- **MQTT / Mosquitto** — a lightweight messaging system for sending small messages (like sensor readings) around. Mosquitto is the specific "post office" (broker) used.
- **PostgreSQL (Postgres)** — the database that stores all the readings permanently.
- **Flyway** — a tool that builds/updates the database tables automatically and remembers which changes it already applied.
- **Grafana** — the tool that draws live charts and gauges from the database.
- **Serial port** — a USB connection your computer uses to talk to hardware like a radio receiver.
- **Baud rate** — the speed of a serial connection (e.g. 38400). Both sides must agree on it.
- **Raw value** — the unconverted number (0–32767) straight from the hardware, before it's turned into real units.
- **Healing** — replacing a clearly-broken reading with the last known-good value so one glitch doesn't ruin the data.
- **Bitmask** — a single number that secretly holds many yes/no flags, one per bit. The definition tables explain what each bit means.
- **Frame** — one complete reading: one line of 15 comma-separated values.

---

*Built with Node-RED, PostgreSQL, Mosquitto, Grafana, and Flyway — all orchestrated by Docker.*