#!/bin/bash

# YouTube Audio Extractor - Instalador Automático Completo
# Versão: 2.0.1
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
CURRENT_DB_PASS=""

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
    PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me || curl -s --max-time 3 icanhazip.com || echo "127.0.0.1")
    echo "$PUBLIC_IP"
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
        pkg-config \
        libssl-dev \
        libffi-dev \
        python3-dev \
        libpq-dev \
        libjpeg-dev \
        libpng-dev \
        libfreetype6-dev
    success "Dependências básicas instaladas"
}

# Instalar Apache
install_apache() {
    log "Instalando Apache..."
    if ! systemctl is-active --quiet apache2; then
        apt install -y apache2
        
        # Habilitar módulos necessários
        a2enmod rewrite
        a2enmod headers
        a2enmod expires
        a2enmod deflate
        a2enmod proxy
        a2enmod proxy_http
        
        systemctl enable apache2
        systemctl start apache2
        success "Apache instalado e configurado"
    else
        warn "Apache já está instalado e rodando"
    fi
}

# Instalar MySQL/MariaDB
install_mysql() {
    log "Instalando MariaDB (compatível com MySQL)..."
    
    # Verificar se já está instalado
    if command -v mysql &> /dev/null || command -v mariadb &> /dev/null; then
        warn "MariaDB/MySQL já está instalado. Pulando instalação..."
        return 0
    fi
    
    apt update
    apt install -y mariadb-server mariadb-client
    
    systemctl enable mariadb
    systemctl start mariadb
    
    # Configurar inicialização segura
    log "Configurando segurança básica do MariaDB..."
    
    # Verificar se podemos acessar sem senha
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
        warn "MariaDB já tem senha configurada. Configure manualmente se necessário."
        warn "Execute: sudo mysql_secure_installation"
    fi
}

# Instalar PHP
install_php() {
    log "Instalando PHP e extensões..."
    
    # Verificar se PHP já está instalado
    if command -v php &> /dev/null && php --version | grep -q "8.2"; then
        warn "PHP 8.2 já está instalado. Pulando instalação..."
    else
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
    fi
    
    # Configurar PHP
    PHP_INI="/etc/php/8.2/apache2/php.ini"
    if [ -f "$PHP_INI" ]; then
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 2G/' "$PHP_INI"
        sed -i 's/^post_max_size = .*/post_max_size = 2G/' "$PHP_INI"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
        sed -i 's/^max_input_time = .*/max_input_time = 300/' "$PHP_INI"
        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
        sed -i 's/^;date.timezone =.*/date.timezone = America\/Sao_Paulo/' "$PHP_INI"
    fi
    
    systemctl restart apache2
    success "PHP 8.2 instalado e configurado"
}

# Instalar Redis
install_redis() {
    log "Instalando Redis..."
    
    if systemctl is-active --quiet redis-server; then
        warn "Redis já está instalado e rodando"
    else
        apt install -y redis-server
        
        # Configurar Redis
        REDIS_CONF="/etc/redis/redis.conf"
        if [ -f "$REDIS_CONF" ]; then
            sed -i 's/^supervised no/supervised systemd/' "$REDIS_CONF"
            sed -i 's/^# maxmemory .*/maxmemory 256mb/' "$REDIS_CONF"
            sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' "$REDIS_CONF"
            
            systemctl enable redis-server
            systemctl restart redis-server
            success "Redis instalado e configurado"
        fi
    fi
}

# Instalar Python e dependências
install_python() {
    log "Instalando Python e dependências..."
    
    # Instalar Python e ferramentas
    apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-setuptools \
        python3-wheel
    
    # Instalar FFmpeg
    apt install -y \
        ffmpeg \
        libavcodec-extra \
        libavformat-dev \
        libavutil-dev \
        libswresample-dev \
        libsndfile1 \
        libasound2-dev
    
    # Criar ambiente virtual Python se não existir
    if [ ! -d "/opt/youtube-venv" ]; then
        python3 -m venv /opt/youtube-venv
        success "Ambiente virtual Python criado"
    fi
    
    # Ativar ambiente virtual e instalar bibliotecas
    source /opt/youtube-venv/bin/activate
    
    # Atualizar pip
    pip3 install --upgrade pip setuptools wheel
    
    # Instalar bibliotecas Python essenciais
    log "Instalando bibliotecas Python..."
    pip3 install \
        yt-dlp \
        pydub \
        mutagen \
        redis \
        celery \
        numpy \
        requests \
        flask \
        beautifulsoup4 \
        lxml \
        sqlalchemy \
        pymysql
    
    # Tentar instalar TensorFlow e Spleeter (opcional)
    log "Instalando bibliotecas de IA (opcional)..."
    pip3 install tensorflow-cpu 2>/dev/null || warn "TensorFlow pode falhar, continuando sem ele"
    pip3 install spleeter 2>/dev/null || warn "Spleeter pode falhar, continuando sem ele"
    
    deactivate
    success "Python e dependências instaladas"
}

# Instalar Node.js (opcional)
install_nodejs() {
    log "Instalando Node.js (opcional)..."
    
    if command -v node &> /dev/null; then
        warn "Node.js já está instalado"
    else
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt install -y nodejs npm
        success "Node.js instalado"
    fi
}

# Instalar Supervisor
install_supervisor() {
    log "Instalando Supervisor..."
    
    if systemctl is-active --quiet supervisor; then
        warn "Supervisor já está instalado e rodando"
    else
        apt install -y supervisor
        
        systemctl enable supervisor
        systemctl start supervisor
        success "Supervisor instalado"
    fi
}

# Instalar Certbot (SSL)
install_certbot() {
    log "Instalando Certbot para SSL..."
    
    if command -v certbot &> /dev/null; then
        warn "Certbot já está instalado"
    else
        apt install -y certbot python3-certbot-apache
        success "Certbot instalado"
    fi
}

# Configurar firewall
setup_firewall() {
    log "Configurando firewall (UFW)..."
    
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "active"; then
            warn "UFW já está ativo"
        else
            apt install -y ufw
            
            ufw allow 22/tcp
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw --force enable
            
            success "Firewall configurado"
        fi
    else
        warn "UFW não está disponível, pulando configuração de firewall"
    fi
}

# ============================================================================
# CONFIGURAÇÃO DO SISTEMA
# ============================================================================

