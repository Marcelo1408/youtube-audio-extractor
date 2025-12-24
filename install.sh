#!/bin/bash

set -e

echo "============================================"
echo "INSTALADOR YOUTUBE AUDIO EXTRACTOR - VPS"
echo "============================================"

# -------------------------------------------------
# 1. CONFIGURAÇÃO PARA EVITAR PERGUNTAS
# -------------------------------------------------
# Configura para não fazer perguntas durante a instalação
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# -------------------------------------------------
# 2. PERGUNTAS DO USUÁRIO
# -------------------------------------------------
echo ""
echo "📝 CONFIGURAÇÃO DO SITE:"
read -p "Digite o DOMÍNIO (ex: audio.seusite.com): " DOMAIN
read -p "Digite seu EMAIL para SSL: " EMAIL

echo ""
echo "🔐 CONFIGURAÇÃO DO BANCO DE DADOS:"
read -p "Senha ROOT do MariaDB: " DB_ROOT_PASS
read -p "Nome do banco (ex: youtube_extractor): " DB_NAME
read -p "Usuário do banco: " DB_USER
read -p "Senha do usuário: " DB_PASS

# -------------------------------------------------
# 3. VARIÁVEIS
# -------------------------------------------------
PROJECT_DIR="/var/www/$DOMAIN"

echo "📋 RESUMO:"
echo "  Domínio: $DOMAIN"
echo "  Email: $EMAIL"
echo "  Diretório: $PROJECT_DIR"
echo "  Banco: $DB_NAME"
echo "============================================"

# -------------------------------------------------
# 4. PREPARAÇÃO DO SISTEMA (SEM PERGUNTAS)
# -------------------------------------------------
echo "🔄 Preparando sistema..."
# Configura para manter versões locais dos arquivos
echo 'libc6 libraries/restart-without-asking boolean true' | sudo debconf-set-selections
echo 'openssh-server openssh-server/permit-root-login boolean true' | sudo debconf-set-selections
echo 'mariadb-server mysql-server/root_password password '$DB_ROOT_PASS | sudo debconf-set-selections
echo 'mariadb-server mysql-server/root_password_again password '$DB_ROOT_PASS | sudo debconf-set-selections

# Limpa locks
sudo rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock 2>/dev/null
sudo dpkg --configure -a

# -------------------------------------------------
# 5. ATUALIZAÇÃO (SEM PERGUNTAS)
# -------------------------------------------------
echo "📦 Atualizando repositórios..."
sudo apt-get update -yq

# -------------------------------------------------
# 6. INSTALA DEPENDÊNCIAS (SEM PERGUNTAS)
# -------------------------------------------------
echo "📦 Instalando Nginx, MariaDB, PHP..."
sudo apt-get install -yq \
    nginx \
    mariadb-server mariadb-client \
    php8.1 php8.1-fpm php8.1-mysql php8.1-cli php8.1-curl php8.1-zip \
    php8.1-mbstring php8.1-xml php8.1-gd \
    python3 python3-pip \
    ffmpeg \
    curl wget unzip git \
    certbot python3-certbot-nginx

# Força configuração do SSH sem perguntas
echo "🔧 Configurando SSH..."
sudo apt-get install -yq --reinstall openssh-server
echo 'openssh-server openssh-server/sshd_config_preserve_local string keep' | sudo debconf-set-selections

# -------------------------------------------------
# 7. CONFIGURA MARIADB
# -------------------------------------------------
echo "🗄️  Configurando MariaDB..."
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Configura senha root
sudo mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
FLUSH PRIVILEGES;
EOF

