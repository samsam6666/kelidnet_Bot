#!/bin/bash
# ==============================================================================
# AlamorVPN Bot Professional Installer & Manager v5.0 (Smart SSL + Safe Nginx)
# ==============================================================================

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

REPO_URL="https://github.com/AlamorNetwork/AlamorVPN_Bot.git"
PROJECT_NAME="AlamorVPN_Bot"
INSTALL_DIR="/var/www/alamorvpn_bot"
BOT_SERVICE_NAME="alamorbot.service"
WEBHOOK_SERVICE_NAME="alamor_webhook.service"

print_success() { echo -e "\n${GREEN}✅ $1${NC}\n"; }
print_error() { echo -e "\n${RED}❌ ERROR: $1${NC}\n"; }
print_info() { echo -e "\n${BLUE}ℹ️ $1${NC}\n"; }
print_warning() { echo -e "\n${YELLOW}⚠️ WARNING: $1${NC}"; }
check_root() { [ "$(id -u)" -ne 0 ] && print_error "Run as root." && exit 1; }

install_bot() {
    check_root
    print_info "Starting full installation..."
    cd /root || { print_error "Cannot access /root"; exit 1; }

    [ -d "$INSTALL_DIR" ] && {
        print_warning "Directory $INSTALL_DIR already exists."
        read -p "Delete and reinstall? (y/n): " confirm_reinstall
        [ "$confirm_reinstall" = "y" ] && remove_bot_internal || exit 0
    }

    apt-get update && apt-get install -y python3 python3-pip python3.10-venv git zip nginx certbot wget
    git clone "$REPO_URL" "$INSTALL_DIR" || { print_error "Failed to clone repo."; exit 1; }

    cd "$INSTALL_DIR" || exit 1
    python3 -m venv .venv
    .venv/bin/pip install -U pip
    .venv/bin/pip install -r requirements.txt
    setup_env_file
    setup_ssl_and_nginx
    setup_services
    print_success "🚀 Installation complete!"
}

setup_env_file() {
    local PYTHON_EXEC="$INSTALL_DIR/.venv/bin/python3"
    print_info "--- .env configuration ---"
    read -p "$(echo -e ${YELLOW}Bot Token:${NC}) " bot_token
    read -p "$(echo -e ${YELLOW}Admin ID:${NC}) " admin_id
    read -p "$(echo -e ${YELLOW}Bot Username (without @):${NC}) " bot_username
    encryption_key=$($PYTHON_EXEC code-generate.py)
    echo -e "${GREEN}Encryption Key: $encryption_key${NC}"
    read -p "Press Enter to continue..."

    cat > .env <<EOL
BOT_TOKEN_ALAMOR="$bot_token"
ADMIN_IDS_ALAMOR="[$admin_id]"
BOT_USERNAME_ALAMOR="$bot_username"
DATABASE_NAME_ALAMOR="database/alamor_vpn.db"
ENCRYPTION_KEY_ALAMOR="$encryption_key"
EOL
    print_success ".env created."
}