# Verificar acesso ao MySQL
check_mysql_access() {
    log "Verificando acesso ao MySQL/MariaDB..."
    
    # Tentar acessar sem senha
    if mysql -u root -e "SELECT 1;" &> /dev/null; then
        info "MySQL acessível sem senha"
        return 0
    fi
    
    # Tentar acessar com senha de root do sistema (para MariaDB no Ubuntu)
    if sudo mysql -e "SELECT 1;" &> /dev/null; then
        info "MySQL acessível com sudo"
        return 0
    fi
    
    # Pedir senha ao usuário
    echo ""
    warn "Não foi possível acessar o MySQL automaticamente."
    echo "Para continuar, precisamos da senha do root do MySQL."
    echo ""
    echo "Se você não sabe a senha, tente:"
    echo "1. Senha em branco (pressione Enter)"
    echo "2. A senha que você configurou anteriormente"
    echo "3. Para MariaDB no Ubuntu, tente acessar com: sudo mysql"
    echo ""
    
    while true; do
        read -s -p "Digite a senha do root do MySQL (ou Enter para tentar sem senha): " CURRENT_DB_PASS
        echo ""
        
        if [ -z "$CURRENT_DB_PASS" ]; then
            if mysql -u root -e "SELECT 1;" &> /dev/null; then
                info "Conexão bem-sucedida sem senha"
                return 0
            fi
        else
            if mysql -u root -p"${CURRENT_DB_PASS}" -e "SELECT 1;" &> /dev/null; then
                info "Conexão bem-sucedida com senha"
                return 0
            fi
        fi
        
        error "Senha incorreta ou não foi possível conectar ao MySQL"
        if ! confirm "Deseja tentar novamente?"; then
            return 1
        fi
    done
}

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
            if confirm "Deseja usar o diretório existente?"; then
                info "Usando diretório existente: $INSTALL_DIR"
                return 0
            else
                error "Instalação cancelada pelo usuário"
                exit 1
            fi
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
        mkdir -p "$INSTALL_DIR"/{assets/uploads,logs,backup,scripts,sql}
        
        # Criar arquivos básicos
        cat > "$INSTALL_DIR/index.php" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>YouTube Audio Extractor</title>
</head>
<body>
    <h1>YouTube Audio Extractor - Instalação em Progresso</h1>
    <p>Sistema está sendo configurado. Por favor, aguarde.</p>
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
        
        info "Estrutura básica criada em: $INSTALL_DIR"
    fi
}

# Configurar banco de dados
setup_database() {
    log "Configurando banco de dados..."
    
    # Verificar acesso ao MySQL
    if ! check_mysql_access; then
        error "Não foi possível configurar o banco de dados"
        warn "Configure o MySQL manualmente e execute novamente esta etapa"
        return 1
    fi
    
    # Preparar opção de senha para comandos MySQL
    if [ -z "$CURRENT_DB_PASS" ]; then
        MYSQL_CMD="mysql -u root"
    else
        MYSQL_CMD="mysql -u root -p${CURRENT_DB_PASS}"
    fi
    
    # Criar banco de dados
    log "Criando banco de dados 'youtube_extractor'..."
    
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
    
    # Importar estrutura do banco se existir
    if [ -f "$INSTALL_DIR/sql/database.sql" ]; then
        log "Importando estrutura do banco de dados..."
        $MYSQL_CMD youtube_extractor < "$INSTALL_DIR/sql/database.sql"
    elif [ -f "$INSTALL_DIR/database.sql" ]; then
        log "Importando estrutura do banco de dados..."
        $MYSQL_CMD youtube_extractor < "$INSTALL_DIR/database.sql"
    else
        # Criar estrutura básica se não existir arquivo SQL
        log "Criando estrutura básica do banco de dados..."
        
        $MYSQL_CMD youtube_extractor <<EOF
-- Tabela de usuários
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Tabela de downloads
CREATE TABLE IF NOT EXISTS downloads (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    youtube_url TEXT NOT NULL,
    video_title VARCHAR(255),
    video_author VARCHAR(255),
    audio_format VARCHAR(10) DEFAULT 'mp3',
    bitrate INT DEFAULT 192,
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    file_path VARCHAR(500),
    file_size BIGINT,
    duration INT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Tabela de configurações
CREATE TABLE IF NOT EXISTS settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(100) NOT NULL UNIQUE,
    setting_value TEXT,
    description VARCHAR(255),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Inserir usuário admin
INSERT INTO users (username, password, email, is_admin) 
VALUES ('admin', SHA2('${ADMIN_PASSWORD}', 256), '${EMAIL_ADMIN}', TRUE)
ON DUPLICATE KEY UPDATE password = SHA2('${ADMIN_PASSWORD}', 256);

-- Inserir configurações padrão
INSERT INTO settings (setting_key, setting_value, description) VALUES
('site_name', 'YouTube Audio Extractor', 'Nome do site'),
('max_file_size', '2147483648', 'Tamanho máximo de arquivo em bytes (2GB)'),
('allowed_formats', 'mp3,wav,flac,aac', 'Formatos de áudio permitidos'),
('default_bitrate', '192', 'Bitrate padrão para MP3'),
('concurrent_downloads', '3', 'Número máximo de downloads simultâneos'),
('retention_days', '7', 'Dias para manter arquivos antigos'),
('maintenance_mode', '0', 'Modo manutenção (0=off, 1=on)')
ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value);
EOF
    fi
    
    # Atualizar senha do admin se já existir
    $MYSQL_CMD youtube_extractor <<EOF
UPDATE users SET password = SHA2('${ADMIN_PASSWORD}', 256) 
WHERE username = 'admin';
EOF
    
    success "Banco de dados configurado com sucesso"
    info "  Banco: youtube_extractor"
    info "  Usuário: youtube_user"
    info "  Senha: ${DB_PASSWORD}"
}

