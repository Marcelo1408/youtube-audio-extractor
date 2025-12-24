#!/bin/bash

# YouTube Audio Extractor - Instalador Automático Completo
# Versão: 2.1.0 - COM SITE ZIP E CONFIGURAÇÃO PERSONALIZADA
# Autor: Sistema YouTube Audio Extractor

set -e

# ============================================================================
# CONFIGURAÇÕES
# ============================================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# URL do site real no GitHub (ZIP)
SITE_ZIP_URL="https://github.com/Marcelo1408/youtube-audio-extractor/raw/18d05c50b5bc8c49d813608941b9d79613fdf611/youtube-audio-extractor.zip"
INSTALL_DIR="/var/www/youtube-audio-extractor"

# Credenciais do banco de dados (do seu config.php)
DB_NAME="youtube_extractor"
DB_USER="audioextrac_usr"
DB_PASS="3GqG!%Yg7i;YsI4Y!"

# Variáveis que serão solicitadas
DOMAIN_NAME=""
EMAIL_ADMIN=""
ADMIN_PASSWORD=$(openssl rand -base64 12)
SECRET_KEY=$(openssl rand -base64 48)
JWT_SECRET=$(openssl rand -base64 48)
ENCRYPTION_KEY=$(openssl rand -base64 32)

# ============================================================================
# FUNÇÕES UTILITÁRIAS
# ============================================================================

# Função para log
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCESSO]${NC} $1"
}

# Função para verificar se é root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root"
        echo "Use: sudo ./install.sh"
        exit 1
    fi
}

# Função para verificar conexão com internet
check_internet() {
    log "Verificando conexão com a internet..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error "Sem conexão com a internet"
        exit 1
    fi
    success "Conexão com internet OK"
}

# Função para obter IP público
get_public_ip() {
    curl -s ifconfig.me
}

# Função para perguntar confirmação
confirm() {
    read -p "$1 (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        return 1
    fi
    return 0
}

# Função para validar domínio
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Função para validar email
validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# FUNÇÕES DE INSTALAÇÃO
# ============================================================================

# Atualizar sistema
update_system() {
    log "Atualizando sistema operacional..."
    apt update
    apt upgrade -y
    apt autoremove -y
    success "Sistema atualizado"
}

# Instalar dependências básicas
install_basic_deps() {
    log "Instalando dependências básicas..."
    apt install -y \
        curl \
        wget \
        git \
        unzip \
        zip \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        htop \
        nano \
        vim \
        net-tools
    success "Dependências básicas instaladas"
}

# Instalar Apache
install_apache() {
    log "Instalando Apache..."
    apt install -y apache2
    
    # Habilitar módulos necessários
    a2enmod rewrite
    a2enmod headers
    a2enmod expires
    a2enmod deflate
    
    systemctl enable apache2
    systemctl start apache2
    success "Apache instalado e configurado"
}

# Instalar MySQL
install_mysql() {
    log "Instalando MariaDB (compatível com MySQL)..."
    
    apt update
    apt install -y mariadb-server mariadb-client
    
    systemctl enable mariadb
    systemctl start mariadb
    
    # Não configurar senha do root aqui - vamos usar sudo mysql
    success "MariaDB instalado"
}

# Instalar PHP
install_php() {
    log "Instalando PHP e extensões..."
    
    # Adicionar repositório do PHP
    apt install -y software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt update
    
    # Instalar PHP 8.2 e extensões
    apt install -y \
    php8.2 \
    php8.2-cli \
    php8.2-fpm \
    php8.2-mysql \
    php8.2-curl \
    php8.2-gd \
    php8.2-mbstring \
    php8.2-xml \
    php8.2-zip \
    php8.2-bcmath \
    php8.2-intl \
    php8.2-redis \
    php8.2-soap \
    php8.2-common \
    php8.2-opcache \
    libapache2-mod-php8.2

    
    # Configurar PHP
    PHP_INI="/etc/php/8.2/apache2/php.ini"
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 2G/' $PHP_INI
    sed -i 's/^post_max_size = .*/post_max_size = 2G/' $PHP_INI
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' $PHP_INI
    sed -i 's/^max_input_time = .*/max_input_time = 300/' $PHP_INI
    sed -i 's/^memory_limit = .*/memory_limit = 512M/' $PHP_INI
    
    systemctl restart apache2
    success "PHP 8.2 instalado e configurado"
}

