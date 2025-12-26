#!/bin/bash
# install-sql.sh - Script simplificado para MariaDB Ubuntu 22.04

set -e

echo "🔧 YouTube Audio Extractor - Database Setup"
echo "=========================================="

# Verificar MariaDB
if ! command -v mysql &> /dev/null; then
    echo "❌ MariaDB não está instalado."
    echo "Instalando MariaDB..."
    sudo apt update
    sudo apt install -y mariadb-server
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
fi

# Baixar schema corrigido
echo "📥 Baixando schema.sql..."
SCHEMA_URL="https://raw.githubusercontent.com/Marcelo1408/youtube-audio-extractor/main/schema.sql"
curl -sSL "$SCHEMA_URL" -o /tmp/schema.sql

if [ ! -s /tmp/schema.sql ]; then
    echo "❌ Erro ao baixar schema.sql"
    exit 1
fi

echo "✅ Schema baixado com sucesso"

# Configurações
DB_NAME="youtube_audio_extractor"
DB_USER="youtube_user"
DB_PASS="YoutubePass123!"

echo ""
echo "⚙️  Configurações:"
echo "   Banco: $DB_NAME"
echo "   Usuário: $DB_USER"
echo "   Senha: $DB_PASS"
echo ""

# Executar com sudo (método Ubuntu 22.04)
echo "📊 Criando banco de dados..."
sudo mysql << EOF
-- Criar banco
CREATE DATABASE IF NOT EXISTS $DB_NAME 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

-- Usar banco
USE $DB_NAME;

-- Executar schema
SOURCE /tmp/schema.sql;

-- Criar usuário
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';

-- Conceder permissões
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';

-- Atualizar privilégios
FLUSH PRIVILEGES;

-- Mostrar tabelas criadas
SHOW TABLES;
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Banco de dados criado com sucesso!"
    
    # Criar .env
    cat > .env << EOF
# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS

# Server
PORT=3000
NODE_ENV=production
SESSION_SECRET=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)

# YouTube
YOUTUBE_API_KEY=SUA_CHAVE_API_AQUI

# Paths
FFMPEG_PATH=/usr/bin/ffmpeg
UPLOAD_DIR=./uploads
EOF
    
    echo "📄 Arquivo .env criado"
    echo ""
    echo "🎉 Pronto! Configure a YOUTUBE_API_KEY no arquivo .env"
    
else
    echo "❌ Erro ao criar banco de dados"
    exit 1
fi

# Limpar
rm -f /tmp/schema.sql
