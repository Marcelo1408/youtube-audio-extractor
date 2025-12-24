#!/bin/bash

set -e

echo "============================================"
echo " YouTube Audio Extractor - Instalador VPS"
echo " Ubuntu 22.04 | Produção"
echo "============================================"

# -------------------------------
# ENTRADAS DO USUÁRIO
# -------------------------------
read -p "Digite o domínio (ex: audioextractor.seudominio.com): " DOMAIN
read -p "Digite o e-mail para SSL (Let's Encrypt): " EMAIL
read -p "Digite a senha ROOT do MySQL: " MYSQL_ROOT_PASS
read -p "Digite o nome do banco de dados: " DB_NAME
read -p "Digite o usuário do banco: " DB_USER
read -p "Digite a senha do banco: " DB_PASS

PROJECT_DIR="/var/www/$DOMAIN"

# -------------------------------
# ATUALIZA SISTEMA
# -------------------------------
apt update && apt upgrade -y

# -------------------------------
# DEPENDÊNCIAS PRINCIPAIS
# -------------------------------
apt install -y \
nginx \
mysql-server \
php8.1 php8.1-fpm php8.1-mysql php8.1-cli php8.1-curl php8.1-zip php8.1-mbstring php8.1-xml \
python3 python3-pip \
ffmpeg \
curl unzip git software-properties-common \
certbot python3-certbot-nginx

# -------------------------------
# CONFIGURA MYSQL
# -------------------------------
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASS';
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# -------------------------------
# BAIXAR CÓDIGO DO GITHUB
# -------------------------------
echo "📥 Baixando código do GitHub..."

GITHUB_ZIP_URL="https://github.com/Marcelo1408/youtube-audio-extractor/blob/afc1691c8aa3777e1d0471c15a25355d090615d2/youtube-audio-extractor.zip"

# Remove diretório antigo se existir
if [ -d "$PROJECT_DIR" ]; then
    echo "Removendo instalação anterior..."
    rm -rf "$PROJECT_DIR"
fi

# Cria diretório temporário
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Baixa o ZIP
echo "Baixando de: $GITHUB_ZIP_URL"
wget -q "$GITHUB_ZIP_URL" -O source.zip

# Extrai
unzip -q source.zip

# Encontra diretório extraído
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "youtube-audio-extractor*" | head -n 1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "❌ ERRO: Diretório extraído não encontrado"
    echo "Conteúdo do ZIP:"
    ls -la
    exit 1
fi

# Move para o diretório do projeto
mkdir -p "$PROJECT_DIR"
mv "$EXTRACTED_DIR"/* "$PROJECT_DIR"/

# Limpeza
cd /
rm -rf "$TEMP_DIR"

echo "✅ Código-fonte instalado em: $PROJECT_DIR"

# -------------------------------
# PYTHON DEPENDÊNCIAS
# -------------------------------
pip3 install --upgrade pip
pip3 install yt-dlp pydub moviepy

# -------------------------------
# PERMISSÕES
# -------------------------------
chown -R www-data:www-data $PROJECT_DIR
chmod -R 755 $PROJECT_DIR
chmod -R 775 $PROJECT_DIR/uploads

# -------------------------------
# GERAR .ENV
# -------------------------------
cat <<EOF > $PROJECT_DIR/.env
APP_ENV=production
APP_URL=https://$DOMAIN

DB_HOST=localhost
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS

PYTHON_PATH=/usr/bin/python3
FFMPEG_PATH=/usr/bin/ffmpeg
YTDLP_PATH=/usr/local/bin/yt-dlp
EOF

chown www-data:www-data $PROJECT_DIR/.env
chmod 600 $PROJECT_DIR/.env

# -------------------------------
# CONFIGURA NGINX
# -------------------------------
cat <<EOF > /etc/nginx/sites-available/$DOMAIN
server {
    listen 80;
    server_name $DOMAIN;
    root $PROJECT_DIR;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# -------------------------------
# SSL LETS ENCRYPT
# -------------------------------
certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive --redirect

# -------------------------------
# FINALIZAÇÃO
# -------------------------------
systemctl restart nginx
systemctl restart php8.1-fpm
systemctl restart mysql

echo "============================================"
echo " ✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO"
echo " 🌐 Site: https://$DOMAIN"
echo "============================================"
