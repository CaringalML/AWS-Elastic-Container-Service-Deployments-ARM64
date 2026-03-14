#!/bin/sh
set -e

# Force IPv4 DNS resolution (Docker Alpine may prefer IPv6 which can fail)
if [ -n "$DB_HOST" ]; then
    IPV4=$(dig +short A "$DB_HOST" @8.8.8.8 2>/dev/null | head -n1)
    if [ -n "$IPV4" ]; then
        echo "$IPV4 $DB_HOST" >> /etc/hosts
        echo "Resolved $DB_HOST to $IPV4 (forced IPv4)"
    else
        echo "WARNING: Could not resolve $DB_HOST to IPv4"
    fi
fi

# Ensure storage directories are writable at runtime
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Fail fast if APP_KEY is not injected — never generate at runtime in production.
# To set: php artisan key:generate --show  →  paste output into terraform.tfvars as app_key
if [ -z "$APP_KEY" ]; then
    echo "ERROR: APP_KEY is not set. Inject it via Secrets Manager." >&2
    exit 1
fi

# Create storage symlink so public/storage → storage/app/public
php artisan storage:link --force

# Cache routes and views for production
php artisan route:cache
php artisan view:cache

# Run migrations (non-blocking — logs error but doesn't stop the container)
php artisan migrate --force || echo "WARNING: Migration failed, skipping..."

exec "$@"
