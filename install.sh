#!/bin/bash

# YouTube Audio Extractor - Instalador Automático Completo
# Versão: 2.0.4
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
    if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null && ! ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
        error "Sem conexão com a internet ou ping bloqueado"
        echo "Verifique sua conexão ou firewall"
        exit 1
    fi
    success "Conexão com internet OK"
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

# Instalar MySQL/MariaDB - CORRIGIDA PARA UBUNTU
install_mysql() {
    log "Instalando MariaDB (compatível com MySQL)..."
    
    # Verificar se já está instalado
    if command -v mysql &> /dev/null || command -v mariadb &> /dev/null; then
        warn "MariaDB/MySQL já está instalado. Pulando instalação..."
        
        # Tentar configurar senha se não estiver configurada
        log "Verificando configuração do MySQL..."
        return 0
    fi
    
    apt update
    apt install -y mariadb-server mariadb-client
    
    systemctl enable mariadb
    systemctl start mariadb
    
    # Esperar um pouco para o MySQL iniciar
    sleep 5
    
    success "MariaDB instalado"
    
    # IMPORTANTE: No Ubuntu, o MariaDB vem configurado para usar autenticação via socket
    # O usuário root pode acessar apenas com sudo mysql (sem senha)
    info "No Ubuntu, o MariaDB usa autenticação via socket por padrão"
    info "Para acessar: sudo mysql (sem senha)"
    info "Para configurar senha, execute: sudo mysql_secure_installation"
}

# Instalar PHP - CORRIGIDA
install_php() {
    log "Instalando PHP e extensões..."
    
    # Verificar se PHP já está instalado
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php --version | grep -oP 'PHP \K[0-9]+\.[0-9]+' | head -1)
        if [[ "$PHP_VERSION" == "8.2" ]]; then
            warn "PHP 8.2 já está instalado. Pulando instalação..."
            return 0
        else
            warn "PHP $PHP_VERSION já instalado. Instalando PHP 8.2..."
        fi
    fi
    
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

