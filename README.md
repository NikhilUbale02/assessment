# Magento 2 — Senior DevOps Assessment

This is my submission for the Senior DevOps Engineer technical assessment. The goal was to deploy a production-grade Magento 2 stack on a single t2.micro EC2 instance using Docker.

---

## What's Running

8 containers, one server, 1GB RAM:

- **nginx** — handles HTTPS, redirects HTTP, serves as reverse proxy
- **php-fpm** — runs the Magento application
- **mysql** — stores all Magento data
- **elasticsearch** — powers product search
- **redis** — handles caching, sessions, and full-page cache
- **varnish** — full-page cache layer (configured, see known limitations)
- **phpmyadmin** — database UI, protected behind basic auth
- **cron** — runs Magento background jobs

---

## Server Details

- **Cloud:** AWS EC2
- **OS:** Debian 12 (Bookworm)
- **Instance:** t2.micro
- **Region:** ap-south-1
- **Storage:** 30GB gp2
- **Elastic IP:** attached (see submission email)

---

## To Access the Store

First add this to your `/etc/hosts` file:

IP test.dyna.com

Then open: `https://test.dyna.com`

You'll get a browser warning about the self-signed certificate — just click proceed/accept.

- **Store:** https://test.dyna.com
- **Admin panel:** https://test.dyna.com/secureadmin
- **phpMyAdmin:** https://test.dyna.com/pma/ (credentials in submission email)
- **Admin credentials:** sent separately via email

---

## How to Reproduce This From Scratch

Assuming a fresh Debian 12 EC2 instance:

```bash
# System setup
sudo apt update && sudo apt upgrade -y
sudo groupadd clp
sudo useradd -m -g clp -s /bin/bash test-ssh

# Swap — critical on 1GB RAM
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Docker
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker admin

# PHP + Composer on host (needed to install Magento files)
sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
sudo apt update
sudo apt install -y php8.2-cli php8.2-curl php8.2-mbstring php8.2-xml php8.2-zip php8.2-mysql php8.2-gd php8.2-intl php8.2-bcmath php8.2-soap php8.2-xsl
curl -sS https://getcomposer.org/installer | php && sudo mv composer.phar /usr/local/bin/composer

# Clone repo and install Magento
git clone https://github.com/NikhilUbale02/assessment.git magento-stack
cd magento-stack
mkdir magento && cd magento

# Add your Magento Marketplace credentials to auth.json here
composer create-project \
  --repository-url=https://repo.magento.com/ \
  magento/project-community-edition=2.4.7-p3 .

cd ..
sudo chmod -R 777 magento/var/ magento/pub/ magento/generated/ magento/app/etc/

# Start everything
docker compose up -d

# Install Magento
docker compose exec php-fpm php -d memory_limit=2G bin/magento setup:install \
  --base-url=https://test.dyna.com/ \
  --base-url-secure=https://test.dyna.com/ \
  --backend-frontname=secureadmin \
  --db-host=mysql --db-name=magento \
  --db-user=magento --db-password=StrongMagentoPass123! \
  --search-engine=elasticsearch7 \
  --elasticsearch-host=elasticsearch --elasticsearch-port=9200 \
  --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 \
  --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 \
  --session-save=redis --session-save-redis-host=redis --session-save-redis-db=2 \
  --admin-firstname=Nikhil --admin-lastname=Ubale \
  --admin-email=nikhil@example.com \
  --admin-user=admin --admin-password=Admin@12345!

docker compose exec php-fpm php -d memory_limit=2G bin/magento setup:upgrade
docker compose exec php-fpm php -d memory_limit=2G bin/magento setup:di:compile
docker compose exec php-fpm php -d memory_limit=2G bin/magento cache:clean
docker compose exec php-fpm php -d memory_limit=2G bin/magento indexer:reindex
```

---

## Architecture

Browser
|
v
NGINX (443/80)
|-- HTTP traffic --> 301 redirect to HTTPS
|-- HTTPS traffic --> PHP-FPM via FastCGI
|-- /pma/ --> phpMyAdmin (basic auth protected)
|
v
PHP-FPM (Magento app)
|
|-- MySQL       (persistent store)
|-- Redis       (cache + sessions + FPC)
|-- Elasticsearch (search index)
Varnish  -- deployed, configured as pass-through (see known limitations)
Cron     -- separate container running Magento cron every 60s

---

## Design Decisions

**Why bind mount for Magento files?**
Both NGINX and PHP-FPM need to access the same files. Using a bind mount (`./magento:/var/www/html`) is the simplest way to share a filesystem between two containers without a file-copying step. In a multi-server setup I'd use EFS or an S3-backed solution instead.