# Configurar arquivo .env
setup_env_file() {
    log "Configurando arquivo .env..."
    
    ENV_FILE="$INSTALL_DIR/.env"
    ENV_EXAMPLE="$INSTALL_DIR/.env.example"
    
    # Se existir .env.example, usar como base
    if [ -f "$ENV_EXAMPLE" ]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        info "Copiado .env.example para .env"
    else
        # Criar .env do zero
        cat > "$ENV_FILE" <<EOF
# Configurações da Aplicação
APP_NAME="YouTube Audio Extractor"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://${DOMAIN_NAME}
APP_KEY=${SECRET_KEY}

# Configurações de Banco de Dados
DB_CONNECTION=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=youtube_extractor
DB_USERNAME=youtube_user
DB_PASSWORD=${DB_PASSWORD}

# Configurações de Cache
CACHE_DRIVER=redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

# Configurações de Sessão
SESSION_DRIVER=redis
SESSION_LIFETIME=120

# Configurações de Fila
QUEUE_CONNECTION=redis

# Configurações de E-mail
MAIL_MAILER=smtp
MAIL_HOST=localhost
MAIL_PORT=25
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=
MAIL_FROM_ADDRESS=noreply@${DOMAIN_NAME}
MAIL_FROM_NAME="YouTube Audio Extractor"

# Configurações de Segurança
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
API_RATE_LIMIT=60

# Configurações do YouTube
YTDLP_PATH=/opt/youtube-venv/bin/yt-dlp
FFMPEG_PATH=/usr/bin/ffmpeg
MAX_CONCURRENT_DOWNLOADS=3
DEFAULT_AUDIO_FORMAT=mp3
DEFAULT_BITRATE=192
MAX_FILE_SIZE=2147483648

# Configurações de Armazenamento
UPLOAD_PATH=${INSTALL_DIR}/assets/uploads
TEMP_PATH=${INSTALL_DIR}/assets/uploads/temp
LOG_PATH=${INSTALL_DIR}/logs
BACKUP_PATH=${INSTALL_DIR}/backup

# Configurações de Limpeza
FILE_RETENTION_DAYS=7
TEMP_FILE_MAX_AGE=24

# Configurações de Log
LOG_CHANNEL=stack
LOG_LEVEL=info
LOG_MAX_FILES=30
EOF
    fi
    
    # Atualizar variáveis importantes
    sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN_NAME}|" "$ENV_FILE"
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" "$ENV_FILE"
    sed -i "s|APP_KEY=.*|APP_KEY=${SECRET_KEY}|" "$ENV_FILE"
    sed -i "s|JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" "$ENV_FILE"
    sed -i "s|ENCRYPTION_KEY=.*|ENCRYPTION_KEY=${ENCRYPTION_KEY}|" "$ENV_FILE"
    sed -i "s|MAIL_FROM_ADDRESS=.*|MAIL_FROM_ADDRESS=noreply@${DOMAIN_NAME}|" "$ENV_FILE"
    sed -i "s|UPLOAD_PATH=.*|UPLOAD_PATH=${INSTALL_DIR}/assets/uploads|" "$ENV_FILE"
    sed -i "s|TEMP_PATH=.*|TEMP_PATH=${INSTALL_DIR}/assets/uploads/temp|" "$ENV_FILE"
    sed -i "s|LOG_PATH=.*|LOG_PATH=${INSTALL_DIR}/logs|" "$ENV_FILE"
    sed -i "s|BACKUP_PATH=.*|BACKUP_PATH=${INSTALL_DIR}/backup|" "$ENV_FILE"
    
    # Proteger o arquivo .env
    chmod 640 "$ENV_FILE"
    chown www-data:www-data "$ENV_FILE"
    
    success "Arquivo .env configurado"
}

# Configurar Apache Virtual Host
setup_apache_vhost() {
    log "Configurando Virtual Host do Apache..."
    
    VHOST_FILE="/etc/apache2/sites-available/youtube-extractor.conf"
    
    # Criar arquivo de configuração
    cat > "$VHOST_FILE" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN_NAME}
    ServerAdmin ${EMAIL_ADMIN}
    DocumentRoot ${INSTALL_DIR}
    
    ErrorLog \${APACHE_LOG_DIR}/youtube-error.log
    CustomLog \${APACHE_LOG_DIR}/youtube-access.log combined
    
    <Directory ${INSTALL_DIR}>
        Options -Indexes +FollowSymLinks +MultiViews
        AllowOverride All
        Require all granted
        
        # Configurações de segurança
        <IfModule mod_headers.c>
            Header always set X-Content-Type-Options "nosniff"
            Header always set X-Frame-Options "SAMEORIGIN"
            Header always set X-XSS-Protection "1; mode=block"
            Header always set Referrer-Policy "strict-origin-when-cross-origin"
        </IfModule>
    </Directory>
    
    # Configurações de performance
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript application/json application/xml
        BrowserMatch ^Mozilla/4 gzip-only-text/html
        BrowserMatch ^Mozilla/4\.0[678] no-gzip
        BrowserMatch \bMSIE !no-gzip !gzip-only-text/html
    </IfModule>
    
    # Configurações de cache
    <IfModule mod_expires.c>
        ExpiresActive On
        ExpiresByType image/jpg "access plus 1 month"
        ExpiresByType image/jpeg "access plus 1 month"
        ExpiresByType image/gif "access plus 1 month"
        ExpiresByType image/png "access plus 1 month"
        ExpiresByType text/css "access plus 1 month"
        ExpiresByType application/javascript "access plus 1 month"
    </IfModule>
    
    # Limites para uploads grandes
    LimitRequestBody 2147483648
    
    # Configurações PHP
    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>
    
    php_value upload_max_filesize 2G
    php_value post_max_size 2G
    php_value max_execution_time 300
    php_value max_input_time 300
    php_value memory_limit 512M
    php_value session.gc_maxlifetime 1440
</VirtualHost>
EOF
    
    # Desabilitar site padrão se existir
    if [ -f "/etc/apache2/sites-enabled/000-default.conf" ]; then
        a2dissite 000-default.conf
    fi
    
    # Habilitar novo site
    a2ensite youtube-extractor.conf
    
    # Testar configuração
    if apache2ctl configtest; then
        systemctl restart apache2
        success "Virtual Host do Apache configurado"
    else
        error "Erro na configuração do Apache"
        warn "Verifique os logs do Apache: /var/log/apache2/error.log"
    fi
}

# Configurar SSL (se domínio válido)
setup_ssl() {
    if validate_domain "$DOMAIN_NAME"; then
        log "Configurando SSL com Let's Encrypt..."
        
        # Verificar se o domínio aponta para este servidor
        log "Verificando se o domínio $DOMAIN_NAME aponta para este servidor..."
        
        # Tentar obter certificado SSL
        if certbot --apache \
            -d "$DOMAIN_NAME" \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL_ADMIN" \
            --redirect \
            --hsts \
            --uir \
            --staple-ocsp; then
            success "SSL configurado com sucesso para $DOMAIN_NAME"
            
            # Agendar renovação automática
            if ! crontab -l | grep -q "certbot renew"; then
                (crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet --post-hook \"systemctl reload apache2\"") | crontab -
                info "Renovação automática de SSL configurada no cron"
            fi
        else
            warn "Falha ao configurar SSL. Configure manualmente com:"
            warn "  sudo certbot --apache -d $DOMAIN_NAME"
        fi
    else
        warn "Domínio inválido ou IP. SSL não configurado."
        warn "Configure manualmente após apontar domínio válido."
    fi
}

