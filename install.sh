#!/bin/bash

set -e

echo "============================================"
echo "INSTALADOR YOUTUBE AUDIO EXTRACTOR - VPS"
echo "============================================"

# -------------------------------------------------
# 1. PERGUNTAS DO USUÁRIO
# -------------------------------------------------
echo ""
echo "📝 CONFIGURAÇÃO DO SITE:"
read -p "Digite o DOMÍNIO (ex: audio.seusite.com): " DOMAIN
read -p "Digite seu EMAIL para SSL: " EMAIL

echo ""
echo "🔐 CONFIGURAÇÃO DO BANCO DE DADOS:"
read -p "Senha ROOT do MariaDB: " DB_ROOT_PASS
read -p "Senha do usuário: " DB_PASS
read -p "Nome do banco (ex: youtube_extractor): " DB_NAME
read -p "Usuário do banco: " DB_USER


# -------------------------------------------------
# 2. VARIÁVEIS DO SISTEMA
# -------------------------------------------------
PROJECT_DIR="/var/www/$DOMAIN"
LOG_FILE="/tmp/install_$(date +%Y%m%d_%H%M%S).log"

echo "📋 RESUMO DA INSTALAÇÃO:" | tee -a "$LOG_FILE"
echo "  Domínio: $DOMAIN" | tee -a "$LOG_FILE"
echo "  Email: $EMAIL" | tee -a "$LOG_FILE"
echo "  Diretório: $PROJECT_DIR" | tee -a "$LOG_FILE"
echo "  Banco: $DB_NAME" | tee -a "$LOG_FILE"
echo "  Usuário DB: $DB_USER" | tee -a "$LOG_FILE"
echo "============================================" | tee -a "$LOG_FILE"

# -------------------------------------------------
# 3. ATUALIZAÇÃO DO SISTEMA
# -------------------------------------------------
echo "🔄 Atualizando sistema..." | tee -a "$LOG_FILE"
sudo apt-get update 2>&1 | tee -a "$LOG_FILE"
sudo apt-get upgrade -y 2>&1 | tee -a "$LOG_FILE"

# -------------------------------------------------
# 4. INSTALA DEPENDÊNCIAS
# -------------------------------------------------
echo "📦 Instalando dependências..." | tee -a "$LOG_FILE"
sudo apt-get install -y \
    nginx \
    mariadb-server mariadb-client \
    php8.1 php8.1-fpm php8.1-mysql php8.1-cli php8.1-curl php8.1-zip \
    php8.1-mbstring php8.1-xml php8.1-gd \
    python3 python3-pip \
    ffmpeg \
    curl wget unzip git \
    certbot python3-certbot-nginx 2>&1 | tee -a "$LOG_FILE"

# -------------------------------------------------
# 5. CONFIGURA MARIADB
# -------------------------------------------------
echo "🗄️  Configurando MariaDB..." | tee -a "$LOG_FILE"
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Configura senha root
echo "🔐 Definindo senha root do MariaDB..." | tee -a "$LOG_FILE"
sudo mysql -u root <<EOF 2>&1 | tee -a "$LOG_FILE"
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
FLUSH PRIVILEGES;
EOF

