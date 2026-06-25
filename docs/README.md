# 🐟 TelemeTuna v1.1

> *Feed the tuna every frame, clean telemetry wins the game.*

**Live telemetry for the Rapidamente electric race car.** The car radios its vital signs — motor RPM, current, voltage, torque, temperatures and fault flags — over a long-range link. TelemeTuna catches every reading, repairs what the radio garbled (and logs every repair), stores it all, and draws it on live dashboards the whole team can watch from anywhere.

It's six ready-made services running together in Docker. If you can run a couple of commands in a terminal, you can run the whole platform.

📖 **Full manual — built for everyone, from non-technical viewers to developers: [Read it online →](https://psyvita.github.io/Rapidamente-TelemeTuna/)**  *(or open `docs/index.html` in a browser from a local clone)*

---

## What it is

A self-contained pipeline that turns a messy radio stream into clean, trustworthy, live data:

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

Nothing fails silently — every dropped frame, healed value, and crash is logged with when, where, and why.

## Quickstart (local)

Only two prerequisites: **Docker** (Docker Desktop, or Docker Engine + Compose) and **Git**. Everything else ships inside the project.

```bash
git clone https://github.com/PsyVita/Rapidamente-TelemeTuna.git
cd Rapidamente-TelemeTuna

cp .env.example .env                  # then edit the passwords
docker volume create postgres_data    # one-time: the database's safe, external home

# start the full stack (production compose)
docker compose -f docker-compose.yaml -f docker-compose.production.yaml up -d
```

Then open **Grafana at http://localhost:3001** — no login needed to watch.

> **Just testing, no real car?** Bring up the throwaway **dev stack** instead — plain `docker compose up -d` — and click the built-in test generator in Node-RED to fill every panel. Never point the fake generator at a production database.

## What's running

| Service | Open at | Login |
|---|---|---|
| **Grafana** — live dashboards | http://localhost:3001 | none to view (anonymous) · `.env` to edit |
| **Node-RED** — the data pipeline | http://localhost:1881 | none |
| **pgAdmin** — browse the database | http://localhost:5051 | from `.env` |
| **Mosquitto** — MQTT broker | `localhost:1884` | — |
| **PostgreSQL** — storage | `localhost:5433` | from `.env` |
| **Flyway** — builds tables, then exits | *(runs once)* | — |

> Host ports are shifted by one from each tool's default (e.g. Postgres `5433` not `5432`) so they don't clash with other software on your machine. Inside the Docker network the standard ports still apply. On a cloud box, replace `localhost` with the server's IP.

## Deploying it

- **☁️ Cloud, one command (team default):** `terraform apply` in `infrastructure/` builds the whole AWS server — EC2 instance, static Elastic IP, encrypted database disk, locked-down firewall, and SSM-managed secrets — and the box configures itself and starts the stack on first boot. No SSH; day-to-day control is the `tuna-*` shortcuts.
- **💻 Local:** the quickstart above; teammates on the same network watch via the host's LAN IP. To read the LoRa receiver straight off a **USB serial port** (no MQTT), run Node-RED natively rather than in Docker — see the [serial-connection guide](https://psyvita.github.io/Rapidamente-TelemeTuna/#serial).
- **🔀 Hybrid:** local stack pointed at a cloud MQTT broker.

Full deployment, operations (the `tuna-*` commands), the security model, and the Terraform internals all live in the **[manual](https://psyvita.github.io/Rapidamente-TelemeTuna/)**.

## How the data works (in one breath)

Each reading is one comma-separated **frame** — 15 fields (16 with a leading timestamp, which CSV replays require). Node-RED stamps each frame on arrival, converts the raw `-32767…32767` numbers into real units, **heals** briefly-corrupted *continuous* values from the last known-good reading (but never guesses alarms), drops anything structurally broken, and logs every decision. The full pipeline — all ten stations, the healing rules, and how fault bitmasks are decoded — is documented in the manual.

## Repo layout

Compose files and `.env` sit at the **repo root**; every service's config lives under **`services/`**, all documentation under **`docs/`**, cloud-provisioning code under **`infrastructure/`**, and team setup/control scripts under **`scripts/`**.

```
Rapidamente-TelemeTuna/
├── docker-compose.yaml              # the full stack (all six services)
├── docker-compose.production.yaml   # override: marks the database volume external (servers)
├── .env.example                     # template for your secrets (copy to .env)
├── .env                             # YOUR secrets (you create this; gitignored)
├── .gitignore
│
├── docs/                            # all documentation
│   ├── README.md                    # this file — rendered as the repo's front page
│   ├── index.html                   # the full interactive HTML manual (served at the Pages URL above)
│   └── processDocumentation.md      # the author's process & design log (TimescaleDB→Postgres, Prisma→Flyway, Terraform…)
│
├── infrastructure/                  # Terraform / infrastructure-as-code (AWS)
│   ├── versions.tf                  # Terraform ≥ 1.5, AWS provider ~> 5.0
│   ├── providers.tf                 # AWS provider + default_tags (Project/Environment/ManagedBy)
│   ├── variables.tf                 # all input variables (region, sizes, credentials…)
│   ├── main.tf                      # wires the four modules below together
│   ├── outputs.tf                   # instance_id, public_ip, grafana_url
│   ├── terraform.tfvars.example     # copy to terraform.tfvars and edit (gitignored)
│   ├── .terraform.lock.hcl          # provider version lock (aws 5.100.0)
│   └── modules/
│       ├── network/                 # default VPC/subnet lookup + security group (firewall)
│       ├── secrets/                 # app credentials → SSM Parameter Store (7 params)
│       ├── iam/                     # EC2 role: SSM access + read-only on its own secrets
│       └── compute/                 # EC2 instance, EBS data volume, Elastic IP
│           └── user_data.sh.tftpl   # first-boot script (installs Docker, clones, starts the stack)
│
├── scripts/                         # team setup + tuna-* control shortcuts
│   ├── script-README.md             # scripts quick-start
│   ├── install-tuna-shortcuts.sh    # one-time: AWS CLI + SSM plugin + SSO profiles + shortcuts (macOS/Linux/Git-Bash)
│   └── tuna-shortcuts.sh            # the tuna-* functions (sourced by your shell rc)
│
└── services/                        # one folder per service's config
    ├── database/
    │   └── migrations/              # SQL files Flyway runs to build the tables, in order
    │       ├── V1__init.sql                     # telemetry_records + time index
    │       ├── V2__add_event_logs.sql           # event_logs
    │       ├── V3__add_bitmask_definitions.sql  # err / warn bit dictionaries
    │       └── V4__unique_timestamp.sql         # unique time; drops the now-redundant index
    ├── grafana/
    │   └── provisioning/            # auto-loaded by Grafana on start (no hand-built dashboards)
    │       ├── dashboards/          # car-telemetry.json (the EV TelemeTuna Dashboard) + dashboard.yaml
    │       └── datasources/         # datasource.yaml → Car Telemetry PostgreSQL
    ├── mosquitto/
    │   └── config/mosquitto.conf    # broker settings (listener 1883, allow_anonymous, persistence)
    └── nodered/
        ├── Dockerfile               # builds Node-RED with the postgres + serialport nodes baked in
        ├── flows.json               # the data-flow wiring — the whole pipeline
        ├── settings.js              # Node-RED runtime settings (uiPort 1880, projects disabled…)
        ├── package.json             # extra Node-RED node dependencies
        ├── package-lock.json
        └── data/                    # CSV drop folder (placeholders: test_raw.csv, test_processed.csv)
```

## Documentation & versioning

This README is the quickstart. The **[full manual](https://psyvita.github.io/Rapidamente-TelemeTuna/)** is the all-in-one reference for every audience — non-technical viewers, operators, and developers — with an interactive dashboard walkthrough, a pipeline playground, and a guided troubleshooter. Design history and the choices behind it (TimescaleDB → Postgres, Prisma → Flyway, Terraform) are in [`docs/processDocumentation.md`](processDocumentation.md).

The project follows [semantic versioning](https://semver.org/); the manual's changelog tracks what changed between releases. **Current: v1.1 — cloud deployment & operations.**

## Contact

Found a bug or have a question? Open a [GitHub Issue](https://github.com/PsyVita/Rapidamente-TelemeTuna/issues). You can also reach the author on Instagram: [@praery.in.april](https://www.instagram.com/praery.in.april).

```
<๏)))>< ∿∿∿
```