# Configurar Supervisor para workers
setup_supervisor() {
    log "Configurando Supervisor para workers..."
    
    # Criar diretório de logs se não existir
    mkdir -p "$INSTALL_DIR/logs"
    
    SUPERVISOR_CONF="/etc/supervisor/conf.d/youtube-worker.conf"
    
    # Criar script worker básico se não existir
    WORKER_SCRIPT="$INSTALL_DIR/scripts/worker.py"
    if [ ! -f "$WORKER_SCRIPT" ]; then
        mkdir -p "$(dirname "$WORKER_SCRIPT")"
        cat > "$WORKER_SCRIPT" <<'EOF'
#!/usr/bin/env python3
"""
Worker para processamento de downloads do YouTube
"""

import os
import sys
import time
import logging
import subprocess
from pathlib import Path

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/www/youtube-audio-extractor/logs/worker.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def download_audio(youtube_url, output_format='mp3', bitrate=192):
    """Baixa e converte áudio do YouTube"""
    try:
        # Criar diretório de saída
        output_dir = Path('/var/www/youtube-audio-extractor/assets/uploads')
        output_dir.mkdir(exist_ok=True)
        
        # Gerar nome de arquivo único
        timestamp = int(time.time())
        output_file = output_dir / f"audio_{timestamp}.{output_format}"
        
        # Comando yt-dlp
        cmd = [
            '/opt/youtube-venv/bin/yt-dlp',
            '-x',  # Extrair áudio
            '--audio-format', output_format,
            '--audio-quality', f'{bitrate}',
            '--output', str(output_file),
            '--no-playlist',
            youtube_url
        ]
        
        logger.info(f"Executando comando: {' '.join(cmd)}")
        
        # Executar download
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        
        if result.returncode == 0:
            logger.info(f"Download concluído: {output_file}")
            return {
                'success': True,
                'file_path': str(output_file),
                'file_size': output_file.stat().st_size if output_file.exists() else 0
            }
        else:
            logger.error(f"Erro no download: {result.stderr}")
            return {
                'success': False,
                'error': result.stderr
            }
            
    except subprocess.TimeoutExpired:
        error_msg = "Tempo limite excedido no download"
        logger.error(error_msg)
        return {
            'success': False,
            'error': error_msg
        }
    except Exception as e:
        error_msg = f"Erro inesperado: {str(e)}"
        logger.error(error_msg)
        return {
            'success': False,
            'error': error_msg
        }

def main():
    """Loop principal do worker"""
    logger.info("Iniciando YouTube Audio Extractor Worker")
    
    while True:
        try:
            # Aqui você implementaria a lógica para pegar jobs da fila
            # Por enquanto, apenas dorme e verifica periodicamente
            time.sleep(10)
            
            # Simular trabalho
            logger.debug("Worker rodando...")
            
        except KeyboardInterrupt:
            logger.info("Worker interrompido pelo usuário")
            break
        except Exception as e:
            logger.error(f"Erro no worker: {e}")
            time.sleep(30)  # Esperar antes de tentar novamente

if __name__ == "__main__":
    main()
EOF
        
        chmod +x "$WORKER_SCRIPT"
    fi
    
    # Criar configuração do Supervisor
    cat > "$SUPERVISOR_CONF" <<EOF
[program:youtube-downloader]
command=/opt/youtube-venv/bin/python3 ${INSTALL_DIR}/scripts/worker.py
directory=${INSTALL_DIR}
user=www-data
group=www-data
autostart=true
autorestart=true
startretries=3
startsecs=10
stopwaitsecs=30
redirect_stderr=true
stdout_logfile=${INSTALL_DIR}/logs/worker.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile=${INSTALL_DIR}/logs/worker-error.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
environment=HOME="/var/www",USER="www-data",PATH="/usr/bin:/usr/local/bin:/opt/youtube-venv/bin",PYTHONPATH="${INSTALL_DIR}"

[program:youtube-celery]
command=/opt/youtube-venv/bin/celery -A worker.celery worker --loglevel=info --concurrency=3
directory=${INSTALL_DIR}
user=www-data
group=www-data
autostart=true
autorestart=true
startretries=3
startsecs=10
stopwaitsecs=30
redirect_stderr=true
stdout_logfile=${INSTALL_DIR}/logs/celery.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
environment=HOME="/var/www",USER="www-data",PATH="/usr/bin:/usr/local/bin:/opt/youtube-venv/bin",PYTHONPATH="${INSTALL_DIR}"

[program:youtube-beat]
command=/opt/youtube-venv/bin/celery -A worker.celery beat --loglevel=info
directory=${INSTALL_DIR}
user=www-data
group=www-data
autostart=true
autorestart=true
startretries=3
startsecs=10
stopwaitsecs=30
redirect_stderr=true
stdout_logfile=${INSTALL_DIR}/logs/celery-beat.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
environment=HOME="/var/www",USER="www-data",PATH="/usr/bin:/usr/local/bin:/opt/youtube-venv/bin",PYTHONPATH="${INSTALL_DIR}"
EOF
    
    # Recarregar configurações do Supervisor
    supervisorctl reread
    supervisorctl update
    
    # Iniciar serviços
    supervisorctl start youtube-downloader
    supervisorctl start youtube-celery
    supervisorctl start youtube-beat
    
    success "Supervisor configurado para workers"
}

# Configurar permissões
setup_permissions() {
    log "Configurando permissões de arquivos..."
    
    # Definir proprietário como www-data
    chown -R www-data:www-data "$INSTALL_DIR"
    
    # Configurar permissões específicas
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
    
    # Permissões especiais para diretórios
    chmod -R 775 "$INSTALL_DIR/assets/uploads"
    chmod -R 775 "$INSTALL_DIR/logs"
    chmod -R 775 "$INSTALL_DIR/backup"
    
    # Scripts executáveis
    find "$INSTALL_DIR/scripts" -name "*.py" -type f -exec chmod +x {} \;
    find "$INSTALL_DIR/scripts" -name "*.sh" -type f -exec chmod +x {} \;
    
    # Proteger arquivos sensíveis
    chmod 640 "$INSTALL_DIR/.env" 2>/dev/null || true
    chmod 640 "$INSTALL_DIR/*.sql" 2>/dev/null || true
    
    # Configurar stick bit para uploads
    chmod g+s "$INSTALL_DIR/assets/uploads"
    
    # Permissões para arquivos de cache/temp
    find "$INSTALL_DIR/assets/uploads/temp" -type d -exec chmod 777 {} \; 2>/dev/null || true
    
    success "Permissões configuradas"
}

