#!/bin/bash

# YouTube Audio Extractor - Instalador Automático Completo
# Versão: 2.0.6
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
DOMAIN_NAME="audioextractor.giize.com"
EMAIL_ADMIN="mpnascimento031@gmail.com"

# Credenciais do banco de dados (do seu arquivo config.php/.env)
DB_DATABASE="audioextractor"
DB_USERNAME="audioextrac_usr"
DB_PASSWORD="3GqG!%Yg7i;YsI4Y"
DB_ROOT_PASSWORD=""  # Será detectada ou configurada

# Gerar outras senhas
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

# Função para perguntar confirmação
confirm() {
    read -p "$1 (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        return 1
    fi
    return 0
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

# Detectar e configurar acesso ao MySQL
detect_mysql_access() {
    log "Detectando configuração do MySQL..."
    
    # Tentar diferentes métodos de acesso
    if mysql -u root -p"${DB_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
        info "✓ MySQL acessível com a senha do usuário do sistema"
        DB_ROOT_PASSWORD="${DB_PASSWORD}"
        return 0
    elif mysql -u root -e "SELECT 1;" &> /dev/null; then
        info "✓ MySQL acessível sem senha"
        DB_ROOT_PASSWORD=""
        return 0
    elif sudo mysql -e "SELECT 1;" &> /dev/null; then
        info "✓ MySQL acessível via socket (sudo mysql)"
        DB_ROOT_PASSWORD=""
        return 0
    else
        warn "Não foi possível detectar acesso ao MySQL"
        return 1
    fi
}

# Instalar MySQL/MariaDB
install_mysql() {
    log "Verificando MySQL/MariaDB..."
    
    # Verificar se já está instalado
    if command -v mysql &> /dev/null || command -v mariadb &> /dev/null; then
        info "MySQL/MariaDB já está instalado"
        
        # Tentar detectar acesso
        if detect_mysql_access; then
            success "Acesso ao MySQL detectado"
            return 0
        else
            warn "Não foi possível acessar o MySQL automaticamente"
            echo ""
            echo "📋 OPÇÕES PARA CONFIGURAR ACESSO:"
            echo "1. Se você sabe a senha do root do MySQL"
            echo "2. Se não tem senha (acesso direto)"
            echo "3. Se usa autenticação via socket (Ubuntu)"
            echo ""
            echo "Para resolver, tente um destes comandos:"
            echo "a) Para configurar senha: sudo mysql_secure_installation"
            echo "b) Para acessar sem senha (Ubuntu): sudo mysql"
            echo "c) Para redefinir senha:"
            echo "   sudo systemctl stop mysql"
            echo "   sudo mysqld_safe --skip-grant-tables &"
            echo "   mysql -u root"
            echo "   FLUSH PRIVILEGES;"
            echo "   ALTER USER 'root'@'localhost' IDENTIFIED BY 'nova_senha';"
            echo ""
            
            read -p "Pressione Enter após configurar o acesso ao MySQL..."
            
            # Tentar novamente
            if detect_mysql_access; then
                success "Acesso ao MySQL configurado"
                return 0
            else
                error "Ainda não foi possível acessar o MySQL"
                return 1
            fi
        fi
    else
        log "Instalando MariaDB..."
        apt update
        apt install -y mariadb-server mariadb-client
        
        systemctl enable mariadb
        systemctl start mariadb
        
        # Esperar iniciar
        sleep 5
        
        # Configurar senha do root
        log "Configurando senha do root do MariaDB..."
        sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
        
        DB_ROOT_PASSWORD="${DB_PASSWORD}"
        success "MariaDB instalado e configurado"
        return 0
    fi
}

# Instalar PHP
install_php() {
    log "Instalando PHP e extensões..."
    
    # Verificar se PHP já está instalado
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php --version | grep -oP 'PHP \K[0-9]+\.[0-9]+' | head -1)
        info "PHP $PHP_VERSION já instalado"
        return 0
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
        flask
    
    deactivate
    success "Python e dependências instaladas"
}

# Instalar Node.js (opcional)
install_nodejs() {
    log "Instalando Node.js (opcional)..."
    
    if command -v node &> /dev/null; then
        info "Node.js já está instalado"
        return 0
    fi
    
    # Instalar de forma simples
    if apt install -y nodejs npm 2>/dev/null; then
        success "Node.js instalado"
        return 0
    fi
    
    warn "Não foi possível instalar Node.js. Pulando..."
    return 1
}

