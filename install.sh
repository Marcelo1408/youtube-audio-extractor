#!/bin/bash

# ============================================
# SCRIPT DE INSTALAÇÃO REAL - PASSO A PASSO
# ============================================

echo "============================================"
echo "INSTALADOR REAL - YOUTUBE AUDIO EXTRACTOR"
echo "============================================"

# -------------------------------------------------
# PASSO 1: PERGUNTAS ESSENCIAIS
# -------------------------------------------------
echo ""
echo "📝 DIGITE AS INFORMAÇÕES:"
echo "-------------------------"
read -p "1. Domínio (ex: audio.meusite.com): " DOMAIN
read -p "2. Email para SSL: " EMAIL
read -p "3. Senha ROOT do MariaDB: " DB_ROOT_PASS
read -p "6. Senha do usuário: " DB_PASS
read -p "4. Nome do banco de dados: " DB_NAME
read -p "5. Usuário do banco: " DB_USER


# -------------------------------------------------
# PASSO 2: DEFINE VARIÁVEIS
# -------------------------------------------------
PROJECT_DIR="/var/www/$DOMAIN"
echo ""
echo "📋 CONFIGURAÇÃO:"
echo "• Domínio: $DOMAIN"
echo "• Diretório: $PROJECT_DIR"
echo "• Banco: $DB_NAME"
echo "• Usuário DB: $DB_USER"
echo "============================================"

# -------------------------------------------------
# PASSO 3: MATA PROCESSOS BLOQUEANTES
# -------------------------------------------------
echo "🔓 Desbloqueando sistema..."
sudo pkill -9 debconf 2>/dev/null || true
sudo pkill -9 apt 2>/dev/null || true
sudo pkill -9 dpkg 2>/dev/null || true

sudo rm -f /var/lib/apt/lists/lock
sudo rm -f /var/lib/dpkg/lock
sudo rm -f /var/cache/apt/archives/lock

# -------------------------------------------------
# PASSO 4: ATUALIZA SISTEMA (SIMPLES)
# -------------------------------------------------
echo "🔄 Atualizando..."
sudo apt-get update

# -------------------------------------------------
# PASSO 5: INSTALA O BÁSICO
# -------------------------------------------------
echo "📦 Instalando pacotes..."
sudo apt-get install -y nginx mariadb-server php8.1-fpm php8.1-mysql python3-pip ffmpeg wget unzip

# -------------------------------------------------
# PASSO 6: CRIA DIRETÓRIO DO PROJETO
# -------------------------------------------------
echo "📁 Criando diretório..."
sudo rm -rf "$PROJECT_DIR" 2>/dev/null
sudo mkdir -p "$PROJECT_DIR"
sudo chown -R $USER:$USER "$PROJECT_DIR"

# -------------------------------------------------
# PASSO 7: BAIXA ARQUIVOS DO GITHUB
# -------------------------------------------------
echo "📥 Baixando arquivos do GitHub..."
cd "$PROJECT_DIR"

# Baixa o ZIP diretamente
echo "• Baixando main.zip..."
wget -q --show-progress "https://github.com/Marcelo1408/youtube-audio-extractor/archive/main.zip" -O site.zip