# Cria banco e usuário
echo "📊 Criando banco de dados '$DB_NAME'..." | tee -a "$LOG_FILE"
sudo mysql -u root -p"$DB_ROOT_PASS" <<EOF 2>&1 | tee -a "$LOG_FILE"
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# -------------------------------------------------
# 6. CRIA TABELAS DO BANCO (SQL COMPLETO)
# -------------------------------------------------
echo "📝 Criando tabelas do banco de dados..." | tee -a "$LOG_FILE"
sudo mysql -u root -p"$DB_ROOT_PASS" $DB_NAME <<'SQL' 2>&1 | tee -a "$LOG_FILE"
-- Tabela users
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
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela processes
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
  KEY `user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela settings
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

-- Insere usuário admin
INSERT INTO `users` (`username`, `email`, `password`, `role`, `plan`, `email_verified`) VALUES
('admin', 'admin@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin', 'enterprise', 1);

-- Insere configurações
INSERT INTO `settings` (`setting_key`, `setting_value`, `description`, `is_public`) VALUES
('site_name', 'YouTube Audio Extractor', 'Nome do site', 1),
('site_description', 'Extraia áudio de vídeos do YouTube', 'Descrição do site', 1),
('max_video_size', '1073741824', 'Tamanho máximo em bytes', 1),
('enable_registration', '1', 'Permitir novos registros', 1);
SQL

# -------------------------------------------------
# 7. CRIA DIRETÓRIO DO PROJETO
# -------------------------------------------------
echo "📁 Criando diretório do projeto..." | tee -a "$LOG_FILE"
sudo rm -rf "$PROJECT_DIR" 2>/dev/null
sudo mkdir -p "$PROJECT_DIR"
sudo chown -R $USER:$USER "$PROJECT_DIR"

# -------------------------------------------------
# 8. BAIXA ARQUIVOS DO GITHUB
# -------------------------------------------------
echo "📥 Baixando arquivos do GitHub..." | tee -a "$LOG_FILE"
cd "$PROJECT_DIR"

# Tenta git clone primeiro
if command -v git >/dev/null; then
    echo "⚡ Usando Git para clonar..." | tee -a "$LOG_FILE"
    git clone https://github.com/Marcelo1408/youtube-audio-extractor.git . 2>&1 | tee -a "$LOG_FILE" || {
        echo "⚠️  Git falhou, usando download direto..." | tee -a "$LOG_FILE"
        wget -q https://github.com/Marcelo1408/youtube-audio-extractor/archive/main.zip -O site.zip
        unzip -q site.zip
        mv youtube-audio-extractor-main/* .
        mv youtube-audio-extractor-main/.* . 2>/dev/null || true
        rm -rf youtube-audio-extractor-main site.zip
    }
else
    echo "📦 Baixando via wget..." | tee -a "$LOG_FILE"
    wget -q https://github.com/Marcelo1408/youtube-audio-extractor/archive/main.zip -O site.zip
    unzip -q site.zip
    mv youtube-audio-extractor-main/* .
    mv youtube-audio-extractor-main/.* . 2>/dev/null || true
    rm -rf youtube-audio-extractor-main site.zip
fi

# -------------------------------------------------
# 9. INSTALA DEPENDÊNCIAS PYTHON
# -------------------------------------------------
echo "🐍 Instalando Python dependencies..." | tee -a "$LOG_FILE"
sudo pip3 install yt-dlp pydub moviepy python-dotenv 2>&1 | tee -a "$LOG_FILE"

# -------------------------------------------------
# 10. CONFIGURA PERMISSÕES
# -------------------------------------------------
echo "🔒 Configurando permissões..." | tee -a "$LOG_FILE"
sudo mkdir -p "$PROJECT_DIR/uploads"
sudo chown -R www-data:www-data "$PROJECT_DIR"
sudo find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
sudo find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
sudo chmod 775 "$PROJECT_DIR/uploads"

# -------------------------------------------------
# 11. CRIA ARQUIVO .ENV
# -------------------------------------------------
echo "⚙️  Criando arquivo .env..." | tee -a "$LOG_FILE"
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
MAX_FILE_SIZE=50M
SESSION_LIFETIME=120
ENV

sudo chown www-data:www-data "$PROJECT_DIR/.env"
sudo chmod 600 "$PROJECT_DIR/.env"

# -------------------------------------------------
# 12. CONFIGURA NGINX
# -------------------------------------------------
echo "🌐 Configurando Nginx..." | tee -a "$LOG_FILE"
sudo rm -f /etc/nginx/sites-enabled/default

sudo cat > "/etc/nginx/sites-available/$DOMAIN" <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    root $PROJECT_DIR;
    index index.php index.html;

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
NGINX

sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"
sudo nginx -t 2>&1 | tee -a "$LOG_FILE"
sudo systemctl restart nginx 2>&1 | tee -a "$LOG_FILE"

# -------------------------------------------------
# 13. CONFIGURA PHP-FPM
# -------------------------------------------------
echo "⚙️  Configurando PHP..." | tee -a "$LOG_FILE"
sudo systemctl restart php8.1-fpm 2>&1 | tee -a "$LOG_FILE"

# -------------------------------------------------
# 14. SSL (LET'S ENCRYPT)
# -------------------------------------------------
echo "🔐 Configurando SSL (Let's Encrypt)..." | tee -a "$LOG_FILE"
echo "📌 NOTA: O SSL só funcionará quando o DNS estiver configurado." | tee -a "$LOG_FILE"
echo "Para configurar SSL depois, execute:" | tee -a "$LOG_FILE"
echo "  sudo certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos" | tee -a "$LOG_FILE"

# -------------------------------------------------
# 15. VERIFICAÇÃO FINAL
# -------------------------------------------------
echo ""
echo "============================================"
echo "✅ VERIFICAÇÃO DA INSTALAÇÃO"
echo "============================================"

echo "📁 Diretório do projeto:" | tee -a "$LOG_FILE"
if [ -d "$PROJECT_DIR" ]; then
    echo "  ✅ $PROJECT_DIR (EXISTE)" | tee -a "$LOG_FILE"
    echo "  📊 $(ls -la "$PROJECT_DIR" | wc -l) itens" | tee -a "$LOG_FILE"
else
    echo "  ❌ $PROJECT_DIR (NÃO EXISTE)" | tee -a "$LOG_FILE"
fi

echo ""
echo "🗄️  Banco de dados:" | tee -a "$LOG_FILE"
if sudo mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SHOW TABLES;" 2>/dev/null | grep -q "users"; then
    echo "  ✅ $DB_NAME (EXISTE)" | tee -a "$LOG_FILE"
    TABLES=$(sudo mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SHOW TABLES;" 2>/dev/null | wc -l)
    echo "  📊 $TABLES tabelas criadas" | tee -a "$LOG_FILE"
else
    echo "  ❌ $DB_NAME (NÃO CRIADO)" | tee -a "$LOG_FILE"
fi

echo ""
echo "🔧 Serviços:" | tee -a "$LOG_FILE"
echo "  Nginx: $(sudo systemctl is-active nginx)" | tee -a "$LOG_FILE"
echo "  MariaDB: $(sudo systemctl is-active mariadb)" | tee -a "$LOG_FILE"
echo "  PHP-FPM: $(sudo systemctl is-active php8.1-fpm)" | tee -a "$LOG_FILE"

echo ""
echo "🌐 Teste de acesso:" | tee -a "$LOG_FILE"
if curl -s -I "http://localhost" 2>/dev/null | grep -q "200\|301"; then
    echo "  ✅ HTTP respondendo" | tee -a "$LOG_FILE"
else
    echo "  ⚠️  Verifique: sudo systemctl status nginx" | tee -a "$LOG_FILE"
fi

echo ""
echo "============================================"
echo "🎉 INSTALAÇÃO COMPLETA!"
echo "============================================"
echo ""
echo "📋 RESUMO:" | tee -a "$LOG_FILE"
echo "  Domínio: $DOMAIN" | tee -a "$LOG_FILE"
echo "  Diretório: $PROJECT_DIR" | tee -a "$LOG_FILE"
echo "  Banco: $DB_NAME" | tee -a "$LOG_FILE"
echo "  Usuário DB: $DB_USER" | tee -a "$LOG_FILE"
echo "  Senha DB: $DB_PASS" | tee -a "$LOG_FILE"
echo "  Senha root MariaDB: $DB_ROOT_PASS" | tee -a "$LOG_FILE"
echo ""
echo "🔧 COMANDOS ÚTEIS:" | tee -a "$LOG_FILE"
echo "  Ver logs: sudo tail -f $LOG_FILE" | tee -a "$LOG_FILE"
echo "  Acessar banco: mysql -u $DB_USER -p$DB_PASS $DB_NAME" | tee -a "$LOG_FILE"
echo "  Ver arquivos: ls -la $PROJECT_DIR" | tee -a "$LOG_FILE"
echo ""
echo "🚀 PRÓXIMOS PASSOS:" | tee -a "$LOG_FILE"
echo "  1. Configure DNS para apontar $DOMAIN para seu IP" | tee -a "$LOG_FILE"
echo "  2. Acesse: http://$DOMAIN" | tee -a "$LOG_FILE"
echo "  3. Para SSL: sudo certbot --nginx -d $DOMAIN --email $EMAIL" | tee -a "$LOG_FILE"
echo ""
echo "⚠️  CREDENCIAIS ADMIN:" | tee -a "$LOG_FILE"
echo "  Email: admin@example.com" | tee -a "$LOG_FILE"
echo "  Senha: password" | tee -a "$LOG_FILE"
echo ""
echo "📝 Log completo em: $LOG_FILE" | tee -a "$LOG_FILE"
echo "============================================" | tee -a "$LOG_FILE"