# Instalar Redis
install_redis() {
    log "Instalando Redis..."
    apt install -y redis-server
    
    # Configurar Redis
    REDIS_CONF="/etc/redis/redis.conf"
    sed -i 's/^supervised no/supervised systemd/' $REDIS_CONF
    sed -i 's/^# maxmemory .*/maxmemory 256mb/' $REDIS_CONF
    sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' $REDIS_CONF
    
    systemctl enable redis-server
    systemctl restart redis-server
    success "Redis instalado e configurado"
}

# Instalar Python e dependências
install_python() {
    log "Instalando Python e dependências..."
    
    # Instalar Python
    apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-setuptools
    
    # Instalar FFmpeg
    apt install -y \
        ffmpeg \
        libavcodec-extra \
        libavformat-dev \
        libavutil-dev \
        libswresample-dev
    
    # Criar ambiente virtual Python
    python3 -m venv /opt/youtube-venv
    source /opt/youtube-venv/bin/activate
    
    # Instalar bibliotecas Python (COM CELERY CORRIGIDO)
    pip3 install --upgrade pip
        pip3 install \
        yt-dlp \
        spleeter \
        tensorflow \
        pydub \
        mutagen \
        redis \
        'celery>=5.3.0' \
        pika \
        flask \
        requests \
        'numpy<2.0.0' \        # ← FORÇAR versão compatível
        scipy
    
    deactivate
    success "Python e dependências instaladas"
}

# Instalar Node.js (opcional)
install_nodejs() {
    log "Instalando Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    success "Node.js instalado"
}

# Instalar Supervisor
install_supervisor() {
    log "Instalando Supervisor..."
    apt install -y supervisor
    
    systemctl enable supervisor
    systemctl start supervisor
    success "Supervisor instalado"
}

# Instalar Certbot (SSL)
install_certbot() {
    log "Instalando Certbot para SSL..."
    apt install -y certbot python3-certbot-apache
    
    success "Certbot instalado"
}

# Configurar firewall
setup_firewall() {
    log "Configurando firewall (UFW)..."
    apt install -y ufw
    
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    
    success "Firewall configurado"
}

# ============================================================================
# CONFIGURAÇÃO DO SISTEMA
# ============================================================================

