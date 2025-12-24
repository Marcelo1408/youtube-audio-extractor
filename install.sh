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
php php-fpm php-mysql php-cli php-curl php-zip php-mbstring php-xml \
python3 python3-pip \
ffmpeg \
curl unzip git software-properties-common \
certbot python3-certbot-nginx

# -------------------------------
# PYTHON DEPENDÊNCIAS
# -------------------------------
pip3 install --upgrade pip
pip3 install yt-dlp pydub moviepy

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
# IMPORTA SQL
# -------------------------------
if [ -f "sql/database.sql" ]; then
  mysql -u $DB_USER -p$DB_PASS $DB_NAME < sql/database.sql
else
  echo "❌ ERRO: sql/database.sql não encontrado"
  exit 1
fi

# -------------------------------
# MOVE PROJETO
# -------------------------------
mkdir -p $PROJECT_DIR
rsync -av --exclude=install.sh ./ $PROJECT_DIR

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
# CRON SSL
# -------------------------------
systemctl enable certbot.timer

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