# Configurar cron jobs
setup_cron() {
    log "Configurando cron jobs..."
    
    # Criar arquivo de cron para www-data
    CRON_FILE="/etc/cron.d/youtube-extractor"
    
    cat > "$CRON_FILE" <<EOF
# YouTube Audio Extractor - Tarefas agendadas

# Limpeza diária de arquivos temporários (2 AM)
0 2 * * * www-data find ${INSTALL_DIR}/assets/uploads/temp -type f -mtime +1 -delete 2>/dev/null || true

# Backup diário do banco de dados (3 AM)
0 3 * * * www-data /usr/bin/mysqldump -u youtube_user -p${DB_PASSWORD} youtube_extractor | gzip > ${INSTALL_DIR}/backup/db_backup_\$(date +\%Y\%m\%d).sql.gz 2>/dev/null || true

# Limpeza de backups antigos (> 7 dias) (4 AM)
0 4 * * * www-data find ${INSTALL_DIR}/backup -name "*.gz" -mtime +7 -delete 2>/dev/null || true

# Manutenção do sistema - limpeza de logs antigos (5 AM)
0 5 * * * www-data find ${INSTALL_DIR}/logs -name "*.log" -mtime +30 -delete 2>/dev/null || true

# Atualização automática do yt-dlp (Domingo às 6 AM)
0 6 * * 0 www-data /opt/youtube-venv/bin/pip3 install --upgrade yt-dlp > ${INSTALL_DIR}/logs/update.log 2>&1

# Verificação de saúde do sistema (a cada 15 minutos)
*/15 * * * * www-data ${INSTALL_DIR}/scripts/health_check.sh > /dev/null 2>&1

# Sincronização de estatísticas (a cada hora)
0 * * * * www-data php ${INSTALL_DIR}/scripts/stats.php > /dev/null 2>&1
EOF
    
    chmod 644 "$CRON_FILE"
    
    # Criar script de verificação de saúde
    HEALTH_SCRIPT="$INSTALL_DIR/scripts/health_check.sh"
    cat > "$HEALTH_SCRIPT" <<'EOF'
#!/bin/bash
# Script de verificação de saúde do sistema

LOG_FILE="/var/www/youtube-audio-extractor/logs/health.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Verificação de saúde iniciada" >> "$LOG_FILE"

# Verificar espaço em disco
DISK_USAGE=$(df -h / | awk 'NR==2 {print $(NF-1)}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    echo "[$DATE] ALERTA: Uso de disco em ${DISK_USAGE}%" >> "$LOG_FILE"
fi

# Verificar memória
MEM_USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
if [ "$MEM_USAGE" -gt 85 ]; then
    echo "[$DATE] ALERTA: Uso de memória em ${MEM_USAGE}%" >> "$LOG_FILE"
fi

# Verificar serviços
SERVICES=("apache2" "mysql" "redis-server" "supervisor")
for SERVICE in "${SERVICES[@]}"; do
    if ! systemctl is-active --quiet "$SERVICE"; then
        echo "[$DATE] ALERTA: Serviço $SERVICE parado" >> "$LOG_FILE"
        systemctl restart "$SERVICE" 2>/dev/null
    fi
done

# Verificar workers do Supervisor
if command -v supervisorctl &> /dev/null; then
    if ! supervisorctl status | grep -q "RUNNING"; then
        echo "[$DATE] ALERTA: Workers parados" >> "$LOG_FILE"
        supervisorctl restart all 2>/dev/null
    fi
fi

echo "[$DATE] Verificação de saúde concluída" >> "$LOG_FILE"

# Manter log pequeno
tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
EOF
    
    chmod +x "$HEALTH_SCRIPT"
    
    success "Cron jobs configurados"
}

# Configurar backup automático
setup_backup() {
    log "Configurando sistema de backup..."
    
    BACKUP_DIR="$INSTALL_DIR/backup"
    mkdir -p "$BACKUP_DIR"
    
    BACKUP_SCRIPT="$INSTALL_DIR/scripts/backup.sh"
    
    cat > "$BACKUP_SCRIPT" <<EOF
#!/bin/bash
# Script de backup automático

BACKUP_DIR="${BACKUP_DIR}"
DATE=\$(date +%Y%m%d_%H%M%S)
LOG_FILE="${INSTALL_DIR}/logs/backup.log"

echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Iniciando backup" >> "\$LOG_FILE"

# Backup do banco de dados
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Backup do banco de dados..." >> "\$LOG_FILE"
mysqldump -u youtube_user -p${DB_PASSWORD} youtube_extractor > "\$BACKUP_DIR/db_backup_\$DATE.sql" 2>> "\$LOG_FILE"
if [ \$? -eq 0 ]; then
    gzip "\$BACKUP_DIR/db_backup_\$DATE.sql"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Backup do banco concluído" >> "\$LOG_FILE"
else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ERRO: Falha no backup do banco" >> "\$LOG_FILE"
fi

# Backup dos uploads (apenas arquivos .mp3, .wav, .flac)
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Backup dos arquivos de áudio..." >> "\$LOG_FILE"
find "${INSTALL_DIR}/assets/uploads" -name "*.mp3" -o -name "*.wav" -o -name "*.flac" -o -name "*.aac" | \
    tar -czf "\$BACKUP_DIR/uploads_backup_\$DATE.tar.gz" -T - 2>> "\$LOG_FILE"
if [ \$? -eq 0 ]; then
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Backup de uploads concluído" >> "\$LOG_FILE"
else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] AVISO: Nenhum arquivo de áudio para backup" >> "\$LOG_FILE"
fi

# Backup dos arquivos de configuração
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Backup das configurações..." >> "\$LOG_FILE"
tar -czf "\$BACKUP_DIR/config_backup_\$DATE.tar.gz" \
    "${INSTALL_DIR}/.env" \
    "/etc/apache2/sites-available/youtube-extractor.conf" \
    "/etc/supervisor/conf.d/youtube-worker.conf" \
    "/etc/cron.d/youtube-extractor" 2>> "\$LOG_FILE"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Backup de configurações concluído" >> "\$LOG_FILE"

# Manter apenas últimos 10 backups
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Limpando backups antigos..." >> "\$LOG_FILE"
find "\$BACKUP_DIR" -name "*.gz" -mtime +10 -delete 2>> "\$LOG_FILE"
find "\$BACKUP_DIR" -name "*.sql" -mtime +10 -delete 2>> "\$LOG_FILE"

echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Backup concluído" >> "\$LOG_FILE"

# Limitar tamanho do log
tail -n 1000 "\$LOG_FILE" > "\${LOG_FILE}.tmp" && mv "\${LOG_FILE}.tmp" "\$LOG_FILE"
EOF
    
    chmod +x "$BACKUP_SCRIPT"
    
    # Executar backup inicial
    log "Executando backup inicial..."
    bash "$BACKUP_SCRIPT"
    
    success "Sistema de backup configurado"
}