# Baixar e extrair site do ZIP
clone_repository() {
    log "Baixando e extraindo site do GitHub (ZIP)..."
    
    if [ -d "$INSTALL_DIR" ]; then
        warn "Diretório $INSTALL_DIR já existe. Fazendo backup..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Criar diretório
    mkdir -p "$INSTALL_DIR"
    
    # Baixar ZIP
    if wget -O /tmp/youtube-audio-extractor.zip "$SITE_ZIP_URL"; then
        success "Site baixado com sucesso!"
    else
        error "Falha ao baixar o site do GitHub"
        exit 1
    fi
    
    # Extrair ZIP
    log "Extraindo site..."
    if unzip -q /tmp/youtube-audio-extractor.zip -d "$INSTALL_DIR"; then
        success "Site extraído com sucesso!"
        
        # Verificar se extraiu para subdiretório
        if [ -d "$INSTALL_DIR/youtube-audio-extractor" ]; then
            # Mover conteúdo para o diretório principal
            mv "$INSTALL_DIR/youtube-audio-extractor"/* "$INSTALL_DIR/" 2>/dev/null
            mv "$INSTALL_DIR/youtube-audio-extractor"/.* "$INSTALL_DIR/" 2>/dev/null || true
            rm -rf "$INSTALL_DIR/youtube-audio-extractor"
            success "Estrutura organizada"
        fi
        
    else
        error "Falha ao extrair o site"
        exit 1
    fi
    
    # Verificar se temos arquivos PHP
    if ! ls "$INSTALL_DIR"/*.php >/dev/null 2>&1; then
        warn "Nenhum arquivo PHP encontrado no site extraído"
        warn "Verifique se o ZIP contém o site correto"
    fi
}

# Configurar banco de dados usando a estrutura SQL do site
setup_database() {
    log "Configurando banco de dados..."
    
    # 1. Verificar se o arquivo SQL do site existe
    SQL_FILE="$INSTALL_DIR/sql/database.sql"
    if [ ! -f "$SQL_FILE" ]; then
        warn "Arquivo SQL do site não encontrado em: $SQL_FILE"
        warn "Criando estrutura básica do banco..."
        
        # Criar estrutura básica se o arquivo SQL não existir
        sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` 
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' 
IDENTIFIED BY '$DB_PASS';

GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* 
TO '$DB_USER'@'localhost';

FLUSH PRIVILEGES;
EOF
        success "Estrutura básica do banco criada"
        return 0
    fi
    
    # 2. Tentar acesso padrão do Ubuntu (sudo mysql)
    log "Tentando acessar o MariaDB com 'sudo mysql'..."
    if ! sudo mysql -e "SELECT 1;" > /dev/null 2>&1; then
        error "Não foi possível acessar o MariaDB com 'sudo mysql'."
        warn "Execute 'sudo mysql' manualmente para verificar o problema."
        return 1
    fi
    
    # 3. Criar banco, usuário e importar estrutura COMPLETA do SQL
    log "Criando banco de dados '$DB_NAME' e importando estrutura completa..."
    
    sudo mysql <<EOF
-- Criar banco de dados se não existir
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` 
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Criar usuário (usando as credenciais do seu config.php)
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' 
IDENTIFIED BY '$DB_PASS';

-- Conceder todos os privilégios
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* 
TO '$DB_USER'@'localhost';

-- Aplicar mudanças
FLUSH PRIVILEGES;
EOF

    # 4. Importar o arquivo SQL COMPLETO do seu site
    if sudo mysql "$DB_NAME" < "$SQL_FILE"; then
        success "Estrutura completa do banco de dados importada com sucesso!"
        
        # 5. Atualizar email do admin para o email fornecido na instalação
        log "Configurando usuário admin padrão..."
        sudo mysql "$DB_NAME" <<EOF
-- Atualizar email do admin
UPDATE users SET email = '$EMAIL_ADMIN' WHERE username = 'admin';
-- Nota: A senha padrão do admin é 'password' (hash já está no SQL)
EOF
        success "Banco de dados '$DB_NAME' configurado e pronto para uso!"
    else
        error "Falha ao importar o arquivo SQL: $SQL_FILE"
        warn "Verifique se há erros de sintaxe no arquivo SQL."
        warn "Criando estrutura básica como fallback..."
        
        # Fallback: criar estrutura básica
        sudo mysql "$DB_NAME" <<EOF
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) NOT NULL UNIQUE,
  email VARCHAR(100) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  role ENUM('user','admin','moderator') DEFAULT 'user',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (username, email, password, role) VALUES
('admin', '$EMAIL_ADMIN', '\$2y\$10\$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin')
ON DUPLICATE KEY UPDATE email='$EMAIL_ADMIN';
EOF
        success "Estrutura básica criada como fallback"
    fi
}

# Configurar arquivo .env usando o config.php como base
setup_env_file() {
    log "Configurando configurações do sistema..."
    
    # Verificar se config.php existe
    CONFIG_FILE="$INSTALL_DIR/config.php"
    if [ ! -f "$CONFIG_FILE" ]; then
        warn "Arquivo config.php não encontrado. Criando configurações básicas..."
        
        # Criar .env básico
        ENV_FILE="$INSTALL_DIR/.env"
        cat > "$ENV_FILE" <<EOF
APP_NAME=YouTube Audio Extractor
APP_ENV=production
APP_DEBUG=false
APP_URL=https://${DOMAIN_NAME}

DB_CONNECTION=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

CACHE_DRIVER=file
SESSION_DRIVER=file

APP_KEY=${SECRET_KEY}
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}

ADMIN_EMAIL=${EMAIL_ADMIN}
EOF
        success "Arquivo .env básico criado"
        return 0
    fi
    
    # Se config.php existe, o sistema já está configurado
    success "Configurações do sistema já definidas em config.php"
}

# Configurar Apache Virtual Host
setup_apache_vhost() {
    log "Configurando Virtual Host do Apache..."
    
    VHOST_FILE="/etc/apache2/sites-available/youtube-extractor.conf"
    
    cat > "$VHOST_FILE" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN_NAME}
    ServerAdmin ${EMAIL_ADMIN}
    DocumentRoot ${INSTALL_DIR}
    
    ErrorLog \${APACHE_LOG_DIR}/youtube-error.log
    CustomLog \${APACHE_LOG_DIR}/youtube-access.log combined
    
    <Directory ${INSTALL_DIR}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # Configurações de performance
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript application/json
    </IfModule>
    
    # Configurações de segurança
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    
    # Limites para uploads grandes
    LimitRequestBody 2147483648
    php_value upload_max_filesize 2G
    php_value post_max_size 2G
    php_value max_execution_time 300
    php_value max_input_time 300
    php_value memory_limit 512M
</VirtualHost>
EOF
    
    # Desabilitar site padrão e habilitar novo
    a2dissite 000-default.conf
    a2ensite youtube-extractor.conf
    
    systemctl restart apache2
    success "Virtual Host do Apache configurado"
}

# Configurar SSL (se domínio válido)
setup_ssl() {
    if validate_domain "$DOMAIN_NAME"; then
        log "Configurando SSL com Let's Encrypt..."
        
        if certbot --apache -d "$DOMAIN_NAME" --non-interactive --agree-tos --email "$EMAIL_ADMIN"; then
            success "SSL configurado com sucesso"
        else
            warn "Falha ao configurar SSL. Configure manualmente mais tarde."
        fi
    else
        warn "Domínio inválido. SSL não configurado."
    fi
}

# Configurar Supervisor para workers
setup_supervisor() {
    log "Configurando Supervisor para workers..."
    
    SUPERVISOR_CONF="/etc/supervisor/conf.d/youtube-worker.conf"
    
    # Verificar se o script worker.py existe
    if [ ! -f "$INSTALL_DIR/scripts/worker.py" ]; then
        warn "Script worker.py não encontrado. Pulando configuração do Supervisor."
        return 0
    fi
    
    cat > "$SUPERVISOR_CONF" <<EOF
[program:youtube-downloader]
command=/opt/youtube-venv/bin/python3 ${INSTALL_DIR}/scripts/worker.py
directory=${INSTALL_DIR}
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=${INSTALL_DIR}/logs/worker.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=${INSTALL_DIR}/logs/worker-error.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
environment=HOME="${INSTALL_DIR}",USER="www-data",PATH="/usr/bin:/usr/local/bin:/opt/youtube-venv/bin"

[program:youtube-celery]
command=/opt/youtube-venv/bin/celery -A scripts.celery_app worker --loglevel=info
directory=${INSTALL_DIR}
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=${INSTALL_DIR}/logs/celery.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
environment=HOME="${INSTALL_DIR}",USER="www-data",PATH="/usr/bin:/usr/local/bin:/opt/youtube-venv/bin"

[program:youtube-beat]
command=/opt/youtube-venv/bin/celery -A scripts.celery_app beat --loglevel=info
directory=${INSTALL_DIR}
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=${INSTALL_DIR}/logs/celery-beat.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
environment=HOME="${INSTALL_DIR}",USER="www-data",PATH="/usr/bin:/usr/local/bin:/opt/youtube-venv/bin"
EOF
    
    # Recarregar configurações do Supervisor
    supervisorctl reread
    supervisorctl update
    supervisorctl start all
    
    success "Supervisor configurado para workers"
}

# Configurar permissões
setup_permissions() {
    log "Configurando permissões de arquivos..."
    
    # Definir proprietário como www-data
    chown -R www-data:www-data "$INSTALL_DIR"
    
    # Configurar permissões específicas
    chmod 755 "$INSTALL_DIR"
    
    # Criar diretórios necessários se não existirem
    mkdir -p "$INSTALL_DIR/assets/uploads" "$INSTALL_DIR/logs" "$INSTALL_DIR/backup" 2>/dev/null || true
    chmod -R 755 "$INSTALL_DIR/assets/uploads" 2>/dev/null || true
    chmod -R 755 "$INSTALL_DIR/logs" 2>/dev/null || true
    chmod -R 755 "$INSTALL_DIR/backup" 2>/dev/null || true
    
    # Scripts executáveis
    if [ -d "$INSTALL_DIR/scripts" ]; then
        chmod +x "$INSTALL_DIR/scripts/"*.py 2>/dev/null || true
        chmod +x "$INSTALL_DIR/scripts/"*.sh 2>/dev/null || true
    fi
    
    success "Permissões configuradas"
}

# Configurar cron jobs
setup_cron() {
    log "Configurando cron jobs..."
    
    CRON_FILE="/etc/cron.d/youtube-extractor"
    
    cat > "$CRON_FILE" <<EOF
# Limpeza diária de arquivos temporários
0 2 * * * www-data find ${INSTALL_DIR}/assets/uploads/temp -type f -mtime +1 -delete 2>/dev/null || true

# Backup diário do banco de dados
0 3 * * * www-data /usr/bin/mysqldump -u ${DB_USER} -p${DB_PASS} ${DB_NAME} | gzip > ${INSTALL_DIR}/backup/db_backup_\$(date +\%Y\%m\%d).sql.gz 2>/dev/null || true

# Limpeza de backups antigos
0 4 * * * www-data find ${INSTALL_DIR}/backup -name "*.gz" -mtime +7 -delete 2>/dev/null || true

# Manutenção do sistema
*/30 * * * * www-data /usr/bin/php ${INSTALL_DIR}/scripts/cleanup.php 2>/dev/null || true

# Monitoramento de espaço em disco
0 * * * * root df -h | grep -E "/\$" | awk '{print \$(NF-1)" usado em "\$NF}' > ${INSTALL_DIR}/logs/disk_usage.log 2>/dev/null || true

# Atualização automática do yt-dlp
0 5 * * 0 www-data /opt/youtube-venv/bin/pip3 install --upgrade yt-dlp 2>/dev/null || true
EOF
    
    chmod 644 "$CRON_FILE"
    success "Cron jobs configurados"
}

