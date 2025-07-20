#!/bin/bash

# ==============================================================================
# AlamorVPN Bot Professional Installer & Manager v4.2 (Final)
# ==============================================================================

# --- Color Codes for better UI ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Variables ---
REPO_URL="https://github.com/AlamorNetwork/AlamorVPN_Bot.git"
PROJECT_NAME="AlamorVPN_Bot"
INSTALL_DIR="/var/www/alamorvpn_bot"
BOT_SERVICE_NAME="alamorbot.service"
WEBHOOK_SERVICE_NAME="alamor_webhook.service"

# --- Helper Functions ---
print_success() { echo -e "\n${GREEN}✅ $1${NC}\n"; }
print_error() { echo -e "\n${RED}❌ ERROR: $1${NC}\n"; }
print_info() { echo -e "\n${BLUE}ℹ️ $1${NC}\n"; }
print_warning() { echo -e "\n${YELLOW}⚠️ WARNING: $1${NC}"; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run with root or sudo privileges."
        exit 1
    fi
}

# --- Main Logic Functions ---

install_bot() {
    check_root
    print_info "Starting the complete installation of AlamorVPN Bot..."

    # Go to a safe directory before starting
    cd /root || { print_error "Cannot change to /root directory. Aborting."; exit 1; }

    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Project directory already exists at $INSTALL_DIR."
        read -p "Do you want to remove it and reinstall? (This will delete all data) (y/n): " confirm_reinstall
        if [[ "$confirm_reinstall" == "y" ]]; then
            remove_bot_internal
        else
            print_info "Installation canceled."; exit 0
        fi
    fi

    print_info "Step 1: Updating system and installing prerequisites..."
    apt-get update && apt-get install -y python3 python3-pip python3.10-venv git zip nginx certbot
    if [ $? -ne 0 ]; then print_error "Failed to install system dependencies. Aborting."; exit 1; fi

    print_info "Step 2: Cloning the project repository from GitHub..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    if [ $? -ne 0 ]; then print_error "Failed to clone the repository. Aborting."; exit 1; fi
    
    cd "$INSTALL_DIR" || { print_error "Failed to cd into project directory. Aborting."; exit 1; }
    
    local VENV_PATH="$INSTALL_DIR/.venv"
    local PYTHON_EXEC="$VENV_PATH/bin/python3"

    print_info "Step 3: Creating virtual environment and installing Python libraries..."
    python3 -m venv .venv
    $PYTHON_EXEC -m pip install --upgrade pip
    $PYTHON_EXEC -m pip install -r requirements.txt
    
    print_info "Step 4: Configuring main bot variables..."
    setup_env_file
    
    print_info "Step 5: Configuring domain and payment gateway..."
    setup_ssl_and_nginx
    
    print_info "Step 6: Setting up persistent services..."
    setup_services
    
    print_success "Installation complete! Your bot is now running as a persistent service."
    print_info "To manage the bot, cd to $INSTALL_DIR and run 'sudo ./install.sh <command>'."
}

setup_env_file() {
    local PYTHON_EXEC="$INSTALL_DIR/.venv/bin/python3"
    print_info "--- Starting .env file configuration ---"
    read -p "$(echo -e ${YELLOW}"Please enter your Telegram Bot Token: "${NC})" bot_token
    read -p "$(echo -e ${YELLOW}"Please enter your numeric Admin ID: "${NC})" admin_id
    read -p "$(echo -e ${YELLOW}"Please enter your bot's username (without @): "${NC})" bot_username
    
    print_info "Generating encryption key..."
    encryption_key=$($PYTHON_EXEC code-generate.py)

    print_warning "CRITICAL: Please save this encryption key in a safe place!"
    print_warning "If you lose this key, you will NOT be able to access your encrypted data."
    echo -e "${GREEN}Your Encryption Key is: $encryption_key${NC}"
    read -p "Press [Enter] to continue after you have saved the key."

    cat > .env <<- EOL
BOT_TOKEN_ALAMOR="$bot_token"
ADMIN_IDS_ALAMOR="[$admin_id]"
BOT_USERNAME_ALAMOR="$bot_username"
DATABASE_NAME_ALAMOR="database/alamor_vpn.db"
ENCRYPTION_KEY_ALAMOR="$encryption_key"
EOL
    print_success ".env file created successfully."
}

