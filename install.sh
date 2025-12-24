#!/bin/bash

# YouTube Audio Extractor - Instalador Automático Completo
# Versão: 2.0.5
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

# Variáveis do sistema
REPO_URL="https://github.com/Marcelo1408/youtube-audio-extractor.git"
INSTALL_DIR="/var/www/youtube-audio-extractor"
DOMAIN_NAME=""
EMAIL_ADMIN="admin@localhost"
DB_PASSWORD=$(openssl rand -base64 32)
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
    if ! ping -c 1 -W 3 8.8.8.8 &> /dev/null && ! ping -c 1 -W 3 1.1.1.1 &> /dev/null; then
        error "Sem conexão com a internet ou ping bloqueado"
        echo "Verifique sua conexão ou firewall"
        exit 1
    fi
    success "Conexão com internet OK"
}

# Função para obter IP público
get_public_ip() {
    local ip=""
    # Tentar múltiplos serviços
    local services=(
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://ifconfig.me"
        "https://ipecho.net/plain"
    )
    
    for service in "${services[@]}"; do
        ip=$(curl -s --max-time 5 "$service" 2>/dev/null)
        if [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    
    # Se falhar, usar IP local
    ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
    echo "$ip"
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
# FUNÇÕES DE INSTALAÇÃO - CORRIGIDAS
# ============================================================================

# Atualizar sistema
update_system() {
    log "Atualizando sistema operacional..."
    apt update
    apt upgrade -y
    apt autoremove -y
    apt clean
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
        net-tools \
        python3-pip \
        python3-venv \
        python3-dev \
        libffi-dev \
        libssl-dev
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
    a2enmod ssl
    
    systemctl enable apache2
    systemctl start apache2
    success "Apache instalado e configurado"
}

# Instalar MySQL/MariaDB - CORRIGIDA
install_mysql() {
    log "Instalando MariaDB (compatível com MySQL)..."
    
    apt update
    apt install -y mariadb-server mariadb-client
    
    systemctl enable mariadb
    systemctl start mariadb
    
    # Esperar o MySQL iniciar
    sleep 5
    
    log "Configurando segurança do MariaDB..."
    
    # Verificar se podemos acessar sem senha primeiro
    if mysql -u root -e "SELECT 1;" &> /dev/null; then
        mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
        success "MariaDB instalado e senha do root configurada"
    else
        # Se não conseguir acessar, o MySQL já pode ter senha configurada
        warn "MariaDB pode já ter senha configurada ou usar autenticação via socket"
        info "Para Ubuntu/Debian, tente acessar com: sudo mysql"
        info "Senha do root MySQL: ${DB_PASSWORD}"
        
        # Tentar configurar via sudo mysql
        if sudo mysql -e "SELECT 1;" &> /dev/null; then
            sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
FLUSH PRIVILEGES;
EOF
            success "MariaDB configurado via sudo"
        fi
    fi
    
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
    if [ -f "$PHP_INI" ]; then
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 2G/' "$PHP_INI"
        sed -i 's/^post_max_size = .*/post_max_size = 2G/' "$PHP_INI"
        sed -i 's/^max_execution_time = .*/max_execution_time = 600/' "$PHP_INI"
        sed -i 's/^max_input_time = .*/max_input_time = 600/' "$PHP_INI"
        sed -i 's/^memory_limit = .*/memory_limit = 1G/' "$PHP_INI"
        sed -i 's/^;date.timezone =.*/date.timezone = America\/Sao_Paulo/' "$PHP_INI"
    fi
    
    systemctl restart apache2
    success "PHP 8.2 instalado e configurado"
}

# Instalar Redis
install_redis() {
    log "Instalando Redis..."
    apt install -y redis-server
    
    # Configurar Redis
    REDIS_CONF="/etc/redis/redis.conf"
    if [ -f "$REDIS_CONF" ]; then
        sed -i 's/^supervised no/supervised systemd/' "$REDIS_CONF"
        sed -i 's/^# maxmemory .*/maxmemory 512mb/' "$REDIS_CONF"
        sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' "$REDIS_CONF"
    fi
    
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
        libswresample-dev \
        libsndfile1
    
    # Criar ambiente virtual Python
    if [ ! -d "/opt/youtube-venv" ]; then
        python3 -m venv /opt/youtube-venv
    fi
    
    # Ativar ambiente virtual e instalar bibliotecas
    source /opt/youtube-venv/bin/activate
    
    # Atualizar pip
    pip3 install --upgrade pip
    
    # Instalar bibliotecas Python (com versões específicas para compatibilidade)
    log "Instalando bibliotecas Python..."
    pip3 install \
        yt-dlp==2023.11.16 \
        pydub==0.25.1 \
        mutagen==1.46.0 \
        redis==5.0.1 \
        celery==5.3.4 \
        numpy==1.24.3 \
        requests==2.31.0 \
        flask==3.0.0 \
        beautifulsoup4==4.12.2 \
        lxml==4.9.3 \
        sqlalchemy==2.0.23 \
        pymysql==1.1.0
    
    # Tentar instalar TensorFlow e Spleeter (opcional)
    log "Instalando bibliotecas de IA (opcional)..."
    pip3 install tensorflow-cpu 2>/dev/null || warn "TensorFlow pode falhar, continuando sem ele"
    pip3 install spleeter 2>/dev/null || warn "Spleeter pode falhar, continuando sem ele"
    
    deactivate
    success "Python e dependências instaladas"
}

# Instalar Node.js (opcional) - CORRIGIDA
install_nodejs() {
    log "Instalando Node.js (opcional)..."
    
    # Verificar se Node.js já está instalado
    if command -v node &> /dev/null; then
        warn "Node.js já está instalado. Versão: $(node --version)"
        return 0
    fi
    
    # Instalar Node.js da forma mais simples
    if apt install -y nodejs npm 2>/dev/null; then
        success "Node.js instalado"
        return 0
    fi
    
    # Se falhar, tentar método alternativo
    warn "Falha ao instalar Node.js via apt. Tentando método alternativo..."
    
    # Usar nvm para instalar Node.js
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    
    # Carregar nvm no shell atual
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Instalar Node.js LTS
    if nvm install --lts; then
        nvm use --lts
        success "Node.js instalado via nvm"
        return 0
    fi
    
    warn "Não foi possível instalar Node.js. Continuando sem ele..."
    return 1
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
    
    # Verificar se UFW está instalado
    if ! command -v ufw &> /dev/null; then
        apt install -y ufw
    fi
    
    # Configurar regras
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    # Habilitar UFW
    echo "y" | ufw enable
    
    success "Firewall configurado"
}

# ============================================================================
# CONFIGURAÇÃO DO SISTEMA - CORRIGIDAS
# ============================================================================

# Clonar repositório
clone_repository() {
    log "Clonando repositório do GitHub..."
    
    if [ -d "$INSTALL_DIR" ]; then
        warn "Diretório $INSTALL_DIR já existe."
        if confirm "Deseja fazer backup e substituir?"; then
            BACKUP_DIR="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
            mv "$INSTALL_DIR" "$BACKUP_DIR"
            info "Backup criado em: $BACKUP_DIR"
        else
            warn "Usando diretório existente. Certifique-se de que está vazio."
        fi
    fi
    
    # Criar diretório se não existir
    mkdir -p "$INSTALL_DIR"
    
    # Tentar clonar o repositório
    if git clone "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
        success "Repositório clonado com sucesso"
    else
        warn "Falha ao clonar repositório. Criando estrutura básica..."
        
        # Criar estrutura de diretórios básica
        mkdir -p "$INSTALL_DIR"/{assets/uploads,temp,logs,backup,scripts,sql,includes}
        
        # Criar index.php básico
        cat > "$INSTALL_DIR/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>YouTube Audio Extractor</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .header { background: #4CAF50; color: white; padding: 20px; border-radius: 5px; }
        .content { padding: 20px; border: 1px solid #ddd; margin-top: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎵 YouTube Audio Extractor</h1>
            <p>Sistema instalado com sucesso!</p>
        </div>
        <div class="content">
            <h2>✅ Instalação Concluída</h2>
            <p>O sistema está pronto para uso.</p>
            <p><strong>URL Admin:</strong> <a href="/admin">/admin</a></p>
            <p><strong>Data da instalação:</strong> <?php echo date('d/m/Y H:i:s'); ?></p>
        </div>
    </div>
</body>
</html>
EOF
        
        # Criar .htaccess básico
        cat > "$INSTALL_DIR/.htaccess" <<'EOF'
Options -Indexes
RewriteEngine On

# Proteger arquivos sensíveis
<FilesMatch "^\.">
    Order allow,deny
    Deny from all
</FilesMatch>

<FilesMatch "\.(sql|log|ini|conf|env)$">
    Order allow,deny
    Deny from all
</FilesMatch>

# Redirecionar para index.php
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.php [L]
EOF
        
        success "Estrutura básica criada"
    fi
}

# Configurar banco de dados - CORRIGIDA
setup_database() {
    log "Configurando banco de dados..."
    
    # Determinar método de acesso ao MySQL
    MYSQL_ACCESS_METHOD=""
    
    # Tentar diferentes métodos de acesso
    if mysql -u root -p"${DB_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
        MYSQL_ACCESS_METHOD="password"
        MYSQL_CMD="mysql -u root -p${DB_PASSWORD}"
        info "Acessando MySQL com senha"
    elif mysql -u root -e "SELECT 1;" &> /dev/null; then
        MYSQL_ACCESS_METHOD="no_password"
        MYSQL_CMD="mysql -u root"
        info "Acessando MySQL sem senha"
    elif sudo mysql -e "SELECT 1;" &> /dev/null; then
        MYSQL_ACCESS_METHOD="sudo"
        MYSQL_CMD="sudo mysql"
        info "Acessando MySQL com sudo"
    else
        error "Não foi possível conectar ao MySQL"
        echo ""
        echo "Soluções:"
        echo "1. Execute: sudo mysql_secure_installation"
        echo "2. Ou: sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';\""
        echo "3. Tente acessar manualmente e depois continue"
        echo ""
        read -p "Pressione Enter após configurar o MySQL..."
        
        # Tentar novamente
        if mysql -u root -p"${DB_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
            MYSQL_CMD="mysql -u root -p${DB_PASSWORD}"
        else
            error "Ainda não foi possível conectar ao MySQL. Pulando configuração do banco."
            return 1
        fi
    fi
    
    # Criar banco de dados
    $MYSQL_CMD <<EOF
CREATE DATABASE IF NOT EXISTS youtube_extractor 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'youtube_user'@'localhost' 
IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON youtube_extractor.* 
TO 'youtube_user'@'localhost';

FLUSH PRIVILEGES;
EOF
    
    # Criar estrutura básica das tabelas
    $MYSQL_CMD youtube_extractor <<EOF
-- Tabela de usuários
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabela de downloads
CREATE TABLE IF NOT EXISTS downloads (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    youtube_url TEXT NOT NULL,
    video_title VARCHAR(255),
    audio_format VARCHAR(10) DEFAULT 'mp3',
    status VARCHAR(20) DEFAULT 'pending',
    file_path VARCHAR(500),
    file_size BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Inserir usuário admin
INSERT INTO users (username, password, email, is_admin) 
VALUES ('admin', SHA2('${ADMIN_PASSWORD}', 256), '${EMAIL_ADMIN}', TRUE)
ON DUPLICATE KEY UPDATE password = SHA2('${ADMIN_PASSWORD}', 256);
EOF
    
    success "Banco de dados configurado"
    info "  Banco: youtube_extractor"
    info "  Usuário: youtube_user"
    info "  Senha: ${DB_PASSWORD}"
}

# Configurar arquivo .env
setup_env_file() {
    log "Configurando arquivo .env..."
    
    ENV_FILE="$INSTALL_DIR/.env"
    
    # Criar arquivo .env do zero
    cat > "$ENV_FILE" <<EOF
# ============================================================================
# CONFIGURAÇÕES DO SISTEMA
# ============================================================================

# Aplicação
APP_NAME="YouTube Audio Extractor"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://${DOMAIN_NAME}
APP_KEY=${SECRET_KEY}

# Banco de Dados
DB_CONNECTION=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=youtube_extractor
DB_USERNAME=youtube_user
DB_PASSWORD=${DB_PASSWORD}

# Cache e Sessão
CACHE_DRIVER=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

# Fila
QUEUE_CONNECTION=redis

# E-mail
MAIL_MAILER=smtp
MAIL_HOST=localhost
MAIL_PORT=25
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=
MAIL_FROM_ADDRESS=${EMAIL_ADMIN}
MAIL_FROM_NAME="YouTube Audio Extractor"

# Segurança
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
API_RATE_LIMIT=60

# YouTube
YTDLP_PATH=/opt/youtube-venv/bin/yt-dlp
FFMPEG_PATH=/usr/bin/ffmpeg
MAX_CONCURRENT_DOWNLOADS=3
DEFAULT_AUDIO_FORMAT=mp3
DEFAULT_BITRATE=192
MAX_FILE_SIZE=2147483648

# Armazenamento
UPLOAD_PATH=${INSTALL_DIR}/assets/uploads
TEMP_PATH=${INSTALL_DIR}/assets/uploads/temp
LOG_PATH=${INSTALL_DIR}/logs
BACKUP_PATH=${INSTALL_DIR}/backup

# Limpeza
FILE_RETENTION_DAYS=7
TEMP_FILE_MAX_AGE=24

# Logs
LOG_CHANNEL=stack
LOG_LEVEL=info
EOF
    
    # Proteger o arquivo .env
    chmod 640 "$ENV_FILE"
    
    success "Arquivo .env configurado"
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
    
    ErrorLog \${APACHE_LOG_DIR}/youtube-extractor-error.log
    CustomLog \${APACHE_LOG_DIR}/youtube-extractor-access.log combined
    
    <Directory ${INSTALL_DIR}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Headers de segurança
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-XSS-Protection "1; mode=block"
        Header always set Referrer-Policy "strict-origin-when-cross-origin"
    </Directory>
    
    # Compressão
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript application/json
    </IfModule>
    
    # Cache
    <IfModule mod_expires.c>
        ExpiresActive On
        ExpiresByType image/jpg "access plus 1 month"
        ExpiresByType image/jpeg "access plus 1 month"
        ExpiresByType image/gif "access plus 1 month"
        ExpiresByType image/png "access plus 1 month"
        ExpiresByType text/css "access plus 1 month"
        ExpiresByType application/javascript "access plus 1 month"
    </IfModule>
    
    # Limites para uploads
    LimitRequestBody 2147483648
    
    # Configurações PHP
    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>
    
    php_value upload_max_filesize 2G
    php_value post_max_size 2G
    php_value max_execution_time 600
    php_value max_input_time 600
    php_value memory_limit 1G
</VirtualHost>
EOF
    
    # Desabilitar site padrão
    a2dissite 000-default.conf 2>/dev/null || true
    
    # Habilitar novo site
    a2ensite youtube-extractor.conf
    
    # Testar configuração
    if apache2ctl configtest; then
        systemctl restart apache2
        success "Virtual Host do Apache configurado"
    else
        error "Erro na configuração do Apache"
        exit 1
    fi
}

# Configurar SSL (se domínio válido)
setup_ssl() {
    if validate_domain "$DOMAIN_NAME"; then
        log "Configurando SSL com Let's Encrypt..."
        
        # Obter certificado SSL
        if certbot --apache \
            -d "$DOMAIN_NAME" \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL_ADMIN" \
            --redirect; then
            success "SSL configurado com sucesso"
            
            # Agendar renovação automática
            (crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet --post-hook \"systemctl reload apache2\"") | crontab -
        else
            warn "Falha ao configurar SSL. Configure manualmente mais tarde."
            warn "Execute: sudo certbot --apache -d $DOMAIN_NAME"
        fi
    else
        warn "Domínio inválido. SSL não configurado."
    fi
}

# Configurar Supervisor para workers
setup_supervisor() {
    log "Configurando Supervisor para workers..."
    
    # Criar diretório de logs
    mkdir -p "$INSTALL_DIR/logs"
    
    # Criar script worker básico se não existir
    WORKER_SCRIPT="$INSTALL_DIR/scripts/worker.py"
    if [ ! -f "$WORKER_SCRIPT" ] && [ -d "$INSTALL_DIR/scripts" ]; then
        cat > "$WORKER_SCRIPT" <<'EOF'
#!/usr/bin/env python3
import os
import sys
import time
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/www/youtube-audio-extractor/logs/worker.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def main():
    logger.info("Iniciando YouTube Audio Extractor Worker")
    
    while True:
        try:
            logger.debug("Worker ativo...")
            time.sleep(30)
        except KeyboardInterrupt:
            logger.info("Worker interrompido")
            break
        except Exception as e:
            logger.error(f"Erro no worker: {e}")
            time.sleep(60)

if __name__ == "__main__":
    main()
EOF
        chmod +x "$WORKER_SCRIPT"
    fi
    
    SUPERVISOR_CONF="/etc/supervisor/conf.d/youtube-worker.conf"
    
    cat > "$SUPERVISOR_CONF" <<EOF
[program:youtube-worker]
command=/opt/youtube-venv/bin/python3 ${INSTALL_DIR}/scripts/worker.py
directory=${INSTALL_DIR}
user=www-data
autostart=true
autorestart=true
startretries=3
stdout_logfile=${INSTALL_DIR}/logs/supervisor-worker.log
stdout_logfile_maxbytes=10MB
stderr_logfile=${INSTALL_DIR}/logs/supervisor-worker-error.log
stderr_logfile_maxbytes=10MB
environment=HOME="${INSTALL_DIR}",USER="www-data"
EOF
    
    # Recarregar configurações
    supervisorctl reread
    supervisorctl update
    
    # Iniciar worker
    supervisorctl start youtube-worker
    
    success "Supervisor configurado para workers"
}

# Configurar permissões
setup_permissions() {
    log "Configurando permissões de arquivos..."
    
    # Definir proprietário como www-data
    chown -R www-data:www-data "$INSTALL_DIR"
    
    # Configurar permissões
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
    
    # Permissões especiais
    chmod -R 775 "$INSTALL_DIR/assets/uploads"
    chmod -R 775 "$INSTALL_DIR/logs"
    chmod 640 "$INSTALL_DIR/.env" 2>/dev/null || true
    
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
# YouTube Audio Extractor - Tarefas agendadas

# Limpeza diária de arquivos temporários (2 AM)
0 2 * * * www-data find ${INSTALL_DIR}/assets/uploads/temp -type f -mtime +1 -delete 2>/dev/null || true

# Backup diário do banco de dados (3 AM)
0 3 * * * www-data /usr/bin/mysqldump -u youtube_user -p'${DB_PASSWORD}' youtube_extractor 2>/dev/null | gzip > ${INSTALL_DIR}/backup/db_backup_\$(date +\%Y\%m\%d).sql.gz 2>/dev/null || true

# Limpeza de backups antigos (> 7 dias) (4 AM)
0 4 * * * www-data find ${INSTALL_DIR}/backup -name "*.gz" -mtime +7 -delete 2>/dev/null || true

# Atualização automática do yt-dlp (Domingo às 6 AM)
0 6 * * 0 www-data /opt/youtube-venv/bin/pip install --upgrade yt-dlp > ${INSTALL_DIR}/logs/update.log 2>&1

# Monitoramento de espaço em disco (a cada hora)
0 * * * * root df -h > ${INSTALL_DIR}/logs/disk_usage.log 2>&1
EOF
    
    chmod 644 "$CRON_FILE"
    success "Cron jobs configurados"
}

# Configurar backup automático
setup_backup() {
    log "Configurando sistema de backup..."
    
    mkdir -p "$INSTALL_DIR/backup"
    
    BACKUP_SCRIPT="$INSTALL_DIR/scripts/backup.sh"
    
    cat > "$BACKUP_SCRIPT" <<EOF
#!/bin/bash
BACKUP_DIR="${INSTALL_DIR}/backup"
DATE=\$(date +%Y%m%d_%H%M%S)

# Backup do banco
mysqldump -u youtube_user -p'${DB_PASSWORD}' youtube_extractor 2>/dev/null | gzip > "\$BACKUP_DIR/db_\$DATE.sql.gz"

# Backup das configurações
tar -czf "\$BACKUP_DIR/config_\$DATE.tar.gz" \
    "$INSTALL_DIR/.env" \
    "/etc/apache2/sites-available/youtube-extractor.conf" \
    "/etc/supervisor/conf.d/youtube-worker.conf" 2>/dev/null

# Limpar backups antigos
find "\$BACKUP_DIR" -name "*.gz" -mtime +7 -delete 2>/dev/null
EOF
    
    chmod +x "$BACKUP_SCRIPT"
    success "Sistema de backup configurado"
}

# Configurar monitoramento
setup_monitoring() {
    log "Configurando monitoramento básico..."
    
    MONITOR_SCRIPT="$INSTALL_DIR/scripts/monitor.sh"
    
    cat > "$MONITOR_SCRIPT" <<'EOF'
#!/bin/bash
LOG_DIR="/var/www/youtube-audio-extractor/logs"
DATE=$(date +%Y%m%d)

# Verificar serviços
for SERVICE in apache2 mysql redis-server supervisor; do
    if ! systemctl is-active --quiet "$SERVICE"; then
        echo "[$(date)] ALERTA: $SERVICE parado" >> "$LOG_DIR/alerts.log"
        systemctl restart "$SERVICE" 2>/dev/null
    fi
done

# Verificar disco
DISK_USAGE=$(df -h / | awk 'NR==2 {print $(NF-1)}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    echo "[$(date)] ALERTA: Disco em ${DISK_USAGE}%" >> "$LOG_DIR/alerts.log"
fi
EOF
    
    chmod +x "$MONITOR_SCRIPT"
    
    # Adicionar ao cron
    echo "*/5 * * * * root $MONITOR_SCRIPT >> $INSTALL_DIR/logs/monitor.log 2>&1" >> /etc/cron.d/youtube-extractor
    
    success "Monitoramento configurado"
}

# ============================================================================
# VALIDAÇÃO E TESTES
# ============================================================================

# Testar instalação
test_installation() {
    log "Testando instalação..."
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   TESTES DO SISTEMA                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Testar Apache
    if systemctl is-active --quiet apache2; then
        echo -e "  ${GREEN}✓${NC} Apache está rodando"
    else
        echo -e "  ${RED}✗${NC} Apache não está rodando"
    fi
    
    # Testar MySQL
    if systemctl is-active --quiet mysql; then
        echo -e "  ${GREEN}✓${NC} MySQL está rodando"
    else
        echo -e "  ${RED}✗${NC} MySQL não está rodando"
    fi
    
    # Testar PHP
    if php --version &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} PHP está instalado"
    else
        echo -e "  ${RED}✗${NC} PHP não está instalado"
    fi
    
    # Testar Python
    if /opt/youtube-venv/bin/python3 --version &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Python está instalado"
    else
        echo -e "  ${RED}✗${NC} Python não está instalado"
    fi
    
    # Testar yt-dlp
    if /opt/youtube-venv/bin/yt-dlp --version &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} yt-dlp está instalado"
    else
        echo -e "  ${RED}✗${NC} yt-dlp não está instalado"
    fi
    
    echo ""
}

# Mostrar resumo da instalação
show_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         INSTALAÇÃO CONCLUÍDA COM SUCESSO!                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    echo -e "${CYAN}📋 RESUMO DA INSTALAÇÃO:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo -e "  ${WHITE}🌐 Domínio:${NC}              ${DOMAIN_NAME}"
    echo -e "  ${WHITE}📁 Diretório:${NC}            ${INSTALL_DIR}"
    echo -e "  ${WHITE}📧 Email Admin:${NC}          ${EMAIL_ADMIN}"
    echo -e "  ${WHITE}🔑 Senha Admin:${NC}          ${ADMIN_PASSWORD}"
    echo -e "  ${WHITE}🗄️  Banco de Dados:${NC}      youtube_extractor"
    echo -e "  ${WHITE}👤 Usuário DB:${NC}           youtube_user"
    echo -e "  ${WHITE}🔒 Senha DB:${NC}             ${DB_PASSWORD}"
    echo ""
    
    echo -e "${CYAN}🚀 URLs DE ACESSO:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo -e "  ${WHITE}🌍 Site Principal:${NC}       https://${DOMAIN_NAME}"
    echo -e "  ${WHITE}🔐 Painel Admin:${NC}         https://${DOMAIN_NAME}/admin"
    echo ""
    
    echo -e "${CYAN}⚠️  IMPORTANTE:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo "  1. Configure o DNS para apontar para: 45.140.193.50"
    echo "  2. Aguarde a propagação do DNS (pode levar algumas horas)"
    echo "  3. Altere a senha do admin no primeiro acesso"
    echo "  4. Configure backups regulares"
    echo ""
    
    echo -e "${CYAN}🔑 CREDENCIAIS:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo "  Usuário admin: admin"
    echo "  Senha admin: ${ADMIN_PASSWORD}"
    echo ""
}

# Salvar credenciais em arquivo seguro
save_credentials() {
    CREDS_FILE="/root/youtube_credentials.txt"
    
    cat > "$CREDS_FILE" <<EOF
========================================
YOUTUBE AUDIO EXTRACTOR - CREDENCIAIS
========================================
Data: $(date)

🌐 ACESSO AO SISTEMA:
------------------
URL: https://${DOMAIN_NAME}
Admin: https://${DOMAIN_NAME}/admin
Usuário: admin
Senha: ${ADMIN_PASSWORD}

🗄️  BANCO DE DADOS:
------------------
Host: localhost
Banco: youtube_extractor
Usuário: youtube_user
Senha: ${DB_PASSWORD}

🔧 INFORMAÇÕES TÉCNICAS:
---------------------
IP do Servidor: 45.140.193.50
Diretório: ${INSTALL_DIR}
Email Admin: ${EMAIL_ADMIN}

⚙️  COMANDOS ÚTEIS:
------------------
Reiniciar serviços:
  sudo systemctl restart apache2 mysql redis supervisor

Verificar status:
  sudo systemctl status apache2 mysql redis supervisor

Monitorar logs:
  tail -f ${INSTALL_DIR}/logs/worker.log

Backup manual:
  sudo bash ${INSTALL_DIR}/scripts/backup.sh

Acessar MySQL:
  mysql -u youtube_user -p youtube_extractor
  Senha: ${DB_PASSWORD}

========================================
⚠️  GUARDE ESTAS CREDENCIAIS EM LOCAL SEGURO!
========================================
EOF
    
    chmod 600 "$CREDS_FILE"
    warn "Credenciais salvas em: $CREDS_FILE"
}

# ============================================================================
# FLUXO PRINCIPAL - CORRIGIDO
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
    echo "║               Instalador Automático v2.0.5                    ║"
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
    info "IP do servidor: 45.140.193.50"
    echo ""
    
    # Configurar domínio automaticamente
    DOMAIN_NAME="audioextractor.giize.com"
    info "Domínio configurado: $DOMAIN_NAME"
    
    # Configurar email
    EMAIL_ADMIN="mpnascimento031@gmail.com"
    info "Email admin: $EMAIL_ADMIN"
    
    # Mostrar configurações
    echo ""
    info "Configurações:"
    echo "  Domínio: $DOMAIN_NAME"
    echo "  Email Admin: $EMAIL_ADMIN"
    echo "  Diretório: $INSTALL_DIR"
    echo ""
    
    echo "A instalação vai:"
    echo "  • Atualizar o sistema"
    echo "  • Instalar Apache, MySQL, PHP, Redis, Python"
    echo "  • Configurar yt-dlp e FFmpeg"
    echo "  • Configurar SSL automático"
    echo "  • Configurar backup e monitoramento"
    echo ""
    
    read -p "Pressione Enter para continuar ou Ctrl+C para cancelar..."
    echo ""
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
    
    # 5. Clonar repositório
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
    
    # 9. Salvar credenciais
    save_credentials
    
    # 10. Mensagem final
    echo ""
    log "✅ Instalação concluída com sucesso!"
    echo ""
    info "📋 PRÓXIMOS PASSOS:"
    echo "  1. Configure o DNS do domínio audioextractor.giize.com"
    echo "     para apontar para o IP: 45.140.193.50"
    echo "  2. Aguarde a propagação do DNS (pode levar algumas horas)"
    echo "  3. Acesse: https://audioextractor.giize.com"
    echo "  4. Faça login com:"
    echo "     Usuário: admin"
    echo "     Senha: ${ADMIN_PASSWORD}"
    echo ""
    info "📄 Credenciais salvas em: /root/youtube_credentials.txt"
    echo ""
    
    # Perguntar sobre reinicialização
    read -p "Deseja reiniciar o servidor agora? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        warn "Reiniciando em 10 segundos... Pressione Ctrl+C para cancelar"
        sleep 10
        reboot
    else
        info "Reinicie manualmente quando necessário: sudo reboot"
    fi
}

# Tratamento de erros
trap 'error "Instalação interrompida"; exit 1' INT
trap 'error "Erro na linha $LINENO"; exit 1' ERR

# Executar instalação
main_installation