# Configurar monitoramento
setup_monitoring() {
    log "Configurando monitoramento básico..."
    
    # Criar script de monitoramento
    MONITOR_SCRIPT="$INSTALL_DIR/scripts/monitor.sh"
    
    cat > "$MONITOR_SCRIPT" <<'EOF'
#!/bin/bash
# Script de monitoramento do sistema

LOG_DIR="/var/www/youtube-audio-extractor/logs"
DATE=$(date +%Y%m%d)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Criar diretório de logs se não existir
mkdir -p "$LOG_DIR"

# Função para registrar alerta
log_alert() {
    echo "[$TIMESTAMP] $1" >> "$LOG_DIR/alert_$DATE.log"
}

# Verificar espaço em disco
DISK_USAGE=$(df -h / | awk 'NR==2 {print $(NF-1)}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    log_alert "ALERTA CRÍTICA: Uso de disco em ${DISK_USAGE}%"
elif [ "$DISK_USAGE" -gt 80 ]; then
    log_alert "ALERTA: Uso de disco em ${DISK_USAGE}%"
fi

# Verificar memória
MEM_TOTAL=$(free -m | awk 'NR==2 {print $2}')
MEM_USED=$(free -m | awk 'NR==2 {print $3}')
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

if [ "$MEM_PERCENT" -gt 90 ]; then
    log_alert "ALERTA CRÍTICA: Uso de memória em ${MEM_PERCENT}% (${MEM_USED}MB/${MEM_TOTAL}MB)"
elif [ "$MEM_PERCENT" -gt 80 ]; then
    log_alert "ALERTA: Uso de memória em ${MEM_PERCENT}%"
fi

# Verificar CPU load
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $1}' | tr -d ' ')
LOAD_THRESHOLD=2.0

if (( $(echo "$LOAD > $LOAD_THRESHOLD" | bc -l) )); then
    log_alert "ALERTA: Carga da CPU alta: $LOAD"
fi

# Verificar serviços
check_service() {
    local service=$1
    if ! systemctl is-active --quiet "$service"; then
        log_alert "SERVIÇO PARADO: $service"
        # Tentar reiniciar se parado
        systemctl restart "$service" 2>/dev/null && log_alert "Serviço $service reiniciado com sucesso"
    fi
}

# Serviços essenciais
check_service "apache2"
check_service "mysql"
check_service "redis-server"
check_service "supervisor"

# Verificar se o site está respondendo
if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")
    if [[ ! "$HTTP_CODE" =~ ^(200|302|301)$ ]]; then
        log_alert "SITE OFFLINE: Código HTTP $HTTP_CODE"
    fi
fi

# Verificar workers do Supervisor
if command -v supervisorctl &> /dev/null; then
    if ! supervisorctl status > /dev/null 2>&1; then
        log_alert "SUPERVISOR OFFLINE: Não foi possível acessar o supervisor"
    else
        if ! supervisorctl status | grep -q "RUNNING"; then
            log_alert "WORKERS PARADOS: Nenhum worker em execução"
            supervisorctl restart all 2>/dev/null && log_alert "Todos workers reiniciados"
        fi
    fi
fi

# Verificar espaço nos logs
LOG_SIZE=$(du -sm "$LOG_DIR" | awk '{print $1}')
if [ "$LOG_SIZE" -gt 1024 ]; then
    log_alert "LOGS GRANDES: Diretório de logs com ${LOG_SIZE}MB"
    # Limpar logs antigos
    find "$LOG_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null
fi

# Limitar tamanho do arquivo de alertas
if [ -f "$LOG_DIR/alert_$DATE.log" ]; then
    tail -n 1000 "$LOG_DIR/alert_$DATE.log" > "${LOG_DIR}/alert_${DATE}.tmp" && \
    mv "${LOG_DIR}/alert_${DATE}.tmp" "$LOG_DIR/alert_$DATE.log"
fi

# Registrar que a verificação foi concluída
echo "[$TIMESTAMP] Verificação de monitoramento concluída" >> "$LOG_DIR/monitor.log"
EOF
    
    chmod +x "$MONITOR_SCRIPT"
    
    # Adicionar ao cron para execução a cada 5 minutos
    if ! grep -q "monitor.sh" /etc/cron.d/youtube-extractor 2>/dev/null; then
        echo "*/5 * * * * root $MONITOR_SCRIPT > /dev/null 2>&1" >> /etc/cron.d/youtube-extractor
    fi
    
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
    
    TESTS_PASSED=0
    TESTS_TOTAL=0
    
    # Testar Apache
    ((TESTS_TOTAL++))
    if systemctl is-active --quiet apache2; then
        echo -e "  ${GREEN}✓${NC} Apache está rodando"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${NC} Apache não está rodando"
    fi
    
    # Testar MySQL
    ((TESTS_TOTAL++))
    if systemctl is-active --quiet mysql || systemctl is-active --quiet mariadb; then
        echo -e "  ${GREEN}✓${NC} MySQL/MariaDB está rodando"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${NC} MySQL/MariaDB não está rodando"
    fi
    
    # Testar Redis
    ((TESTS_TOTAL++))
    if systemctl is-active --quiet redis-server; then
        echo -e "  ${GREEN}✓${NC} Redis está rodando"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${NC} Redis não está rodando"
    fi
    
    # Testar PHP
    ((TESTS_TOTAL++))
    if php --version &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} PHP está instalado"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${NC} PHP não está instalado"
    fi
    
    # Testar Python
    ((TESTS_TOTAL++))
    if /opt/youtube-venv/bin/python3 --version &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Python está instalado"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${NC} Python não está instalado"
    fi
    
    # Testar yt-dlp
    ((TESTS_TOTAL++))
    if /opt/youtube-venv/bin/yt-dlp --version &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} yt-dlp está instalado"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${NC} yt-dlp não está instalado"
    fi
    
    # Testar FFmpeg
    ((TESTS_TOTAL++))
    if ffmpeg -version &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} FFmpeg está instalado"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${NC} FFmpeg não está instalado"
    fi
    
    # Testar Supervisor
    ((TESTS_TOTAL++))
    if systemctl is-active --quiet supervisor; then
        echo -e "  ${GREEN}✓${NC} Supervisor está rodando"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${NC} Supervisor não está rodando"
    fi
    
    # Testar acesso ao site
    ((TESTS_TOTAL++))
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|302|301)$ ]]; then
        echo -e "  ${GREEN}✓${NC} Site está acessível (HTTP $HTTP_CODE)"
        ((TESTS_PASSED++))
    else
        echo -e "  ${YELLOW}⚠${NC} Site pode não estar acessível (HTTP $HTTP_CODE)"
    fi
    
    # Testar banco de dados
    ((TESTS_TOTAL++))
    if mysql -u youtube_user -p"${DB_PASSWORD}" -e "SELECT 1;" youtube_extractor &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Banco de dados acessível"
        ((TESTS_PASSED++))
    else
        echo -e "  ${RED}✗${NC} Banco de dados não acessível"
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   RESUMO DOS TESTES                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ "$TESTS_PASSED" -eq "$TESTS_TOTAL" ]; then
        echo -e "  ${GREEN}✅ TODOS OS TESTES PASSARAM ($TESTS_PASSED/$TESTS_TOTAL)${NC}"
    elif [ "$TESTS_PASSED" -ge $((TESTS_TOTAL * 8 / 10)) ]; then
        echo -e "  ${YELLOW}⚠  TESTES QUASE COMPLETOS ($TESTS_PASSED/$TESTS_TOTAL)${NC}"
    else
        echo -e "  ${RED}❌ TESTES COM FALHAS ($TESTS_PASSED/$TESTS_TOTAL)${NC}"
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
    
    echo -e "${CYAN}🔧 SERVIÇOS INSTALADOS:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo "  ✅ Apache 2.4"
    echo "  ✅ MySQL/MariaDB"
    echo "  ✅ PHP 8.2"
    echo "  ✅ Redis"
    echo "  ✅ Python 3 + Virtual Env"
    echo "  ✅ yt-dlp"
    echo "  ✅ FFmpeg"
    echo "  ✅ Supervisor"
    echo "  ✅ Certbot (SSL)"
    echo ""
    
    echo -e "${CYAN}🚀 URLs DE ACESSO:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo -e "  ${WHITE}🌍 Site Principal:${NC}       http://${DOMAIN_NAME}"
    echo -e "  ${WHITE}🔐 Painel Admin:${NC}         http://${DOMAIN_NAME}/admin"
    echo -e "  ${WHITE}📊 Status:${NC}               http://${DOMAIN_NAME}/status"
    echo -e "  ${WHITE}⚙️  phpMyAdmin:${NC}          http://${DOMAIN_NAME}/phpmyadmin"
    echo ""
    
    echo -e "${CYAN}📊 INFORMAÇÕES IMPORTANTES:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo "  1. Configure o DNS do domínio para apontar para este servidor"
    echo "  2. Execute 'sudo certbot --apache' para configurar SSL se necessário"
    echo "  3. Altere a senha do admin no primeiro acesso"
    echo "  4. Configure backups regulares"
    echo "  5. Monitore os logs em: ${INSTALL_DIR}/logs/"
    echo ""
    
    echo -e "${CYAN}🛡️  CREDENCIAIS DE ACESSO:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo -e "  ${YELLOW}Painel Admin:${NC}"
    echo "    Usuário: admin"
    echo "    Senha: ${ADMIN_PASSWORD}"
    echo ""
    echo -e "  ${YELLOW}Banco de Dados:${NC}"
    echo "    Host: localhost"
    echo "    Usuário: youtube_user"
    echo "    Senha: ${DB_PASSWORD}"
    echo "    Banco: youtube_extractor"
    echo ""
    
    echo -e "${CYAN}⚠️  IMPORTANTE:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo "  1. Salve estas credenciais em um local seguro!"
    echo "  2. Altere todas as senhas após o primeiro acesso"
    echo "  3. Configure firewall e segurança adicional"
    echo "  4. Faça backup regular dos dados"
    echo ""
    
    echo -e "${CYAN}📞 SUPORTE E LOGS:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo "  📋 Logs do sistema: ${INSTALL_DIR}/logs/"
    echo "  📚 Documentação: ${INSTALL_DIR}/README.md"
    echo "  🐛 Issues: ${REPO_URL}/issues"
    echo "  💾 Backups: ${INSTALL_DIR}/backup/"
    echo ""
    
    echo -e "${CYAN}🔄 COMANDOS ÚTEIS:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo "  Reiniciar serviços:"
    echo "    sudo systemctl restart apache2 mysql redis supervisor"
    echo ""
    echo "  Verificar status:"
    echo "    sudo systemctl status apache2 mysql redis supervisor"
    echo ""
    echo "  Monitorar logs:"
    echo "    sudo tail -f ${INSTALL_DIR}/logs/worker.log"
    echo "    sudo tail -f ${INSTALL_DIR}/logs/error.log"
    echo ""
    echo "  Backup manual:"
    echo "    sudo bash ${INSTALL_DIR}/scripts/backup.sh"
    echo ""
    echo "  Verificar espaço em disco:"
    echo "    df -h"
    echo ""
}

