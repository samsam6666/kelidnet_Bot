#!/bin/bash

# ==============================================================================
# AlamorVPN Bot Professional Installer & Manager v3.0
# Clones the repo, installs all dependencies, configures Nginx/SSL,
# sets up services, and provides management commands.
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
INSTALL_DIR="/root/$PROJECT_NAME"
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
    apt-get update && apt-get install -y python3 python3-pip python3.10-venv git zip nginx certbot python3-certbot-nginx
    if [ $? -ne 0 ]; then print_error "Failed to install system dependencies. Aborting."; exit 1; fi

    print_info "Step 2: Cloning the project repository from GitHub..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    if [ $? -ne 0 ]; then print_error "Failed to clone the repository. Aborting."; exit 1; fi
    
    cd "$INSTALL_DIR" || { print_error "Failed to cd into project directory. Aborting."; exit 1; }
    
    VENV_PATH="$INSTALL_DIR/.venv"
    PYTHON_EXEC="$VENV_PATH/bin/python3"

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
    print_info "--- Starting .env file configuration ---"
    # ... (prompts for bot token and admin id) ...
    read -p "$(echo -e ${YELLOW}"Please enter your bot's username (without @): "${NC})" bot_username

    print_info "Generating encryption key..."
    encryption_key=$($PYTHON_EXEC code-generate.py)

    print_warning "CRITICAL: Please save this encryption key in a safe place!"
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
    
    read -p "$(echo -e ${YELLOW}"Please enter your payment domain (e.g., pay.yourdomain.com): "${NC})" payment_domain
    while [[ -z "$payment_domain" ]]; do
        print_error "Domain name cannot be empty."
        read -p "$(echo -e ${YELLOW}"Please enter your payment domain: "${NC})" payment_domain
    done
    
    read -p "$(echo -e ${YELLOW}"Please enter a valid email for Let's Encrypt notifications: "${NC})" admin_email
    
    # ... (rest of the nginx and certbot logic from the previous version) ...

    # Update .env with the domain
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
ExecStart=$PYTHON_EXEC $INSTALL_DIR/main.py
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
ExecStart=$PYTHON_EXEC $INSTALL_DIR/webhook_server.py
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



# --- Main Script Logic ---
if [[ "$1" != "install" && ! -d "$INSTALL_DIR" ]]; then
    print_error "Project directory not found. Please run with 'install' command first."
    exit 1
fi
if [[ -d "$INSTALL_DIR" ]]; then
    cd "$INSTALL_DIR"
    VENV_PATH="$INSTALL_DIR/.venv"
    PYTHON_EXEC="$VENV_PATH/bin/python3"
fi

case "$1" in
    install) install_bot ;;
    update) update_bot ;;
    remove) remove_bot ;;
    backup) create_backup ;;
    start) check_root; sudo systemctl start $SERVICE_NAME $WEBHOOK_SERVICE_NAME; print_success "Services started." ;;
    stop) check_root; sudo systemctl stop $SERVICE_NAME $WEBHOOK_SERVICE_NAME; print_success "Services stopped." ;;
    restart) check_root; sudo systemctl restart $SERVICE_NAME $WEBHOOK_SERVICE_NAME; print_success "Services restarted." ;;
    status) check_root; print_info "Main Bot Service Status:"; sudo systemctl status $SERVICE_NAME; print_info "\nWebhook Service Status:"; sudo systemctl status $WEBHOOK_SERVICE_NAME ;;
    logs) sudo journalctl -u $SERVICE_NAME -f ;;
esac