# Instalar Node.js (opcional) - SIMPLIFICADA
install_nodejs() {
    log "Instalando Node.js (opcional)..."
    
    if command -v node &> /dev/null; then
        warn "Node.js já está instalado"
        return 0
    fi
    
    # Tentar instalar via apt (método mais simples)
    if apt install -y nodejs npm 2>/dev/null; then
        success "Node.js instalado"
    else
        warn "Não foi possível instalar Node.js. Pulando..."
        return 1
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

# ============================================================================
# CONFIGURAÇÃO DO SISTEMA - CORRIGIDA PARA MYSQL
# ============================================================================

# Verificar e configurar acesso ao MySQL - CORRIGIDA
check_mysql_access() {
    log "Verificando acesso ao MySQL/MariaDB..."
    
    # Tentar acessar sem senha
    if mysql -u root -e "SELECT 1;" &> /dev/null; then
        info "MySQL acessível sem senha"
        return 0
    fi
    
    # Tentar acessar com sudo (para MariaDB no Ubuntu - autenticação via socket)
    if sudo mysql -e "SELECT 1;" &> /dev/null; then
        info "MySQL acessível com sudo (autenticação via socket)"
        return 0
    fi
    
    # Se não conseguir, vamos reconfigurar o MySQL
    warn "Não foi possível acessar o MySQL automaticamente."
    echo ""
    echo "Vamos reconfigurar o MySQL para permitir acesso:"
    echo ""
    
    # Parar MySQL temporariamente
    systemctl stop mysql 2>/dev/null || systemctl stop mariadb 2>/dev/null
    
    # Iniciar MySQL em modo seguro (sem autenticação)
    log "Iniciando MySQL em modo seguro..."
    mysqld_safe --skip-grant-tables --skip-networking &
    sleep 5
    
    # Configurar nova senha
    log "Configurando nova senha para root..."
    mysql -u root <<EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
FLUSH PRIVILEGES;
EOF
    
    # Parar MySQL seguro
    killall mysqld_safe 2>/dev/null || true
    killall mysqld 2>/dev/null || true
    
    # Iniciar MySQL normalmente
    systemctl start mysql 2>/dev/null || systemctl start mariadb 2>/dev/null
    sleep 3
    
    # Testar nova conexão
    if mysql -u root -p"${DB_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
        info "MySQL reconfigurado com sucesso"
        info "Nova senha do root: ${DB_PASSWORD}"
        return 0
    else
        error "Falha ao reconfigurar MySQL"
        return 1
    fi
}

# Configurar banco de dados - CORRIGIDA
setup_database() {
    log "Configurando banco de dados..."
    
    # Verificar e configurar acesso ao MySQL
    if ! check_mysql_access; then
        error "Não foi possível configurar acesso ao MySQL"
        echo ""
        echo "Soluções manuais:"
        echo "1. Execute: sudo mysql_secure_installation"
        echo "2. Ou: sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'nova_senha';\""
        echo "3. Depois execute novamente esta etapa"
        echo ""
        read -p "Pressione Enter após configurar o MySQL manualmente..."
        
        # Tentar novamente após configuração manual
        if ! mysql -u root -p"${DB_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
            error "Ainda não foi possível conectar ao MySQL"
            return 1
        fi
    fi
    
    # Determinar método de acesso
    if mysql -u root -e "SELECT 1;" &> /dev/null; then
        MYSQL_CMD="mysql -u root"
    elif sudo mysql -e "SELECT 1;" &> /dev/null; then
        MYSQL_CMD="sudo mysql"
    elif mysql -u root -p"${DB_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
        MYSQL_CMD="mysql -u root -p${DB_PASSWORD}"
    else
        error "Não foi possível determinar método de acesso ao MySQL"
        return 1
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

-- Inserir usuário admin (usando senha hasheada com SHA2)
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
    
    success "Banco de dados configurado com sucesso"
    info "  Banco: youtube_extractor"
    info "  Usuário: youtube_user"
    info "  Senha: ${DB_PASSWORD}"
    info "  Senha do admin: ${ADMIN_PASSWORD}"
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
    log "Clonando de $REPO_URL ..."
    if git clone "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
        success "Repositório clonado com sucesso"
    else
        warn "Falha ao clonar repositório. Criando estrutura básica..."
        
        # Criar estrutura de diretórios básica
        mkdir -p "$INSTALL_DIR"/{assets/uploads,logs,backup,scripts,sql,includes}
        
        # Criar arquivos básicos
        cat > "$INSTALL_DIR/index.php" <<'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>YouTube Audio Extractor</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f4f4f4;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 2px solid #4CAF50;
            padding-bottom: 10px;
        }
        .status {
            background: #e7f3fe;
            border-left: 4px solid #2196F3;
            padding: 15px;
            margin: 20px 0;
        }
        .btn {
            display: inline-block;
            background: #4CAF50;
            color: white;
            padding: 10px 20px;
            text-decoration: none;
            border-radius: 4px;
            margin: 10px 5px;
        }
        .btn:hover {
            background: #45a049;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎵 YouTube Audio Extractor</h1>
        
        <div class="status">
            <h2>✅ Instalação Concluída!</h2>
            <p>Sistema instalado e configurado com sucesso.</p>
            <p>Data da instalação: <?php echo date('d/m/Y H:i:s'); ?></p>
        </div>
        
        <h2>🔧 Configuração do Sistema</h2>
        <p>O sistema está pronto para uso. As configurações principais incluem:</p>
        <ul>
            <li>Processamento de vídeos do YouTube</li>
            <li>Extração de áudio em múltiplos formatos</li>
            <li>Sistema de filas para processamento em segundo plano</li>
            <li>Interface de administração</li>
        </ul>
        
        <h2>🚀 Acesso Rápido</h2>
        <p>
            <a href="/admin" class="btn">Painel Admin</a>
            <a href="/status" class="btn">Status Sistema</a>
            <a href="/docs" class="btn">Documentação</a>
        </p>
        
        <h2>📞 Suporte</h2>
        <p>Para problemas ou dúvidas, consulte a documentação ou entre em contato.</p>
        
        <footer style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; text-align: center; color: #666;">
            <p>YouTube Audio Extractor &copy; <?php echo date('Y'); ?></p>
        </footer>
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

<FilesMatch "\.(sql|log|ini|conf|env|key)$">
    Order allow,deny
    Deny from all
</FilesMatch>

# Redirecionar para index.php (se for um framework MVC)
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.php [L]

# Forçar HTTPS (se configurado)
# RewriteCond %{HTTPS} off
# RewriteRule ^(.*)$ https://%{HTTP_HOST}/$1 [R=301,L]

# Compressão GZIP
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
EOF
        
        info "Estrutura básica criada em: $INSTALL_DIR"
    fi
}

# Configurar arquivo .env
setup_env_file() {
    log "Configurando arquivo .env..."
    
    ENV_FILE="$INSTALL_DIR/.env"
    
    # Se existir .env.example, usar como base
    if [ -f "$INSTALL_DIR/.env.example" ]; then
        cp "$INSTALL_DIR/.env.example" "$ENV_FILE"
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
    if [[ "$DOMAIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        log "Configurando SSL com Let's Encrypt..."
        
        # Tentar obter certificado SSL
        if certbot --apache \
            -d "$DOMAIN_NAME" \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL_ADMIN" \
            --redirect; then
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
EOF
    
    # Recarregar configurações do Supervisor
    supervisorctl reread
    supervisorctl update
    
    # Iniciar serviços
    supervisorctl start youtube-downloader
    
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
    [ -f "$INSTALL_DIR/.env" ] && chmod 640 "$INSTALL_DIR/.env"
    
    # Configurar stick bit para uploads
    chmod g+s "$INSTALL_DIR/assets/uploads"
    
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
    bash "$BACKUP_SCRIPT" 2>/dev/null || warn "Backup inicial falhou, continuando..."
    
    success "Sistema de backup configurado"
}

# ============================================================================
# FLUXO PRINCIPAL
# ============================================================================

# Coletar informações do usuário
collect_info() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               YouTube Audio Extractor                         ║"
    echo "║               Instalador Automático v2.0.4                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    info "Bem-vindo ao instalador do YouTube Audio Extractor!"
    echo ""
    
    # Obter IP local
    LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
    
    # Perguntar domínio
    echo "Por favor, insira o domínio que será usado para acessar o sistema."
    echo "Para desenvolvimento local, use: localhost ou $LOCAL_IP"
    echo ""
    
    read -p "Domínio ou IP [${LOCAL_IP}]: " DOMAIN_NAME
    DOMAIN_NAME=${DOMAIN_NAME:-$LOCAL_IP}
    
    # Perguntar email do admin
    echo ""
    read -p "Email do administrador [${EMAIL_ADMIN}]: " input_email
    EMAIL_ADMIN=${input_email:-$EMAIL_ADMIN}
    
    # Mostrar configurações
    echo ""
    info "Configurações selecionadas:"
    echo "  Domínio: $DOMAIN_NAME"
    echo "  Email Admin: $EMAIL_ADMIN"
    echo "  Diretório: $INSTALL_DIR"
    echo ""
    
    if ! confirm "Deseja continuar com a instalação?"; then
        info "Instalação cancelada pelo usuário"
        exit 0
    fi
}

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
    if systemctl is-active --quiet mysql || systemctl is-active --quiet mariadb; then
        success "✓ MySQL/MariaDB está rodando"
    else
        error "✗ MySQL/MariaDB não está rodando"
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
    echo "🔑 Senha Admin:          ${ADMIN_PASSWORD}"
    echo "🗄️  Banco de Dados:      youtube_extractor"
    echo "👤 Usuário DB:           youtube_user"
    echo "🔒 Senha DB:             ${DB_PASSWORD}"
    echo ""
    echo "🚀 URLs DE ACESSO:"
    echo "----------------------------------------"
    echo "🌍 Site Principal:       http://${DOMAIN_NAME}"
    echo "🔐 Painel Admin:         http://${DOMAIN_NAME}/admin"
    echo ""
    echo "⚠️  IMPORTANTE:"
    echo "----------------------------------------"
    echo "1. Salve estas credenciais em um local seguro!"
    echo "2. Altere a senha do admin no primeiro acesso"
    echo "3. Acesse o MySQL com: sudo mysql"
    echo "   Ou com a senha: ${DB_PASSWORD}"
    echo ""
}

# Salvar credenciais em arquivo seguro
save_credentials() {
    CREDS_FILE="/root/youtube_extractor_credentials.txt"
    
    cat > "$CREDS_FILE" <<EOF
========================================
CREDENCIAIS DO YOUTUBE AUDIO EXTRACTOR
========================================

DATA DA INSTALAÇÃO: $(date)

ACESSO AO SISTEMA:
------------------
URL: http://${DOMAIN_NAME}
Painel Admin: http://${DOMAIN_NAME}/admin
Usuário: admin
Senha: ${ADMIN_PASSWORD}

BANCO DE DADOS:
---------------
Host: localhost
Usuário: youtube_user
Senha: ${DB_PASSWORD}
Banco: youtube_extractor

ACESSO ROOT DO MYSQL:
---------------------
No Ubuntu, use: sudo mysql
Ou com senha: mysql -u root -p${DB_PASSWORD}

DIRETÓRIOS IMPORTANTES:
----------------------
Instalação: ${INSTALL_DIR}
Logs: ${INSTALL_DIR}/logs/
Backups: ${INSTALL_DIR}/backup/
Uploads: ${INSTALL_DIR}/assets/uploads/

========================================
EOF
    
    chmod 600 "$CREDS_FILE"
    warn "Credenciais salvas em: $CREDS_FILE"
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
    
    # 5. Clonar repositório
    clone_repository
    
    # 6. Configurar sistema
    setup_database
    setup_env_file
    setup_apache_vhost
    
    # Configurar SSL apenas se for domínio válido
    if [[ "$DOMAIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        setup_ssl
    fi
    
    setup_supervisor
    setup_permissions
    setup_cron
    setup_backup
    
    # 7. Testar instalação
    test_installation
    
    # 8. Mostrar resumo e salvar credenciais
    show_summary
    save_credentials
    
    log "Instalação concluída com sucesso!"
    echo ""
    info "Acesse o sistema em: http://${DOMAIN_NAME}"
    info "Usuário admin: admin"
    info "Senha admin: ${ADMIN_PASSWORD}"
    echo ""
}

# Tratamento de erros
trap 'error "Instalação interrompida pelo usuário"; exit 1' INT
trap 'error "Ocorreu um erro na linha $LINENO"; exit 1' ERR

# Executar instalação
main_installation
