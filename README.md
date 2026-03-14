# Employee CRUD — Laravel + Inertia.js + React + Supabase Real-Time

A full-stack employee management application with **real-time updates** powered by Supabase Realtime. Built with Laravel (backend), Inertia.js + React (frontend), and PostgreSQL via Supabase (database). Containerized with Docker and deployable to AWS ECS Fargate via Terraform.

---

## Tech Stack

| Layer          | Technology                                      |
| -------------- | ----------------------------------------------- |
| Backend        | Laravel 11 (PHP 8.2)                            |
| Frontend       | React 18 + Inertia.js                           |
| Database       | PostgreSQL (Supabase)                            |
| Real-Time      | Supabase Realtime (WebSocket)                    |
| CSS            | Tailwind CSS                                     |
| Containerization | Docker (multi-stage, Nginx + PHP-FPM + Supervisor) |
| CI/CD          | GitHub Actions (ARM64 native build)              |
| Infrastructure | Terraform (AWS ECS Fargate on Graviton)          |
| Registry       | Docker Hub                                       |

---

## Project Structure

```
├── app/
│   ├── Http/Controllers/EmployeeController.php   # CRUD operations
│   ├── Http/Middleware/HandleInertiaRequests.php   # Flash message sharing
│   └── Models/Employee.php
├── resources/js/
│   ├── lib/supabase.js                            # Supabase client (singleton)
│   └── Pages/Employees/
│       ├── Index.jsx                              # List + real-time subscription
│       ├── Create.jsx                             # Create form
│       └── Edit.jsx                               # Edit form
├── terraform-aws/                                 # AWS ECS Fargate infrastructure
│   ├── variables.tf                               # Variables + Laravel env vars
│   ├── task-definition.tf                         # ECS task with env injection
│   ├── ecs-fargate-service.tf
│   ├── vpc.tf / security-group.tf / iam.tf
│   ├── cluster.tf / cloudwatch.tf / outputs.tf
│   └── versions.tf
├── docker/
│   ├── nginx.conf                                 # Nginx server config
│   ├── supervisord.conf                           # Runs Nginx + PHP-FPM
│   └── entrypoint.sh                              # Startup script (migrations, caching)
├── .github/workflows/deploy.yml                   # CI/CD pipeline
├── Dockerfile                                     # Multi-stage build (Node + Composer + PHP-FPM)
└── .env                                           # Environment variables (not committed)
```

---

## Prerequisites

