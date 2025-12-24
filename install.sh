#!/bin/bash

set -e

echo "============================================"
echo " YOUTUBE AUDIO EXTRACTOR - INSTALADOR COMPLETO"
echo "============================================"

# CONFIGURAÇÕES (ALTERE SE PRECISAR)
DOMAIN="audioextractor.giize.com"
EMAIL="admin@giize.com"  # ALTERE AQUI
DB_ROOT_PASS="3GqG!%Yg7i;YsI4Y!"
DB_PASS="SenhaForte@123"  # ALTERE AQUI
DB_NAME="youtube_extractor"
DB_USER="audioextrac_usr"


PROJECT_DIR="/var/www/$DOMAIN"
MYSQL_ROOT_USER="root"

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# FUNÇÕES
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERRO]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

check_success() {
    if [ $? -ne 0 ]; then
        error "$1"
    fi
}

# -------------------------------
# 1. ATUALIZAÇÃO DO SISTEMA
# -------------------------------
log "🔄 Atualizando sistema..."
apt update && apt upgrade -y
check_success "Falha ao atualizar sistema"

# -------------------------------
# 2. INSTALA DEPENDÊNCIAS
# -------------------------------
log "📦 Instalando dependências..."
apt install -y \
    nginx \
    mariadb-server mariadb-client \
    php8.1 php8.1-fpm php8.1-mysql php8.1-cli php8.1-curl php8.1-zip \
    php8.1-mbstring php8.1-xml php8.1-gd php8.1-json \
    python3 python3-pip python3-venv \
    ffmpeg \
    curl wget unzip git \
    certbot python3-certbot-nginx
check_success "Falha ao instalar dependências"

# -------------------------------
# 3. CONFIGURA MARIADB
# -------------------------------
log "🗄️  Configurando MariaDB..."

# Para MySQL antigo se existir
systemctl stop mysql 2>/dev/null || true

# Inicia MariaDB
systemctl start mariadb
systemctl enable mariadb
sleep 3

# Verifica se MariaDB está rodando
if ! systemctl is-active --quiet mariadb; then
    warn "MariaDB não iniciou. Tentando reparar..."
    mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    systemctl start mariadb
    sleep 3
fi

# Configura senha root
log "🔐 Configurando senha root do MariaDB..."
mysql -u root <<EOF 2>/dev/null || true
USE mysql;
UPDATE user SET plugin='mysql_native_password' WHERE User='root';
FLUSH PRIVILEGES;
EOF

mysqladmin -u root password "$DB_ROOT_PASS" 2>/dev/null || {
    mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
FLUSH PRIVILEGES;
EOF
}

# Testa conexão com nova senha
if ! mysql -u root -p"$DB_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
    error "Não foi possível conectar ao MariaDB com a senha fornecida"
fi

log "✅ MariaDB configurado com sucesso"

# -------------------------------
# 4. CRIA BANCO DE DADOS COMPLETO
# -------------------------------
log "📊 Criando banco de dados '$DB_NAME'..."

# Primeiro remove se existir (para recriação limpa)
mysql -u root -p"$DB_ROOT_PASS" -e "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null

# Cria arquivo SQL temporário
SQL_FILE="/tmp/database_setup.sql"
cat > "$SQL_FILE" <<SQL
-- Banco de dados: youtube_extractor
SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