# Instalar Supervisor
install_supervisor() {
    log "Instalando Supervisor..."
    
    if systemctl is-active --quiet supervisor; then
        info "Supervisor já está instalado"
        return 0
    fi
    
    apt install -y supervisor
    
    systemctl enable supervisor
    systemctl start supervisor
    success "Supervisor instalado"
}

# Instalar Certbot (SSL)
install_certbot() {
    log "Instalando Certbot para SSL..."
    
    if command -v certbot &> /dev/null; then
        info "Certbot já está instalado"
        return 0
    fi
    
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
    echo "y" | ufw enable 2>/dev/null || true
    
    success "Firewall configurado"
}

# ============================================================================
# CONFIGURAÇÃO DO SISTEMA - CORRIGIDAS
# ============================================================================

# Obter comando MySQL baseado no método de acesso detectado
get_mysql_command() {
    if [ -n "$DB_ROOT_PASSWORD" ]; then
        echo "mysql -u root -p${DB_ROOT_PASSWORD}"
    else
        # Tentar sem senha primeiro
        if mysql -u root -e "SELECT 1;" &> /dev/null; then
            echo "mysql -u root"
        elif sudo mysql -e "SELECT 1;" &> /dev/null; then
            echo "sudo mysql"
        else
            echo ""
        fi
    fi
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
            warn "Usando diretório existente."
        fi
    fi
    
    # Criar diretório se não existir
    mkdir -p "$INSTALL_DIR"
    
    # Tentar clonar o repositório
    if git clone "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
        success "Repositório clonado com sucesso"
    else
        warn "Falha ao clonar repositório. Verificando arquivos existentes..."
        
        # Verificar se já existe conteúdo
        if [ "$(ls -A $INSTALL_DIR 2>/dev/null)" ]; then
            info "Usando arquivos existentes em $INSTALL_DIR"
        else
            error "Diretório vazio e não foi possível clonar repositório"
            return 1
        fi
    fi
    
    # Verificar se existe config.php ou .env
    if [ -f "$INSTALL_DIR/config.php" ]; then
        info "Encontrado config.php com configurações do sistema"
        # Extrair credenciais do config.php se necessário
    elif [ -f "$INSTALL_DIR/.env" ]; then
        info "Encontrado .env com configurações do sistema"
    else
        warn "Arquivos de configuração não encontrados. Serão criados padrões."
    fi
}

