# 🚀 SoftTime Production Deployment Guide

## Prerequisites

- Docker & Docker Compose (latest versions)
- Linux server or VM with at least 2GB RAM, 10GB disk
- Domain name (recommended for SSL/HTTPS)
- Firebase Admin SDK JSON credentials for FCM
- Git (to clone repository)

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/softtime.git
cd softtime
```

### 2. Configure Environment

```bash
# Copy example env file
cp .env.prod.example .env.prod

# Edit with your settings
nano .env.prod
```

**Critical settings to change:**
- `SECRET_KEY` - Generate a strong random key
- `DB_PASSWORD` - Set secure database password
- `REDIS_PASSWORD` - Set secure Redis password
- `ADMIN_PASSWORD` - Set admin account password
- `ALLOWED_ORIGINS` - Add your domain names
- Firebase credentials (see Firebase setup below)

### 3. Firebase Setup (for Push Notifications)

1. Create Firebase project at https://console.firebase.google.com
2. Create Service Account:
   - Project Settings → Service Accounts → Generate New Private Key
   - Download JSON file
3. Copy JSON content to `backend/firebase-adminsdk.json`:

```bash
cp ~/Downloads/serviceAccountKey.json backend/firebase-adminsdk.json
```

### 4. Start Production Services

```bash
# Start all services (PostgreSQL, Redis, Backend, Admin Web)
docker-compose -f docker-compose.prod.full.yml up -d

# Check status
docker-compose -f docker-compose.prod.full.yml ps

# View logs
docker-compose -f docker-compose.prod.full.yml logs -f backend
```

### 5. Initialize Database

```bash
# Run migrations
docker-compose -f docker-compose.prod.full.yml exec backend alembic upgrade head

# Create default admin user (if not auto-created)
docker-compose -f docker-compose.prod.full.yml exec backend python seed.py
```

### 6. Access Services

- **Admin Web:** http://your-server-ip:3000
- **Backend API:** http://your-server-ip:8000
- **Swagger Docs:** http://your-server-ip:8000/docs

Login with:
- Username: `admin` (or your `ADMIN_USERNAME`)
- Password: (from `ADMIN_PASSWORD`)

## SSL/HTTPS Setup (Recommended)

### Option 1: Let's Encrypt with Nginx

```bash
# Install certbot
sudo apt update && sudo apt install certbot python3-certbot-nginx -y

# Generate certificate
sudo certbot certonly --standalone -d yourdomain.com -d admin.yourdomain.com

# Certificates stored in: /etc/letsencrypt/live/yourdomain.com/
```

Update `nginx/default.conf` to use SSL and update `.env.prod`:

```conf
server {
    listen 443 ssl http2;
    server_name yourdomain.com admin.yourdomain.com;
    
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    
    # ... rest of config
}
```

### Option 2: Reverse Proxy with Traefik

Create `traefik.yml` and integrate with compose file for automatic SSL.

## Monitoring & Maintenance

### Check Health

```bash
# Backend health check
curl http://localhost:8000/api/v1/health

# Database connection
docker-compose -f docker-compose.prod.full.yml exec postgres pg_isready

# Redis connection
docker-compose -f docker-compose.prod.full.yml exec redis redis-cli ping
```

### Backup Database

```bash
# Daily backup script
docker-compose -f docker-compose.prod.full.yml exec postgres \
  pg_dump -U softtime softtime > backup_$(date +%Y%m%d).sql
```

### View Logs

```bash
# Backend logs
docker-compose -f docker-compose.prod.full.yml logs -f backend --tail=100

# All services
docker-compose -f docker-compose.prod.full.yml logs -f
```

### Stop Services

```bash
docker-compose -f docker-compose.prod.full.yml down

# Stop and remove volumes (WARNING: deletes data!)
docker-compose -f docker-compose.prod.full.yml down -v
```

## Updating Application

```bash
# Pull latest code
git pull origin main

# Rebuild backend image
docker-compose -f docker-compose.prod.full.yml build --no-cache backend

# Apply migrations
docker-compose -f docker-compose.prod.full.yml exec backend alembic upgrade head

# Restart services
docker-compose -f docker-compose.prod.full.yml up -d
```

## Troubleshooting

### Backend can't connect to database
```bash
# Check PostgreSQL logs
docker-compose -f docker-compose.prod.full.yml logs postgres

# Verify DB_PASSWORD in .env.prod
cat .env.prod | grep DB_PASSWORD
```

### Redis connection error
```bash
# Check Redis logs and password
docker-compose -f docker-compose.prod.full.yml logs redis

# Verify REDIS_PASSWORD
cat .env.prod | grep REDIS_PASSWORD
```

### FCM notifications not working
```bash
# Check Firebase credentials file exists
ls -la backend/firebase-adminsdk.json

# Check backend logs for Firebase errors
docker-compose -f docker-compose.prod.full.yml logs backend | grep -i firebase
```

### Port conflicts
```bash
# Change ports in .env.prod
BACKEND_PORT=8001
ADMIN_WEB_PORT=3001
```

## Security Checklist

- [ ] Changed all default passwords in `.env.prod`
- [ ] Generated strong `SECRET_KEY` (min 32 chars, random)
- [ ] Enabled HTTPS/SSL certificates
- [ ] Set `ALLOWED_ORIGINS` to your domains only
- [ ] Backed up `firebase-adminsdk.json` securely
- [ ] Configured firewall rules
- [ ] Set up automated database backups
- [ ] Enabled audit logs
- [ ] Monitored system resources

## Performance Tuning

### Database
```yaml
# In docker-compose.prod.full.yml:
environment:
  - POSTGRES_INITDB_ARGS="-c shared_buffers=256MB -c max_connections=200"
```

### Redis
```yaml
# In docker-compose.prod.full.yml:
command: redis-server --maxmemory 1gb --maxmemory-policy allkeys-lru
```

### Backend
```bash
# Use gunicorn in production (instead of uvicorn)
# Update Dockerfile.prod to use: gunicorn -w 4 -k uvicorn.workers.UvicornWorker
```

## Support & Documentation

- **API Docs:** http://your-server:8000/docs
- **GitHub:** https://github.com/yourusername/softtime
- **Issues:** Report on GitHub Issues
- **Docs:** See `/docs` directory in repository

---

**Last Updated:** May 2026 | **Version:** 2.0