**Why install Magento on the host with Composer, not inside the Docker image?**
Baking Magento into the image during `docker build` creates a 2GB+ layer that is slow to build, difficult to debug, and needs the image rebuilt every time a file changes. Installing on the host and mounting it in keeps the image lean and the code directly inspectable.

**PHP-FPM pool tuning:**

pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500

Each PHP-FPM worker uses ~80-120MB RAM. With only 1GB split across 8 services, 5 workers is the safe ceiling — anything more risks OOM kills. `dynamic` mode lets idle workers die off, freeing memory during low traffic periods. `max_requests = 500` prevents gradual memory leaks by recycling workers periodically.

**Elasticsearch heap cap:**

ES_JAVA_OPTS=-Xms256m -Xmx256m

Elasticsearch is the biggest RAM consumer in this stack. Without this cap it will grab 512MB+ by default which kills everything else on a 1GB server. 256MB is enough for the search index on a dev/assessment scale deployment.

**MySQL buffer pool:**

--innodb-buffer-pool-size=256M

Default is 128MB. Bumping to 256MB improves query performance without being greedy. Leaves enough headroom for the rest of the stack.

**Redis — why 3 separate logical databases?**

DB 0 → default cache (config, layout, compiled config)
DB 1 → full-page cache (entire rendered HTML pages)
DB 2 → sessions (logged-in user data)

Separating them means I can flush the page cache (`DB 1`) after a deploy without invalidating user sessions (`DB 2`) or compiled config cache (`DB 0`). If they were all in one database a `FLUSHDB` would log out every user.

**Why 2GB swap on a 1GB server?**
`setup:di:compile` alone needs ~420MB of memory. Without swap it OOM-kills mid-compile. Swap is slow but it keeps the process alive. On a real server I'd use a larger instance — on a t2.micro swap is a necessity.

**TLS certificate:**
Self-signed, generated with:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout test.dyna.com.key -out test.dyna.com.crt \
  -subj "/CN=test.dyna.com" \
  -addext "subjectAltName=DNS:test.dyna.com"
```
In production this would be a Let's Encrypt certificate via Certbot.

---

## Verification

```bash
# HTTP redirects to HTTPS
curl -I http://test.dyna.com/
# → 301 Moved Permanently

# Store is live
curl -k -I https://test.dyna.com/
# → 200 OK

# Redis is being used
docker compose exec redis redis-cli keys "*" | wc -l
# → 400+ keys

# Data survives a restart
docker compose down && docker compose up -d
# → all containers come back, store still works
```

---

## Known Limitations

**Sample data:** Not installed. Magento 2.4.7-p3 has a dependency conflict — `magento/security-package` requires `google/recaptcha ^1.2` which in its latest version requires PHP 8.4, but we're running PHP 8.2. The `--ignore-platform-reqs` flag doesn't help here because it's a Composer resolver conflict, not a platform check. With more time I'd pin `google/recaptcha` to an older compatible version.

**Varnish:** The container is running but configured in pass-through mode (`return(pass)` in the VCL). Proper Varnish integration requires exporting the VCL from Magento Admin after the store is fully configured. I ran out of time to complete this step but the container, Dockerfile, and VCL structure are all in place and ready for the real config.

**Container user:** PHP-FPM runs as root rather than `test-ssh:clp`. This is a side effect of using a bind mount — files created by Composer on the host are owned by the host user, and matching UIDs across host and container with a bind mount requires additional entrypoint scripting. In a pure Docker image approach I had the non-root user correctly configured (see the php-fpm Dockerfile comments).

---

## File Structure

magento-stack/
├── docker-compose.yml
├── .env                    ← not committed
├── .gitignore
├── README.md
├── nginx/
│   ├── Dockerfile
│   ├── conf.d/
│   │   └── test.dyna.com.conf
│   └── certs/              ← .key not committed
├── varnish/
│   ├── Dockerfile
│   └── default.vcl
└── php-fpm/
├── Dockerfile
└── www.conf

---

## Security Group Justification

| Port | Open To | Why |
|---|---|---|
| 22 | My IP only | SSH — restricted to prevent brute force |
| 80 | 0.0.0.0/0 | HTTP — needed to serve the 301 redirect to HTTPS |
| 443 | 0.0.0.0/0 | HTTPS — the actual store traffic |

Nothing else is open. MySQL, Redis, Elasticsearch, and phpMyAdmin are all on an internal Docker network and not reachable from outside.


