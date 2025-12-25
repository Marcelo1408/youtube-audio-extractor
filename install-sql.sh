#!/bin/bash
# backend/database/install.sh

echo "📦 Instalando banco de dados MariaDB..."

# Verificar se MariaDB está instalado
if ! command -v mysql &> /dev/null; then
    echo "❌ MariaDB não está instalado."
    echo "Instale com: sudo apt install mariadb-server"
    exit 1
fi

# Perguntar credenciais
read -p "Usuário MySQL (padrão: root): " DB_USER
DB_USER=${DB_USER:-root}

read -sp "Senha MySQL: " DB_PASS
echo ""

read -p "Host MySQL (padrão: localhost): " DB_HOST
DB_HOST=${DB_HOST:-localhost}

read -p "Porta MySQL (padrão: 3306): " DB_PORT
DB_PORT=${DB_PORT:-3306}

echo "📊 Criando banco de dados..."

# Executar script SQL
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS < schema.sql

if [ $? -eq 0 ]; then
    echo "✅ Banco de dados criado com sucesso!"
    
    # Criar arquivo .env
    echo "🔧 Criando arquivo .env..."
    
    cat > ../.env << EOF
# Configurações do Banco de Dados
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
DB_NAME=youtube_audio_extractor
DB_POOL_MIN=2
DB_POOL_MAX=10

# Configurações do Servidor
PORT=3000
NODE_ENV=development
SESSION_SECRET=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)
CLIENT_URL=http://localhost:3000

# Configurações de Email
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=seu-email@gmail.com
SMTP_PASS=sua-senha-app
EMAIL_FROM=noreply@youraudioextractor.com

# Configurações do Google OAuth
GOOGLE_CLIENT_ID=seu-client-id
GOOGLE_CLIENT_SECRET=seu-client-secret
GOOGLE_CALLBACK_URL=http://localhost:3000/api/auth/google/callback

# Configurações de Upload
UPLOAD_DIR=./uploads
MAX_FILE_SIZE=104857600
ALLOWED_AUDIO_FORMATS=mp3,wav,flac

# Configurações de Processamento
MAX_CONCURRENT_PROCESSES=3
TEMP_DIR=./uploads/temp
KEEP_VIDEO_DAYS=7
DELETE_TEMP_FILES_AFTER=24

# Configurações de Rate Limiting
RATE_LIMIT_WINDOW=15
RATE_LIMIT_MAX=100
EOF
    
    echo "✅ Arquivo .env criado!"
    echo "📝 Atualize as configurações no arquivo .env antes de iniciar o servidor."
    
else
    echo "❌ Erro ao criar banco de dados."
fi
