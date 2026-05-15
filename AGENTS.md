# AGENTS.md - Grit Dependencies Infrastructure

## Project Overview
This is a Docker Compose-based infrastructure stack for local development, providing PostgreSQL, Authentik, MinIO, Neo4j, Redis, and related data pipeline services.

---

## Build/Run/Stop Commands

### Starting Services
Start all services:
```bash
docker compose up -d
```

Start specific service:
```bash
docker compose up -d postgresql
docker compose up -d authentik
```

### Stopping Services
Stop all services:
```bash
docker compose down
```

Stop and remove volumes (clean reset):
```bash
docker compose down -v
```

### Status and Logs
Check service status:
```bash
docker compose ps
```

View logs for a specific service:
```bash
docker compose logs postgresql
docker compose logs authentik
docker compose logs -f authentik  # Follow logs
```

### Database Commands
Connect to PostgreSQL:
```bash
docker compose exec postgresql psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

Run database initialization script manually:
```bash
docker compose exec postgresql psql -U "$POSTGRES_USER" -d postgres -f /docker-entrypoint-initdb.d/init-db.sh
```

List databases:
```bash
docker compose exec postgresql psql -U "$POSTGRES_USER" -d postgres -c "\l"
```

Verify pgvector extension:
```bash
docker compose exec postgresql psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT extname FROM pg_extension WHERE extname='vector';"
```

### Health Checks
Check PostgreSQL health:
```bash
docker compose exec postgresql pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

Check Redis:
```bash
docker compose exec redis redis-cli ping
```

---

## Testing Commands

This project is infrastructure-as-code. Testing focuses on service verification:

### Verify All Services Running
```bash
docker compose ps
```
All services should show "running" status.

### Verify PostgreSQL Connection
```bash
docker compose exec postgresql psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;"
```

### Verify Authentik
Access the web interface at `http://localhost:${COMPOSE_PORT_HTTP:-9000}` (default from .env)

### Verify MinIO
Access console at `http://localhost:${MINIO_SERVICE_PORT:-9001}`

### Verify Neo4j
Access browser at `http://localhost:7474`

---

## Code Style Guidelines

### Shell Scripts (.sh files)
- Use `set -e` at the top to exit on error
- Use `set -o pipefail` for pipeline error handling
- Quote all variable substitutions: `"$VAR"` not `$VAR`
- Use `-v ON_ERROR_STOP=1` for psql commands
- Use heredocs (<<-EOSQL) for multi-line SQL

Example:
```bash
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
```

### Docker Compose Files
- Use version 3.8+ syntax (omit version key for modern Compose)
- Use named volumes for persistence
- Include healthchecks for critical services
- Use `restart: unless-stopped` for services
- Use `.env` files for configuration (never hardcode secrets)
- Use `depends_on` with `condition: service_healthy` where appropriate

### Environment Files (.env)
- Copy from `.env.example` to create `.env`
- Never commit `.env` files (they're in .gitignore)
- Document all required variables in `.env.example`
- Use descriptive variable names (e.g., `POSTGRES_PASSWORD` not `PWD`)
- Include default values in docker-compose using `${VAR:-default}`

### SQL in Shell Scripts
- Include `IF NOT EXISTS` / `IF EXISTS` for idempotent operations
- Use explicit schema qualifiers when necessary
- Enable extensions per-database as needed

### Directory Structure
```
/Users/sangcha/workspace/grit/grit-dependencies/
├── airflow/
│   ├── dags/        # Airflow DAG definitions (Python)
│   ├── logs/        # Airflow logs
│   └── plugins/     # Airflow plugins
├── certs/           # SSL/TLS certificates
├── custom-templates/ # Custom templates
├── data/            # Persistent data
├── n8n_data/        # n8n workflow data
├── sftp_upload/     # SFTP upload directory
├── .env             # Environment variables (gitignored)
├── .env.example     # Template for .env
├── docker-compose.yml
├── docker-compose-full.yml
├── docker-compose-db.yml
├── docker-compose-n8n.yml
├── init-db.sh       # Database initialization
└── README.md
```

---

## Naming Conventions

### Services
- Use lowercase service names matching container purposes (e.g., `postgresql`, `redis`)
- Use explicit `container_name` for clarity

### Variables
- Database: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- Service-specific: `NEO4J_DATABASE`, `NEO4J_USER`, `NEO4J_PASSWORD`
- Use prefix patterns for grouped services

### Volumes
- Use descriptive names: `postgres_data`, `minio_data`, `neo4j_data`

---

## Error Handling

### Common Issues

**PostgreSQL database not created:**
If `postgres_data` volume already exists, `init-db.sh` won't run:
```bash
# Option 1: Manual creation
docker compose exec postgresql psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE airflow;"

# Option 2: Clean reset
docker compose down -v
docker compose up -d
```

**Authentik secret key missing:**
Ensure `AUTHENTIK_SECRET_KEY` is set in `.env`:
```bash
# Generate a key
openssl rand -base64 50
```

**Service dependencies not ready:**
Use healthchecks and `depends_on` with conditions:
```yaml
depends_on:
  postgresql:
    condition: service_healthy
```

---

## Best Practices

1. **Environment Variables**: Always use `.env` for secrets - never commit credentials
2. **Idempotent Scripts**: All init scripts should be safe to run multiple times
3. **Healthchecks**: Include healthchecks for all stateful services
4. **Volume Persistence**: Use named volumes for data that must persist
5. **Resource Limits**: Consider adding resource constraints for production
6. **Logs**: Check `docker compose logs <service>` when debugging
7. **Clean Resets**: Use `docker compose down -v` only when you want to delete all data
8. **Port Conflicts**: Check `.env` port mappings if services fail to start

---

## Extensions for Future Code

If adding Airflow DAGs:
- Place Python DAG files in `airflow/dags/`
- Use Airflow 2.8+ TaskFlow API
- Import conventions: `from airflow import DAG`, `from airflow.operators.python import PythonOperator`
- Follow PEP 8 style for Python code
- Document DAG purposes in docstrings

If adding n8n workflows:
- Workflows stored in `n8n_data/database.sqlite`
- Use n8n CLI for workflow imports/exports if needed

---

## Useful Aliases

```bash
alias dc='docker compose'
alias dcl='docker compose logs -f'
alias dce='docker compose exec'
alias dcp='docker compose ps'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
```

---

## Related Documentation
- PostgreSQL pgvector: https://github.com/pgvector/pgvector
- Authentik: https://goauthentik.io/docs/
- MinIO: https://min.io/docs/minio/linux/operations/
- Neo4j: https://neo4j.com/docs/
- Docker Compose: https://docs.docker.com/compose/