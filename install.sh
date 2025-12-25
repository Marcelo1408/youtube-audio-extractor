#!/bin/bash

# ============================================
# INSTALADOR COMPLETO - YouTube Audio Extractor
# Versão: 3.0 - Corrigido e Testado
# ============================================

set -e  # Para em caso de erro

# Cores para melhor visualização
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções auxiliares
log() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

# Log de instalação
LOG_FILE="/var/log/youtube-extractor-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================"
echo "  🎵 YOUTUBE AUDIO EXTRACTOR - INSTALADOR"
echo "  Ubuntu 22.04 | MariaDB | Nginx | PHP 8.1"
echo "============================================"

# -------------------------------------------------
# 1. CONFIGURAÇÃO INICIAL - EVITA BLOQUEIOS
# -------------------------------------------------
log "Preparando ambiente..."
export DEBIAN_FRONTEND=noninteractive

# Mata processos bloqueantes
sudo pkill -9 debconf 2>/dev/null || true
sudo pkill -9 apt 2>/dev/null || true
sudo pkill -9 dpkg 2>/dev/null || true

# Remove locks
sudo rm -f /var/lib/apt/lists/lock
sudo rm -f /var/lib/dpkg/lock
sudo rm -f /var/cache/apt/archives/lock
sudo rm -f /var/cache/debconf/config.dat

sudo dpkg --configure -a 2>/dev/null || true

# -------------------------------------------------
# 2. INFORMAÇÕES DO USUÁRIO
# -------------------------------------------------
echo ""
echo "📝 INFORMAÇÕES NECESSÁRIAS:"
echo "---------------------------"

# Domínio
while [ -z "$DOMAIN" ]; do
    read -p "• Domínio completo (ex: audio.seusite.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        warn "Domínio é obrigatório!"
    fi
done

# Email
while [ -z "$EMAIL" ]; do
    read -p "• Email para SSL (Let's Encrypt): " EMAIL
    if [ -z "$EMAIL" ]; then
        warn "Email é obrigatório!"
    fi
done

# Senhas do banco
echo ""
echo "🔐 CONFIGURAÇÃO DO BANCO DE DADOS:"