# Configurar backup automático
setup_backup() {
    log "Configurando sistema de backup..."
    
    BACKUP_DIR="$INSTALL_DIR/backup"
    mkdir -p "$BACKUP_DIR"
    
    BACKUP_SCRIPT="$INSTALL_DIR/scripts/backup.sh"
    
    # Criar script de backup se não existir
    if [ ! -f "$BACKUP_SCRIPT" ]; then
        mkdir -p "$INSTALL_DIR/scripts"
        cat > "$BACKUP_SCRIPT" <<EOF
#!/bin/bash
# Script de backup automático

BACKUP_DIR="${BACKUP_DIR}"
DATE=\$(date +%Y%m%d_%H%M%S)
LOG_FILE="${INSTALL_DIR}/logs/backup.log"

echo "[\$(date)] Iniciando backup" >> "\$LOG_FILE"

# Backup do banco de dados
mysqldump -u ${DB_USER} -p${DB_PASS} ${DB_NAME} > "\$BACKUP_DIR/db_backup_\$DATE.sql" 2>/dev/null
gzip "\$BACKUP_DIR/db_backup_\$DATE.sql" 2>/dev/null

# Backup dos uploads (se existir)
if [ -d "${INSTALL_DIR}/assets/uploads" ]; then
    tar -czf "\$BACKUP_DIR/uploads_backup_\$DATE.tar.gz" -C "${INSTALL_DIR}/assets/uploads" . 2>/dev/null
fi

# Backup dos arquivos de configuração
tar -czf "\$BACKUP_DIR/config_backup_\$DATE.tar.gz" \\
    "${INSTALL_DIR}/config.php" \\
    "/etc/apache2/sites-available/youtube-extractor.conf" \\
    "/etc/supervisor/conf.d/youtube-worker.conf" 2>/dev/null || true

# Manter apenas últimos 10 backups
find "\$BACKUP_DIR" -name "*.gz" -mtime +10 -delete 2>/dev/null || true
find "\$BACKUP_DIR" -name "*.sql" -mtime +10 -delete 2>/dev/null || true

echo "[\$(date)] Backup concluído" >> "\$LOG_FILE"
EOF
    fi
    
    chmod +x "$BACKUP_SCRIPT"
    
    # Executar backup inicial
    bash "$BACKUP_SCRIPT" 2>/dev/null || true
    
    success "Sistema de backup configurado"
}

