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
echo "📦 Atualizando sistema..."
apt update && apt upgrade -y

# -------------------------------
# DEPENDÊNCIAS PRINCIPAIS
# -------------------------------
echo "📦 Instalando dependências principais..."
apt install -y \
nginx \
mariadb-server mariadb-client \
php php-fpm php-mysql php-cli php-curl php-zip php-mbstring php-xml php-gd \
python3 python3-pip python3-venv \
ffmpeg \
curl unzip git software-properties-common \
ufw \
certbot python3-certbot-nginx

# -------------------------------
# CONFIGURA FIREWALL (UFW)
# -------------------------------
echo "🔥 Configurando firewall..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# -------------------------------
# CONFIGURA MARIADB
# -------------------------------
echo "🗄️  Configurando MariaDB..."

# Inicia e habilita MariaDB
systemctl start mariadb
systemctl enable mariadb

# Verifica se o serviço está rodando
if ! systemctl is-active --quiet mariadb; then
    echo "❌ ERRO: MariaDB não está rodando"
    echo "Tentando reparar..."
    mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    systemctl start mariadb
fi

# Aguarda MariaDB estar pronto
sleep 3

# Executa configuração segura
mysql -u root <<EOF
-- Remove usuários anônimos
DELETE FROM mysql.user WHERE User='';
-- Remove acesso root remoto
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- Remove banco de teste
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- Atualiza senha root
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
-- Cria banco e usuário do projeto
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "✅ MariaDB configurado com sucesso!"

# -------------------------------
# PYTHON DEPENDÊNCIAS EM VIRTUAL ENV
# -------------------------------
echo "🐍 Configurando ambiente Python..."
mkdir -p /opt/audio_extractor
python3 -m venv /opt/audio_extractor/venv
source /opt/audio_extractor/venv/bin/activate

pip install --upgrade pip
pip install yt-dlp pydub moviepy python-dotenv

# Cria link simbólico para facilitar acesso
ln -sf /opt/audio_extractor/venv/bin/python3 /usr/local/bin/audio-extractor-python
ln -sf /opt/audio_extractor/venv/bin/yt-dlp /usr/local/bin/audio-extractor-ytdlp

deactivate

# -------------------------------
# IMPORTA SQL (SE EXISTIR)
# -------------------------------
echo "📊 Importando estrutura do banco de dados..."
if [ -f "sql/database.sql" ]; then
  mysql -u $DB_USER -p$DB_PASS $DB_NAME < sql/database.sql
  echo "✅ Banco de dados importado!"
