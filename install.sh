#!/bin/bash

set -e

echo "============================================"
echo " YouTube Audio Extractor - Instalador VPS"
echo " Ubuntu 22.04 | MariaDB | Produção"
echo "============================================"

# -------------------------------
# ENTRADAS DO USUÁRIO
# -------------------------------
read -p "Digite o domínio (ex: audioextractor.seudominio.com): " DOMAIN
read -p "Digite o e-mail para SSL (Let's Encrypt): " EMAIL
read -p "Digite a senha ROOT do MariaDB: " DB_ROOT_PASS
read -p "Digite o nome do banco de dados: " DB_NAME
read -p "Digite o usuário do banco: " DB_USER
read -p "Digite a senha do banco: " DB_PASS

PROJECT_DIR="/var/www/$DOMAIN"

# -------------------------------
# ATUALIZA SISTEMA
# -------------------------------
echo "🔄 Atualizando sistema..."
apt update && apt upgrade -y

# -------------------------------
# DEPENDÊNCIAS PRINCIPAIS (COM MARIADB)
# -------------------------------
echo "📦 Instalando dependências..."
apt install -y \
    nginx \
    mariadb-server mariadb-client \
    php8.1 php8.1-fpm php8.1-mysql php8.1-cli php8.1-curl php8.1-zip \
    php8.1-mbstring php8.1-xml php8.1-gd \
    python3 python3-pip \
    ffmpeg \
    curl unzip git software-properties-common \
    certbot python3-certbot-nginx

# -------------------------------
# CONFIGURA MARIADB
# -------------------------------
echo "🗄️  Configurando MariaDB..."

# Inicia e habilita MariaDB
systemctl start mariadb
systemctl enable mariadb

# Aguarda MariaDB iniciar
sleep 3

# Configuração segura do MariaDB
echo "🔒 Executando configuração inicial do MariaDB..."
mysql -u root <<EOF
-- Define senha root
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

# Cria banco e usuário para a aplicação
echo "📊 Criando banco de dados '$DB_NAME'..."
mysql -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "✅ MariaDB configurado!"

# -------------------------------
# BAIXAR CÓDIGO DO GITHUB
# -------------------------------
echo "📥 Baixando código do GitHub..."

GITHUB_ZIP_URL="https://github.com/Marcelo1408/youtube-audio-extractor/archive/refs/heads/main.zip"

if [ -d "$PROJECT_DIR" ]; then
    echo "🧹 Limpando instalação anterior..."
    rm -rf "$PROJECT_DIR"
fi

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "⬇️  Baixando de: $GITHUB_ZIP_URL"
wget --quiet "$GITHUB_ZIP_URL" -O source.zip

# Verifica se o download foi bem sucedido
if [ ! -s "source.zip" ]; then
    echo "❌ Download falhou. Tentando com curl..."
    curl -L "$GITHUB_ZIP_URL" -o source.zip || {
        echo "❌ ERRO: Não foi possível baixar o código do GitHub"
        exit 1
    }
fi

echo "📦 Extraindo arquivos..."
unzip -q source.zip

# Encontra diretório extraído
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "youtube-audio-extractor*" | head -n 1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "🔍 Procurando qualquer diretório extraído..."
    EXTRACTED_DIR=$(find . -maxdepth 1 -type d ! -name "." | head -n 1)
fi

if [ -z "$EXTRACTED_DIR" ]; then
    echo "❌ ERRO: Nenhum diretório encontrado no ZIP"
    echo "Conteúdo do ZIP:"
    unzip -l source.zip
    exit 1
fi

echo "✅ Encontrado: $EXTRACTED_DIR"

# Move para diretório final
mkdir -p "$PROJECT_DIR"
mv "$EXTRACTED_DIR"/* "$PROJECT_DIR"/ 2>/dev/null
mv "$EXTRACTED_DIR"/.??* "$PROJECT_DIR"/ 2>/dev/null || true

cd /
rm -rf "$TEMP_DIR"

echo "✅ Código instalado em: $PROJECT_DIR"

# -------------------------------
# PYTHON DEPENDÊNCIAS
# -------------------------------
echo "🐍 Instalando dependências Python..."
pip3 install --upgrade pip
pip3 install yt-dlp pydub moviepy python-dotenv

# -------------------------------
# PERMISSÕES
# -------------------------------
echo "🔒 Ajustando permissões..."
chown -R www-data:www-data "$PROJECT_DIR"
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;

# Cria diretório de uploads
mkdir -p "$PROJECT_DIR/uploads"
chown www-data:www-data "$PROJECT_DIR/uploads"
chmod 775 "$PROJECT_DIR/uploads"

# -------------------------------
# ARQUIVO .ENV
# -------------------------------
echo "⚙️  Criando arquivo .env..."
cat <<EOF > "$PROJECT_DIR/.env"
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
MAX_FILE_SIZE=50M
EOF

chown www-data:www-data "$PROJECT_DIR/.env"
chmod 600 "$PROJECT_DIR/.env"

# -------------------------------
# CONFIGURA NGINX
# -------------------------------
echo "🌐 Configurando Nginx..."

# Remove configuração default
rm -f /etc/nginx/sites-enabled/default

cat <<EOF > "/etc/nginx/sites-available/$DOMAIN"
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $PROJECT_DIR;
    index index.php index.html index.htm;

    client_max_body_size 50M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"

# Testa configuração
nginx -t

echo "✅ Nginx configurado!"

# -------------------------------
# CONFIGURA PHP-FPM
# -------------------------------
echo "⚙️  Otimizando PHP-FPM..."

PHP_CONF_FILE="/etc/php/8.1/fpm/php.ini"
if [ -f "$PHP_CONF_FILE" ]; then
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 50M/' "$PHP_CONF_FILE"
    sed -i 's/^post_max_size = .*/post_max_size = 50M/' "$PHP_CONF_FILE"
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_CONF_FILE"
    echo "✅ Configuração PHP ajustada"
fi

systemctl restart php8.1-fpm

# -------------------------------
# SSL LETS ENCRYPT
# -------------------------------
echo "🔐 Configurando SSL..."

# Reinicia Nginx primeiro
systemctl restart nginx
sleep 2

# Tenta obter certificado
if certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect 2>/dev/null; then
    echo "✅ SSL configurado com sucesso!"
else
    echo "⚠️  SSL não configurado automaticamente"
    echo "   Configure manualmente depois com:"
    echo "   certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos"
fi

# -------------------------------
# REINICIA SERVIÇOS
# -------------------------------
echo "🔄 Reiniciando serviços..."
systemctl restart nginx
systemctl restart php8.1-fpm
systemctl restart mariadb

# -------------------------------
# FINALIZAÇÃO
# -------------------------------
echo ""
echo "============================================"
echo "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "============================================"
echo ""
echo "🌐 URL: https://$DOMAIN"
echo "📁 Diretório: $PROJECT_DIR"
echo "🗄️  Banco de dados: $DB_NAME"
echo "👤 Usuário DB: $DB_USER"
echo "🔐 Senha root MariaDB: $DB_ROOT_PASS"
echo ""
echo "⚙️  Serviços instalados:"
echo "   - Nginx"
echo "   - MariaDB"
echo "   - PHP 8.1"
echo "   - Python 3 + yt-dlp"
echo "   - FFmpeg"
echo ""
echo "🔧 Comandos úteis:"
echo "   systemctl status nginx mariadb php8.1-fpm"
echo "   tail -f /var/log/nginx/error.log"
echo "   mysql -u $DB_USER -p$DB_PASS $DB_NAME"
echo ""
echo "============================================"
