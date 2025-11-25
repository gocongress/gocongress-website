#!/bin/bash

docker compose -p aga-congress up -d

CLI_CONTAINER="aga-congress-wp-cli-1"

# Wait for MariaDB to be ready
echo "Waiting for database..."
until docker exec -i aga-congress-db-1 mysql -uwordpress -pwordpress -e "SELECT 1;" wordpress >/dev/null 2>&1; do
    echo -n "."
    sleep 3
done
echo "Database ready!"

# Command to run wp-cli in docker

ADMIN_USERNAME="admin"

# Prompt for admin email with double verification
DEFAULT_EMAIL="admin@example.test"
while true; do
    read -p "Admin email (leave blank for $DEFAULT_EMAIL): " ADMIN_EMAIL

    # Use default if blank
    if [ -z "$ADMIN_EMAIL" ]; then
        ADMIN_EMAIL="$DEFAULT_EMAIL"
        echo "Using default email: $ADMIN_EMAIL"
        break
    fi

    read -p "Confirm admin email: " ADMIN_EMAIL_CONFIRM

    if [ "$ADMIN_EMAIL" = "$ADMIN_EMAIL_CONFIRM" ]; then
        echo "Email confirmed: $ADMIN_EMAIL"
        break
    else
        echo "Emails do not match. Please try again."
    fi
done

# URL prompt
DEFAULT_URL="http://localhost:11434"
while true; do
    read -p "GOCONGRESS URL (leave blank for $DEFAULT_URL): " GOCONGRESS_URL

    # Use default if blank
    if [ -z "$GOCONGRESS_URL" ]; then
        GOCONGRESS_URL="$DEFAULT_URL"
        echo "Using default URL: $GOCONGRESS_URL"
        break
    fi

    read -p "Confirm URL: " GOCONGRESS_URL_CONFIRM

    if [ "$GOCONGRESS_URL" = "$GOCONGRESS_URL_CONFIRM" ]; then
        echo "URL confirmed: $GOCONGRESS_URL"
        break
    else
        echo "URLs do not match. Please try again."
    fi
done

# Prompt for admin password with double verification
while true; do
    read -s -p "Admin password: " ADMIN_PASSWORD
    echo
    read -s -p "Confirm password: " ADMIN_PASSWORD_CONFIRM
    echo

    if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

BASE_CMD="docker exec -it $CLI_CONTAINER "

# Install core site with default credentials
# Use non-tty docker exec (-i, not -t) and pass the password via stdin to the container
docker exec -i "$CLI_CONTAINER" bash -c \
  'read -r PASS; wp core install --skip-email --url="$3" --title="U.S. Go Congress" --admin_user="$1" --admin_password="$PASS" --admin_email="$2"' \
  -- "$ADMIN_USERNAME" "$ADMIN_EMAIL" "$GOCONGRESS_URL" <<EOF
$ADMIN_PASSWORD
EOF
unset ADMIN_PASSWORD

# Wait for WP to be ready
echo "Waiting for WordPress..."
until docker exec -i "$CLI_CONTAINER" env wp core is-installed >/dev/null 2>&1; do
    echo -n "."
    sleep 3
done
echo " WordPress is ready!"

# Delete default content
echo "Deleting default WordPress content..."

# Delete all posts
POST_IDS=$($BASE_CMD wp post list --post_type=post --field=ID)
if [ -n "$POST_IDS" ]; then
    echo "Deleting posts: $POST_IDS"
    $BASE_CMD wp post delete $POST_IDS --force
fi

# Delete all pages
PAGE_IDS=$($BASE_CMD wp post list --post_type=page --field=ID)
if [ -n "$PAGE_IDS" ]; then
    echo "Deleting pages: $PAGE_IDS"
    $BASE_CMD wp post delete $PAGE_IDS --force
fi

# Delete all comments
COMMENT_IDS=$($BASE_CMD wp comment list --field=ID)
if [ -n "$COMMENT_IDS" ]; then
    echo "Deleting comments: $COMMENT_IDS"
    $BASE_CMD wp comment delete $COMMENT_IDS --force
fi

# Import our pages
$BASE_CMD wp plugin install wordpress-importer --activate
$BASE_CMD cp /import_data/base_pages.xml /var/www/html/base_pages.xml
$BASE_CMD wp import /var/www/html/base_pages.xml --authors=create

# Install kadence theme and plugins
$BASE_CMD wp theme install kadence --activate
$BASE_CMD wp plugin install stackable-ultimate-gutenberg-blocks --activate
$BASE_CMD wp plugin install wp-super-cache --activate

# Make front page show a static page instead of blog posts, and set it to our home page
$BASE_CMD wp option update show_on_front 'page'
$BASE_CMD wp option update page_on_front 5

# Increase base upload size
$BASE_CMD cp /import_data/htaccess /var/www/html/.htaccess

# Show user URL for admin login
echo "Log in to admin panel at $GOCONGRESS_URL/wp-admin"
