# 🐟 TelemeTuna v1.1

**TelemeTuna** is a self-contained telemetry platform for the **RapidAmente** electric race car. It catches live sensor data streamed from the car, cleans it up, stores it safely in a database, and draws it on live dashboards.

It is built almost entirely out of ready-made building blocks that run inside **Docker**, and it ships with **Terraform** to stand the whole thing up on **AWS** with one command. If you can copy a file and run a couple of commands in a terminal, you can run this project.

> **Repository:** https://github.com/PsyVita/RapidAmente-TelemeTuna

---

## 📑 Table of Contents

1. [What this project does](#-what-this-project-does)
2. [How it all fits together (the big picture)](#-how-it-all-fits-together-the-big-picture)
3. [Deployment: cloud first, local optional](#-deployment-cloud-first-local-optional)
4. [Cloud deployment with Terraform (AWS)](#-cloud-deployment-with-terraform-aws)
5. [Team operations: the `tuna-*` shortcuts](#-team-operations-the-tuna--shortcuts)
6. [What's inside the box (the services)](#-whats-inside-the-box-the-services)
7. [The data: what a "frame" looks like](#-the-data-what-a-frame-looks-like)
8. [Timestamps: who stamps, and why](#-timestamps-who-stamps-and-why)
9. [The processing pipeline, step by step](#-the-processing-pipeline-step-by-step)
10. [Before you start (prerequisites)](#-before-you-start-prerequisites)
11. [Installation & first run (local)](#-installation--first-run-local)
12. [How to feed data in](#-how-to-feed-data-in)
13. [Optional: running Node-RED locally for a direct serial connection](#-optional-running-node-red-locally-for-a-direct-serial-connection)
14. [The database tables](#-the-database-tables)
15. [The Grafana dashboard](#-the-grafana-dashboard)
16. [Team access: watching together](#-team-access-watching-together)
17. [Design decisions & concerns — the exhaustive FAQ](#-design-decisions--concerns--the-exhaustive-faq)
18. [Project folder layout](#-project-folder-layout)
19. [Troubleshooting](#-troubleshooting)
20. [Glossary (plain-English definitions)](#-glossary-plain-english-definitions)
21. [Changelog](#-changelog)

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

On a cloud deployment, that entire Docker box is itself created from code: **Terraform** provisions the AWS server, its disk, its firewall, and its secrets, and a boot script clones this repo and starts the stack automatically. See [Cloud deployment with Terraform](#-cloud-deployment-with-terraform-aws).

---

## ☁️ Deployment: cloud first, local optional

The same Docker setup runs anywhere. Pick the deployment that fits you:

### Option A — Everything on a cloud server *(how the RapidAmente team runs it)*

The **whole platform** — Mosquitto, Node-RED, PostgreSQL, Grafana, pgAdmin — runs on one cloud VM. The receiver ESP32 publishes to the **cloud server's public IP**, and the whole team watches the dashboards from anywhere, no shared network needed:

```
http://<cloud-public-ip>:3001   ← Grafana       http://<cloud-public-ip>:1881  ← Node-RED
http://<cloud-public-ip>:5051   ← pgAdmin       <cloud-public-ip>:1884         ← MQTT (ESP32 publishes here)
```

This is fully automated with the Terraform code in [`infrastructure/`](#-cloud-deployment-with-terraform-aws): one `terraform apply` builds the server (a stable Elastic IP, a dedicated encrypted database disk, a locked-down firewall, and SSM-managed secrets), installs Docker, clones the repo, and brings the stack up — no manual SSH, no hand-copied passwords. Day-to-day the team starts and stops the server with the [`tuna-*` shortcuts](#-team-operations-the-tuna--shortcuts).

### Option B — Everything on one local PC

The classic setup: run the stack on a laptop, open everything at `localhost`. Best for development, testing, and tracks with zero connectivity. Teammates on the **same network** can still watch (see [Team access](#-team-access-watching-together)). This is the path in [Installation & first run (local)](#-installation--first-run-local).

### Option C — Hybrid

Local stack on the pit laptop, but the Mosquitto broker in the cloud (point Node-RED's MQTT node and the ESP32 at the cloud broker). Useful when the dashboard machine sits behind a strict network but the car still needs a reachable broker.

---

## 🌍 Cloud deployment with Terraform (AWS)

Everything needed to run TelemeTuna on AWS lives in the **`infrastructure/`** folder as **Terraform** (infrastructure-as-code). Instead of clicking around the AWS console, you describe the server in code and let Terraform create, update, and tear it down reproducibly. This is the **primary** way the RapidAmente team runs the platform.

### What Terraform builds for you

One `terraform apply` provisions a complete, self-starting telemetry server:

| Resource | What it is | Why it's there |
|---|---|---|
| **EC2 instance** | An Ubuntu 22.04 server (default `t3.small`) | Runs the whole Docker stack |
| **Elastic IP (EIP)** | A static public IP, attached to the instance | The address the ESP32 and the team point at — survives stop/start |
| **Dedicated EBS data volume** | A separate encrypted `gp3` disk for PostgreSQL only | Database lives on its own disk so backups/snapshots target just the data |
| **Security group** | The firewall | Opens only the ports the platform needs, only to your IP |
| **IAM role + instance profile** | The server's identity | Lets the box use SSM and read *only its own* secrets |
| **SSM Parameter Store parameters** | Encrypted config + passwords | Credentials never live in the repo; the boot script reads them at first launch |

There is **no SSH key and no port 22** — administrative shell access is through **AWS Systems Manager (SSM) Session Manager**, which is both more secure (nothing to leak, full audit trail) and friendlier (the [`tuna-*` shortcuts](#-team-operations-the-tuna--shortcuts) wrap it).

### The module layout

The Terraform is split into a small **root module** that wires four **child modules** together. Dependency order is inferred automatically from the references (`secrets → iam`, `network → compute`, `iam → compute`):

```
infrastructure/
├── versions.tf              ← Terraform ≥ 1.5, AWS provider ~> 5.0
├── providers.tf             ← AWS provider + default_tags (Project/Environment/ManagedBy)
├── variables.tf             ← all input variables (region, sizes, credentials…)
├── main.tf                  ← wires the four modules below together
├── outputs.tf               ← instance_id, public_ip, grafana_url
├── terraform.tfvars.example ← copy to terraform.tfvars and edit
├── .terraform.lock.hcl      ← provider version lock (aws 5.100.0)
└── modules/
    ├── network/   ← default VPC/subnet lookup + the security group (firewall)
    ├── secrets/   ← pushes all app credentials into SSM Parameter Store
    ├── iam/       ← EC2 role: SSM access + read-only on its own 7 secrets
    └── compute/   ← the EC2 instance, its data volume, the Elastic IP, and the boot script
```

**`modules/network`** — finds your account's **default VPC** and its first **default subnet** (and that subnet's availability zone, because the data volume must live in the same AZ). It creates the security group `telemetuna-prod-sg` with one ingress rule per published port, each scoped to `admin_cidr`:

| Port (host) | Service | Container port |
|---|---|---|
| `1881` | Node-RED | 1880 |
| `1884` | MQTT broker | 1883 |
| `3001` | Grafana | 3000 |
| `5051` | pgAdmin | 80 |
| `5433` | PostgreSQL | 5432 |

Egress is open (so the box can pull Docker images, OS updates, and reach SSM). **There is deliberately no `22`/SSH rule.**

**`modules/secrets`** — writes **seven** parameters into **SSM Parameter Store** under the path `/<project>/<environment>/…` (e.g. `/telemetuna/prod/postgres_password`). Usernames, the DB name, and the pgAdmin email are stored as plain `String`; the three passwords are stored as encrypted `SecureString`. The module outputs the parameter ARNs so the IAM policy can be scoped to exactly these and nothing else.

**`modules/iam`** — creates the EC2 role the instance assumes. It attaches the AWS-managed **`AmazonSSMManagedInstanceCore`** policy (enables Session Manager) and an inline policy that allows `ssm:GetParameter`/`GetParameters` on **only the seven parameter ARNs** above, plus `kms:Decrypt` restricted (via a `kms:ViaService` condition) to SSM in this region. The role is exposed through an instance profile.

**`modules/compute`** — the heart of it:

- Looks up the **latest Ubuntu 22.04 (Jammy) AMI** from Canonical (no hard-coded AMI IDs).
- Creates a dedicated **encrypted `gp3` EBS volume** for Postgres data (tagged `Backup = postgres` so a snapshot policy can target it), in the subnet's AZ, attached at `/dev/sdf`.
- Launches the **EC2 instance** with a public IP, an encrypted `gp3` root disk, and **IMDSv2 required** (`http_tokens = "required"`).
- Runs the **boot script** (`user_data.sh.tftpl`) on first launch (details below).
- Creates an **Elastic IP** and associates it. ⚠️ `terraform destroy` **releases** this address, so a full rebuild changes the public IP. Use **stop/start** (not destroy) to keep the same IP day to day.

### The boot script (`user_data.sh.tftpl`)

The instance configures itself on first boot in nine logged steps — you never have to SSH in to set it up:

1. **Install Docker + Compose plugin.**
2. **Install AWS CLI v2** (so it can read SSM).
3. **Mount the dedicated Postgres data volume** — finds the non-root disk, formats it `ext4` if it's blank, adds it to `/etc/fstab` (mounted at `/mnt/pgdata`), and removes the `lost+found` directory so Postgres can `initdb` into a clean folder.
4. **Read config + secrets from SSM** Parameter Store (decrypting the passwords).
5. **Clone the application repo** into `/opt/RapidAmente-TelemeTuna`.
6. **Hand the Node-RED folder to uid 1000** (`chown` of `services/nodered`) so the Node-RED container can write to its `/data` mount.
7. **Bind the `postgres_data` Docker volume to the EBS disk** (`/mnt/pgdata`) so the database is stored on the dedicated, snapshottable volume.
8. **Write `.env` entirely from SSM** (`umask 077`) — production does **not** depend on `.env.example`; every value comes from Parameter Store.
9. **Write helper scripts and auto-start the stack** — creates `start-telemetuna.sh` and `update-telemetuna.sh`, then brings the stack up with both compose files. Because every service uses `restart: unless-stopped`, the stack also comes back by itself after a reboot or stop/start.

Two helper scripts are left on the box for day-2 work:

```bash
sudo /opt/RapidAmente-TelemeTuna/start-telemetuna.sh    # bring the stack up
sudo /opt/RapidAmente-TelemeTuna/update-telemetuna.sh   # git pull + rebuild + up -d (ship app updates)
```

### Prerequisites (cloud)

- **Terraform ≥ 1.5** — `brew install terraform` (macOS) or see https://developer.hashicorp.com/terraform/install
- **AWS CLI v2** signed in to an account with permission to create the resources above. The team uses **IAM Identity Center (SSO)**: `aws sso login --profile tuna` (the [`tuna-*` installer](#-team-operations-the-tuna--shortcuts) sets these profiles up for you).
- An idea of **your own public IP** for `admin_cidr` — find it with `curl ifconfig.me`.

### Variables (`terraform.tfvars`)

Copy the example and edit it. Secrets and your `terraform.tfvars` are **gitignored** and never committed:

```bash
cd infrastructure
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
```

| Variable | Default | Notes |
|---|---|---|
| `aws_region` | `ap-southeast-7` | Asia Pacific (Bangkok) |
| `project` | `telemetuna` | Used for naming/tagging and the SSM path |
| `environment` | `prod` | Used for naming/tagging and the SSM path |
| `admin_cidr` | *(required)* | **Your** public IP as CIDR, e.g. `203.0.113.5/32`. Restricts every open port to you. *(The example file ships `0.0.0.0/0` — tighten it.)* |
| `instance_type` | `t3.small` | EC2 size |
| `root_volume_size` | `20` | OS disk (GB) |
| `data_volume_size` | `5` | Postgres data disk (GB) — `gp3` can grow later, never shrink |
| `repo_url` | this repo | App repo the boot script clones |
| `postgres_user` / `postgres_db` | `user` / `telemetry` | Non-secret; become SSM `String` params |
| `grafana_admin_user` / `pgadmin_email` | `user` / `admin@admin.com` | Non-secret; become SSM `String` params |
| `postgres_password` | *(required, secret)* | Stored as SSM `SecureString` |
| `grafana_admin_password` | *(required, secret)* | Stored as SSM `SecureString` |
| `pgadmin_password` | *(required, secret)* | Stored as SSM `SecureString` |

> 🔐 **The whole point of the secrets/SSM design:** in production the app's `.env` is built **on the instance** from Parameter Store, so passwords are set once in `terraform.tfvars` (which stays on your machine) and never travel through the git repo. To read the generated file on the box: `sudo cat /opt/RapidAmente-TelemeTuna/.env`.

### Deploy

```bash
cd infrastructure
terraform init      # download the AWS provider (pinned in .terraform.lock.hcl)
terraform plan      # preview exactly what will be created
terraform apply     # type "yes" to build it
```

When it finishes, Terraform prints the outputs:

```bash
terraform output                      # instance_id, public_ip, grafana_url
terraform output -raw grafana_url     # e.g. http://203.0.113.5:3001
```

Give the instance a couple of minutes after `apply` (the boot script is installing Docker, cloning, and starting containers in the background), then open the Grafana URL.

### Security model at a glance

- **No SSH.** Shell access is via SSM Session Manager only — nothing to leak, fully audited.
- **IMDSv2 required** on the instance (blocks a common metadata-theft vector).
- **Least-privilege IAM** — the instance can read only its own seven SSM parameters and decrypt only via SSM.
- **Firewall scoped to `admin_cidr`** — keep it at your `/32`; open `1884` wider only if the ESP32 publishes from a changing IP, and prefer adding MQTT auth/TLS if you do.
- **Encryption at rest** — both the root and the data EBS volumes are encrypted.
- **Tagging** — `default_tags` (Project/Environment/ManagedBy=Terraform) on every resource makes cost tracking and cleanup easy.

### Data persistence & backups

The dedicated Postgres EBS volume is mounted at `/mnt/pgdata` and bound to the Docker volume `postgres_data`, which `docker-compose.production.yaml` marks **`external: true`** — so an accidental `docker compose down -v` **cannot** erase it (see [Development vs production compose](#development-vs-production-compose)). For real backups, enable EBS **snapshots** of the volume tagged `Backup = postgres` (your provider's scheduled-snapshot/Data Lifecycle Manager policy), and/or run a periodic `pg_dump`.

### Day-2 operations

- **Pause/resume to save money, keep the IP:** `tuna-stop` / `tuna-start` (or `aws ec2 stop-instances` / `start-instances`). The Elastic IP and all data stay put.
- **Ship an app update:** `tuna-restart`, or SSH-free via the on-box `update-telemetuna.sh`.
- **Tear it all down:** `terraform destroy` — **but** this releases the Elastic IP (new IP next time) and, unless you've snapshotted, the data volume goes too. Prefer `tuna-stop` for everyday pauses.

The raw start/stop commands (for reference, from the process log) are:

```bash
aws ec2 stop-instances  --instance-ids <id> --region ap-southeast-7 --profile tuna
aws ec2 start-instances --instance-ids <id> --region ap-southeast-7 --profile tuna
```

---

## 🐟 Team operations: the `tuna-*` shortcuts

The **`scripts/`** folder turns all the AWS housekeeping into friendly `tuna-*` commands so any teammate can sign in and run the server without memorizing AWS CLI incantations.

- **`install-tuna-shortcuts.sh`** — one-time setup: installs the AWS CLI v2 + the SSM Session Manager plugin (if missing), creates the SSO profiles (`op-tuna`, `ic-tuna`, `ad-tuna`), and wires the shortcuts into your shell.
- **`tuna-shortcuts.sh`** — the `tuna-*` functions themselves (sourced by your shell rc).
- **`bootstrap-windows.ps1`** — a one-command Windows bootstrap that installs Git for Windows, then runs the bash installer for you.

The three profiles map to three IAM Identity Center roles, so each teammate uses only the access they need:

| Profile | Role | What it can do |
|---|---|---|
| `op-tuna` | **Operator** | Most tasks, including SSM shell/commands |
| `ic-tuna` | **InstanceController** | Start/stop the instance only |
| `ad-tuna` | **Admin** | Full administrative access |

> The SSO portal URL, region (`ap-southeast-7`), and account ID are baked into the installer — there's nothing to configure.

### Setup

**macOS / Linux:**

```bash
git clone https://github.com/PsyVita/RapidAmente-TelemeTuna.git
cd RapidAmente-TelemeTuna
chmod +x scripts/install-tuna-shortcuts.sh
./scripts/install-tuna-shortcuts.sh
```

Then run the `source …` line the script prints (e.g. `source ~/.zshrc` on macOS, `source ~/.bashrc` on most Linux).

**Windows (easiest — one PowerShell command, installs everything including Git Bash):**

Get the repo first (clone it if you have git, or download the ZIP from GitHub and extract it), then in **PowerShell**, from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\bootstrap-windows.ps1
```

That installs Git for Windows (if missing) via `winget`, then runs the bash installer (AWS CLI + SSM plugin + profiles + shortcuts). When it finishes, open **Git Bash** and:

```bash
source ~/.bashrc
tuna-login-op        # or tuna-login-ic / tuna-login-ad
```

**Windows (manual alternative, if you already have Git Bash):** run the bash installer directly from Git Bash:

```bash
git clone https://github.com/PsyVita/RapidAmente-TelemeTuna.git
cd RapidAmente-TelemeTuna
./scripts/install-tuna-shortcuts.sh
source ~/.bashrc
```

**Notes for Windows:**

- The `tuna-*` commands run in **Git Bash**, not PowerShell/CMD (they're bash). The PowerShell bootstrap is only the installer; daily use is in Git Bash. WSL also works and behaves like the Linux instructions above.
- `winget` is needed for the auto-install (built into Windows 10 1709+ / 11). On older Windows, install Git for Windows manually first, then use the manual alternative.
- UAC / installer windows may pop up for the AWS CLI / SSM plugin — approve them. If `aws` isn't found right after a first-time install, reopen the shell and re-run.

### Everyday use

Pick the role you need for this terminal (this also signs you in):

```bash
tuna-login-op      # Operator  (most tasks)
tuna-login-ic      # InstanceController (start/stop only)
tuna-login-ad      # Admin
```

Then, for example:

```bash
tuna-check         # confirm you're signed in (prints your role ARN)
tuna-start         # boot the server
tuna-status        # show its state + public IP
tuna-grafana       # open the dashboards in your browser
tuna-stop          # pause it when you're done
tuna-help          # full list of commands
```

The full command set (`tuna-help` prints these as two tables):

**Any role (`op-tuna` / `ic-tuna` / `ad-tuna`):**

| Command | What it does |
|---|---|
| `tuna-login-op` / `-ic` / `-ad` | Sign in and select the role for this shell |
| `tuna-whoami` | Show which profile the actions use |
| `tuna-check` | Check whether you're logged in (role ARN) |
| `tuna-start` | Start the instance and resume the stack |
| `tuna-stop` | Stop the instance (pause; data safe, same IP) |
| `tuna-status` | Show instance ID, state, and public IP |
| `tuna-ip` | Print just the public IP |
| `tuna-grafana` / `tuna-nodered` / `tuna-pgadmin` | Open that UI in your browser |
| `tuna-help` | Show the help |

**SSM-capable roles only (`op-tuna` / `ad-tuna`) + instance must be running:**

| Command | What it does |
|---|---|
| `tuna-ssm` | Shell into the box via SSM Session Manager |
| `tuna-ps` | Container status + health |
| `tuna-logs [svc]` | Tail logs; one service: `tuna-logs grafana` |
| `tuna-restart [svc]` | Restart the stack, or just `tuna-restart grafana` |
| `tuna-disk` | Show disk usage on the box |

Under the hood, the UI shortcuts just open the public URL (the ports are open in the security group, so no tunnel is needed), while `tuna-ps`/`tuna-logs`/`tuna-restart`/`tuna-disk` run remote one-shot commands on the box through **SSM `send-command`** and print the output locally.

### Notes

- A profile only works for roles you're actually assigned in Identity Center; creating one you don't have is harmless (login just won't authorize it).
- Safe to re-run the installer anytime — existing AWS profiles are left as-is and the shell block is replaced, never duplicated.
- The portal URL is baked into the installer, so there's nothing to configure.

---

## 📦 What's inside the box (the services)

When you start the project with Docker, six things run together. You don't install them one by one — Docker does it for you.

| Service | What it is | Where you reach it | Why it's here |
|---|---|---|---|
| **PostgreSQL** | The database | `localhost:5433` | Permanent storage for every reading |
| **Node-RED** | Visual data-flow tool | http://localhost:1881 | The "brain" — stamps, cleans, converts, heals, logs |
| **Grafana** | Dashboard tool | http://localhost:3001 | Live charts and gauges |
| **Mosquitto** | MQTT message broker | `localhost:1884` | Carries live data messages |
| **Flyway** | Database migration tool | *(runs once, then exits)* | Creates the tables automatically on first start |
| **pgAdmin** | Database admin UI | http://localhost:5051 | Browse and query the stored data by hand |

> 💡 **Why these ports?** The **host** ports are deliberately shifted (`5433` instead of the usual 5432, `1881` instead of 1880, `3001` instead of 3000, `1884` instead of 1883 for MQTT, `5051` instead of the usual 5050) so they don't collide with other software you might already have running. On a cloud deployment, replace `localhost` with the server's public IP.

> 🛰️ **MQTT port note (read this if you touch the broker):** the published host port is **1884**, but **`mosquitto.conf` sets `listener 1883`**, so Mosquitto actually listens on **1883 inside the container**. `docker-compose.yaml` therefore maps **`1884:1883`** (host 1884 → container 1883). External publishers (the ESP32, `mosquitto_pub`) connect to **`<host-or-cloud-ip>:1884`**; clients *inside* the Docker network reach the broker at **`mosquitto:1883`** (the listener port). If you change the MQTT port, change **all three together**: the `listener` in `mosquitto.conf`, the **Port** on the Node-RED MQTT-broker node (`flows.json`), and **both sides** of the Compose mapping — and keep the Node-RED broker port equal to the `mosquitto.conf` listener.

> 🔌 **Other internal container ports** (used by container-to-container links, not published as shown): `postgresdb:5432`, `grafana:3000`, `node-red:1880`, `pgadmin:80`. Grafana also has **anonymous viewing enabled** (`GF_AUTH_ANONYMOUS_ENABLED=true`, role `Viewer`) and a `300ms` minimum dashboard refresh; the timezone for Node-RED is `Asia/Bangkok`.

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

Inside Node-RED there are **four "tabs"** (think of them as four pages of wiring):

- **Real-Time Imports** — the entry point for live data. Two source options feed it: **Option 2 — MQTT** (the `mqtt in` listener on topic `car_telemetry`, QoS 2 — the normal racing path) and **Option 1 — Serial Port** (the `fishPort` serial-in node, shipped **disabled**; only used by a locally-run Node-RED wired to a USB receiver).
- **CSV Imports** — the entry points for loading raw or processed files (timestamp column required; it's stripped here, then raw rows join the pipeline below).
- **Background Flow** — the cleaning/conversion pipeline that live data and raw CSVs funnel into.
- **Test Flow** — the **FAKE Data Generator** and its **Test Injection Node**, kept on their own tab so the test rig is never confused with real wiring. (Comment on the tab: *"ONLY click for testing the program."*)

### How the tabs are wired together (the link nodes)

Node-RED's *link out → link in* nodes carry frames between tabs without drawing wires across the canvas. Each entry tab has a **link-out**; the Background Flow has the matching **link-ins**:

| Source tab | Link-out node | Routes to link-in |
|---|---|---|
| Real-Time Imports (MQTT) | **`link out 3`** | `Link In to Background Flow (for Real-Time Imports and Test Flow)` |
| Real-Time Imports (Serial, disabled) | **`link out 2`** | `Link In to Background Flow (for Real-Time Imports and Test Flow)` |
| Test Flow | **`Test Flow Link Out`** | `Link In to Background Flow (for Real-Time Imports and Test Flow)` |
| CSV Imports (raw) | **`Raw CSV Link Out`** | `Link In to Background Flow (for Raw CSV)` |

So the Background Flow has **two** entry link-ins: one shared by live MQTT, the disabled serial option, and the Test Flow; and a separate one for raw CSVs. (Processed CSVs never enter the Background Flow — they're parsed by **`Parse Processed CSV`** and written straight to the database inside the CSV Imports tab.)

Every raw frame passes through these stations, in order:

1. **Strip Timestamp** — Separates time from data. A 16-field frame keeps its own timestamp; a 15-field frame is stamped with arrival time (silently — this is the normal live case). Any other field count drops the frame (`FD`).
2. **Parse CSV** — Splits the line into its 15 fields and checks each one: right count, gear present, every other field a real number. Any failure drops the **whole frame** (`FD`) — at this stage the structure isn't trusted yet, so no repairs are attempted.
3. **Raw → Real Conversion** (`Raw to Real Convertion (rpm/amp/volt/trq)`) — Scales raw -32767…32767 into real units via `real = raw ÷ 32767 × max`:
   - `rpm` → max 5,500 RPM (rounded to a whole number — sensor precision doesn't justify decimals)
   - `amp` → max 212.1 A · `volt` → max 200 V · `trq` → max 125 Nm (1 decimal each)
   - A raw value outside ±32767 didn't come from the hardware → becomes `null` + `warn` logged (the Heal step will repair it).
4. **Map Mode** — `N`→0, `D`→1, `R`→2. Anything else → `null` + `warn` (healable — the car can't teleport between gears in 300 ms).
5. **Temperature Conversion** (`Temperature Conversion (igbt_c/mot_c)`) — raw counts → °C:
   - **IGBT:** 32-point manufacturer lookup table (raw 16308 = −30 °C … raw 28480 = +125 °C) with straight-line interpolation between neighboring points.
   - **Motor:** linear sensor, two-point fit: `temp = 30 + (raw − 11446) × 70 ÷ 4554` (valid raw range 10000–20000).
   - Out-of-range raw values → `null` + `warn`, healable.
6. **Heal** (`Heal (rpm/amp/volt/trq/igbt_c/mot_c/mode)`) — The safety net for the seven continuous values. Keeps a per-field snapshot of the last known-good value and checks each new value against a plausibility range: rpm ±6000, amp ±250, volt ±250, trq ±150, temps −40…200 °C, mode 0–2. Valid → keep & update snapshot. Invalid/missing/null → **replace with the snapshot value** and record the field name. Every healed row carries its `healed_fields` list into the database **and** a summary into the event log — repairs are never silent.
7. **Flags** (`Flags (L_REGEN/L_ERR/L_WARN_L_OK/L_PUMP/drive_ena)`) — The six 0/1 lights become true/false. Anything that isn't exactly 0 or 1 → `null` + `error` logged. **Flags are never healed** — copying yesterday's "no error" over a corrupted error light could hide a real fault.
8. **Validate Bitmasks** (`Validate Bitmasks (err/warn)`) — `err` and `warn` must be whole numbers 0–65535 (what 16 bits can hold). Invalid → `null` + `error`. The numbers are stored as-is; decoding into fault names happens in Grafana at display time.
9. **Build Parameters** — Packs timestamp, converted values, flags, bitmasks, and the healed-fields list into one ordered row.
10. **Car Telemetry Database** — Inserts into `telemetry_records` with `ON CONFLICT (time) DO NOTHING`: the `time` column is unique, so replaying the same data can never create duplicates.

### What happens when something goes wrong

- Every station has a **second output** that sends structured complaints to a **"Normalize Log Event"** node → the `Log Database` node → the `event_logs` table.
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

The **Test Flow** tab contains a **"FAKE Data Generator"** wired to a **"Test Injection Node"** (it reaches the pipeline through the `Test Flow Link Out` → `Link In to Background Flow (for Real-Time Imports and Test Flow)` pair). One click simulates a full driving cycle (idle → accelerate → cruise → coast → regen → stop) and then deliberately exercises **every defence in the pipeline**, phase by phase: fault bitmask combinations (FAULTS), every status-light combination (FLAGS), corrupted values that trigger healing (HEAL), malformed frames that get dropped whole — wrong field counts, non-numeric values, bad timestamps (DROPS) — and finally simulated code errors that land in the log as `critical` (CRITICAL). After one run, every panel on both dashboard tabs has something to show.

---

## ✅ Before you start (prerequisites)

**For a local run, you only need two things:**

1. **Docker Desktop** (or Docker Engine on a Linux server) — https://www.docker.com/products/docker-desktop/
2. **Git** — https://git-scm.com/downloads (or download the project as a ZIP from GitHub).

That's it. PostgreSQL, Node-RED, Grafana, Mosquitto, Flyway, and pgAdmin all come inside the project.

> The only optional extra is **Node.js + Node-RED**, and only for the advanced *local serial port* setup described in its own section below.

**For a cloud run** you additionally need **Terraform ≥ 1.5** and the **AWS CLI v2** signed in — see [Cloud deployment with Terraform](#-cloud-deployment-with-terraform-aws).

---

## 🚀 Installation & first run (local)

### Step 1 — Download the project

```bash
git clone https://github.com/PsyVita/RapidAmente-TelemeTuna.git
cd RapidAmente-TelemeTuna
```

### Step 2 — Create your environment (`.env`) file

The `.env.example` template and the compose files live at the **repository root**, so this is done from the project root (no `cd` needed):

```bash
cp .env.example .env
```

Open `.env` in any text editor and set your own values:

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

> ⚠️ The `.env` file is intentionally **not** uploaded to GitHub (it's in `.gitignore`) because it holds your passwords. **These local passwords are for development only** — in production the `.env` is generated on the server from SSM (`sudo cat /opt/RapidAmente-TelemeTuna/.env` to read it).

### Step 3 — Start everything

```bash
docker compose up -d
```

Both `docker-compose.yaml` and `.env` are at the repo root, so run this from the project root. First start takes a few minutes (downloads + builds). What happens automatically: PostgreSQL starts → Flyway builds all tables and exits (that's normal!) → Node-RED, Grafana, Mosquitto, and pgAdmin come up and stay running.

#### Development vs production compose

There are **two** compose files at the root:

| File | Purpose |
|---|---|
| `docker-compose.yaml` | The full stack — all six services, ports, healthchecks, and **named** Docker volumes. This is everything you need for local development. |
| `docker-compose.production.yaml` | A small **override** that redeclares just the **database** volume (`postgres_data`) as `external: true`. Layer it on top of the base file for cloud/server deployments. |

Plain `docker compose up -d` uses managed named volumes — simple, but `docker compose down -v` would erase them. For a server, mark the **database** volume **external** so Compose refuses to delete it: create it once, then bring the stack up with **both** files (the override is merged on top of the base):

```bash
docker volume create postgres_data
docker compose -f docker-compose.yaml -f docker-compose.production.yaml up -d
```

An external volume survives `docker compose down -v`, container recreation, and image upgrades — the telemetry lives on the provider's disk, not in a volume Compose feels free to remove. **Only `postgres_data` is protected this way**, because it's the only irreplaceable data: Grafana's dashboards and datasource are re-provisioned from `services/grafana/provisioning/` on every start, and the Mosquitto/pgAdmin volumes are convenience-only, so they stay as managed named volumes. *(On the Terraform-built server, the boot script does the `docker volume create` for you and binds it to the dedicated EBS disk.)*

> 🧱 The compose files follow the modern Compose spec, so there is **no top-level `version:` key** (it's obsolete). Image pins: `postgres:16` (pinned), plus `grafana/grafana:latest`, `eclipse-mosquitto:latest`, `flyway/flyway:latest`, `dpage/pgadmin4:latest`, and a custom Node-RED image built from `nodered/node-red:latest`. Every long-running service has a healthcheck and `restart: unless-stopped`; Flyway intentionally runs once (`command: migrate`) and exits.

### Step 4 — Check that it's working

| What | Address | Login |
|---|---|---|
| Node-RED | http://localhost:1881 | none |
| Grafana | http://localhost:3001 | Grafana user/password from `.env` (or browse anonymously as a Viewer) |
| pgAdmin | http://localhost:5051 | pgAdmin email/password from `.env` |

> 🐘 **First time in pgAdmin:** register the database once. Right-click *Servers* → *Register* → *Server*, any name, and under *Connection* set **Host** = `postgresdb`, **Port** = `5432`, plus the `POSTGRES_*` values from `.env`. Tick **Save password**. (It must be `postgresdb:5432`, *not* `localhost:5433` — pgAdmin lives *inside* the Docker network with the database.)

Command-line peek at the database:

```bash
docker exec -it telemetry-postgresdb psql -U <YOUR_POSTGRES_USER> -d <YOUR_POSTGRES_DB> -c "SELECT count(*) FROM telemetry_records;"
```

### Step 5 — Generate test data (no car needed!)

1. Open Node-RED → **Test Flow** tab.
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

Node-RED is always listening on MQTT topic **`car_telemetry`**. The receiver ESP32 publishes each 15-field frame there — cloud deployment: to the cloud server's IP on **port 1884**; local: to the PC's IP on **port 1884**. Frames flow straight into the pipeline, stamped on arrival. Nothing to click.

Test it by hand from any machine with an MQTT client:

```bash
mosquitto_pub -h <server-ip> -p 1884 -t car_telemetry \
  -m "15000,-8000,19660,12000,D,21357,11644,0,0,0,0,0,1,0,1"
```

### Way 2 — CSV file import (replays and testing)

Both CSV types **require a timestamp as the first column** (16 columns total):

- **Raw CSV** — timestamp + 15 raw fields → full cleaning pipeline (keeps the file's original timestamps).
- **Processed CSV** — timestamp + 15 already-cleaned fields (data that went through TelemeTuna before) → written straight to the database, no double-cleaning.

**How to:**

1. Put the file in `services/nodered/data/` — Node-RED sees it as `/data/data/yourfile.csv` (the whole `services/nodered/` folder is mounted into the container at `/data`). Two sample paths already exist there: `test_raw.csv` and `test_processed.csv` (currently empty placeholders — drop your rows in or point the nodes at your own file).
2. Open the **CSV Imports** tab in Node-RED.
3. Edit the file path in the matching **file-in** node (comment: "Edit Path to Insert Your File").
4. Click the inject button on **Load Raw CSV** or **Load Processed CSV**.

Blank lines are ignored (`Ignore Blank Frames`); rows with bad timestamps or field counts are dropped and logged. 🔁 **Safe to re-run:** duplicate timestamps are skipped, so importing the same file twice never duplicates data.

### Way 3 — Direct serial (advanced, local only)

See the [dedicated section below](#-optional-running-node-red-locally-for-a-direct-serial-connection) — only needed when the LoRa receiver is plugged into the computer by USB and you want to skip MQTT entirely.

---

## 🔌 Optional: running Node-RED locally for a direct serial connection

> **Most users skip this.** Docker containers cannot access USB serial ports, so reading the receiver directly requires Node-RED to run natively on your machine. In the committed flow the serial path is **Option 1** in the **Real-Time Imports** tab — the `fishPort` serial-in node, which ships **disabled** (MQTT is **Option 2** and is the default). To use serial, run Node-RED locally, enable `fishPort`, and point it at your device; its output already feeds `link out 2` → the Background Flow, exactly like the MQTT path.

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

Flyway creates these automatically from the migration files (V1–V4 under `services/database/migrations/`). You never write them by hand — and to change the schema later you add a **new** higher-numbered migration rather than editing an applied one.

### `telemetry_records` — every cleaned reading *(V1, amended by V4)*

| Column | Type | Notes |
|---|---|---|
| `time` | `TIMESTAMPTZ` | when the reading happened. **Unique** — a second row with the same timestamp is skipped on insert (V4) |
| `rpm`, `amp`, `volt`, `trq` | `DOUBLE PRECISION` | converted real-world values |
| `mode` | `INTEGER` | 0=Neutral, 1=Drive, 2=Reverse |
| `err`, `warn` | `INTEGER` | bitmask numbers (decoded in Grafana via the definition tables) |
| `igbt_c`, `mot_c` | `DOUBLE PRECISION` | temperatures in °C |
| `l_regen`, `l_err`, `l_warn`, `l_ok`, `l_pump`, `drive_ena` | `BOOLEAN` | status lights (null = was corrupted, never healed) |
| `healed_fields` | `TEXT[]` | which fields (if any) were repaired for this row |

### `event_logs` — the pipeline's diary *(V2)*

| Column | Type | Notes |
|---|---|---|
| `time` | `TIMESTAMPTZ` | when it happened |
| `level` | `TEXT` | `warn`, `error`, `FD`, `critical` |
| `node` | `TEXT` | which pipeline station raised it |
| `message` | `TEXT` | human-readable explanation |
| `fields` | `TEXT[]` | involved field names (e.g. the healed fields) |

### `err_bit_definitions` & `warn_bit_definitions` — the fault dictionary *(V3)*

`err` and `warn` are stored as plain numbers where each **bit** means one specific fault (bit 7 of `err` = "IGBT-Temp. Max. Limit"). These two tables map all 16 + 16 bits to a `name` and `description` straight from the motor controller's manual, so Grafana can show readable fault names instead of cryptic numbers. (Both keep a `bit` primary key `CHECK`-constrained to 0–15.)

> Each migration is recorded in Flyway's own `flyway_schema_history` table, so Flyway knows which scripts it has already applied and never re-runs them.

---

## 📊 The Grafana dashboard

A pre-built dashboard — the **EV TelemeTuna Dashboard** — is provisioned automatically from `services/grafana/provisioning/` (a datasource provider + the dashboard JSON). It refreshes very fast (down to 300 ms) and is organized into **two tabs**:

> 🧩 The dashboard file (`car-telemetry.json`) is exported in Grafana's newer **v2 schema** (`apiVersion: dashboard.grafana.app/v2`, `kind: Dashboard`), so if you hand-edit it, expect the `spec.elements` / `spec.layout` structure rather than the old flat `panels` array. The datasource is provisioned separately as **Car Telemetry PostgreSQL** (`type: postgres`, `url: postgresdb:5432`, `sslmode: disable`, `isDefault: true`). *(Note: the datasource still carries a leftover `timescaledb: true` feature flag from an earlier design — harmless on plain PostgreSQL.)*

### Tab 1 — Car Live Dashboard

- **Live gauges & stats** — RPM, voltage, current, torque, motor & IGBT temperature, drive mode, and the six status lights.
- **Time-series charts** — RPM, torque, voltage & current, and both temperatures over time.
- **Active Errors & Warnings** — the latest `err`/`warn` bitmasks decoded into named faults (joined against the V3 definition tables, e.g. `err & (1 << bit)`). When a frame exists and no fault bits are set, it shows a friendly **"No active faults — All systems normal"** row, so an empty table is never ambiguous.

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

**Cloud deployment (Option A):** nothing extra to do — everyone opens the cloud IP addresses from anywhere (or just runs `tuna-grafana` / `tuna-nodered` / `tuna-pgadmin`). The security group must allow their IPs (`admin_cidr`); see [the Terraform security model](#security-model-at-a-glance).

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

**Why PostgreSQL and not TimescaleDB?** Considered (see `docs/processDocumentation.md`). The project runs in sessions, not continuously; plain PostgreSQL with a time index handles this scale comfortably with one less moving part. (A leftover `timescaledb: true` flag remains in the Grafana datasource but is harmless.)

**Why Flyway instead of writing tables by hand or an ORM (Prisma)?** Versioned migrations (V1–V4) run once each, in order, automatically, with history tracked in the database itself — and Flyway runs as a throwaway container, nothing to install.

**Why is Flyway "exited" in `docker compose ps`?** That's its design: run migrations, quit. Check it succeeded with `docker compose logs flyway`.

**Why the shifted ports (5433/1881/3001/1884/5051)?** To avoid colliding with default installs of the same tools on your machine. Inside the Docker network most services still talk on their standard ports (e.g. `postgresdb:5432`, `grafana:3000`, `node-red:1880`) — the published host port is what's shifted. **Mosquitto is the subtle one:** `mosquitto.conf` sets `listener 1883`, so the broker listens on **1883 inside the container** and Compose publishes it as **`1884:1883`**; external publishers use host **1884** while in-network clients use `mosquitto:1883`. ⚠️ If you change the MQTT port, keep all three in sync: `mosquitto.conf`'s `listener`, the Node-RED MQTT-broker node's port, and **both sides** of the compose port mapping — and make the Node-RED broker port equal the listener.

**Is it safe to click "Test Injection" twice?** Yes — a new run kills the previous one (the generator clears its interval timer first). Timestamps are current-time so the runs just append.

**Can two people import CSVs or run the generator at once?** Yes, but their rows interleave in the database by timestamp; the unique-time rule resolves any exact collisions by keeping the first arrival.

**What's protected when someone runs `docker compose down -v`?** With the plain `docker-compose.yaml` (named volumes): nothing — it erases all volumes (database included). That's what **`docker-compose.production.yaml`** is for: it marks the **database** volume (`postgres_data`) as `external: true`, so once you've `docker volume create postgres_data` and bring the stack up with both files, `down -v` **refuses** to delete it. The other three volumes stay managed (and would be wiped by `down -v`) on purpose — Grafana re-provisions its dashboards/datasource from files, and the Mosquitto/pgAdmin data is reconstructable — so only the irreplaceable telemetry is locked down. On the cloud box that external volume is bound to a dedicated, encrypted EBS disk that can also be snapshotted.

**How are production secrets handled?** They never touch the repo. Terraform writes them to **SSM Parameter Store** (passwords as `SecureString`); the EC2 boot script reads them back and writes `/opt/RapidAmente-TelemeTuna/.env` on the instance. The instance's IAM role can read **only those seven parameters**. See [Cloud deployment](#-cloud-deployment-with-terraform-aws).

**Why no SSH on the cloud server?** Shell access is via **SSM Session Manager** (`tuna-ssm`), so there's no open port 22, no key to leak, and every session is auditable. The instance also enforces **IMDSv2**.

**Why a dedicated EBS volume just for Postgres?** So backups/snapshots target only the database (tagged `Backup = postgres`), and so the data survives instance rebuilds independently of the OS disk. It's mounted at `/mnt/pgdata` and bound to the external `postgres_data` Docker volume.

**Why does `terraform destroy` change my public IP, but stop/start doesn't?** The Elastic IP is Terraform-managed: `destroy` releases it. For everyday pauses use `tuna-stop`/`tuna-start` (or the EC2 stop/start commands) — the EIP and the data stay put.

**Is the data sent by the car encrypted or authenticated?** No — LoRa frames and MQTT (`allow_anonymous true`) are plaintext. On a cloud deployment, anyone allowed through the firewall to the broker could publish fake frames. Acceptable for a race-team prototype, and the firewall is scoped to `admin_cidr`; the hardening path is MQTT username/password + TLS (port 8883) on Mosquitto, both supported by ESP32 and Node-RED.

**How fast can data arrive?** The pipeline is event-driven; the FAKE generator pushes a frame every 300 ms comfortably, and Grafana's minimum refresh is 300 ms. The practical ceiling is far above the car's transmit rate.

**What's the storage footprint?** One row ≈ a few hundred bytes. A 2-hour session at 300 ms ≈ 24,000 rows ≈ a few MB. Years of racing fit in single-digit GB (the default data volume is just 5 GB and `gp3` can grow later).

---

## 📁 Project folder layout

The compose files and `.env` sit at the **repo root**, every service's config lives under **`services/`**, all documentation under **`docs/`**, cloud-provisioning code under **`infrastructure/`**, and team setup/control scripts under **`scripts/`**.

```
RapidAmente-TelemeTuna/
├── docker-compose.yaml             ← the full stack (all six services)
├── docker-compose.production.yaml  ← override: marks the database volume external (servers)
├── .env.example                    ← template for your local secrets (copy to .env)
├── .env                            ← YOUR local secrets (you create this; not on GitHub)
├── .gitignore
├── docs/
│   ├── README.md                   ← the main project README (GitHub renders it as the repo README)
│   ├── processDocumentation.md     ← the author's process & design log (TimescaleDB→Postgres, Prisma→Flyway, Terraform…)
│   └── TelemeTuna-Manual.html      ← user manual (empty placeholder for now)
├── infrastructure/                 ← Terraform / infrastructure-as-code (AWS)
│   ├── versions.tf                 ← Terraform ≥ 1.5, AWS provider ~> 5.0
│   ├── providers.tf                ← AWS provider + default_tags
│   ├── variables.tf                ← all input variables
│   ├── main.tf                     ← wires the four modules together
│   ├── outputs.tf                  ← instance_id, public_ip, grafana_url
│   ├── terraform.tfvars.example    ← copy to terraform.tfvars and edit (gitignored)
│   ├── .terraform.lock.hcl         ← provider version lock (aws 5.100.0)
│   └── modules/
│       ├── network/                ← default VPC/subnet lookup + security group (firewall)
│       ├── secrets/                ← app credentials → SSM Parameter Store (7 params)
│       ├── iam/                    ← EC2 role: SSM access + read-only on its own secrets
│       └── compute/                ← EC2 instance, EBS data volume, Elastic IP
│           └── user_data.sh.tftpl  ← first-boot script (installs Docker, clones, starts stack)
├── scripts/                        ← team setup + tuna-* control shortcuts
│   ├── README.md                   ← scripts quick-start (folded into this README)
│   ├── install-tuna-shortcuts.sh   ← one-time: AWS CLI + SSM plugin + SSO profiles + shortcuts
│   ├── tuna-shortcuts.sh           ← the tuna-* functions (sourced by your shell rc)
│   └── bootstrap-windows.ps1       ← one-command Windows bootstrap (installs Git Bash, then the above)
└── services/
    ├── database/
    │   └── migrations/             ← SQL files Flyway runs to build the tables
    │       ├── V1__init.sql                 (telemetry_records + time index)
    │       ├── V2__add_event_logs.sql       (event_logs)
    │       ├── V3__add_bitmask_definitions.sql (err/warn bit dictionaries)
    │       └── V4__unique_timestamp.sql     (unique time; drops the now-redundant index)
    ├── grafana/
    │   └── provisioning/           ← auto-loaded by Grafana on start
    │       ├── dashboards/         (car-telemetry.json [v2 schema], dashboard.yaml)
    │       └── datasources/        (datasource.yaml → Car Telemetry PostgreSQL)
    ├── mosquitto/
    │   └── config/mosquitto.conf   ← MQTT broker settings (listener 1883, anonymous, persistence)
    └── nodered/
        ├── Dockerfile              ← builds Node-RED with the postgres + serialport nodes baked in
        ├── flows.json              ← the data-flow wiring (the whole pipeline)
        ├── settings.js             ← Node-RED runtime settings (flowFile, flowFilePretty, uiPort 1880, projects disabled…)
        ├── package.json            ← extra Node-RED node dependencies
        ├── package-lock.json
        └── data/                   ← CSV drop folder (placeholders: test_raw.csv, test_processed.csv)
```

> 🔐 `flows_cred.json` (Node-RED's encrypted credentials), any `*.backup`/hidden flow files, `.env`, and all Terraform state/`*.tfvars` are **gitignored** and never committed.

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
Wrong broker address on the ESP32 (must be the cloud/host IP, **port 1884**), wrong topic (must be `car_telemetry`), or port 1884 blocked by the firewall / security group (`admin_cidr` on the cloud box). Also confirm the compose port mapping is `1884:1883` so the broker is actually reachable from outside Docker.

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

**Node-RED can't connect to the MQTT broker.**
In-network clients must use the broker's **listener** port. `mosquitto.conf` sets `listener 1883`, so the Node-RED MQTT-broker node's **Server** should be `mosquitto` and its **Port** should match that listener. Make sure `mosquitto.conf`'s `listener`, the Node-RED node's port, and the compose mapping (`1884:<listener>`) all agree.

**Teammates can't open the dashboards.**
Cloud: use the cloud public IP (or `tuna-grafana`); check ports 3001/1881/5051 are allowed for their IP in the security group (`admin_cidr`). Local: host's LAN IP (not `localhost`), same subnet, host firewall open.

**Port already in use.**
Something else owns 5433, 1881, 1884, 3001, or 5051 — stop it or change the published port in `docker-compose.yaml` (at the repo root).

**MQTT works between containers but external publishers (ESP32 / `mosquitto_pub`) can't connect.**
Check the Mosquitto port mapping in `docker-compose.yaml`. The broker listens on **1883 inside the container**, so the mapping must publish to it — **`1884:1883`**. With the host side closed in the cloud firewall, external publishers also fail; open `1884` to the publisher's IP in the security group.

**Mosquitto shows `unhealthy` in `docker compose ps`.**
The container healthcheck runs `mosquitto_pub -t healthcheck/ping -m ok`, which defaults to port 1883 — matching the `listener`, so it should pass. If you move the listener off 1883, update the healthcheck (and the Node-RED node, and the mapping) to match, or `depends_on` waits will stall.

**Can't log in to Grafana / pgAdmin.**
Use the values from `.env` (on the cloud box: `sudo cat /opt/RapidAmente-TelemeTuna/.env`). If you changed them *after* first start, `docker compose down -v` (erases data!) and restart, or change them in the running app.

**Serial port won't open (local setup).**
Check the exact device name (`ls /dev/cu.*` on macOS, Device Manager on Windows), make sure no other program holds the port, baud = 38400.

### Cloud / Terraform troubleshooting

**`terraform apply` fails on credentials.**
Sign in first: `aws sso login --profile tuna` (or `tuna-login-op`). Make sure the profile's account/region match the Terraform `aws_region`.

**The server is up but Grafana won't load for a few minutes.**
The boot script is still installing Docker, cloning the repo, and starting containers. Give it a couple of minutes; then `tuna-grafana`. To watch progress, `tuna-ssm` in and run `sudo docker ps` / check `/var/log/cloud-init-output.log`.

**I can reach the server but my own IP changed.**
`admin_cidr` only allows the IP you set. Update it in `terraform.tfvars` and re-apply, or widen it temporarily.

**My public IP changed after a rebuild.**
`terraform destroy`/recreate releases the Elastic IP. Use `tuna-stop`/`tuna-start` for everyday pauses to keep the same IP.

**`tuna-*` commands say I'm not authorized.**
A profile only authorizes roles you're actually assigned in Identity Center. SSM commands (`tuna-ps`, `tuna-logs`, `tuna-restart`, `tuna-ssm`) need an SSM-capable role (`op-tuna`/`ad-tuna`) **and** the instance running.

---

## 📖 Glossary (plain-English definitions)

- **ESP32** — a small, cheap microcontroller board with built-in Wi-Fi. This project uses two: a **sender** on the car and a **receiver** that publishes to MQTT.
- **LoRa** — long-range, low-power radio; how the sender talks to the receiver.
- **Docker / container** — packages software so it runs the same on any computer, no manual installs.
- **Docker Compose** — starts several containers together from one config file. This project has two: `docker-compose.yaml` (base) and `docker-compose.production.yaml` (an override that makes the database volume external for servers).
- **Terraform / infrastructure-as-code (IaC)** — declarative files that provision cloud resources (the VM, networking, firewall rules, disks, secrets) from code instead of by hand. Lives in `infrastructure/`; run with `terraform init/plan/apply`.
- **AWS** — Amazon Web Services, the cloud this project deploys to. **EC2** is the virtual server; **EBS** is its disk; an **Elastic IP (EIP)** is a static public address; a **security group** is the firewall; **AMI** is the OS image.
- **SSM (AWS Systems Manager)** — **Session Manager** gives shell access without SSH; **Parameter Store** holds config/secrets (the app's production passwords live here as `SecureString`).
- **IAM** — AWS permissions. The instance gets a least-privilege **role/instance profile**; teammates sign in through **IAM Identity Center (SSO)** with the `op-/ic-/ad-tuna` profiles.
- **IMDSv2** — the hardened way an instance reads its own metadata; required here for security.
- **Node-RED** — a visual, drag-and-wire programming tool; here it's the pipeline "brain".
- **MQTT / Mosquitto** — a lightweight publish/subscribe messaging system; Mosquitto is the broker ("post office"). The listener is on **1883** in-container, published on host **1884**.
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

## 🗒️ Changelog

This project follows [semantic versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`): backward-compatible new capability bumps the **minor** version, breaking changes bump the **major**, and fixes bump the **patch**.

### v1.1 — Cloud deployment & operations

- **Cloud deployment via Terraform.** Added the `infrastructure/` infrastructure-as-code that provisions the whole stack on AWS in one `terraform apply`: an EC2 server, a static **Elastic IP**, a dedicated **encrypted EBS data disk** for PostgreSQL, a firewall (**security group**) scoped to your IP, and a self-configuring first-boot script that installs Docker, clones the repo, and starts the stack automatically. Split into `network` / `secrets` / `iam` / `compute` modules.
- **Secrets via SSM Parameter Store.** Production credentials are stored in AWS SSM (passwords as `SecureString`) and written into the instance `.env` at boot — production no longer depends on `.env.example`.
- **No-SSH administration.** Shell access is through **SSM Session Manager** (no port 22, fully audited); the instance enforces **IMDSv2** and a least-privilege IAM role that can read only its own secrets.
- **`tuna-*` operator shortcuts.** Added `scripts/` with one-time setup (AWS CLI + SSM plugin + the `op-/ic-/ad-tuna` SSO profiles), a Windows PowerShell bootstrap, and friendly `tuna-start` / `tuna-stop` / `tuna-status` / `tuna-logs` / `tuna-ssm` commands.
- **Production compose documented.** Clarified use of the `docker-compose.production.yaml` override (external `postgres_data` volume, bound to the EBS disk on the cloud box).
- **Docs.** Expanded this README with cloud/Terraform and operations sections, an updated folder layout, and matching FAQ/troubleshooting/glossary entries.
- **Backward compatible** — the local Docker workflow (Option B) is unchanged from v1.0.

### v1.0 — Initial release

- Self-contained **local telemetry platform** on Docker: PostgreSQL, Node-RED, Grafana, Mosquitto, Flyway, and pgAdmin, started with a single `docker compose up -d`.
- **Ingestion** via live MQTT (topic `car_telemetry`, QoS 2), CSV replay (raw and processed), and an optional local serial path.
- **Node-RED pipeline**: arrival timestamping, frame parsing, raw→real conversion, IGBT/motor temperature lookup, healing of continuous values from the last known-good reading, flag/bitmask validation, and structured event logging with a `warn`/`error`/`FD`/`critical` severity model.
- **Flyway migrations V1–V4**: `telemetry_records`, `event_logs`, the `err`/`warn` bit dictionaries, and the unique-timestamp constraint.
- **Pre-provisioned Grafana** "EV TelemeTuna Dashboard" with a live dashboard tab and a pipeline-health tab, plus a built-in fake-data generator for testing without hardware.

> Releasing this set of changes? Tag it: `git tag -a v1.1.0 -m "Cloud deployment & operations" && git push --tags`.

---