if [ -f "site.zip" ]; then
    echo "• Extraindo..."
    unzip -q site.zip
    echo "• Movendo arquivos..."
    
    # Encontra o diretório extraído
    if [ -d "youtube-audio-extractor-main" ]; then
        mv youtube-audio-extractor-main/* . 2>/dev/null || true
        mv youtube-audio-extractor-main/.* . 2>/dev/null || true
        rm -rf youtube-audio-extractor-main
    fi
    
    # Lista o que foi baixado
    echo "✅ Arquivos baixados:"
    ls -la | head -10
else
    echo "❌ Falha no download. Criando site básico..."
    echo "<h1>YouTube Audio Extractor</h1><p>Instalado em $DOMAIN</p>" > index.html
fi

sudo rm -f site.zip 2>/dev/null

# -------------------------------------------------
# PASSO 8: CONFIGURA MARIADB
# -------------------------------------------------
echo "🗄️  Configurando MariaDB..."

# Inicia serviço
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Configura senha root (método direto)
echo "• Configurando senha root..."
sudo mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
FLUSH PRIVILEGES;
EOF

# Cria banco de dados
echo "• Criando banco '$DB_NAME'..."
sudo mysql -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# -------------------------------------------------
# PASSO 9: CRIA TABELAS (SEU SQL)
# -------------------------------------------------
echo "📝 Criando tabelas do banco..."

# Cria arquivo SQL temporário
SQL_FILE="/tmp/banco_setup.sql"
cat > "$SQL_FILE" <<'SQL'
-- Banco de dados: youtube_extractor
CREATE DATABASE IF NOT EXISTS youtube_extractor_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE youtube_extractor_db;

-- Tabela users
CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  email VARCHAR(100) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  role ENUM('user','admin') DEFAULT 'user',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabela processes
CREATE TABLE processes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT,
  youtube_url TEXT NOT NULL,
  status ENUM('pending','processing','completed','failed') DEFAULT 'pending',
  file_path VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insere admin
INSERT INTO users (username, email, password, role) VALUES 
('admin', 'admin@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin');
SQL

# Executa o SQL
sudo mysql -u root -p"$DB_ROOT_PASS" $DB_NAME < "$SQL_FILE"
rm -f "$SQL_FILE"

echo "✅ Tabelas criadas!"

# -------------------------------------------------
# PASSO 10: INSTALA DEPENDÊNCIAS PYTHON
# -------------------------------------------------
echo "🐍 Instalando Python..."
sudo pip3 install yt-dlp pydub moviepy

# -------------------------------------------------
# PASSO 11: PERMISSÕES
# -------------------------------------------------
echo "🔒 Ajustando permissões..."
sudo mkdir -p "$PROJECT_DIR/uploads"
sudo chown -R www-data:www-data "$PROJECT_DIR"
sudo chmod -R 755 "$PROJECT_DIR"
sudo chmod 775 "$PROJECT_DIR/uploads"

# -------------------------------------------------
# PASSO 12: CRIA .ENV
# -------------------------------------------------
echo "⚙️  Criando .env..."
cat > "$PROJECT_DIR/.env" <<ENV
APP_URL=https://$DOMAIN
DB_HOST=localhost
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
UPLOAD_DIR=$PROJECT_DIR/uploads
ENV

sudo chown www-data:www-data "$PROJECT_DIR/.env"
sudo chmod 600 "$PROJECT_DIR/.env"

# -------------------------------------------------
# PASSO 13: CONFIGURA NGINX
# -------------------------------------------------
echo "🌐 Configurando Nginx..."

# Cria configuração
sudo cat > "/etc/nginx/sites-available/$DOMAIN" <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    root $PROJECT_DIR;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }
}
NGINX

# Ativa site
sudo ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"
sudo rm -f /etc/nginx/sites-enabled/default

# Testa e reinicia
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl restart php8.1-fpm

# -------------------------------------------------
# PASSO 14: VERIFICAÇÃO FINAL
# -------------------------------------------------
echo ""
echo "============================================"
echo "🔍 VERIFICAÇÃO"
echo "============================================"

# 1. Verifica diretório
echo "1. 📁 Diretório: $PROJECT_DIR"
if [ -d "$PROJECT_DIR" ]; then
    echo "   ✅ EXISTE"
    echo "   📊 Conteúdo: $(ls "$PROJECT_DIR" | wc -l) arquivos"
else
    echo "   ❌ NÃO EXISTE"
fi

# 2. Verifica banco
echo ""
echo "2. 🗄️  Banco: $DB_NAME"
if sudo mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" 2>/dev/null; then
    echo "   ✅ EXISTE"
    TABLES=$(sudo mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SHOW TABLES;" 2>/dev/null | wc -l)
    echo "   📊 $TABLES tabelas"
else
    echo "   ❌ NÃO EXISTE"
fi

# 3. Verifica serviços
echo ""
echo "3. 🔧 Serviços:"
echo "   • Nginx: $(sudo systemctl is-active nginx)"
echo "   • MariaDB: $(sudo systemctl is-active mariadb)"
echo "   • PHP: $(sudo systemctl is-active php8.1-fpm)"

# 4. Testa site
echo ""
echo "4. 🌐 Teste do site:"
if curl -s -I http://localhost 2>/dev/null | head -1 | grep -q "200\|301"; then
    echo "   ✅ SITE FUNCIONANDO"
else
    echo "   ⚠️  Verifique: sudo systemctl status nginx"
fi

echo ""
echo "============================================"
echo "🎉 INSTALAÇÃO COMPLETA!"
echo "============================================"
echo ""
echo "✅ O QUE FOI CRIADO:"
echo "1. 📁 Diretório: $PROJECT_DIR"
echo "2. 🗄️  Banco: $DB_NAME"
echo "3. 👤 Usuário DB: $DB_USER"
echo "4. 🔐 Senha DB: $DB_PASS"
echo "5. 🌐 Site: http://$DOMAIN"
echo ""
echo "🔧 COMANDOS PARA TESTAR:"
echo "• Ver arquivos: ls -la $PROJECT_DIR"
echo "• Acessar banco: mysql -u $DB_USER -p$DB_PASS $DB_NAME"
echo "• Ver logs: sudo tail -f /var/log/nginx/error.log"
echo ""
echo "🚀 PRÓXIMOS PASSOS:"
echo "1. Configure DNS para $DOMAIN apontar para esta VPS"
echo "2. Para SSL: sudo certbot --nginx -d $DOMAIN --email $EMAIL"
echo "3. Acesse: http://$DOMAIN"
echo ""
echo "============================================"