# Configurar monitoramento
setup_monitoring() {
    log "Configurando monitoramento básico..."
    
    MONITOR_SCRIPT="$INSTALL_DIR/scripts/monitor.sh"
    
    # Criar script de monitoramento se não existir
    if [ ! -f "$MONITOR_SCRIPT" ]; then
        mkdir -p "$INSTALL_DIR/scripts"
        cat > "$MONITOR_SCRIPT" <<EOF
#!/bin/bash
# Script de monitoramento

LOG_DIR="${INSTALL_DIR}/logs"
DATE=\$(date +%Y%m%d)

# Verificar espaço em disco
DISK_USAGE=\$(df -h / | awk 'NR==2 {print \$(NF-1)}' | sed 's/%//' 2>/dev/null)
if [ -n "\$DISK_USAGE" ] && [ "\$DISK_USAGE" -gt 90 ]; then
    echo "[\$(date)] ALERTA: Uso de disco em \$DISK_USAGE%" >> "\$LOG_DIR/alert_\$DATE.log"
fi

# Verificar memória
MEM_USAGE=\$(free | awk 'NR==2 {printf "%.0f", \$3/\$2 * 100}' 2>/dev/null)
if [ -n "\$MEM_USAGE" ] && [ "\$MEM_USAGE" -gt 90 ]; then
    echo "[\$(date)] ALERTA: Uso de memória em \$MEM_USAGE%" >> "\$LOG_DIR/alert_\$DATE.log"
fi

# Verificar serviços
for SERVICE in apache2 mariadb redis-server supervisor; do
    if ! systemctl is-active --quiet \$SERVICE 2>/dev/null; then
        echo "[\$(date)] ALERTA: Serviço \$SERVICE parado" >> "\$LOG_DIR/alert_\$DATE.log"
        systemctl restart \$SERVICE 2>/dev/null || true
    fi
done

# Verificar workers do Supervisor
if supervisorctl status 2>/dev/null | grep -q "RUNNING"; then
    true
else
    echo "[\$(date)] ALERTA: Workers parados" >> "\$LOG_DIR/alert_\$DATE.log"
    supervisorctl restart all 2>/dev/null || true
fi
EOF
    fi
    
    chmod +x "$MONITOR_SCRIPT"
    
    # Adicionar ao cron para execução a cada 5 minutos
    echo "*/5 * * * * root $MONITOR_SCRIPT" >> /etc/cron.d/youtube-monitor 2>/dev/null || true
    
    success "Monitoramento configurado"
}