setup_ssl_and_nginx() {
    print_info "\n--- SSL & NGINX Configuration ---"
    
    read -p "$(echo -e ${YELLOW}» Enter your webhook/payment domain (e.g. pay.example.com): ${NC})" payment_domain
    read -p "$(echo -e ${YELLOW}» Enter a valid email for Let's Encrypt (e.g. you@example.com): ${NC})" admin_email
    echo ""
    echo -e "${YELLOW}SSL Mode:${NC} (recommended: 1 for test, 2 for real)"
    echo "1) Testing (staging certbot)"
    echo "2) Production (real certificate)"
    read -p "Choose SSL mode [1/2]: " ssl_mode
    echo ""

    if [[ "$ssl_mode" == "1" ]]; then
        CERTBOT_ARGS="--staging"
        print_warning "Using staging mode for SSL (NOT trusted certificate)."
    else
        CERTBOT_ARGS=""
        print_info "Using production mode for SSL (trusted certificate)."
    fi

    SSL_CERT_PATH="/etc/letsencrypt/live/$payment_domain/fullchain.pem"
    SSL_KEY_PATH="/etc/letsencrypt/live/$payment_domain/privkey.pem"

    if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
        print_info "Valid SSL certificate already exists."
    else
        sudo systemctl stop nginx
        sudo mkdir -p /var/www/sslwebroot

        print_info "Requesting SSL via certbot..."
        sudo certbot certonly --webroot -w /var/www/sslwebroot -d "$payment_domain" \
            --email "$admin_email" --agree-tos --no-eff-email --non-interactive $CERTBOT_ARGS

        [ $? -ne 0 ] && print_warning "❌ SSL failed. Will fallback to HTTP."
    fi

    print_info "Downloading fallback SSL configs if missing..."
    [ ! -f "/etc/letsencrypt/options-ssl-nginx.conf" ] && sudo wget -q https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf -O /etc/letsencrypt/options-ssl-nginx.conf
    [ ! -f "/etc/letsencrypt/ssl-dhparams.pem" ] && sudo wget -q https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem -O /etc/letsencrypt/ssl-dhparams.pem

    print_info "Generating NGINX config..."
    NGINX_CONFIG_PATH="/etc/nginx/sites-available/alamor_webhook"

    if [ -f "$SSL_CERT_PATH" ] && [ -f "$SSL_KEY_PATH" ]; then
        sudo tee "$NGINX_CONFIG_PATH" > /dev/null <<EOL
server {
    listen 80;
    server_name $payment_domain;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name $payment_domain;
    ssl_certificate $SSL_CERT_PATH;
    ssl_certificate_key $SSL_KEY_PATH;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL
    else
        sudo tee "$NGINX_CONFIG_PATH" > /dev/null <<EOL
server {
    listen 80;
    server_name $payment_domain;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL
    fi

    sudo ln -sf "$NGINX_CONFIG_PATH" /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null

    sudo nginx -t && sudo systemctl restart nginx
    print_success "NGINX configured."

    echo -e "\n# Webhook Settings" >> .env
    echo "WEBHOOK_DOMAIN=\"$payment_domain\"" >> .env
}

setup_services() {
    print_info "Creating systemd services..."

    sudo tee /etc/systemd/system/$BOT_SERVICE_NAME > /dev/null <<EOL
[Unit]
Description=Alamor VPN Telegram Bot
After=network.target
[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/.venv/bin/python3 $INSTALL_DIR/main.py
Restart=always
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOL

    if grep -q "WEBHOOK_DOMAIN" .env; then
        sudo tee /etc/systemd/system/$WEBHOOK_SERVICE_NAME > /dev/null <<EOL
[Unit]
Description=Alamor Webhook Server
After=network.target
[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/.venv/bin/python3 $INSTALL_DIR/webhook_server.py
Restart=always
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOL
        sudo systemctl enable $WEBHOOK_SERVICE_NAME
        sudo systemctl start $WEBHOOK_SERVICE_NAME
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable $BOT_SERVICE_NAME
    sudo systemctl start $BOT_SERVICE_NAME
    print_success "Services started."
}

update_bot() {
    check_root
    print_info "Updating bot..."
    sudo systemctl stop $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null
    git pull origin main
    $INSTALL_DIR/.venv/bin/pip install -r requirements.txt
    sudo systemctl start $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null
    print_success "Bot updated."
}

remove_bot_internal() {
    print_info "Stopping services..."
    sudo systemctl stop $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null
    sudo systemctl disable $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null
    sudo rm -f /etc/systemd/system/$BOT_SERVICE_NAME /etc/systemd/system/$WEBHOOK_SERVICE_NAME
    sudo systemctl daemon-reload
    sudo rm -f /etc/nginx/sites-enabled/alamor_webhook /etc/nginx/sites-available/alamor_webhook
    sudo systemctl restart nginx
}

remove_bot() {
    check_root
    print_warning "This will DELETE the bot."
    read -p "Are you sure? (y/n): " confirm
    [ "$confirm" = "y" ] && remove_bot_internal && rm -rf "$INSTALL_DIR" && print_success "Bot removed."
}

create_backup() {
    print_info "Creating backup..."
    BACKUP_NAME="alamor_backup_$(date +%F_%H-%M).zip"
    DB_PATH=$(grep "DATABASE_NAME_ALAMOR" .env | cut -d '=' -f2 | tr -d '"')
    [ -f ".env" ] && [ -f "$DB_PATH" ] && zip "$BACKUP_NAME" .env "$DB_PATH" && print_success "Backup created: $BACKUP_NAME" || print_error "Missing files."
}

show_help() {
    echo -e "${BLUE}===== AlamorVPN Bot Manager =====${NC}"
    echo -e "Usage: sudo ./install.sh [command]"
    echo -e "${GREEN}install${NC}   Install the bot"
    echo -e "${GREEN}update${NC}    Update from GitHub"
    echo -e "${GREEN}remove${NC}    Uninstall everything"
    echo -e "${YELLOW}start${NC}     Start services"
    echo -e "${YELLOW}stop${NC}      Stop services"
    echo -e "${YELLOW}restart${NC}   Restart services"
    echo -e "${YELLOW}status${NC}    Show service status"
    echo -e "${YELLOW}logs${NC}      Live logs"
    echo -e "${YELLOW}backup${NC}    Backup .env & DB"
    echo -e "${BLUE}==================================${NC}"
}

# --- Main Entry ---
[ "$1" = "install" ] && install_bot && exit 0
[ ! -f "main.py" ] && cd "$INSTALL_DIR" 2>/dev/null || { print_error "Run install first"; exit 1; }

case "$1" in
    update) update_bot ;;
    remove) remove_bot ;;
    backup) create_backup ;;
    start) check_root; sudo systemctl start $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME; print_success "Started." ;;
    stop) check_root; sudo systemctl stop $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME; print_success "Stopped." ;;
    restart) check_root; sudo systemctl restart $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME; print_success "Restarted." ;;
    status) check_root; systemctl status $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME ;;
    logs) journalctl -u $BOT_SERVICE_NAME -f ;;
    *) show_help ;;
esac