# Configurar banco de dados - USANDO SUAS CREDENCIAIS
setup_database() {
    log "Configurando banco de dados..."
    
    # Obter comando MySQL
    MYSQL_CMD=$(get_mysql_command)
    
    if [ -z "$MYSQL_CMD" ]; then
        error "Não foi possível obter comando de acesso ao MySQL"
        warn "Pulando configuração do banco de dados"
        return 1
    fi
    
    info "Usando comando: $MYSQL_CMD"
    
    # Testar conexão
    if ! $MYSQL_CMD -e "SELECT 1;" &> /dev/null; then
        error "Não foi possível conectar ao MySQL com o comando fornecido"
        return 1
    fi
    
    # Criar banco de dados se não existir
    log "Criando/verificando banco de dados: $DB_DATABASE"
    $MYSQL_CMD <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_DATABASE}\` 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;
EOF
    
    # Criar usuário se não existir
    log "Criando/verificando usuário: $DB_USERNAME"
    $MYSQL_CMD <<EOF
CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'localhost' 
IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* 
TO '${DB_USERNAME}'@'localhost';

FLUSH PRIVILEGES;
EOF
    
    # Importar estrutura SQL se existir
    SQL_FILES=(
        "$INSTALL_DIR/database.sql"
        "$INSTALL_DIR/sql/database.sql"
        "$INSTALL_DIR/sql/schema.sql"
        "$INSTALL_DIR/sql/structure.sql"
    )
    
    for SQL_FILE in "${SQL_FILES[@]}"; do
        if [ -f "$SQL_FILE" ]; then
            log "Importando estrutura do banco de: $SQL_FILE"
            $MYSQL_CMD "$DB_DATABASE" < "$SQL_FILE"
            break
        fi
    done
    
    success "Banco de dados configurado com sucesso"
    info "  Banco: $DB_DATABASE"
    info "  Usuário: $DB_USERNAME"
    info "  Senha: [já configurada no sistema]"
}

# Configurar arquivo .env - USANDO SUAS CREDENCIAIS
setup_env_file() {
    log "Configurando arquivos de configuração..."
    
    # Primeiro, verificar arquivos existentes
    if [ -f "$INSTALL_DIR/config.php" ]; then
        info "Arquivo config.php encontrado. Verificando configurações..."
        
        # Verificar se as credenciais estão corretas no config.php
        if grep -q "DB_DATABASE.*$DB_DATABASE" "$INSTALL_DIR/config.php" || \
           grep -q "'database'.*'$DB_DATABASE'" "$INSTALL_DIR/config.php"; then
            info "Configurações do banco já estão no config.php"
        else
            warn "Configurações do banco podem não estar corretas no config.php"
        fi
        
    elif [ -f "$INSTALL_DIR/.env" ]; then
        info "Arquivo .env encontrado. Atualizando configurações..."
        
        # Atualizar .env com suas credenciais
        sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_DATABASE}|" "$INSTALL_DIR/.env"
        sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USERNAME}|" "$INSTALL_DIR/.env"
        sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" "$INSTALL_DIR/.env"
        sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN_NAME}|" "$INSTALL_DIR/.env"
        
    else
        # Criar .env do zero com suas credenciais
        ENV_FILE="$INSTALL_DIR/.env"
        cat > "$ENV_FILE" <<EOF
# ============================================================================
# YOUTUBE AUDIO EXTRACTOR - CONFIGURAÇÕES
# ============================================================================

APP_NAME="YouTube Audio Extractor"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://${DOMAIN_NAME}
APP_KEY=${SECRET_KEY}

# Banco de Dados - SUAS CREDENCIAIS
DB_CONNECTION=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=${DB_DATABASE}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}

# Cache
CACHE_DRIVER=redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Sessão
SESSION_DRIVER=redis
SESSION_LIFETIME=120

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

# YouTube
YTDLP_PATH=/opt/youtube-venv/bin/yt-dlp
FFMPEG_PATH=/usr/bin/ffmpeg
MAX_CONCURRENT_DOWNLOADS=3
DEFAULT_AUDIO_FORMAT=mp3
DEFAULT_BITRATE=192

# Armazenamento
UPLOAD_PATH=${INSTALL_DIR}/uploads
LOG_PATH=${INSTALL_DIR}/logs
EOF
        
        info "Arquivo .env criado com suas credenciais"
    fi
    
    # Proteger arquivos sensíveis
    chmod 640 "$INSTALL_DIR/.env" 2>/dev/null || true
    chmod 640 "$INSTALL_DIR/config.php" 2>/dev/null || true
    
    success "Arquivos de configuração configurados"
}

# Configurar Apache Virtual Host
setup_apache_vhost() {
    log "Configurando Virtual Host do Apache..."
    
    VHOST_FILE="/etc/apache2/sites-available/youtube-extractor.conf"
    
    cat > "$VHOST_FILE" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN_NAME}
    ServerAdmin ${EMAIL_ADMIN}
    DocumentRoot ${INSTALL_DIR}/public
    
    ErrorLog \${APACHE_LOG_DIR}/youtube-extractor-error.log
    CustomLog \${APACHE_LOG_DIR}/youtube-extractor-access.log combined
    
    <Directory ${INSTALL_DIR}/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Headers de segurança
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-XSS-Protection "1; mode=block"
    </Directory>
    
    # Configurações PHP
    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>
    
    php_value upload_max_filesize 2G
    php_value post_max_size 2G
    php_value max_execution_time 600
    php_value memory_limit 1G
</VirtualHost>

<VirtualHost *:443>
    ServerName ${DOMAIN_NAME}
    ServerAdmin ${EMAIL_ADMIN}
    DocumentRoot ${INSTALL_DIR}/public
    
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem
    
    ErrorLog \${APACHE_LOG_DIR}/youtube-extractor-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/youtube-extractor-ssl-access.log combined
    
    <Directory ${INSTALL_DIR}/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Headers de segurança
        Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-XSS-Protection "1; mode=block"
    </Directory>
    
    # Configurações PHP
    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>
    
    php_value upload_max_filesize 2G
    php_value post_max_size 2G
    php_value max_execution_time 600
    php_value memory_limit 1G
</VirtualHost>
EOF
    
    # Verificar se existe diretório public
    if [ ! -d "$INSTALL_DIR/public" ]; then
        # Se não existir, usar o diretório raiz
        sed -i "s|${INSTALL_DIR}/public|${INSTALL_DIR}|g" "$VHOST_FILE"
        # Remover a segunda ocorrência também
        sed -i "27s|${INSTALL_DIR}/public|${INSTALL_DIR}|" "$VHOST_FILE"
    fi
    
    # Desabilitar site padrão
    a2dissite 000-default.conf 2>/dev/null || true
    
    # Habilitar novo site
    a2ensite youtube-extractor.conf
    
    # Habilitar SSL
    a2enmod ssl
    
    # Testar configuração
    if apache2ctl configtest; then
        systemctl restart apache2
        success "Virtual Host do Apache configurado"
    else
        error "Erro na configuração do Apache"
        exit 1
    fi
}

# Configurar SSL
setup_ssl() {
    log "Configurando SSL para ${DOMAIN_NAME}..."
    
    # Verificar se o domínio aponta para este servidor
    CURRENT_IP=$(curl -s http://checkip.amazonaws.com || echo "unknown")
    info "IP público atual: $CURRENT_IP"
    info "Domínio: $DOMAIN_NAME"
    
    echo ""
    info "⚠️  IMPORTANTE: Certifique-se de que:"
    info "   1. O domínio ${DOMAIN_NAME} está apontando para o IP ${CURRENT_IP}"
    info "   2. O DNS já propagou (pode levar até 24 horas)"
    echo ""
    
    if confirm "O DNS já está configurado e propagado?"; then
        # Obter certificado SSL
        if certbot --apache \
            -d "$DOMAIN_NAME" \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL_ADMIN" \
            --redirect; then
            success "SSL configurado com sucesso"
            
            # Agendar renovação
            (crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet") | crontab -
        else
            warn "Falha ao obter certificado SSL"
            warn "Execute manualmente após confirmar DNS:"
            warn "  sudo certbot --apache -d ${DOMAIN_NAME}"
        fi
    else
        warn "SSL não configurado. Configure após o DNS propagar:"
        warn "  sudo certbot --apache -d ${DOMAIN_NAME}"
    fi
}

# Configurar Supervisor para workers
setup_supervisor() {
    log "Configurando Supervisor..."
    
    # Criar diretório de logs
    mkdir -p "$INSTALL_DIR/logs"
    
    # Verificar se existe script worker
    WORKER_SCRIPT=""
    for script in "$INSTALL_DIR/worker.py" "$INSTALL_DIR/scripts/worker.py" "$INSTALL_DIR/app/worker.py"; do
        if [ -f "$script" ]; then
            WORKER_SCRIPT="$script"
            break
        fi
    done
    
    if [ -z "$WORKER_SCRIPT" ]; then
        # Criar worker básico
        WORKER_SCRIPT="$INSTALL_DIR/worker.py"
        cat > "$WORKER_SCRIPT" <<'EOF'
#!/usr/bin/env python3
import time
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/www/youtube-audio-extractor/logs/worker.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

def main():
    logger.info("YouTube Audio Extractor Worker iniciado")
    
    while True:
        try:
            logger.info("Worker ativo")
            time.sleep(60)
        except KeyboardInterrupt:
            logger.info("Worker interrompido")
            break
        except Exception as e:
            logger.error(f"Erro: {e}")
            time.sleep(30)

if __name__ == "__main__":
    main()
EOF
        chmod +x "$WORKER_SCRIPT"
    fi
    
    SUPERVISOR_CONF="/etc/supervisor/conf.d/youtube-worker.conf"
    
    cat > "$SUPERVISOR_CONF" <<EOF
[program:youtube-worker]
command=/opt/youtube-venv/bin/python3 ${WORKER_SCRIPT}
directory=${INSTALL_DIR}
user=www-data
autostart=true
autorestart=true
startretries=3
stdout_logfile=${INSTALL_DIR}/logs/supervisor.log
stdout_logfile_maxbytes=10MB
stderr_logfile=${INSTALL_DIR}/logs/supervisor-error.log
stderr_logfile_maxbytes=10MB
environment=PYTHONPATH="${INSTALL_DIR}"
EOF
    
    supervisorctl reread
    supervisorctl update
    
    # Tentar iniciar
    if supervisorctl start youtube-worker; then
        success "Supervisor configurado"
    else
        warn "Supervisor configurado mas não iniciado"
    fi
}

# Configurar permissões
setup_permissions() {
    log "Configurando permissões..."
    
    # Definir proprietário
    chown -R www-data:www-data "$INSTALL_DIR"
    
    # Configurar permissões
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
    
    # Permissões especiais
    chmod -R 775 "$INSTALL_DIR/logs" 2>/dev/null || true
    chmod -R 775 "$INSTALL_DIR/uploads" 2>/dev/null || true
    chmod -R 775 "$INSTALL_DIR/storage" 2>/dev/null || true
    
    # Scripts executáveis
    find "$INSTALL_DIR" -name "*.py" -type f -exec chmod +x {} \; 2>/dev/null || true
    find "$INSTALL_DIR" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
    
    # Proteger arquivos sensíveis
    [ -f "$INSTALL_DIR/.env" ] && chmod 640 "$INSTALL_DIR/.env"
    [ -f "$INSTALL_DIR/config.php" ] && chmod 640 "$INSTALL_DIR/config.php"
    
    success "Permissões configuradas"
}

# Configurar cron jobs
setup_cron() {
    log "Configurando tarefas agendadas..."
    
    CRON_FILE="/etc/cron.d/youtube-extractor"
    
    cat > "$CRON_FILE" <<EOF
# YouTube Audio Extractor - Tarefas agendadas

# Limpeza diária (2 AM)
0 2 * * * www-data find ${INSTALL_DIR}/tmp -type f -mtime +1 -delete 2>/dev/null || true

# Backup do banco (3 AM)
0 3 * * * www-data mysqldump -u ${DB_USERNAME} -p'${DB_PASSWORD}' ${DB_DATABASE} 2>/dev/null | gzip > ${INSTALL_DIR}/backups/db_\$(date +\%Y\%m\%d).sql.gz 2>/dev/null || true

# Atualização yt-dlp (Domingos 6 AM)
0 6 * * 0 www-data /opt/youtube-venv/bin/pip install --upgrade yt-dlp > ${INSTALL_DIR}/logs/update.log 2>&1

# Monitoramento (a cada 5 minutos)
*/5 * * * * root ${INSTALL_DIR}/scripts/monitor.sh 2>/dev/null || true
EOF
    
    chmod 644 "$CRON_FILE"
    
    # Criar script de monitoramento básico
    MONITOR_SCRIPT="$INSTALL_DIR/scripts/monitor.sh"
    mkdir -p "$(dirname "$MONITOR_SCRIPT")"
    
    cat > "$MONITOR_SCRIPT" <<'EOF'
#!/bin/bash
LOG="${INSTALL_DIR}/logs/monitor.log"
echo "[$(date)] Monitoramento executado" >> "$LOG"

# Verificar serviços
for service in apache2 mysql redis-server supervisor; do
    if ! systemctl is-active --quiet "$service"; then
        echo "[$(date)] ALERTA: $service parado" >> "$LOG"
        systemctl restart "$service" 2>/dev/null
    fi
done
EOF
    
    chmod +x "$MONITOR_SCRIPT"
    
    success "Tarefas agendadas configuradas"
}

# ============================================================================
# FLUXO PRINCIPAL
# ============================================================================

# Banner inicial
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               YOUTUBE AUDIO EXTRACTOR                        ║"
    echo "║               Instalador Automático v2.0.6                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Mostrar configurações
show_config() {
    echo -e "${CYAN}⚙️  CONFIGURAÇÕES DO SISTEMA:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo -e "  ${WHITE}🌐 Domínio:${NC}          ${DOMAIN_NAME}"
    echo -e "  ${WHITE}📧 Email Admin:${NC}      ${EMAIL_ADMIN}"
    echo -e "  ${WHITE}📁 Diretório:${NC}        ${INSTALL_DIR}"
    echo ""
    echo -e "${CYAN}🗄️  BANCO DE DADOS:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo -e "  ${WHITE}Banco:${NC}               ${DB_DATABASE}"
    echo -e "  ${WHITE}Usuário:${NC}             ${DB_USERNAME}"
    echo -e "  ${WHITE}Senha:${NC}               [configurada no sistema]"
    echo ""
}

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
        echo -e "  ${YELLOW}⚠${NC} MySQL pode não estar rodando"
    fi
    
    # Testar PHP
    if php --version &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} PHP está instalado"
    else
        echo -e "  ${RED}✗${NC} PHP não está instalado"
    fi
    
    # Testar acesso ao banco
    MYSQL_CMD=$(get_mysql_command)
    if [ -n "$MYSQL_CMD" ] && $MYSQL_CMD -e "SELECT 1;" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Acesso ao MySQL OK"
        
        # Testar banco específico
        if $MYSQL_CMD -e "USE \`${DB_DATABASE}\`; SELECT 1;" &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} Banco '${DB_DATABASE}' acessível"
        else
            echo -e "  ${YELLOW}⚠${NC} Banco '${DB_DATABASE}' não encontrado"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Acesso ao MySQL não testado"
    fi
    
    echo ""
}

# Mostrar resumo
show_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         INSTALAÇÃO CONCLUÍDA!                                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    show_config
    
    echo -e "${CYAN}🚀 URLs DE ACESSO:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo -e "  ${WHITE}🌍 Site:${NC}               https://${DOMAIN_NAME}"
    echo -e "  ${WHITE}🔐 Admin:${NC}              https://${DOMAIN_NAME}/admin"
    echo ""
    
    echo -e "${CYAN}⚙️  PRÓXIMOS PASSOS:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo "  1. Configure o DNS: ${DOMAIN_NAME} → 45.140.193.50"
    echo "  2. Aguarde propagação do DNS (até 24h)"
    echo "  3. Acesse o site após DNS propagar"
    echo "  4. Configure SSL (se não configurado automaticamente)"
    echo ""
    
    echo -e "${CYAN}🔧 COMANDOS ÚTEIS:${NC}"
    echo "────────────────────────────────────────────────────────"
    echo "  Acessar MySQL: mysql -u ${DB_USERNAME} -p ${DB_DATABASE}"
    echo "  Monitorar logs: tail -f ${INSTALL_DIR}/logs/*.log"
    echo "  Reiniciar: sudo systemctl restart apache2 mysql"
    echo ""
}

# Salvar credenciais
save_credentials() {
    CREDS_FILE="/root/audioextractor_credentials.txt"
    
    cat > "$CREDS_FILE" <<EOF
========================================
YOUTUBE AUDIO EXTRACTOR - CREDENCIAIS
========================================
Instalação: $(date)

🌐 SISTEMA:
----------
URL: https://${DOMAIN_NAME}
Admin: https://${DOMAIN_NAME}/admin
Diretório: ${INSTALL_DIR}
Email: ${EMAIL_ADMIN}

🗄️  BANCO DE DADOS:
------------------
Host: localhost
Banco: ${DB_DATABASE}
Usuário: ${DB_USERNAME}
Senha: ${DB_PASSWORD}

🔧 COMANDOS:
-----------
Acessar MySQL:
  mysql -u ${DB_USERNAME} -p ${DB_DATABASE}

Configurar SSL (se necessário):
  sudo certbot --apache -d ${DOMAIN_NAME}

Reiniciar serviços:
  sudo systemctl restart apache2 mysql redis supervisor

Verificar status:
  sudo systemctl status apache2 mysql redis supervisor

========================================
EOF
    
    chmod 600 "$CREDS_FILE"
    warn "Credenciais salvas em: $CREDS_FILE"
}

# Fluxo principal
main_installation() {
    show_banner
    
    info "Iniciando instalação do YouTube Audio Extractor"
    echo ""
    
    show_config
    
    echo "Este instalador vai:"
    echo "  • Usar suas credenciais existentes do banco de dados"
    echo "  • Instalar e configurar todos os serviços necessários"
    echo "  • Configurar SSL automático (após DNS propagar)"
    echo ""
    
    if ! confirm "Deseja continuar?"; then
        info "Instalação cancelada"
        exit 0
    fi
    
    echo ""
    
    # 1. Verificar requisitos
    check_root
    check_internet
    
    # 2. Atualizar sistema
    update_system
    
    # 3. Instalar dependências
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
    
    # 4. Clonar/configurar repositório
    clone_repository
    
    # 5. Configurar sistema
    setup_database
    setup_env_file
    setup_apache_vhost
    setup_ssl
    setup_supervisor
    setup_permissions
    setup_cron
    
    # 6. Testar
    test_installation
    
    # 7. Resumo
    show_summary
    save_credentials
    
    # 8. Finalização
    echo ""
    log "✅ Instalação concluída!"
    echo ""
    info "IMPORTANTE: Configure o DNS antes de acessar o sistema:"
    info "  Domínio: ${DOMAIN_NAME}"
    info "  IP: 45.140.193.50"
    echo ""
    info "Credenciais salvas em: /root/audioextractor_credentials.txt"
    echo ""
}

# Tratamento de erros
trap 'error "Instalação interrompida"; exit 1' INT
trap 'error "Erro na linha $LINENO"; exit 1' ERR

# Executar
main_installation