# ============================================================================
# VALIDAÇÃO E TESTES
# ============================================================================

# Testar instalação
test_installation() {
    log "Testando instalação..."
    
    echo ""
    info "Realizando testes de sistema:"
    echo "========================================"
    
    # Testar Apache
    if systemctl is-active --quiet apache2; then
        success "✓ Apache está rodando"
    else
        error "✗ Apache não está rodando"
    fi
    
    # Testar MySQL
    if systemctl is-active --quiet mariadb; then
        success "✓ MySQL/MariaDB está rodando"
    else
        error "✗ MySQL/MariaDB não está rodando"
    fi
    
    # Testar Redis
    if systemctl is-active --quiet redis-server; then
        success "✓ Redis está rodando"
    else
        error "✗ Redis não está rodando"
    fi
    
    # Testar PHP
    if php --version &> /dev/null; then
        success "✓ PHP está instalado"
    else
        error "✗ PHP não está instalado"
    fi
    
    # Testar Python
    if /opt/youtube-venv/bin/python3 --version &> /dev/null; then
        success "✓ Python está instalado"
    else
        error "✗ Python não está instalado"
    fi
    
    # Testar yt-dlp
    if /opt/youtube-venv/bin/yt-dlp --version &> /dev/null; then
        success "✓ yt-dlp está instalado"
    else
        error "✗ yt-dlp não está instalado"
    fi
    
    # Testar FFmpeg
    if ffmpeg -version &> /dev/null; then
        success "✓ FFmpeg está instalado"
    else
        error "✗ FFmpeg não está instalado"
    fi
    
    # Testar acesso ao site
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost" | grep -q "200\|302"; then
        success "✓ Site está acessível localmente"
    else
        warn "⚠ Site pode não estar acessível localmente"
    fi
    
    # Testar banco de dados
    if sudo mysql -e "USE $DB_NAME; SELECT 1;" &> /dev/null; then
        success "✓ Banco de dados '$DB_NAME' está acessível"
    else
        error "✗ Banco de dados '$DB_NAME' não está acessível"
    fi
    
    echo "========================================"
}

