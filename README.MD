# Grit Local Infrastructure (Data Pipeline Stack)

This repository provisions a complete local infrastructure stack for data engineering, pipeline development, and testing. It is optimized to run smoothly on both standard Linux environments and Apple Silicon (macOS).

It includes:
- **PostgreSQL 16** (Relational Database & Airflow Metadata)
- **Apache Airflow 2.8.1** (Orchestration & Scheduling)
- **MinIO** (S3-compatible Object Storage)
- **Neo4j 5** (Graph Database)
- **Redis 7** (In-memory Cache / KV Store)
- **Alpine SFTP** (Source Data Simulation)
- **Docker Mailserver** (Email Alerting for Pipelines)

---

## 1. Prerequisites

- **Docker Engine / Docker Desktop**
- **Docker Compose v2**
- **System Memory:** Minimum 4GB (8GB+ recommended) allocated to Docker.
- **Mac Users (M1/M2/M3):** Ensure **Rosetta 2** is installed (`softwareupdate --install-rosetta`), as the SFTP and Mailserver services utilize `linux/amd64` emulation.

---

## 2. Project Files

To set up this stack, you need to create three files in your project root directory: `docker-compose.yml`, `init-db.sh`, and `.env`. 

### File 1: `docker-compose.yml`
Create a file named `docker-compose.yml` and paste the following:

```yaml
version: '3.8'

x-airflow-common: &airflow-common
  image: apache/airflow:2.8.1
  environment:
    &airflow-common-env
    AIRFLOW__CORE__EXECUTOR: LocalExecutor
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@grit-postgres:5432/airflow
    AIRFLOW__CORE__FERNET_KEY: ${AIRFLOW_FERNET_KEY}
    AIRFLOW__CORE__LOAD_EXAMPLES: 'false'
    AIRFLOW__SMTP__SMTP_HOST: grit-mailserver
    AIRFLOW__SMTP__SMTP_PORT: 25
    AIRFLOW__SMTP__SMTP_USER: admin@${MAIL_DOMAIN}
  volumes:
    - ./airflow/dags:/opt/airflow/dags
    - ./airflow/logs:/opt/airflow/logs
    - ./airflow/plugins:/opt/airflow/plugins
  user: "${AIRFLOW_UID:-50000}:0"
  depends_on:
    postgres:
      condition: service_healthy

services:
  postgres:
    image: postgres:16
    container_name: grit-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-db.sh:/docker-entrypoint-initdb.d/init-db.sh
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  minio:
    image: minio/minio:latest
    container_name: grit-minio
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data

  neo4j:
    image: neo4j:5
    container_name: grit-neo4j
    restart: unless-stopped
    environment:
      NEO4J_AUTH: ${NEO4J_USER}/${NEO4J_PASSWORD}
      NEO4J_dbms_default__database: ${NEO4J_DATABASE}
    ports:
      - "7474:7474"
      - "7687:7687"
    volumes:
      - neo4j_data:/data
      - neo4j_logs:/logs

  redis:
    image: redis:7-alpine
    container_name: grit-redis
    restart: unless-stopped
    command: redis-server --save 60 1 --loglevel warning
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  airflow-webserver:
    <<: *airflow-common
    container_name: grit-airflow-webserver
    command: webserver
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5

  airflow-scheduler:
    <<: *airflow-common
    container_name: grit-airflow-scheduler
    command: scheduler

  sftp:
    image: atmoz/sftp
    container_name: grit-sftp
    platform: linux/amd64
    restart: unless-stopped
    ports:
      - "2222:22"
    volumes:
      - ./sftp_upload:/home/${SFTP_USER}/upload
    command: ${SFTP_USER}:${SFTP_PASS}:1001

  mailserver:
    image: mailserver/docker-mailserver
    container_name: grit-mailserver
    hostname: mail
    domainname: ${MAIL_DOMAIN}
    environment:
      ENABLE_SPAMASSASSIN: 0
      ENABLE_CLAMAV: 0
      ENABLE_FAIL2BAN: 0
    ports:
      - "25:25"
      - "587:587"

volumes:
  postgres_data:
  minio_data:
  neo4j_data:
  neo4j_logs:
  redis_data:
```
  
### File 2: `init-db.sh`
Create a file named init-db.sh in the same directory. This script forces Postgres to create the separate metadata database Airflow requires.  

```bash
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
    CREATE DATABASE airflow;
EOSQL
```

### File 3: Environment Setup (`.env` Required)

Create a file named `.env` in the root directory and populate it with your secure credentials.

To generate your unique `AIRFLOW_FERNET_KEY`, run:

```bash
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Paste this into your `.env` file:

```
# Postgres
POSTGRES_DB=grit
POSTGRES_USER=grit-admin
POSTGRES_PASSWORD=password123

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin

# Neo4j
NEO4J_DATABASE=neo4j
NEO4J_USER=neo4j
NEO4J_PASSWORD=password123

# SFTP
SFTP_USER=grituser
SFTP_PASS=gritpass

# Mail
MAIL_DOMAIN=example.com

# Airflow
AIRFLOW_FERNET_KEY=YOUR_GENERATED_KEY_HERE
AIRFLOW_UID=50000
```

## 3. Initialization Instructions
Before starting the containers, you must create the necessary local directories and ensure your database initialization script is executable. Run these commands in your terminal:

```bash
# 1. Create Airflow and SFTP directories
mkdir -p ./airflow/dags ./airflow/logs ./airflow/plugins ./sftp_upload

# 2. Grant permissions so Airflow can write logs locally
chmod -R 777 ./airflow

# 3. Ensure the Postgres init script is executable
chmod +x init-db.sh
```

## 4. How to Run
**Start all services:**

```bash
docker compose up -d
```

**Check service health and status::**

```bash
docker compose ps
```

**Stop all services:**

```bash
docker compose down
```

**Destroy all data (Wipe volumes):**

```bash
docker compose down -v
```

## Verification
Wait about 10-15 seconds after starting the containers, then verify the services:

**Postgres Initialization:**

```bash
docker exec -it grit-postgres psql -U grit-admin -l
(You should see both grit and airflow databases listed).
```

**Airflow UI:**

```bash
Navigate to http://localhost:8080.
```

**SFTP Connection:**

```Bash
sftp -P 2222 grituser@localhost
```

**MinIO Health:**

```Bash
curl http://localhost:9000/minio/health/live
(Or visit the UI at http://localhost:9001)
```

**Redis Test:**

```Bash
docker exec -it grit-redis redis-cli ping
(Expected output: PONG)
```

## 6. Security & Troubleshooting Notes
* **Secrets**: The .env file contains secrets. Do not commit it to version control. Add it to your .gitignore.

* **Database 'airflow' does not exist**: If you see this error in the Postgres logs, it means the database volume was created before the init-db.sh script was properly configured. Run docker compose down -v to wipe the volume and start fresh.

* **Mac Emulation Warnings**: Warnings stating "The requested image's platform (linux/amd64) does not match the detected host platform" for SFTP and Mailserver are expected. Rosetta 2 will handle the emulation automatically.