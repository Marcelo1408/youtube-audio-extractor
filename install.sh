#!/bin/bash
set -e

# =========================================
# YOUTUBE AUDIO EXTRACTOR - INSTALLER
# Versão Estável Produção
# =========================================

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variáveis
INSTALL_DIR="/var/www/youtube-audio-extractor"
REPO_URL="https://github.com/Marcelo1408/youtube-audio-extractor.git"
PYTHON_VERSION="3.10"
DB_NAME="youtube_extractor"
DB_USER="youtube_user"
DB_PASS=$(openssl rand -hex 16)
ADMIN_PASS=$(openssl rand -hex 8)

log() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
  echo -e "${RED}[ERRO]${NC} $1"
  exit 1
}

check_root() {
  [[ "$EUID" -ne 0 ]] && error "Execute como root: sudo ./install.sh"
}

check_internet() {
  ping -c 1 8.8.8.8 &>/dev/null || error "Sem conexão com a internet"
}

# =========================================
# COLETA DE DADOS
# =========================================
read -p "Domínio ou IP do servidor: " DOMAIN
read -p "Email do administrador: " EMAIL

# =========================================
# SISTEMA
# =========================================
log "Atualizando sistema"
apt update && apt upgrade -y

log "Instalando dependências base"
apt install -y curl wget git unzip zip ufw build-essential software-properties-common ca-certificates gnupg lsb-release

# =========================================
# APACHE + PHP
# =========================================
log "Instalando Apache e PHP 8.2"
add-apt-repository -y ppa:ondrej/php
apt update
apt install -y apache2 php8.2 libapache2-mod-php8.2 php8.2-{cli,mysql,curl,mbstring,xml,zip,gd,bcmath,intl}

a2enmod rewrite headers
systemctl enable apache2
systemctl restart apache2

# =========================================
# MARIADB
# =========================================
log "Instalando MariaDB"
apt install -y mariadb-server mariadb-client
systemctl enable mariadb
systemctl start mariadb

mysql <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# =========================================
# REDIS
# =========================================
apt install -y redis-server
systemctl enable redis-server
systemctl start redis-server

# =========================================
# PYTHON 3.10 + VENV
# =========================================
log "Instalando Python ${PYTHON_VERSION}"
apt install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev ffmpeg

python${PYTHON_VERSION} -m venv /opt/youtube-venv
source /opt/youtube-venv/bin/activate

pip install --upgrade pip setuptools wheel

# DEPENDÊNCIAS COMPATÍVEIS
pip install "numpy<2.0"
pip install "scipy<1.12"
pip install "tensorflow<2.16"

pip install \
 yt-dlp \
 spleeter \
 flask \
 redis \
 celery \
 requests \
 pydub \
 mutagen

deactivate

# =========================================
# SUPERVISOR
# =========================================
apt install -y supervisor
systemctl enable supervisor
systemctl start supervisor

# =========================================
# CLONAR SISTEMA
# =========================================
log "Clonando sistema"
rm -rf ${INSTALL_DIR}
git clone ${REPO_URL} ${INSTALL_DIR}

mkdir -p ${INSTALL_DIR}/{logs,backup,assets/uploads}
chown -R www-data:www-data ${INSTALL_DIR}

# =========================================
# .ENV
# =========================================
cp ${INSTALL_DIR}/.env.example ${INSTALL_DIR}/.env

sed -i "s|APP_URL=.*|APP_URL=http://${DOMAIN}|" ${INSTALL_DIR}/.env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" ${INSTALL_DIR}/.env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" ${INSTALL_DIR}/.env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" ${INSTALL_DIR}/.env

# =========================================
# APACHE VHOST
# =========================================
cat > /etc/apache2/sites-available/youtube.conf <<EOF
<VirtualHost *:80>
 ServerName ${DOMAIN}
 DocumentRoot ${INSTALL_DIR}

 <Directory ${INSTALL_DIR}>
  AllowOverride All
  Require all granted
 </Directory>
</VirtualHost>
EOF

a2dissite 000-default.conf
a2ensite youtube.conf
systemctl reload apache2

# =========================================
# FIREWALL
# =========================================
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

# =========================================
# CREDENCIAIS
# =========================================
cat > ${INSTALL_DIR}/CREDENCIAIS.txt <<EOF
URL: http://${DOMAIN}
Admin: admin
Senha: ${ADMIN_PASS}

Banco:
DB: ${DB_NAME}
Usuário: ${DB_USER}
Senha: ${DB_PASS}
EOF

chmod 600 ${INSTALL_DIR}/CREDENCIAIS.txt

# =========================================
# FINAL
# =========================================
log "INSTALAÇÃO CONCLUÍDA COM SUCESSO"
log "Acesse: http://${DOMAIN}"
log "Credenciais salvas em ${INSTALL_DIR}/CREDENCIAIS.txt"
log "Recomenda-se reiniciar o servidor"