# Mostrar resumo da instalação
show_summary() {
    echo ""
    echo "========================================"
    echo "  INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "========================================"
    echo ""
    echo "📋 RESUMO DA INSTALAÇÃO:"
    echo "----------------------------------------"
    echo "🌐 Domínio:              ${DOMAIN_NAME}"
    echo "📁 Diretório:            ${INSTALL_DIR}"
    echo "📧 Email Admin:          ${EMAIL_ADMIN}"
    echo "🔑 Senha Admin:          password (padrão - altere!)"
    echo "🗄️  Banco de Dados:      ${DB_NAME}"
    echo "👤 Usuário DB:           ${DB_USER}"
    echo "🔒 Senha DB:             ${DB_PASS}"
    echo ""
    echo "🔧 SERVIÇOS INSTALADOS:"
    echo "----------------------------------------"
    echo "✅ Apache 2.4"
    echo "✅ MariaDB (MySQL)"
    echo "✅ PHP 8.2"
    echo "✅ Redis"
    echo "✅ Python 3 + Virtual Env"
    echo "✅ yt-dlp (com Celery 5.3+)"
    echo "✅ FFmpeg"
    echo "✅ Spleeter (IA)"
    echo "✅ TensorFlow"
    echo "✅ Supervisor"
    echo "✅ Certbot (SSL pronto)"
    echo ""
    echo "🚀 URLs DE ACESSO:"
    echo "----------------------------------------"
    echo "🌍 Site Principal:       http://${DOMAIN_NAME}"
    echo "🔒 Site com SSL:         https://${DOMAIN_NAME} (após configurar DNS)"
    echo ""
    echo "📊 INFORMAÇÕES IMPORTANTES:"
    echo "----------------------------------------"
    echo "1. Configure o DNS do domínio para apontar para o IP do servidor"
    echo "2. Acesse o site e faça login com:"
    echo "   Usuário: admin"
    echo "   Senha: password (ALTERE NO PRIMEIRO ACESSO!)"
    echo "3. Configure backups regulares"
    echo "4. Monitore os logs em: ${INSTALL_DIR}/logs/"
    echo ""
    echo "🛡️  CREDENCIAIS DE ACESSO:"
    echo "----------------------------------------"
    echo "Painel Admin:"
    echo "  Usuário: admin"
    echo "  Senha: password (altere imediatamente!)"
    echo ""
    echo "Banco de Dados:"
    echo "  Host: localhost"
    echo "  Usuário: ${DB_USER}"
    echo "  Senha: ${DB_PASS}"
    echo "  Banco: ${DB_NAME}"
    echo ""
    echo "⚠️  IMPORTANTE:"
    echo "----------------------------------------"
    echo "1. Altere a senha do admin no primeiro acesso!"
    echo "2. Configure firewall adequadamente"
    echo "3. Mantenha o sistema atualizado"
    echo "4. Faça backup regular dos dados"
    echo ""
    echo "📞 SUPORTE:"
    echo "----------------------------------------"
    echo "Logs do sistema: ${INSTALL_DIR}/logs/"
    echo "Documentação: ${INSTALL_DIR}/README.md"
    echo ""
    echo "🔄 COMANDOS ÚTEIS:"
    echo "----------------------------------------"
    echo "Reiniciar serviços:"
    echo "  sudo systemctl restart apache2 mariadb redis"
    echo ""
    echo "Verificar status:"
    echo "  sudo systemctl status apache2 mariadb redis supervisor"
    echo ""
    echo "Monitorar logs:"
    echo "  tail -f ${INSTALL_DIR}/logs/process.log"
    echo "  tail -f /var/log/apache2/youtube-error.log"
    echo ""
    echo "Backup manual:"
    echo "  sudo bash ${INSTALL_DIR}/scripts/backup.sh"
    echo ""
    echo "========================================"
}

# ============================================================================
# FLUXO PRINCIPAL
# ============================================================================

# Banner inicial
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║  ██╗   ██╗ ██████╗ ██╗   ██╗████████╗██████╗  ██████╗ █████╗  ║"
    echo "║  ╚██╗ ██╔╝██╔═══██╗██║   ██║╚══██╔══╝██╔══██╗██╔═══██╗██╔══██╗ ║"
    echo "║   ╚████╔╝ ██║   ██║██║   ██║   ██║   ██████╔╝██║   ██║███████║ ║"
    echo "║    ╚██╔╝  ██║   ██║██║   ██║   ██║   ██╔══██╗██║   ██║██╔══██║ ║"
    echo "║     ██║   ╚██████╔╝╚██████╔╝   ██║   ██║  ██║╚██████╔╝██║  ██║ ║"
    echo "║     ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ║"
    echo "║                                                              ║"
    echo "║               YouTube Audio Extractor                         ║"
    echo "║               Instalador Automático v2.1                      ║"
    echo "║                  (com site ZIP)                              ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Coletar informações do usuário