else
  echo "⚠️  Aviso: sql/database.sql não encontrado"
  echo "Criando tabelas manualmente..."
  
  mysql -u $DB_USER -p$DB_PASS $DB_NAME <<SQL
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    credits INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS downloads (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    youtube_url VARCHAR(500) NOT NULL,
    audio_file VARCHAR(255),
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(128) PRIMARY KEY,
    user_id INT,
    expires TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL
fi

# -------------------------------
# MOVE PROJETO
# -------------------------------
echo "📁 Configurando diretório do projeto..."
mkdir -p $PROJECT_DIR

# Copia arquivos mantendo estrutura
rsync -av --exclude={'install.sh','README.md','.git'} ./ $PROJECT_DIR/

# -------------------------------
# PERMISSÕES
# -------------------------------
echo "🔒 Ajustando permissões..."
chown -R www-data:www-data $PROJECT_DIR
chmod -R 755 $PROJECT_DIR
find $PROJECT_DIR -type f -exec chmod 644 {} \;
find $PROJECT_DIR -type d -exec chmod 755 {} \;

# Diretórios de upload e cache
mkdir -p $PROJECT_DIR/uploads
mkdir -p $PROJECT_DIR/cache
chown -R www-data:www-data $PROJECT_DIR/uploads $PROJECT_DIR/cache
chmod -R 775 $PROJECT_DIR/uploads $PROJECT_DIR/cache

# -------------------------------
# GERAR .ENV
# -------------------------------
echo "⚙️  Criando arquivo de configuração..."
cat <<EOF > $PROJECT_DIR/.env
APP_ENV=production
APP_URL=https://$DOMAIN
APP_KEY=$(openssl rand -base64 32)

DB_HOST=localhost
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS

PYTHON_PATH=/opt/audio_extractor/venv/bin/python3
FFMPEG_PATH=/usr/bin/ffmpeg
YTDLP_PATH=/opt/audio_extractor/venv/bin/yt-dlp

UPLOAD_DIR=$PROJECT_DIR/uploads
MAX_FILE_SIZE=50M
ALLOWED_AUDIO_FORMATS=mp3,wav,m4a

SESSION_LIFETIME=120
EOF

chown www-data:www-data $PROJECT_DIR/.env
chmod 600 $PROJECT_DIR/.env

# -------------------------------
# CONFIGURA NGINX
# -------------------------------
echo "🌐 Configurando Nginx..."

# Remove configuração default
rm -f /etc/nginx/sites-enabled/default

cat <<EOF > /etc/nginx/sites-available/$DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $PROJECT_DIR/public;
    index index.php index.html index.htm;

    client_max_body_size 50M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    location /uploads/ {
        internal;
        alias $PROJECT_DIR/uploads/;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
nginx -t

# -------------------------------
# CONFIGURA PHP-FPM
# -------------------------------
echo "⚙️  Otimizando PHP-FPM..."
PHP_CONF="/etc/php/8.1/fpm/php.ini"
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 50M/' $PHP_CONF
sed -i 's/^post_max_size = .*/post_max_size = 50M/' $PHP_CONF
sed -i 's/^max_execution_time = .*/max_execution_time = 300/' $PHP_CONF
sed -i 's/^memory_limit = .*/memory_limit = 256M/' $PHP_CONF

systemctl restart php8.1-fpm

# -------------------------------
# SSL LETS ENCRYPT
# -------------------------------
echo "🔐 Configurando SSL..."
if certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive --redirect; then
    echo "✅ SSL configurado com sucesso!"
else
    echo "⚠️  Não foi possível obter SSL. Configure manualmente com:"
    echo "certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos"
fi

# -------------------------------
# CRON PARA RENOVAÇÃO SSL
# -------------------------------
echo "⏰ Configurando cron para renovação SSL..."
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

# -------------------------------
# SISTEMA DE LOGS
# -------------------------------
echo "📝 Configurando sistema de logs..."
mkdir -p /var/log/audio-extractor
touch /var/log/audio-extractor/{app.log,error.log,processing.log}
chown -R www-data:www-data /var/log/audio-extractor
chmod -R 755 /var/log/audio-extractor

# Adiciona logrotate
cat <<EOF > /etc/logrotate.d/audio-extractor
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
        systemctl reload php8.1-fpm > /dev/null 2>&1 || true
    endscript
}
EOF

# -------------------------------
# SCRIPT DE MONITORAMENTO
# -------------------------------
cat <<'EOF' > /usr/local/bin/monitor-audio-extractor
#!/bin/bash
echo "=== MONITORAMENTO AUDIO EXTRACTOR ==="
echo "Data: $(date)"
echo ""
echo "📦 Serviços:"
systemctl is-active nginx mariadb php8.1-fpm | grep -E "active|failed" | while read service; do
    echo "  $service"
done
echo ""
echo "💾 Espaço em disco:"
df -h /var/www
echo ""
echo "🗄️  Banco de dados:"
mysql -u $DB_USER -p$DB_PASS -e "SELECT COUNT(*) as total_users FROM users; SELECT COUNT(*) as total_downloads FROM downloads;" $DB_NAME 2>/dev/null || echo "  Não conectado"
echo ""
echo "📊 Downloads recentes:"
find /var/www/*/uploads -name "*.mp3" -type f 2>/dev/null | wc -l | xargs echo "  Arquivos MP3:"
EOF

chmod +x /usr/local/bin/monitor-audio-extractor

# -------------------------------
# REINICIA SERVIÇOS
# -------------------------------
echo "🔄 Reiniciando serviços..."
systemctl restart nginx
systemctl restart php8.1-fpm
systemctl restart mariadb

# -------------------------------
# TESTE DO SISTEMA
# -------------------------------
echo "🧪 Realizando testes do sistema..."

# Testa Python
if /opt/audio_extractor/venv/bin/python3 -c "import yt_dlp, pydub, moviepy; print('✅ Python OK')"; then
    echo "✅ Python dependências OK"
else
    echo "⚠️  Problema com dependências Python"
fi

# Testa conexão com banco
if mysql -u $DB_USER -p$DB_PASS -e "SELECT 1;" $DB_NAME >/dev/null 2>&1; then
    echo "✅ Conexão com banco OK"
else
    echo "❌ ERRO: Não foi possível conectar ao banco"
fi

# Testa Nginx
if curl -s -I http://localhost | grep -q "200\|301"; then
    echo "✅ Nginx respondendo"
else
    echo "⚠️  Nginx pode não estar respondendo"
fi

# -------------------------------
# FINALIZAÇÃO
# -------------------------------
echo "============================================"
echo " 🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "============================================"
echo ""
echo "🌐 URL do site: https://$DOMAIN"
echo ""
echo "🔑 CREDENCIAIS DE ACESSO:"
echo "   MariaDB Root: $DB_ROOT_PASS"
echo "   Banco de dados: $DB_NAME"
echo "   Usuário DB: $DB_USER"
echo "   Senha DB: $DB_PASS"
echo ""
echo "📁 DIRETÓRIOS:"
echo "   Projeto: $PROJECT_DIR"
echo "   Uploads: $PROJECT_DIR/uploads"
echo "   Python: /opt/audio_extractor/venv/"
echo "   Logs: /var/log/audio-extractor/"
echo ""
echo "⚙️  COMANDOS ÚTEIS:"
echo "   Monitorar: monitor-audio-extractor"
echo "   Reiniciar tudo: systemctl restart nginx mariadb php8.1-fpm"
echo "   Ver logs: tail -f /var/log/audio-extractor/app.log"
echo "   Ambiente Python: source /opt/audio_extractor/venv/bin/activate"
echo ""
echo "🔒 PRÓXIMOS PASSOS RECOMENDADOS:"
echo "   1. Acesse https://$DOMAIN"
echo "   2. Crie um usuário administrador"
echo "   3. Configure backups automáticos"
echo "   4. Monitore os logs regularmente"
echo ""
echo "============================================"