# Cria banco e usuário
sudo mysql -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# -------------------------------------------------
# 8. CRIA TABELAS DO BANCO
# -------------------------------------------------
echo "📝 Criando tabelas..."
sudo mysql -u root -p"$DB_ROOT_PASS" $DB_NAME <<'SQL'
CREATE TABLE IF NOT EXISTS users (
  id int(11) NOT NULL AUTO_INCREMENT,
  username varchar(50) NOT NULL,
  email varchar(100) NOT NULL,
  password varchar(255) NOT NULL,
  role enum('user','admin','moderator') DEFAULT 'user',
  plan enum('free','premium','enterprise') DEFAULT 'free',
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY username (username),
  UNIQUE KEY email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO users (username, email, password, role, plan) VALUES
('admin', 'admin@example.com', '\$2y\$10\$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin', 'enterprise');
SQL

# -------------------------------------------------
# 9. CRIA DIRETÓRIO DO PROJETO
# -------------------------------------------------
echo "📁 Criando diretório $PROJECT_DIR..."
sudo rm -rf "$PROJECT_DIR" 2>/dev/null
sudo mkdir -p "$PROJECT_DIR"
sudo chown -R $USER:$USER "$PROJECT_DIR"

# -------------------------------------------------
# 10. BAIXA ARQUIVOS DO GITHUB
# -------------------------------------------------
echo "📥 Baixando do GitHub..."
cd "$PROJECT_DIR"

# Tenta wget primeiro (mais confiável)
wget -q https://github.com/Marcelo1408/youtube-audio-extractor/archive/main.zip -O site.zip
if [ -f "site.zip" ]; then
    unzip -q site.zip
    mv youtube-audio-extractor-main/* . 2>/dev/null || true
    mv youtube-audio-extractor-main/.* . 2>/dev/null || true
    rm -rf youtube-audio-extractor-main site.zip
    echo "✅ Arquivos extraídos"
else
    echo "⚠️  Download falhou, criando estrutura básica..."
    echo "<?php echo '<h1>YouTube Audio Extractor</h1><p>Site em construção</p>'; ?>" > index.php
fi

# -------------------------------------------------
# 11. DEPENDÊNCIAS PYTHON
# -------------------------------------------------
echo "🐍 Instalando Python..."
sudo pip3 install yt-dlp pydub moviepy python-dotenv

# -------------------------------------------------
# 12. PERMISSÕES
# -------------------------------------------------
echo "🔒 Permissões..."
sudo mkdir -p "$PROJECT_DIR/uploads"
sudo chown -R www-data:www-data "$PROJECT_DIR"
sudo chmod -R 755 "$PROJECT_DIR"
sudo chmod 775 "$PROJECT_DIR/uploads"

# -------------------------------------------------
# 13. ARQUIVO .ENV
# -------------------------------------------------
echo "⚙️  Criando .env..."
cat > "$PROJECT_DIR/.env" <<ENV
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
ENV

sudo chown www-data:www-data "$PROJECT_DIR/.env"
sudo chmod 600 "$PROJECT_DIR/.env"

# -------------------------------------------------
# 14. NGINX
# -------------------------------------------------
echo "🌐 Configurando Nginx..."
sudo rm -f /etc/nginx/sites-enabled/default

sudo cat > "/etc/nginx/sites-available/$DOMAIN" <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    root $PROJECT_DIR;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }
}
NGINX

sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"
sudo nginx -t && sudo systemctl restart nginx

# -------------------------------------------------
# 15. PHP
# -------------------------------------------------
echo "⚙️  PHP..."
sudo systemctl restart php8.1-fpm

# -------------------------------------------------
# 16. VERIFICAÇÃO
# -------------------------------------------------
echo ""
echo "============================================"
echo "✅ VERIFICAÇÃO"
echo "============================================"

echo "📁 Diretório: $PROJECT_DIR"
if [ -d "$PROJECT_DIR" ]; then
    echo "  Status: ✅ CRIADO"
    echo "  Arquivos: $(ls -1 "$PROJECT_DIR" | wc -l)"
else
    echo "  Status: ❌ FALHOU"
fi

echo ""
echo "🗄️  Banco: $DB_NAME"
if sudo mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" 2>/dev/null; then
    echo "  Status: ✅ CRIADO"
else
    echo "  Status: ❌ FALHOU"
fi

echo ""
echo "🔧 Serviços:"
echo "  Nginx: $(systemctl is-active nginx)"
echo "  MariaDB: $(systemctl is-active mariadb)"
echo "  PHP: $(systemctl is-active php8.1-fpm)"

echo ""
echo "============================================"
echo "🎉 INSTALAÇÃO COMPLETA!"
echo "============================================"
echo ""
echo "🌐 URL: http://$DOMAIN"
echo "📁 Diretório: $PROJECT_DIR"
echo "🗄️  Banco: $DB_NAME"
echo "👤 Usuário DB: $DB_USER"
echo "🔐 Senha DB: $DB_PASS"
echo ""
echo "🚀 Para SSL depois:"
echo "  sudo certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos"
echo "============================================"