collect_info() {
    show_banner
    
    info "Bem-vindo ao instalador do YouTube Audio Extractor!"
    echo ""
    
    # Obter IP público
    PUBLIC_IP=$(get_public_ip)
    info "IP público detectado: $PUBLIC_IP"
    echo ""
    
    # Perguntar domínio
    echo "Por favor, insira o domínio que será usado para acessar o sistema."
    echo "Se não tiver um domínio, você pode usar o IP: $PUBLIC_IP"
    echo ""
    
    read -p "Domínio ou IP [${PUBLIC_IP}]: " DOMAIN_NAME
    DOMAIN_NAME=${DOMAIN_NAME:-$PUBLIC_IP}
    
    # Validar domínio
    if ! validate_domain "$DOMAIN_NAME" && [[ ! $DOMAIN_NAME =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "Domínio/IP pode ser inválido. Continuando com: $DOMAIN_NAME"
    fi
    
    # Perguntar email do admin
    echo ""
    read -p "Email do administrador [admin@${DOMAIN_NAME}]: " input_email
    if [ -z "$input_email" ]; then
        EMAIL_ADMIN="admin@${DOMAIN_NAME}"
    else
        EMAIL_ADMIN="$input_email"
    fi
    
    if ! validate_email "$EMAIL_ADMIN"; then
        warn "Email pode ser inválido. Continuando com: $EMAIL_ADMIN"
    fi
    
    # Mostrar configurações
    echo ""
    info "Configurações selecionadas:"
    echo "  Domínio: $DOMAIN_NAME"
    echo "  Email Admin: $EMAIL_ADMIN"
    echo "  Diretório: $INSTALL_DIR"
    echo "  Site: Baixado do GitHub (ZIP)"
    echo "  Banco: $DB_NAME (usuário: $DB_USER)"
    echo ""
    
    if ! confirm "Deseja continuar com estas configurações?"; then
        info "Instalação cancelada pelo usuário"
        exit 0
    fi
}

# Fluxo principal de instalação
main_installation() {
    log "Iniciando instalação do YouTube Audio Extractor..."
    echo ""
    
    # 1. Verificar requisitos
    check_root
    check_internet
    
    # 2. Coletar informações
    collect_info
    
    # 3. Atualizar sistema
    update_system
    
    # 4. Instalar dependências
    install_basic_deps
    install_apache
    install_mysql
    install_php
    install_redis
    install_python
    install_nodejs
    install_supervisor
    install_certbot
    setup_firewall
    
    # 5. Baixar e extrair site do ZIP
    clone_repository
    
    # 6. Configurar sistema
    setup_database
    setup_env_file
    setup_apache_vhost
    setup_ssl
    setup_supervisor
    setup_permissions
    setup_cron
    setup_backup
    setup_monitoring
    
    # 7. Testar instalação
    test_installation
    
    # 8. Mostrar resumo
    show_summary
    
    # 9. Criar arquivo de credenciais
    save_credentials
    
    log "Instalação concluída com sucesso!"
    echo ""
    info "Acesse o sistema em: http://${DOMAIN_NAME}"
    info "Login: admin / password (ALTERE ESTA SENHA!)"
    echo ""
}

# Salvar credenciais em arquivo seguro
save_credentials() {
    CREDS_FILE="${INSTALL_DIR}/SECURITY_CREDENTIALS.txt"
    
    cat > "$CREDS_FILE" <<EOF
========================================
CREDENCIAIS DO YOUTUBE AUDIO EXTRACTOR
========================================

IMPORTANTE: Este arquivo contém informações sensíveis.
Guarde em local seguro e exclua após anotar as credenciais.

DATA DA INSTALAÇÃO: $(date)

ACESSO AO SISTEMA:
------------------
URL: https://${DOMAIN_NAME}
Usuário: admin
Senha: password (ALTERE IMEDIATAMENTE!)

BANCO DE DADOS:
---------------
Host: localhost
Usuário: ${DB_USER}
Senha: ${DB_PASS}
Banco: ${DB_NAME}

CONFIGURAÇÕES DO SISTEMA:
------------------------
Diretório: ${INSTALL_DIR}
Logs: ${INSTALL_DIR}/logs/
Backups: ${INSTALL_DIR}/backup/
Uploads: ${INSTALL_DIR}/assets/uploads/

COMANDOS ÚTEIS:
---------------
Reiniciar serviços: sudo systemctl restart apache2 mariadb redis
Verificar status: sudo systemctl status apache2 mariadb redis supervisor
Monitorar logs: tail -f ${INSTALL_DIR}/logs/process.log
Backup manual: sudo bash ${INSTALL_DIR}/scripts/backup.sh

SEGURANÇA:
---------
1. ALTERE A SENHA DO ADMIN NO PRIMEIRO ACESSO!
2. Configure firewall adequadamente
3. Mantenha o sistema atualizado
4. Faça backups regulares
5. Monitore os logs diariamente

========================================
IMPORTANTE: EXCLUA ESTE ARQUIVO APÓS ANOTAR AS CREDENCIAIS
========================================
EOF
    
    chmod 600 "$CREDS_FILE"
    warn "Credenciais salvas em: $CREDS_FILE"
    warn "EXCLUA ESTE ARQUIVO APÓS ANOTAR AS CREDENCIAIS!"
}

# Tratamento de erros
trap 'error "Instalação interrompida pelo usuário"; exit 1' INT
trap 'error "Ocorreu um erro na linha $LINENO"; exit 1' ERR

# Executar instalação
main_installation