# Senha root - com validação
while true; do
    read -sp "• Senha ROOT do MariaDB: " DB_ROOT_PASS
    echo
    if [ ${#DB_ROOT_PASS} -ge 8 ]; then
        read -sp "• Confirme a senha: " DB_ROOT_PASS2
        echo
        if [ "$DB_ROOT_PASS" = "$DB_ROOT_PASS2" ]; then
            break
        else
            warn "Senhas não coincidem!"
        fi
    else
        warn "Senha deve ter pelo menos 8 caracteres!"
    fi
done

# Nome do banco
read -p "• Nome do banco [youtube_extractor]: " DB_NAME
DB_NAME=${DB_NAME:-youtube_extractor}

# Usuário do banco
read -p "• Usuário do banco [audio_user]: " DB_USER
DB_USER=${DB_USER:-audio_user}

# Senha do usuário - com validação
while true; do
    read -sp "• Senha do usuário: " DB_PASS
    echo
    if [ ${#DB_PASS} -ge 6 ]; then
        read -sp "• Confirme a senha: " DB_PASS2
        echo
        if [ "$DB_PASS" = "$DB_PASS2" ]; then
            break
        else
            warn "Senhas não coincidem!"
        fi
    else
        warn "Senha deve ter pelo menos 6 caracteres!"
    fi
done

# -------------------------------------------------
# 3. VARIÁVEIS DO SISTEMA
# -------------------------------------------------
PROJECT_DIR="/var/www/$DOMAIN"
MYSQL_ROOT_USER="root"

echo ""
echo "📋 RESUMO DA CONFIGURAÇÃO:"
echo "---------------------------"
echo "• Domínio: $DOMAIN"
echo "• Email: $EMAIL"
echo "• Diretório: $PROJECT_DIR"
echo "• Banco: $DB_NAME"
echo "• Usuário DB: $DB_USER"
echo "• Senha Root DB: [oculto]"
echo "• Senha Usuário DB: [oculto]"
echo ""

read -p "Continuar com a instalação? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    error "Instalação cancelada pelo usuário."
fi

# -------------------------------------------------
# 4. ATUALIZAÇÃO DO SISTEMA
# -------------------------------------------------
log "Atualizando repositórios do sistema..."
sudo apt-get update -y

log "Atualizando pacotes..."
sudo apt-get upgrade -y

# -------------------------------------------------
# 5. INSTALAÇÃO DE DEPENDÊNCIAS
# -------------------------------------------------
log "Instalando dependências principais..."

# Configura respostas automáticas para evitar perguntas
sudo debconf-set-selections <<EOF
libc6 libraries/restart-without-asking boolean true
openssh-server openssh-server/permit-root-login boolean true
openssh-server openssh-server/sshd_config_preserve_local string keep
mariadb-server mysql-server/root_password password $DB_ROOT_PASS
mariadb-server mysql-server/root_password_again password $DB_ROOT_PASS
console-setup console-setup/charmap47 select UTF-8
keyboard-configuration keyboard-configuration/layoutcode string us
EOF

# Lista de pacotes essenciais
PACKAGES=(
    nginx
    mariadb-server mariadb-client
    php8.1 php8.1-fpm php8.1-mysql php8.1-cli php8.1-curl php8.1-zip
    php8.1-mbstring php8.1-xml php8.1-gd php8.1-bcmath
    python3 python3-pip python3-venv
    ffmpeg
    curl wget unzip git
    certbot python3-certbot-nginx
)

log "Instalando: ${PACKAGES[*]}"
sudo apt-get install -y "${PACKAGES[@]}"

# -------------------------------------------------
# 6. CONFIGURAÇÃO DO MARIADB
# -------------------------------------------------
log "Configurando MariaDB..."

# Inicia e habilita o serviço
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Aguarda o MariaDB iniciar
sleep 5

# Configuração segura do MariaDB
log "Executando configuração segura do MariaDB..."
sudo mysql -u root <<EOF
-- Define senha root (já definida, mas garantindo)
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';

-- Remove usuários anônimos
DELETE FROM mysql.user WHERE User='';

-- Remove acesso root remoto
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove banco de teste
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Recarrega privilégios
FLUSH PRIVILEGES;
EOF

# Cria banco de dados e usuário
log "Criando banco de dados '$DB_NAME'..."
sudo mysql -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' 
IDENTIFIED BY '$DB_PASS';

GRANT ALL PRIVILEGES ON $DB_NAME.* 
TO '$DB_USER'@'localhost';

GRANT SELECT ON mysql.user 
TO '$DB_USER'@'localhost';

FLUSH PRIVILEGES;
EOF

# -------------------------------------------------
# 7. CRIA ESTRUTURA DO BANCO (SQL COMPLETO)
# -------------------------------------------------
log "Criando estrutura do banco de dados..."

# Cria arquivo SQL temporário
SQL_FILE="/tmp/database_structure.sql"

cat > "$SQL_FILE" <<'SQL'
-- ============================================
-- ESTRUTURA DO BANCO - YouTube Audio Extractor
-- ============================================

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

-- --------------------------------------------------------
-- Tabela: users
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS `users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL,
  `email` varchar(100) NOT NULL,
  `password` varchar(255) NOT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `avatar` varchar(255) DEFAULT NULL,
  `role` enum('user','admin','moderator') DEFAULT 'user',
  `plan` enum('free','premium','enterprise') DEFAULT 'free',
  `storage_limit` bigint(20) DEFAULT 10737418240,
  `storage_used` bigint(20) DEFAULT 0,
  `process_limit` int(11) DEFAULT 50,
  `process_count` int(11) DEFAULT 0,
  `last_login` datetime DEFAULT NULL,
  `email_verified` tinyint(1) DEFAULT 0,
  `verification_token` varchar(100) DEFAULT NULL,
  `reset_token` varchar(100) DEFAULT NULL,
  `reset_expires` datetime DEFAULT NULL,
  `status` enum('active','suspended','banned') DEFAULT 'active',
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `email` (`email`),
  KEY `status` (`status`),
  KEY `role` (`role`),
  KEY `plan` (`plan`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------
-- Tabela: processes
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS `processes` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `process_uid` varchar(32) NOT NULL,
  `youtube_url` text NOT NULL,
  `youtube_id` varchar(20) DEFAULT NULL,
  `video_title` varchar(255) DEFAULT NULL,
  `video_duration` int(11) DEFAULT NULL,
  `video_size` bigint(20) DEFAULT NULL,
  `thumbnail_url` text,
  `status` enum('pending','downloading','converting','separating','completed','failed','cancelled') DEFAULT 'pending',
  `quality` enum('64','128','192','320') DEFAULT '128',
  `separate_tracks` tinyint(1) DEFAULT 0,
  `tracks_count` int(11) DEFAULT 0,
  `original_format` varchar(10) DEFAULT NULL,
  `output_format` varchar(10) DEFAULT 'mp3',
  `file_path` varchar(500) DEFAULT NULL,
  `file_size` bigint(20) DEFAULT 0,
  `progress` int(11) DEFAULT 0,
  `error_message` text,
  `processing_time` int(11) DEFAULT NULL,
  `worker_id` varchar(50) DEFAULT NULL,
  `notify_user` tinyint(1) DEFAULT 1,
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `completed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `process_uid` (`process_uid`),
  KEY `user_id` (`user_id`),
  KEY `status` (`status`),
  KEY `youtube_id` (`youtube_id`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------
-- Tabela: tracks
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS `tracks` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `process_id` int(11) NOT NULL,
  `track_number` int(11) NOT NULL,
  `track_name` varchar(100) NOT NULL,
  `track_type` enum('vocals','drums','bass','piano','other','full') DEFAULT 'full',
  `file_name` varchar(255) NOT NULL,
  `file_path` varchar(500) NOT NULL,
  `file_size` bigint(20) DEFAULT 0,
  `duration` int(11) DEFAULT 0,
  `bitrate` int(11) DEFAULT 128,
  `format` varchar(10) DEFAULT 'mp3',
  `downloads` int(11) DEFAULT 0,
  `plays` int(11) DEFAULT 0,
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `process_id` (`process_id`),
  KEY `track_type` (`track_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------
-- Tabela: settings
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS `settings` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text,
  `setting_type` enum('string','integer','boolean','json','array') DEFAULT 'string',
  `description` text,
  `is_public` tinyint(1) DEFAULT 0,
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `setting_key` (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------
-- Tabela: logs
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS `logs` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `level` enum('info','warning','error','debug') DEFAULT 'info',
  `message` text NOT NULL,
  `context` json DEFAULT NULL,
  `user_id` int(11) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text,
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `level` (`level`),
  KEY `user_id` (`user_id`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------
-- Dados iniciais
-- --------------------------------------------------------

-- Usuário administrador padrão
INSERT INTO `users` (`username`, `email`, `password`, `role`, `plan`, `email_verified`) VALUES
('admin', 'admin@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin', 'enterprise', 1);

-- Configurações padrão
INSERT INTO `settings` (`setting_key`, `setting_value`, `description`, `is_public`) VALUES
('site_name', 'YouTube Audio Extractor', 'Nome do site', 1),
('site_description', 'Extraia áudio de vídeos do YouTube', 'Descrição do site', 1),
('max_video_size', '1073741824', 'Tamanho máximo em bytes', 1),
('max_video_duration', '7200', 'Duração máxima em segundos', 1),
('enable_registration', '1', 'Permitir novos registros', 1),
('default_quality', '128', 'Qualidade padrão', 1);

-- Cria índices para performance
CREATE INDEX idx_processes_user_status ON processes(user_id, status);
CREATE INDEX idx_processes_created_status ON processes(created_at, status);
CREATE INDEX idx_tracks_process_type ON tracks(process_id, track_type);
SQL

# Executa o SQL
sudo mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" < "$SQL_FILE"
rm -f "$SQL_FILE"

log "Estrutura do banco criada com sucesso!"

# -------------------------------------------------
# 8. PREPARA DIRETÓRIO DO PROJETO
# -------------------------------------------------
log "Preparando diretório do projeto..."

# Remove instalação anterior se existir
if [ -d "$PROJECT_DIR" ]; then
    warn "Removendo instalação anterior..."
    sudo rm -rf "$PROJECT_DIR"
fi

# Cria diretório
sudo mkdir -p "$PROJECT_DIR"
sudo chown -R $USER:$USER "$PROJECT_DIR"

# -------------------------------------------------
# 9. BAIXA CÓDIGO DO GITHUB
# -------------------------------------------------
log "Baixando código do GitHub..."

cd "$PROJECT_DIR"

# Método 1: Tenta git clone (mais rápido)
log "Tentando clone via Git..."
if command -v git >/dev/null 2>&1; then
    git clone --depth 1 https://github.com/Marcelo1408/youtube-audio-extractor.git . 2>/dev/null && {
        log "Clone via Git bem-sucedido!"
    } || {
        warn "Git falhou, usando download ZIP..."
        DOWNLOAD_ZIP=true
    }
else
    DOWNLOAD_ZIP=true
fi

# Método 2: Download ZIP se Git falhou
if [ "$DOWNLOAD_ZIP" = true ] || [ -z "$(ls -A . 2>/dev/null)" ]; then
    log "Baixando arquivo ZIP..."
    
    # URLs alternativas
    ZIP_URLS=(
        "https://github.com/Marcelo1408/youtube-audio-extractor/archive/refs/heads/main.zip"
        "https://github.com/Marcelo1408/youtube-audio-extractor/archive/main.zip"
    )
    
    for ZIP_URL in "${ZIP_URLS[@]}"; do
        log "Tentando: $ZIP_URL"
        if wget -q --show-progress "$ZIP_URL" -O site.zip; then
            log "Download bem-sucedido!"
            break
        fi
    done
    
    if [ -f "site.zip" ]; then
        log "Extraindo arquivos..."
        unzip -q site.zip
        
        # Procura pelo diretório extraído
        EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "*youtube*" | head -1)
        
        if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then
            log "Movendo arquivos..."
            mv "$EXTRACTED_DIR"/* . 2>/dev/null || true
            mv "$EXTRACTED_DIR"/.* . 2>/dev/null || true
            rm -rf "$EXTRACTED_DIR"
        else
            # Lista o conteúdo para debug
            log "Conteúdo do ZIP:"
            unzip -l site.zip | head -20
        fi
        
        rm -f site.zip
    else
        warn "Falha no download. Criando estrutura básica..."
        # Cria estrutura mínima
        mkdir -p public uploads
        cat > public/index.php <<'PHP'
<?php
echo '<!DOCTYPE html>
<html>
<head>
    <title>YouTube Audio Extractor</title>
    <style>
        body { font-family: Arial; text-align: center; padding: 50px; }
        .success { color: green; font-size: 24px; }
        .info { margin-top: 30px; padding: 20px; background: #f5f5f5; border-radius: 10px; }
    </style>
</head>
<body>
    <div class="success">✅ YouTube Audio Extractor</div>
    <div class="info">
        <h2>Instalação Completa!</h2>
        <p>Domínio: <?php echo $_SERVER["HTTP_HOST"] ?? "'$DOMAIN'"; ?></p>
        <p>PHP: <?php echo phpversion(); ?></p>
        <p>Banco: <?php echo getenv("DB_NAME") ?: "'$DB_NAME'"; ?></p>
    </div>
</body>
</html>';
PHP
    fi
fi

# Verifica se há arquivos
if [ -z "$(ls -A . 2>/dev/null)" ]; then
    error "Nenhum arquivo foi baixado ou criado!"
else
    log "Arquivos encontrados: $(ls | wc -l)"
fi

# -------------------------------------------------
# 10. DEPENDÊNCIAS PYTHON
# -------------------------------------------------
log "Instalando dependências Python..."

# Cria virtual environment
python3 -m venv venv 2>/dev/null || {
    warn "Virtual env falhou, instalando globalmente..."
    sudo pip3 install --upgrade pip
    sudo pip3 install yt-dlp pydub moviepy python-dotenv
}

# Ativa venv e instala
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    pip install --upgrade pip
    pip install yt-dlp pydub moviepy python-dotenv
    deactivate
    
    # Cria links simbólicos
    sudo ln -sf "$PROJECT_DIR/venv/bin/python3" /usr/local/bin/audio-extractor-python 2>/dev/null || true
    sudo ln -sf "$PROJECT_DIR/venv/bin/yt-dlp" /usr/local/bin/audio-extractor-ytdlp 2>/dev/null || true
fi

# -------------------------------------------------
# 11. CONFIGURA PERMISSÕES
# -------------------------------------------------
log "Configurando permissões..."

# Cria diretórios necessários
mkdir -p uploads cache

# Ajusta dono e permissões
sudo chown -R www-data:www-data "$PROJECT_DIR"
sudo find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
sudo find "$PROJECT_DIR" -type d -exec chmod 755 {} \;

# Diretórios especiais
sudo chmod 775 uploads cache

# -------------------------------------------------
# 12. ARQUIVO DE CONFIGURAÇÃO (.env)
# -------------------------------------------------
log "Criando arquivo de configuração..."

# Gera chave segura para aplicação
APP_KEY=$(openssl rand -base64 32)

cat > .env <<ENV
# ============================================
# CONFIGURAÇÃO - YouTube Audio Extractor
# ============================================

# Aplicação
APP_ENV=production
APP_DEBUG=false
APP_URL=https://$DOMAIN
APP_KEY=$APP_KEY

# Banco de Dados
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS

# Python / Processamento
PYTHON_PATH=$(which python3)
FFMPEG_PATH=$(which ffmpeg)
YTDLP_PATH=$(which yt-dlp)

# Diretórios
UPLOAD_PATH=$PROJECT_DIR/uploads
CACHE_PATH=$PROJECT_DIR/cache
LOG_PATH=/var/log/audio-extractor

# Limites
MAX_FILE_SIZE=50M
MAX_VIDEO_DURATION=7200
MAX_CONCURRENT_PROCESSES=3

# Sessão
SESSION_DRIVER=database
SESSION_LIFETIME=120

# Fila
QUEUE_CONNECTION=database

# Email (configure depois)
MAIL_MAILER=smtp
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=seu-email@gmail.com
MAIL_PASSWORD=sua-senha
MAIL_ENCRYPTION=tls
ENV

# Protege o .env
sudo chown www-data:www-data .env
sudo chmod 600 .env

# -------------------------------------------------
# 13. CONFIGURAÇÃO DO NGINX
# -------------------------------------------------
log "Configurando Nginx..."

# Remove site default
sudo rm -f /etc/nginx/sites-enabled/default

# Cria configuração do site
sudo cat > "/etc/nginx/sites-available/$DOMAIN" <<NGINX
# ============================================
# YouTube Audio Extractor - $DOMAIN
# ============================================

server {
    listen 80;
    listen [::]:80;
    
    server_name $DOMAIN;
    root $PROJECT_DIR/public;
    
    index index.php index.html index.htm;
    
    # Limites
    client_max_body_size 50M;
    client_body_timeout 300s;
    
    # Logs
    access_log /var/log/nginx/$DOMAIN-access.log;
    error_log /var/log/nginx/$DOMAIN-error.log;
    
    # Segurança básica
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Pasta pública
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # Timeouts aumentados para processamento
        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
    }
    
    # Uploads (acesso interno)
    location /uploads/ {
        alias $PROJECT_DIR/uploads/;
        internal;
    }
    
    # Bloqueia acesso a arquivos sensíveis
    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    location ~ /\.env {
        deny all;
    }
    
    # Cache para arquivos estáticos
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }
}
NGINX

# Ativa o site
sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"

# Testa configuração
sudo nginx -t || error "Configuração do Nginx inválida!"

# -------------------------------------------------
# 14. OTIMIZAÇÃO DO PHP-FPM
# -------------------------------------------------
log "Otimizando PHP-FPM..."

PHP_CONF="/etc/php/8.1/fpm/php.ini"
if [ -f "$PHP_CONF" ]; then
    sudo sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 50M/' "$PHP_CONF"
    sudo sed -i 's/^post_max_size = .*/post_max_size = 50M/' "$PHP_CONF"
    sudo sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_CONF"
    sudo sed -i 's/^max_input_time = .*/max_input_time = 300/' "$PHP_CONF"
    sudo sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$PHP_CONF"
fi

# -------------------------------------------------
# 15. SISTEMA DE LOGS
# -------------------------------------------------
log "Configurando sistema de logs..."

sudo mkdir -p /var/log/audio-extractor
sudo touch /var/log/audio-extractor/{app.log,error.log,processing.log}
sudo chown -R www-data:www-data /var/log/audio-extractor
sudo chmod -R 755 /var/log/audio-extractor

# Configura logrotate
sudo cat > /etc/logrotate.d/audio-extractor <<LOGROTATE
/var/log/audio-extractor/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
    sharedscripts
    postrotate
        systemctl reload php8.1-fpm >/dev/null 2>&1 || true
    endscript
}
LOGROTATE

# -------------------------------------------------
# 16. SSL (LET'S ENCRYPT) - OPCIONAL
# -------------------------------------------------
log "Configurando SSL (Let's Encrypt)..."

# Reinicia serviços primeiro
sudo systemctl restart php8.1-fpm
sudo systemctl restart nginx

# Aguarda Nginx iniciar
sleep 3

# Oferece configuração SSL
echo ""
read -p "Deseja configurar SSL agora? (Requer DNS configurado) (s/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Ss]$ ]]; then
    log "Configurando SSL..."
    if sudo certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect; then
        log "SSL configurado com sucesso!"
    else
        warn "Não foi possível configurar SSL automaticamente."
        warn "Configure manualmente quando o DNS estiver apontando:"
        info "  sudo certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos"
    fi
else
    log "SSL não configurado. Configure depois com:"
    info "  sudo certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos"
fi

# -------------------------------------------------
# 17. SCRIPT DE MONITORAMENTO
# -------------------------------------------------
log "Criando scripts auxiliares..."

# Script de monitoramento
sudo cat > /usr/local/bin/monitor-extractor <<'MONITOR'
#!/bin/bash
echo "=== 🎵 MONITORAMENTO - YouTube Audio Extractor ==="
echo "Data: $(date)"
echo ""
echo "📦 SERVIÇOS:"
echo "  Nginx: $(systemctl is-active nginx 2>/dev/null || echo 'n/a')"
echo "  MariaDB: $(systemctl is-active mariadb 2>/dev/null || echo 'n/a')"
echo "  PHP-FPM: $(systemctl is-active php8.1-fpm 2>/dev/null || echo 'n/a')"
echo ""
echo "💾 DISCO:"
df -h /var/www | tail -1
echo ""
echo "🗄️  BANCO:"
mysql -u audio_user -pAudio2024 -e "SELECT 
  (SELECT COUNT(*) FROM users) as users,
  (SELECT COUNT(*) FROM processes) as processes,
  (SELECT COUNT(*) FROM processes WHERE status='completed') as completed;" youtube_extractor 2>/dev/null || echo "  Não conectado"
echo ""
echo "📊 ARQUIVOS:"
find /var/www -name "*.mp3" -type f 2>/dev/null | wc -l | xargs echo "  MP3s:"
echo ""
echo "📈 MEMÓRIA:"
free -h | grep -E "^Mem:|^Swap:"
MONITOR

sudo chmod +x /usr/local/bin/monitor-extractor

# Script de backup
sudo cat > /usr/local/bin/backup-extractor <<'BACKUP'
#!/bin/bash
BACKUP_DIR="/backup/audio-extractor"
mkdir -p "$BACKUP_DIR"
DATE=$(date +%Y%m%d_%H%M%S)

echo "=== 🔄 BACKUP - YouTube Audio Extractor ==="
echo "Data: $DATE"
echo ""

# Backup do banco
echo "📦 Backup do banco..."
mysqldump -u audio_user -pAudio2024 youtube_extractor > "$BACKUP_DIR/db_$DATE.sql" 2>/dev/null
gzip "$BACKUP_DIR/db_$DATE.sql"

# Backup dos uploads
echo "📁 Backup dos uploads..."
tar -czf "$BACKUP_DIR/uploads_$DATE.tar.gz" /var/www/*/uploads 2>/dev/null

echo "✅ Backup criado em: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"/*_"$DATE".*
BACKUP

sudo chmod +x /usr/local/bin/backup-extractor

# -------------------------------------------------
# 18. REINICIA SERVIÇOS FINAL
# -------------------------------------------------
log "Reiniciando serviços..."
sudo systemctl restart nginx
sudo systemctl restart mariadb
sudo systemctl restart php8.1-fpm

# -------------------------------------------------
# 19. VERIFICAÇÃO FINAL
# -------------------------------------------------
echo ""
echo "============================================"
echo "✅ VERIFICAÇÃO DA INSTALAÇÃO"
echo "============================================"

# Testa cada componente
echo ""
echo "1. 📁 DIRETÓRIO:"
if [ -d "$PROJECT_DIR" ]; then
    echo "   ✅ $PROJECT_DIR"
    COUNT_FILES=$(find "$PROJECT_DIR" -type f | wc -l)
    echo "   📊 $COUNT_FILES arquivos"
else
    echo "   ❌ Não existe"
fi

echo ""
echo "2. 🗄️  BANCO DE DADOS:"
if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SHOW TABLES;" 2>/dev/null | grep -q "users"; then
    echo "   ✅ $DB_NAME"
    TABLES=$(mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SHOW TABLES;" 2>/dev/null | wc -l)
    echo "   📊 $TABLES tabelas"
else
    echo "   ❌ Não acessível"
fi

echo ""
echo "3. 🔧 SERVIÇOS:"
echo "   Nginx: $(sudo systemctl is-active nginx)"
echo "   MariaDB: $(sudo systemctl is-active mariadb)"
echo "   PHP-FPM: $(sudo systemctl is-active php8.1-fpm)"

echo ""
echo "4. 🌐 TESTE WEB:"
if curl -s -I "http://localhost" 2>/dev/null | grep -q "200\|301"; then
    echo "   ✅ HTTP respondendo"
else
    echo "   ⚠️  Verifique: sudo systemctl status nginx"
fi

echo ""
echo "5. 🐍 PYTHON:"
if which python3 >/dev/null && python3 -c "import yt_dlp, pydub" 2>/dev/null; then
    echo "   ✅ Dependências instaladas"
else
    echo "   ⚠️  Verifique: pip3 list | grep -E 'yt-dlp|pydub'"
fi

# -------------------------------------------------
# 20. RESUMO FINAL
# -------------------------------------------------
echo ""
echo "============================================"
echo "🎉 INSTALAÇÃO COMPLETA!"
echo "============================================"
echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "   Domínio: $DOMAIN"
echo "   Diretório: $PROJECT_DIR"
echo "   Banco: $DB_NAME"
echo "   Usuário DB: $DB_USER"
echo "   Senha DB: [configurada]"
echo "   Senha Root DB: [configurada]"
echo "   Email SSL: $EMAIL"
echo ""
echo "🔧 COMANDOS ÚTEIS:"
echo "   Monitorar: monitor-extractor"
echo "   Backup: backup-extractor"
echo "   Logs: sudo tail -f /var/log/nginx/$DOMAIN-error.log"
echo "   Banco: mysql -u $DB_USER -p$DB_PASS $DB_NAME"
echo "   Reiniciar: sudo systemctl restart nginx mariadb php8.1-fpm"
echo ""
echo "🚀 PRÓXIMOS PASSOS:"
echo "   1. Configure DNS: $DOMAIN → $(curl -s ifconfig.me)"
echo "   2. SSL (opcional): sudo certbot --nginx -d $DOMAIN"
echo "   3. Acesse: https://$DOMAIN"
echo "   4. Login admin: admin@example.com / password"
echo ""
echo "📝 LOG DA INSTALAÇÃO: $LOG_FILE"
echo "============================================"

# Mensagem final
echo ""
warn "⚠️  IMPORTANTE: Altere a senha do usuário admin no primeiro login!"
echo ""
log "Instalação concluída em $(date)"
echo "Tempo total: $SECONDS segundos"