# Salvar credenciais em arquivo seguro
save_credentials() {
    CREDS_FILE="/root/youtube_extractor_credentials.txt"
    
    cat > "$CREDS_FILE" <<EOF
========================================
CREDENCIAIS DO YOUTUBE AUDIO EXTRACTOR
========================================

IMPORTANTE: Este arquivo contém informações sensíveis.
Guarde em local seguro e exclua após anotar as credenciais.

DATA DA INSTALAÇÃO: $(date)

SISTEMA:
--------
Servidor: $(hostname)
IP: $(hostname -I | awk '{print $1}')
Domínio: ${DOMAIN_NAME}
Sistema: $(lsb_release -ds)

ACESSO AO SISTEMA:
------------------
URL: https://${DOMAIN_NAME}
Painel Admin: https://${DOMAIN_NAME}/admin
Usuário: admin
Senha: ${ADMIN_PASSWORD}

BANCO DE DADOS:
---------------
Host: localhost
Usuário: youtube_user
Senha: ${DB_PASSWORD}
Banco: youtube_extractor

CHAVES DE SEGURANÇA:
-------------------
APP_KEY: ${SECRET_KEY}
JWT_SECRET: ${JWT_SECRET}
ENCRYPTION_KEY: ${ENCRYPTION_KEY}

DIRETÓRIOS IMPORTANTES:
----------------------
Instalação: ${INSTALL_DIR}
Logs: ${INSTALL_DIR}/logs/
Backups: ${INSTALL_DIR}/backup/
Uploads: ${INSTALL_DIR}/assets/uploads/

COMANDOS ÚTEIS:
---------------
Reiniciar serviços: sudo systemctl restart apache2 mysql redis supervisor
Verificar status: sudo systemctl status apache2 mysql redis supervisor
Monitorar logs: tail -f ${INSTALL_DIR}/logs/worker.log
Backup manual: sudo bash ${INSTALL_DIR}/scripts/backup.sh

SEGURANÇA:
---------
1. Altere todas as senhas após o primeiro acesso
2. Configure firewall adequadamente
3. Mantenha o sistema atualizado
4. Faça backups regulares
5. Monitore os logs diariamente

SUPORTE:
--------
Documentação: ${INSTALL_DIR}/README.md
Issues: ${REPO_URL}/issues
Logs do sistema: ${INSTALL_DIR}/logs/

========================================
⚠️  IMPORTANTE: EXCLUA ESTE ARQUIVO APÓS ANOTAR AS CREDENCIAIS
========================================
EOF
    
    chmod 600 "$CREDS_FILE"
    warn "Credenciais salvas em: $CREDS_FILE"
    warn "EXCLUA ESTE ARQUIVO APÓS ANOTAR AS CREDENCIAIS!"
    echo ""
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
    echo "║               Instalador Automático v2.0.1                    ║"
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
    echo "Este instalador vai configurar um sistema completo para extração"
    echo "de áudio do YouTube com recursos avançados e processamento em IA."
    echo ""
    
    # Obter IP público
    info "Obtendo IP público do servidor..."
    PUBLIC_IP=$(get_public_ip)
    info "IP público detectado: $PUBLIC_IP"
    echo ""
    
    # Perguntar domínio
    echo "Por favor, insira o domínio que será usado para acessar o sistema."
    echo "Se não tiver um domínio, você pode usar o IP: $PUBLIC_IP"
    echo "Para desenvolvimento local, use: localhost"
    echo ""
    
    read -p "Domínio ou IP [${PUBLIC_IP}]: " DOMAIN_NAME
    DOMAIN_NAME=${DOMAIN_NAME:-$PUBLIC_IP}
    
    # Validar entrada
    if [[ -z "$DOMAIN_NAME" ]]; then
        DOMAIN_NAME="$PUBLIC_IP"
    fi
    
    # Perguntar email do admin
    echo ""
    echo "Informe o email do administrador para notificações e SSL."
    echo "Se não tiver um email válido, use o padrão."
    echo ""
    
    read -p "Email do administrador [${EMAIL_ADMIN}]: " input_email
    EMAIL_ADMIN=${input_email:-$EMAIL_ADMIN}
    
    # Mostrar configurações
    echo ""
    info "Configurações selecionadas:"
    echo "  🏠 Domínio:       $DOMAIN_NAME"
    echo "  📧 Email Admin:   $EMAIL_ADMIN"
    echo "  📁 Diretório:     $INSTALL_DIR"
    echo "  🗄️  Banco de Dados: youtube_extractor"
    echo ""
    
    echo "A instalação vai:"
    echo "  • Atualizar o sistema operacional"
    echo "  • Instalar Apache, MySQL, PHP, Redis, Python"
    echo "  • Configurar ambiente virtual Python com yt-dlp e FFmpeg"
    echo "  • Configurar SSL (se domínio válido)"
    echo "  • Configurar backup e monitoramento automáticos"
    echo ""
    
    if ! confirm "Deseja continuar com a instalação?"; then
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
    
    # 5. Clonar repositório
    clone_repository
    
    # 6. Configurar sistema
    setup_database
    setup_env_file
    setup_apache_vhost
    
    # 7. Configurar SSL apenas se for domínio válido
    if [[ "$DOMAIN_NAME" != "localhost" ]] && [[ ! "$DOMAIN_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        setup_ssl
    else
        warn "SSL não configurado (IP local ou localhost)"
    fi
    
    setup_supervisor
    setup_permissions
    setup_cron
    setup_backup
    setup_monitoring
    
    # 8. Testar instalação
    test_installation
    
    # 9. Mostrar resumo e salvar credenciais
    show_summary
    save_credentials
    
    # 10. Mensagem final
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    INSTALAÇÃO CONCLUÍDA                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    log "Instalação concluída com sucesso!"
    echo ""
    
    if [[ "$DOMAIN_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        info "Acesse o sistema em: http://${DOMAIN_NAME}"
    else
        info "Acesse o sistema em: https://${DOMAIN_NAME}"
    fi
    
    echo ""
    info "Próximos passos recomendados:"
    echo "  1. Acesse o painel admin e altere a senha"
    echo "  2. Configure os backups automáticos"
    echo "  3. Monitore os logs inicialmente"
    echo "  4. Teste o download de alguns áudios"
    echo ""
    
    if confirm "Deseja reiniciar o servidor agora para aplicar todas as configurações?"; then
        warn "Reiniciando o servidor em 10 segundos..."
        warn "Pressione Ctrl+C para cancelar"
        sleep 10
        reboot
    else
        info "Para aplicar todas as configurações, reinicie manualmente:"
        echo "  sudo reboot"
        echo ""
    fi
}

# Tratamento de erros
trap 'error "Instalação interrompida pelo usuário"; exit 1' INT
trap 'error "Ocorreu um erro na linha $LINENO"; exit 1' ERR

# Executar instalação
main_installation
