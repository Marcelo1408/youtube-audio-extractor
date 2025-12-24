#!/bin/bash
# YouTube Audio Extractor - Instalador Automático
# Versão 2.2.0 (REESCRITO E CORRIGIDO)
# Autor: Marcelo Pereira

set -e

# ================== CORES ==================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ================== VARIÁVEIS ==================
SITE_ZIP_URL="https://github.com/Marcelo1408/youtube-audio-extractor/raw/7fe00f0d688f7a93a9e9eabaf5d29bddb1360120/youtube-audio-extractor.zip"
INSTALL_DIR="/var/www/youtube-audio-extractor"
VENV_DIR="/opt/youtube-venv"

DB_NAME="youtube_extractor"
DB_USER="youtube_user"
DB_PASS="youtube_pass"

DOMAIN_NAME=""
EMAIL_ADMIN=""

# ================== FUNÇÕES ==================
log(){ echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn(){ echo -e "${YELLOW}[AVISO]${NC} $1"; }
error(){ echo -e "${RED}[ERRO]${NC} $1"; }

check_root() {
  if [ "$EUID" -ne 0 ]; then
    error "Execute como root (sudo)"
    exit 1
  fi
}

check_internet() {
  ping -c 1 8.8.8.8 &>/dev/null || { error "Sem internet"; exit 1; }
}

# ================== COLETA ==================
collect_info() {
  read -p "Domínio ou IP do servidor: " DOMAIN_NAME
  read -p "Email do administrador: " EMAIL_ADMIN
}

# ================== SISTEMA ==================
update_system() {
  log "Atualizando sistema..."
  apt update && apt upgrade -y
}

install_packages() {
  log "Instalando pacotes..."
  apt install -y \
    apache2 mariadb-server redis-server \
    curl wget unzip git supervisor \
    ffmpeg \
    python3 python3-pip python3-venv python3-dev \
    build-essential
}

# ================== BANCO ==================
setup_database() {
  log "Configurando banco de dados..."
  mysql <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
}

# ================== SITE ==================
download_site() {
  log "Baixando site..."
  mkdir -p $INSTALL_DIR
  wget -O /tmp/site.zip "$SITE_ZIP_URL"
  unzip -o /tmp/site.zip -d $INSTALL_DIR
}

import_sql() {
  if [ -f "$INSTALL_DIR/database.sql" ]; then
    log "Importando banco..."
    mysql -u${DB_USER} -p${DB_PASS} ${DB_NAME} < $INSTALL_DIR/database.sql
  else
    warn "Arquivo SQL não encontrado"
  fi
}

# ================== PYTHON ==================
setup_python() {
  log "Configurando Python..."
  python3 -m venv $VENV_DIR
  source $VENV_DIR/bin/activate

  pip install --upgrade pip setuptools wheel

  # FIX DEFINITIVO CELERY
  pip install \
    pytz==2023.3 \
    celery==5.3.6 \
    redis==5.0.1 \
    billiard==4.2.0 \
    kombu==5.3.4

  pip install \
    flask \
    yt-dlp \
    spleeter \
    pydub \
    mutagen \
    requests
}

# ================== APACHE ==================
setup_apache() {
  log "Configurando Apache..."
  a2enmod rewrite headers
  cat > /etc/apache2/sites-available/youtube.conf <<EOF
<VirtualHost *:80>
  ServerName ${DOMAIN_NAME}
  DocumentRoot ${INSTALL_DIR}

  <Directory ${INSTALL_DIR}>
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
EOF

  a2ensite youtube.conf
  a2dissite 000-default.conf
  systemctl restart apache2
}

# ================== SUPERVISOR ==================
setup_supervisor() {
  log "Configurando Supervisor..."
  cat > /etc/supervisor/conf.d/youtube-worker.conf <<EOF
[program:youtube-worker]
command=${VENV_DIR}/bin/python ${INSTALL_DIR}/worker.py
directory=${INSTALL_DIR}
autostart=true
autorestart=true
user=www-data
EOF

  supervisorctl reread
  supervisorctl update
}

# ================== PERMISSÕES ==================
set_permissions() {
  chown -R www-data:www-data $INSTALL_DIR
  chmod -R 755 $INSTALL_DIR
}

# ================== EXECUÇÃO ==================
main() {
  check_root
  check_internet
  collect_info
  update_system
  install_packages
  setup_database
  download_site
  import_sql
  setup_python
  setup_apache
  setup_supervisor
  set_permissions

  echo ""
  log "INSTALAÇÃO CONCLUÍDA COM SUCESSO"
  echo "Acesse: http://${DOMAIN_NAME}"
}

main