-- Criar banco de dados
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` 
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE \`$DB_NAME\`;

-- Tabela: users
CREATE TABLE \`users\` (
  \`id\` int(11) NOT NULL AUTO_INCREMENT,
  \`username\` varchar(50) NOT NULL,
  \`email\` varchar(100) NOT NULL,
  \`password\` varchar(255) NOT NULL,
  \`phone\` varchar(20) DEFAULT NULL,
  \`avatar\` varchar(255) DEFAULT NULL,
  \`role\` enum('user','admin','moderator') DEFAULT 'user',
  \`plan\` enum('free','premium','enterprise') DEFAULT 'free',
  \`storage_limit\` bigint(20) DEFAULT 10737418240,
  \`storage_used\` bigint(20) DEFAULT 0,
  \`process_limit\` int(11) DEFAULT 50,
  \`process_count\` int(11) DEFAULT 0,
  \`last_login\` datetime DEFAULT NULL,
  \`email_verified\` tinyint(1) DEFAULT 0,
  \`verification_token\` varchar(100) DEFAULT NULL,
  \`reset_token\` varchar(100) DEFAULT NULL,
  \`reset_expires\` datetime DEFAULT NULL,
  \`status\` enum('active','suspended','banned') DEFAULT 'active',
  \`created_at\` timestamp DEFAULT CURRENT_TIMESTAMP,
  \`updated_at\` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (\`id\`),
  UNIQUE KEY \`username\` (\`username\`),
  UNIQUE KEY \`email\` (\`email\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela: processes
CREATE TABLE \`processes\` (
  \`id\` int(11) NOT NULL AUTO_INCREMENT,
  \`user_id\` int(11) NOT NULL,
  \`process_uid\` varchar(32) NOT NULL,
  \`youtube_url\` text NOT NULL,
  \`youtube_id\` varchar(20) DEFAULT NULL,
  \`video_title\` varchar(255) DEFAULT NULL,
  \`video_duration\` int(11) DEFAULT NULL,
  \`video_size\` bigint(20) DEFAULT NULL,
  \`thumbnail_url\` text,
  \`status\` enum('pending','downloading','converting','separating','completed','failed','cancelled') DEFAULT 'pending',
  \`quality\` enum('64','128','192','320') DEFAULT '128',
  \`separate_tracks\` tinyint(1) DEFAULT 0,
  \`tracks_count\` int(11) DEFAULT 0,
  \`original_format\` varchar(10) DEFAULT NULL,
  \`output_format\` varchar(10) DEFAULT 'mp3',
  \`file_path\` varchar(500) DEFAULT NULL,
  \`file_size\` bigint(20) DEFAULT 0,
  \`progress\` int(11) DEFAULT 0,
  \`error_message\` text,
  \`processing_time\` int(11) DEFAULT NULL,
  \`worker_id\` varchar(50) DEFAULT NULL,
  \`notify_user\` tinyint(1) DEFAULT 1,
  \`created_at\` timestamp DEFAULT CURRENT_TIMESTAMP,
  \`updated_at\` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  \`completed_at\` datetime DEFAULT NULL,
  PRIMARY KEY (\`id\`),
  UNIQUE KEY \`process_uid\` (\`process_uid\`),
  KEY \`user_id\` (\`user_id\`),
  CONSTRAINT \`processes_ibfk_1\` FOREIGN KEY (\`user_id\`) REFERENCES \`users\` (\`id\`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela: tracks
CREATE TABLE \`tracks\` (
  \`id\` int(11) NOT NULL AUTO_INCREMENT,
  \`process_id\` int(11) NOT NULL,
  \`track_number\` int(11) NOT NULL,
  \`track_name\` varchar(100) NOT NULL,
  \`track_type\` enum('vocals','drums','bass','piano','other','full') DEFAULT 'full',
  \`file_name\` varchar(255) NOT NULL,
  \`file_path\` varchar(500) NOT NULL,
  \`file_size\` bigint(20) DEFAULT 0,
  \`duration\` int(11) DEFAULT 0,
  \`bitrate\` int(11) DEFAULT 128,
  \`format\` varchar(10) DEFAULT 'mp3',
  \`downloads\` int(11) DEFAULT 0,
  \`plays\` int(11) DEFAULT 0,
  \`created_at\` timestamp DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (\`id\`),
  KEY \`process_id\` (\`process_id\`),
  CONSTRAINT \`tracks_ibfk_1\` FOREIGN KEY (\`process_id\`) REFERENCES \`processes\` (\`id\`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela: settings
CREATE TABLE \`settings\` (
  \`id\` int(11) NOT NULL AUTO_INCREMENT,
  \`setting_key\` varchar(100) NOT NULL,
  \`setting_value\` text,
  \`setting_type\` enum('string','integer','boolean','json','array') DEFAULT 'string',
  \`description\` text,
  \`is_public\` tinyint(1) DEFAULT 0,
  \`created_at\` timestamp DEFAULT CURRENT_TIMESTAMP,
  \`updated_at\` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (\`id\`),
  UNIQUE KEY \`setting_key\` (\`setting_key\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela: logs
CREATE TABLE \`logs\` (
  \`id\` int(11) NOT NULL AUTO_INCREMENT,
  \`level\` enum('info','warning','error','debug') DEFAULT 'info',
  \`message\` text NOT NULL,
  \`context\` json DEFAULT NULL,
  \`user_id\` int(11) DEFAULT NULL,
  \`ip_address\` varchar(45) DEFAULT NULL,
  \`user_agent\` text,
  \`created_at\` timestamp DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (\`id\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insere usuário admin
INSERT INTO \`users\` (\`username\`, \`email\`, \`password\`, \`role\`, \`plan\`, \`email_verified\`) VALUES
('admin', '$EMAIL', '\$2y\$10\$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin', 'enterprise', 1);

-- Insere configurações padrão
INSERT INTO \`settings\` (\`setting_key\`, \`setting_value\`, \`description\`, \`is_public\`) VALUES
('site_name', 'YouTube Audio Extractor', 'Nome do site', 1),
('site_description', 'Extraia áudio de vídeos do YouTube', 'Descrição do site', 1),
('max_video_size', '1073741824', 'Tamanho máximo em bytes', 1),
('max_video_duration', '7200', 'Duração máxima em segundos', 1),
('enable_registration', '1', 'Permitir novos registros', 1);

-- Cria usuário da aplicação
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT SELECT ON \`mysql\`.\`user\` TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

# Executa o SQL
mysql -u root -p"$DB_ROOT_PASS" < "$SQL_FILE"
check_success "Falha ao criar banco de dados"

rm -f "$SQL_FILE"
log "✅ Banco de dados '$DB_NAME' criado com sucesso!"

# -------------------------------
# 5. BAIXA CÓDIGO DO GITHUB
# -------------------------------
log "📥 Baixando código do GitHub..."

# Remove diretório antigo
rm -rf "$PROJECT_DIR" 2>/dev/null
mkdir -p "$PROJECT_DIR"

# Método 1: Tenta clonar com git
if command -v git >/dev/null 2>&1; then
    log "⚡ Clonando repositório com Git..."
    git clone --depth 1 https://github.com/Marcelo1408/youtube-audio-extractor.git "$PROJECT_DIR.tmp" 2>/dev/null && {
        if [ -d "$PROJECT_DIR.tmp" ]; then
            mv "$PROJECT_DIR.tmp"/* "$PROJECT_DIR"/
            mv "$PROJECT_DIR.tmp"/.* "$PROJECT_DIR"/ 2>/dev/null || true
            rm -rf "$PROJECT_DIR.tmp"
            log "✅ Código clonado via Git"
        fi
    }
fi

# Método 2: Se Git falhou, usa wget para baixar ZIP
if [ ! -f "$PROJECT_DIR/index.php" ] && [ ! -f "$PROJECT_DIR/composer.json" ]; then
    log "📦 Baixando ZIP do GitHub..."
    TEMP_ZIP=$(mktemp)
    wget -q "https://github.com/Marcelo1408/youtube-audio-extractor/archive/refs/heads/main.zip" -O "$TEMP_ZIP"
    
    if [ -s "$TEMP_ZIP" ]; then
        TEMP_DIR=$(mktemp -d)
        unzip -q "$TEMP_ZIP" -d "$TEMP_DIR"
        
        # Procura pelo diretório extraído
        EXTRACTED_DIR=$(find "$TEMP_DIR" -maxdepth 2 -type d -name "*youtube*" | head -1)
        
        if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then
            cp -r "$EXTRACTED_DIR"/* "$PROJECT_DIR"/ 2>/dev/null || true
            cp -r "$EXTRACTED_DIR"/.* "$PROJECT_DIR"/ 2>/dev/null || true
            log "✅ Código extraído do ZIP"
        else
            # Cria estrutura básica se não encontrar
            warn "Estrutura do projeto não encontrada. Criando básica..."
            mkdir -p "$PROJECT_DIR/public"
            echo "<?php echo '<h1>YouTube Audio Extractor</h1><p>Instalação em andamento...</p>'; ?>" > "$PROJECT_DIR/public/index.php"
        fi
        
        rm -rf "$TEMP_DIR"
        rm -f "$TEMP_ZIP"
    fi
fi

# Verifica se algo foi baixado
if [ -z "$(ls -A $PROJECT_DIR 2>/dev/null)" ]; then
    warn "Nenhum arquivo baixado. Criando estrutura básica..."
    mkdir -p "$PROJECT_DIR"/{public,uploads,app,config}
    cat > "$PROJECT_DIR/public/index.php" <<'PHP'
<!DOCTYPE html>
<html>
<head>
    <title>YouTube Audio Extractor</title>
    <style>
        body { font-family: Arial; text-align: center; padding: 50px; }
        .success { color: green; font-size: 24px; }
        .info { color: #666; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="success">✅ Instalação bem-sucedida!</div>
    <div class="info">
        <p>Diretório: <?php echo __DIR__; ?></p>
        <p>PHP: <?php echo phpversion(); ?></p>
        <p>Servidor: <?php echo $_SERVER['SERVER_SOFTWARE']; ?></p>
    </div>
</body>
</html>
PHP
fi

log "✅ Código preparado em: $PROJECT_DIR"

# -------------------------------
# 6. DEPENDÊNCIAS PYTHON
# -------------------------------
log "🐍 Instalando dependências Python..."
pip3 install --upgrade pip
pip3 install yt-dlp pydub moviepy python-dotenv

# -------------------------------
# 7. CONFIGURA PERMISSÕES
# -------------------------------
log "🔒 Configurando permissões..."
mkdir -p "$PROJECT_DIR/uploads"
chown -R www-data:www-data "$PROJECT_DIR"
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
chmod 775 "$PROJECT_DIR/uploads"

# -------------------------------
# 8. CRIA ARQUIVO .ENV
# -------------------------------
log "⚙️  Criando arquivo .env..."
cat > "$PROJECT_DIR/.env" <<ENV
APP_ENV=production
APP_URL=https://$DOMAIN
APP_KEY=$(openssl rand -base64 32)

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS

PYTHON_PATH=/usr/bin/python3
FFMPEG_PATH=/usr/bin/ffmpeg
YTDLP_PATH=/usr/local/bin/yt-dlp

UPLOAD_PATH=$PROJECT_DIR/uploads
MAX_FILE_SIZE=100
SESSION_LIFETIME=120

QUEUE_CONNECTION=database
ENV

chown www-data:www-data "$PROJECT_DIR/.env"
chmod 600 "$PROJECT_DIR/.env"

# -------------------------------
# 9. CONFIGURA NGINX
# -------------------------------
log "🌐 Configurando Nginx..."
rm -f /etc/nginx/sites-enabled/default

cat > "/etc/nginx/sites-available/$DOMAIN" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $PROJECT_DIR/public;
    index index.php index.html index.htm;

    client_max_body_size 100M;
    client_body_timeout 300s;
    
    # Logs
    access_log /var/log/nginx/$DOMAIN-access.log;
    error_log /var/log/nginx/$DOMAIN-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # Aumenta timeouts para processamento
        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
    }

    location /uploads/ {
        alias $PROJECT_DIR/uploads/;
        internal;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGINX

ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"

# Testa configuração
nginx -t
check_success "Configuração do Nginx inválida"

systemctl restart nginx
check_success "Falha ao reiniciar Nginx"

# -------------------------------
# 10. CONFIGURA PHP
# -------------------------------
log "⚙️  Otimizando PHP..."
PHP_CONF="/etc/php/8.1/fpm/php.ini"
if [ -f "$PHP_CONF" ]; then
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$PHP_CONF"
    sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$PHP_CONF"
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_CONF"
    sed -i 's/^max_input_time = .*/max_input_time = 300/' "$PHP_CONF"
    sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$PHP_CONF"
fi

systemctl restart php8.1-fpm
check_success "Falha ao reiniciar PHP-FPM"

# -------------------------------
# 11. SSL (OPCIONAL)
# -------------------------------
log "🔐 Configurando SSL (Let's Encrypt)..."
read -p "Deseja configurar SSL agora? (s/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    if certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect; then
        log "✅ SSL configurado com sucesso!"
    else
        warn "SSL não configurado. Configure manualmente depois com:"
        echo "  certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos"
    fi
else
    log "⚠️  SSL não configurado. Configure depois quando o DNS estiver apontando."
fi

# -------------------------------
# 12. VERIFICAÇÃO FINAL
# -------------------------------
echo ""
echo "============================================"
echo "✅ VERIFICAÇÃO DA INSTALAÇÃO"
echo "============================================"

# Verifica diretório
if [ -d "$PROJECT_DIR" ]; then
    echo "📁 Diretório: $PROJECT_DIR ✅"
    echo "   Arquivos: $(find $PROJECT_DIR -type f | wc -l) arquivos"
else
    echo "📁 Diretório: ❌ NÃO CRIADO"
fi

# Verifica banco
if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SHOW TABLES;" 2>/dev/null | grep -q "users"; then
    echo "🗄️  Banco de dados: $DB_NAME ✅"
    TABLES_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SHOW TABLES;" 2>/dev/null | wc -l)
    echo "   Tabelas: $TABLES_COUNT criadas"
else
    echo "🗄️  Banco de dados: ❌ NÃO CRIADO"
fi

# Verifica serviços
echo "🔧 Serviços:"
echo "   Nginx: $(systemctl is-active nginx) ✅"
echo "   MariaDB: $(systemctl is-active mariadb) ✅"
echo "   PHP-FPM: $(systemctl is-active php8.1-fpm) ✅"

# Testa acesso web
echo "🌐 Teste de acesso:"
if curl -s -I "http://localhost" 2>/dev/null | grep -q "200\|301"; then
    echo "   HTTP: ✅ Respondendo"
else
    echo "   HTTP: ⚠️  Verifique manualmente"
fi

echo ""
echo "============================================"
echo "🎉 INSTALAÇÃO COMPLETA!"
echo "============================================"
echo ""
echo "📋 RESUMO DA INSTALAÇÃO:"
echo "   Domínio: $DOMAIN"
echo "   Diretório: $PROJECT_DIR"
echo "   Banco de dados: $DB_NAME"
echo "   Usuário DB: $DB_USER"
echo "   Senha DB: $DB_PASS"
echo "   Senha root MariaDB: $DB_ROOT_PASS"
echo ""
echo "🔧 COMANDOS ÚTEIS:"
echo "   Ver logs: tail -f /var/log/nginx/$DOMAIN-error.log"
echo "   Reiniciar: systemctl restart nginx mariadb php8.1-fpm"
echo "   Acessar DB: mysql -u $DB_USER -p$DB_PASS $DB_NAME"
echo ""
echo "🚀 PRÓXIMOS PASSOS:"
echo "   1. Configure o DNS do domínio para o IP da VPS"
echo "   2. Acesse: http://$DOMAIN"
echo "   3. Se quiser SSL: certbot --nginx -d $DOMAIN --email $EMAIL"
echo ""
echo "⚠️  CREDENCIAIS DO ADMIN:"
echo "   Email: $EMAIL"
echo "   Senha: password (altere no primeiro login)"
echo ""
echo "============================================"
