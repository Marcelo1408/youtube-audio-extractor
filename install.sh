#!/bin/bash

set -e

echo "============================================"
echo " YOUTUBE AUDIO EXTRACTOR - INSTALADOR"
echo "============================================"

# CONFIGURAÇÕES
DOMAIN="audioextractor.giize.com"
EMAIL="admin@giize.com"
DB_ROOT_PASS="3GqG!%Yg7i;YsI4Y!"
DB_PASS="SenhaForte@123"
DB_NAME="youtube_extractor"
DB_USER="audioextrac_usr"


PROJECT_DIR="/var/www/$DOMAIN"

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# FUNÇÕES
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }

# -------------------------------
# 1. LIMPA LOCKS DO APT
# -------------------------------
log "🔓 Limpando locks do sistema..."
sudo rm -f /var/lib/apt/lists/lock 2>/dev/null
sudo rm -f /var/lib/dpkg/lock 2>/dev/null
sudo rm -f /var/cache/apt/archives/lock 2>/dev/null
sudo dpkg --configure -a 2>/dev/null

# -------------------------------
# 2. INSTALA DEPENDÊNCIAS DIRETO
# -------------------------------
log "📦 Instalando dependências..."
sudo apt-get install -y \
    nginx \
    mariadb-server mariadb-client \
    php8.1 php8.1-fpm php8.1-mysql php8.1-cli php8.1-curl php8.1-zip \
    php8.1-mbstring php8.1-xml php8.1-gd \
    python3 python3-pip \
    ffmpeg \
    curl wget unzip git \
    certbot python3-certbot-nginx

# -------------------------------
# 3. CONFIGURA MARIADB
# -------------------------------
log "🗄️  Configurando MariaDB..."
sudo systemctl start mariadb
sudo systemctl enable mariadb
sleep 3

# Configura senha root
sudo mysql -u root <<EOF 2>/dev/null || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
FLUSH PRIVILEGES;
EOF

# Cria banco
sudo mysql -u root -p"$DB_ROOT_PASS" <<EOF 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

log "✅ MariaDB configurado"

# -------------------------------
# 4. BAIXA CÓDIGO DO GITHUB
# -------------------------------
log "📥 Baixando código..."
sudo rm -rf "$PROJECT_DIR" 2>/dev/null
sudo mkdir -p "$PROJECT_DIR"

# Tenta clonar
if command -v git >/dev/null 2>&1; then
    sudo git clone https://github.com/Marcelo1408/youtube-audio-extractor.git "$PROJECT_DIR" 2>/dev/null || {
        # Se falhar, baixa ZIP
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        sudo wget -q "https://github.com/Marcelo1408/youtube-audio-extractor/archive/main.zip" -O source.zip
        sudo unzip -q source.zip 2>/dev/null
        sudo mv youtube-audio-extractor-main/* "$PROJECT_DIR"/ 2>/dev/null || true
        cd /
        sudo rm -rf "$TEMP_DIR"
    }
else
    # Baixa via wget
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    sudo wget -q "https://github.com/Marcelo1408/youtube-audio-extractor/archive/main.zip" -O source.zip
    sudo unzip -q source.zip 2>/dev/null
    sudo mv youtube-audio-extractor-main/* "$PROJECT_DIR"/ 2>/dev/null || true
    cd /
    sudo rm -rf "$TEMP_DIR"
fi

# Cria index.php se não existir
if [ ! -f "$PROJECT_DIR/index.php" ]; then
    sudo cat > "$PROJECT_DIR/index.php" <<'PHP'
<?php
echo "<h1>YouTube Audio Extractor</h1>";
echo "<p>Instalação completa!</p>";
echo "<p>Banco: <?php echo getenv('DB_NAME') ?: 'youtube_extractor'; ?></p>";
?>
PHP
fi

log "✅ Código baixado"

# -------------------------------
# 5. DEPENDÊNCIAS PYTHON
# -------------------------------
log "🐍 Python dependencies..."
sudo pip3 install yt-dlp pydub moviepy

# -------------------------------
# 6. PERMISSÕES
# -------------------------------
log "🔒 Permissões..."
sudo mkdir -p "$PROJECT_DIR/uploads"
sudo chown -R www-data:www-data "$PROJECT_DIR"
sudo chmod -R 755 "$PROJECT_DIR"
sudo chmod 775 "$PROJECT_DIR/uploads"

# -------------------------------
# 7. ARQUIVO .ENV
# -------------------------------
log "⚙️  Criando .env..."
sudo cat > "$PROJECT_DIR/.env" <<ENV
APP_ENV=production
APP_URL=https://$DOMAIN

DB_HOST=localhost
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS

PYTHON_PATH=/usr/bin/python3
FFMPEG_PATH=/usr/bin/ffmpeg
YTDLP_PATH=/usr/local/bin/yt-dlp

UPLOAD_DIR=$PROJECT_DIR/uploads
ENV

sudo chown www-data:www-data "$PROJECT_DIR/.env"
sudo chmod 600 "$PROJECT_DIR/.env"

# -------------------------------
# 8. NGINX
# -------------------------------
log "🌐 Nginx..."
sudo cat > "/etc/nginx/sites-available/$DOMAIN" <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    root $PROJECT_DIR;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }
}
NGINX

sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t 2>/dev/null && sudo systemctl restart nginx

# -------------------------------
# 9. PHP
# -------------------------------
log "⚙️  PHP..."
sudo systemctl restart php8.1-fpm

# -------------------------------
# 10. FINALIZAÇÃO
# -------------------------------
echo ""
echo "============================================"
echo "✅ INSTALAÇÃO COMPLETA!"
echo "============================================"
echo "🌐 URL: http://$DOMAIN"
echo "📁 Diretório: $PROJECT_DIR"
echo "🗄️  Banco: $DB_NAME"
echo "👤 Usuário DB: $DB_USER"
echo "🔐 Senha DB: $DB_PASS"
echo ""
echo "📋 Verificação:"
echo "   ls -la $PROJECT_DIR"
echo "   mysql -u $DB_USER -p$DB_PASS $DB_NAME -e 'SHOW TABLES;'"
echo "   systemctl status nginx mariadb php8.1-fpm"
echo "============================================"