setup_ssl_and_nginx() {
    print_info "\n--- Configuring SSL for Payment Domain ---"
    read -p "Do you want to configure an online payment domain? (y/n): " setup_ssl
    if [[ "$setup_ssl" != "y" ]]; then print_success "Skipping SSL configuration."; return; fi

    read -p "$(echo -e ${YELLOW}"Please enter your payment domain (e.g., pay.yourdomain.com): "${NC})" payment_domain
    read -p "$(echo -e ${YELLOW}"Please enter a valid email for Let's Encrypt notifications: "${NC})" admin_email
    
    print_warning "IMPORTANT: To continue, port 80 must be open and pointed to this server's IP."
    
    # Stop Nginx to free up port 80 for Certbot
    print_info "Stopping Nginx temporarily to obtain SSL certificate..."
    sudo systemctl stop nginx
    
    # Get certificate using standalone mode
    print_info "Requesting SSL certificate using Certbot (standalone)..."
    sudo certbot certonly --standalone -d "$payment_domain" --email "$admin_email" --agree-tos --no-eff-email --non-interactive

    if [ $? -ne 0 ]; then
        print_error "Failed to issue SSL certificate. Please ensure the domain is correctly pointed to the server's IP and port 80 is not blocked."
        sudo systemctl start nginx
        exit 1
    fi
    print_success "SSL certificate issued successfully for $payment_domain."

    # Now that the cert exists, create the final Nginx config
    print_info "Configuring Nginx as a Reverse Proxy..."
    NGINX_CONFIG_PATH="/etc/nginx/sites-available/alamor_webhook"
    
    sudo cat > "$NGINX_CONFIG_PATH" <<- EOL
server {
    listen 80;
    server_name $payment_domain;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name $payment_domain;
    ssl_certificate /etc/letsencrypt/live/$payment_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$payment_domain/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL

    # Enable the new config and remove default to prevent conflicts
    sudo ln -s -f "$NGINX_CONFIG_PATH" /etc/nginx/sites-enabled/
    if [ -f "/etc/nginx/sites-enabled/default" ]; then
        sudo rm "/etc/nginx/sites-enabled/default"
    fi

    sudo systemctl start nginx
    print_success "Nginx successfully configured and started."
    
    # Update .env file with the domain
    echo -e "\n# Webhook Settings" >> .env
    echo "WEBHOOK_DOMAIN=\"$payment_domain\"" >> .env
    print_success "Payment domain saved to .env file."
}

setup_services() {
    print_info "Creating systemd services..."
    # Bot Service
    sudo cat > /etc/systemd/system/$BOT_SERVICE_NAME <<- EOL
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

    # Webhook Service
    if grep -q "WEBHOOK_DOMAIN" .env; then
        sudo cat > /etc/systemd/system/$WEBHOOK_SERVICE_NAME <<- EOL
[Unit]
Description=AlamorBot Webhook Server for Payments
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
    print_success "Bot and Webhook services have been enabled and started."
}

update_bot() {
    check_root
    print_info "Updating the bot from the 'main' branch on GitHub..."
    sudo systemctl stop $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null
    git pull origin main
    if [ $? -ne 0 ]; then print_error "Failed to pull updates from GitHub. Aborting."; exit 1; fi
    $INSTALL_DIR/.venv/bin/python3 -m pip install -r requirements.txt
    sudo systemctl start $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null
    print_success "Bot updated and restarted successfully."
}

remove_bot_internal() {
    print_info "Stopping and disabling services..."
    sudo systemctl stop $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null
    sudo systemctl disable $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null
    print_info "Removing service files..."
    sudo rm -f "/etc/systemd/system/$BOT_SERVICE_NAME"
    sudo rm -f "/etc/systemd/system/$WEBHOOK_SERVICE_NAME"
    sudo systemctl daemon-reload
    print_info "Removing Nginx config file..."
    sudo rm -f "/etc/nginx/sites-enabled/alamor_webhook"
    sudo rm -f "/etc/nginx/sites-available/alamor_webhook"
    sudo systemctl restart nginx 2>/dev/null
}

remove_bot() {
    check_root
    print_warning "This operation will completely remove the bot and its related services."
    read -p "Are you sure? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then print_info "Operation canceled."; exit 0; fi
    remove_bot_internal
    print_info "Removing project directory..."
    rm -rf "$INSTALL_DIR"
    print_success "Removal complete."
}

create_backup() {
    print_info "Creating backup file..."
    BACKUP_NAME="alamor_backup_$(date +%Y-%m-%d_%H-%M).zip"
    DB_PATH=$(grep "DATABASE_NAME_ALAMOR" .env | cut -d '=' -f2 | tr -d '"')
    if [ -f ".env" ] && [ -f "$DB_PATH" ]; then
        zip "$BACKUP_NAME" .env "$DB_PATH"
        print_success "Backup file created as $BACKUP_NAME in the current directory."
    else
        print_error "Could not find .env or database file to backup."
    fi
}

show_help() {
    echo -e "${BLUE}======= AlamorVPN Bot Manager =======${NC}"
    echo "Usage: sudo ./install.sh [command]"
    echo "-----------------------------------"
    echo "Commands:"
    echo -e "  ${GREEN}install${NC}   Full installation and initial setup of the bot."
    echo -e "  ${GREEN}update${NC}    Update the bot to the latest version from GitHub."
    echo -e "  ${GREEN}remove${NC}    Completely remove the bot and its services."
    echo -e "  ${YELLOW}start${NC}     Start the bot and webhook services."
    echo -e "  ${YELLOW}stop${NC}      Stop the bot and webhook services."
    echo -e "  ${YELLOW}restart${NC}   Restart the bot and webhook services."
    echo -e "  ${YELLOW}status${NC}    Show the status of the services."
    echo -e "  ${YELLOW}logs${NC}      View the live logs of the main bot."
    echo -e "  ${YELLOW}backup${NC}    Create a backup of the database and settings."
    echo -e "${BLUE}=====================================${NC}"
}

# --- Main Script Logic ---
if [[ "$1" == "install" ]]; then
    install_bot
    exit 0
fi

# For management commands, ensure we are in the project directory
if [ ! -f "main.py" ]; then
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
    else
        print_error "Project directory not found. Please run with 'install' command first or run this script from the project root."
        show_help
        exit 1
    fi
fi

case "$1" in
    update) update_bot ;;
    remove) remove_bot ;;
    backup) create_backup ;;
    start) check_root; sudo systemctl start $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null; print_success "Services started." ;;
    stop) check_root; sudo systemctl stop $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null; print_success "Services stopped." ;;
    restart) check_root; sudo systemctl restart $BOT_SERVICE_NAME $WEBHOOK_SERVICE_NAME 2>/dev/null; print_success "Services restarted." ;;
    status) check_root; print_info "Main Bot Service Status:"; sudo systemctl --no-pager status $BOT_SERVICE_NAME; print_info "\nWebhook Service Status:"; sudo systemctl --no-pager status $WEBHOOK_SERVICE_NAME ;;
    logs) sudo journalctl -u $BOT_SERVICE_NAME -f ;;
    *) show_help ;;
esac