- PHP 8.2+
- Composer
- Node.js 20+
- Docker
- A [Supabase](https://supabase.com) project with PostgreSQL

---

## Local Development Setup

### 1. Clone and Install Dependencies

```bash
git clone https://github.com/CaringalML/laravel-inertiareact.git
cd laravel-inertiareact
composer install
npm install
```

### 2. Configure Environment

Copy `.env.example` to `.env` and set these values:

```env
APP_KEY=base64:your-app-key-here

# Supabase PostgreSQL via Connection Pooler

# Supabase Real-Time (frontend)

# Local PostgreSQL example
DB_CONNECTION=pgsql
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=postgres
DB_USERNAME=postgres
DB_PASSWORD=ENgineer_caringal2000
DB_SSLMODE=prefer
```

### 3. Run Migrations

```bash
php artisan migrate
```

### 4. Start Development Servers

```bash
php artisan serve
npm run dev
```

Visit `http://localhost:8000/employees`

---

## Supabase Configuration

### Why Use the Connection Pooler Instead of Direct Connection (Critical)

Local PostgreSQL provides a straightforward connection method without the need for a connection pooler.

| Connection Type      | Hostname                                      | Port   | Resolves To | Works In Docker/ECS? |
| -------------------- | --------------------------------------------- | ------ | ----------- | -------------------- |
| **Direct**           | `db.your-project-ref.supabase.co`             | `5432` | **IPv6**    | ❌ No                |
| **Connection Pooler** | `aws-1-ap-south-1.pooler.supabase.com`       | `6543` | **IPv4**    | ✅ Yes               |

**The problem:** Supabase's direct database connection resolves to an **IPv6 address**. Most containerized environments — Docker, AWS ECS Fargate, GitHub Actions runners, and many cloud VMs — do not have IPv6 networking enabled by default. This causes `SQLSTATE[HY000] [2002] Connection refused` or DNS resolution failures when Laravel tries to connect to the database.

**The fix:** Use the **connection pooler** (PgBouncer) instead. The pooler endpoint resolves to an **IPv4 address**, which is universally supported. This was the key fix that resolved database connection failures in Docker and ECS deployments.

**Additional benefits of the pooler:**

**How to get the pooler URL:**
1. Go to Supabase Dashboard → **Connect** (top right)
2. Select **Connection Pooler** (Transaction mode)
3. Copy the host — it looks like: `aws-1-ap-south-1.pooler.supabase.com`
4. The port is `6543` (not the default `5432`)

```env
# ✅ Correct — Connection Pooler (IPv4, works everywhere)

# ❌ Wrong — Direct connection (IPv6, fails in Docker/ECS)
```

### Finding the Correct Pooler Region (Important)

The pooler hostname contains an **AWS region** (e.g., `aws-1-ap-south-1`), and it **must match the actual region where your Supabase project is hosted**.

The region shown on the Supabase project card (e.g., `AWS | ap-south-1`) is the actual region. This is also reflected in the pooler hostname: `aws-1-ap-south-1.pooler.supabase.com`. If you use the wrong region in the hostname, the connection will fail.

**How to verify the correct region:**

1. **From the Project Card** — On the Supabase Dashboard home page, each project card shows the region directly below the project name (e.g., `AWS | ap-south-1`).

2. **From the Connect Dialog** — Go to Supabase Dashboard → **Connect** (top right button) → the pooler URL is displayed with the correct region already included. Always copy this directly.

3. **From Project Settings** — Go to **Settings** → **General** → the **Region** field shows the actual AWS region.

> **Rule of thumb:** Never manually construct the pooler hostname. Always copy it directly from the Supabase Dashboard → Connect page to avoid region mismatches.

### Enable Real-Time on the Employees Table

Supabase Realtime uses PostgreSQL's logical replication. You need to enable it for the `employees` table:

**Step 1 — Enable Realtime on the table:**
1. Go to Supabase Dashboard → **Database** → **Tables**
2. Click on the `employees` table
3. Toggle **Enable Realtime** to ON

Or via SQL:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE employees;
```

**Step 2 — Enable Row Level Security (RLS) with a permissive policy:**

Since the real-time subscription uses the **anon (public) key** in the browser, RLS must allow the anon role to receive change events. Without a policy, the anon key is blocked from seeing any data — even real-time events.

1. Go to Supabase Dashboard → **Authentication** → **Policies**
2. Click on the `employees` table
3. Create a new policy:

| Setting            | Value                   |
| ------------------ | ----------------------- |
| **Policy Name**    | `enable-realtime`       |
| **Policy Command** | `ALL`                   |
| **Target Roles**   | (leave empty = public)  |
| **USING**          | `true`                  |
| **WITH CHECK**     | `true`                  |

Or via SQL:

```sql
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

CREATE POLICY "enable-realtime"
ON public.employees
FOR ALL
TO public
USING (true)
WITH CHECK (true);
```

> **Why `true` / `true`?** This is a public CRUD app without authentication. Setting both `USING` (read filter) and `WITH CHECK` (write filter) to `true` allows the anon role full access. For production apps with auth, replace `true` with proper conditions like `auth.uid() = user_id`.

### API Keys Explained

Supabase provides two types of API keys:

| Key              | Purpose                          | Safe in Browser? |
| ---------------- | -------------------------------- | ---------------- |
| **anon (public)**  | Client-side access, limited by RLS | ✅ Yes          |
| **service_role (secret)** | Full admin access, bypasses RLS | ❌ Never       |

This project uses the **anon key** in the frontend for real-time WebSocket subscriptions only. All actual CRUD operations go through Laravel directly to PostgreSQL (bypassing Supabase's API entirely).

Find your keys in: Supabase Dashboard → **Settings** → **API Keys**

---

## How Real-Time Works

```
Browser (React)                    Supabase                    Laravel
     │                                │                           │
     │── WebSocket subscription ──────│                           │
     │   (anon key, employees table)  │                           │
     │                                │                           │
     │                                │                           │
     │── Create/Edit/Delete ──────────│───────────────────────────│
     │   (Inertia.js form submit)     │  PostgreSQL direct conn   │
     │                                │                           │
     │                                │◄── DB change detected ────│
     │◄── Real-time event ────────────│                           │
     │                                │                           │
     │── router.reload({only:         │                           │
     │   ['employees']}) ─────────────│───────────────────────────│
     │   (Inertia partial reload)     │  Fetch fresh data         │
     │                                │                           │
```

1. The React `Index.jsx` component subscribes to `postgres_changes` on the `employees` table via Supabase Realtime WebSocket
2. When any user creates/edits/deletes an employee (via Laravel), the change is written to PostgreSQL
3. Supabase detects the change and pushes a real-time event to all connected clients
4. The browser receives the event and calls `router.reload({ only: ['employees'] })` — an Inertia.js partial reload that fetches only the `employees` prop from Laravel without a full page reload
5. The table updates instantly on all connected browsers

---

## Docker

### Build Locally

```bash
docker build \
  --build-arg VITE_SUPABASE_URL=https://your-project-ref.supabase.co \
  --build-arg VITE_SUPABASE_ANON_KEY=your-anon-key \
  -t employee-crud .
```

> The `VITE_` args are needed at build time because Vite inlines them into the JavaScript bundle during `npm run build`.

### Run Locally

```bash
docker run -p 80:80 --env-file .env employee-crud
```

Visit `http://localhost`

### Docker Architecture

The Dockerfile uses a 3-stage multi-stage build:

| Stage       | Base Image            | Purpose                                |
| ----------- | --------------------- | -------------------------------------- |
| `frontend`  | `node:20-alpine`      | Install npm deps, build Vite assets    |
| `composer`  | `composer:2`          | Install PHP deps, optimize autoloader  |
| `production`| `php:8.2-fpm-alpine`  | Final image: Nginx + PHP-FPM + Supervisor |

The production image runs **Nginx** (reverse proxy) and **PHP-FPM** (application server) together using **Supervisor** in a single container. Config files are in the `docker/` directory:

- `docker/nginx.conf` — Nginx server configuration
- `docker/supervisord.conf` — Runs both Nginx and PHP-FPM
- `docker/entrypoint.sh` — Runs migrations, caches config/routes on startup

---

## CI/CD — GitHub Actions

The pipeline (`.github/workflows/deploy.yml`) builds an ARM64 Docker image and pushes it to Docker Hub on every push to `main`.

**Key details:**
- Uses `ubuntu-24.04-arm` runner for native ARM64 builds (no QEMU emulation — much faster)
- Builds and pushes to `rencecaringal000/employee-crud:latest`
- Passes Supabase env vars as build args from GitHub secrets

### Required GitHub Secrets

Add these in your repo: **Settings** → **Secrets and variables** → **Actions**

| Secret                   | Value                                     |
| ------------------------ | ----------------------------------------- |
| `DOCKERHUB_TOKEN`        | Docker Hub access token                   |
| `VITE_SUPABASE_URL`      | `https://your-project-ref.supabase.co`    |
| `VITE_SUPABASE_ANON_KEY` | Your Supabase anon public key             |

---

## AWS Infrastructure — Terraform

The `terraform-aws/` directory contains Terraform configs to deploy the app on **AWS ECS Fargate with Graviton (ARM64)** processors.

### Resources Created

| Resource               | Description                                          |
| ---------------------- | ---------------------------------------------------- |
| VPC                    | Custom VPC with 3 public subnets across 3 AZs        |
| Internet Gateway       | Allows public internet access                         |
| Security Group         | Allows HTTP (port 80) ingress from anywhere           |
| ECS Cluster            | Fargate cluster with container insights enabled       |
| Task Definition        | ARM64 Fargate task with Laravel env vars injected     |
| ECS Service            | Runs 1 task with public IP (no ALB needed)            |
| IAM Roles              | Task execution role + task role                       |
| CloudWatch Log Group   | 7-day log retention                                   |

### Deploy

```bash
cd terraform-aws

# Create terraform.tfvars with your credentials
cat > terraform.tfvars <<EOF
app_key     = "base64:your-app-key"
db_host     = "aws-1-ap-south-1.pooler.supabase.com"
db_port     = "6543"
db_database = "postgres"
db_username = "postgres.your-project-ref"
db_password = "your-password"
EOF

terraform init
terraform plan
terraform apply
```

### Access the App

After `terraform apply`, get the public IP:
1. Go to **AWS Console** → **ECS** → **Clusters** → **aws-web-app-infra**
2. Click on **Tasks** → click the running task
3. Copy the **Public IP**
4. Open `http://<public-ip>` in your browser

### Tear Down

```bash
terraform destroy --auto-approve
```

---

## Troubleshooting

### Database connection refused in Docker/ECS

**Cause:** Using Supabase's direct connection (IPv6) instead of the connection pooler (IPv4).

**Fix:** Switch to the pooler URL:
```env
DB_HOST=aws-1-ap-south-1.pooler.supabase.com
DB_PORT=6543
```

### Real-time not working (channel SUBSCRIBED but no events)

**Cause:** RLS is blocking the anon key from receiving change events.

**Fix:**
1. Ensure Realtime is enabled on the `employees` table (Database → Tables → toggle)
2. Add an RLS policy with `USING (true)` and `WITH CHECK (true)` as described above

### Multiple GoTrueClient instances warning

**Cause:** Vite HMR recreates the Supabase client on hot reload during development.

**Fix:** Already handled — the Supabase client uses a singleton pattern in `resources/js/lib/supabase.js`. This warning only appears in development and is harmless.

### Full page reloads on button clicks

**Cause:** `<button>` elements nested inside Inertia `<Link>` components. Since `<Link>` renders as `<a>`, having `<button>` inside `<a>` is invalid HTML — the button intercepts clicks before Inertia's SPA handler fires.

**Fix:** Already applied — buttons are replaced with styled `<Link>` elements directly. Forms use Inertia's `useForm` hook which handles submissions via XHR.

---

## License

This project is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).
