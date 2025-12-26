#!/bin/bash
# install-continue.sh - Continuação da instalação

set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}✅ npm instalado com sucesso!${NC}"
echo "Continuando instalação..."

# ==================== CONFIGURAR DIRETÓRIO DO PROJETO ====================
PROJECT_DIR="/opt/youtube-audio-extractor"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo "📁 Diretório do projeto: $PROJECT_DIR"

# ==================== BAIXAR PROJETO DO GITHUB ====================
echo "📥 Baixando projeto do GitHub..."

# Verificar se git está instalado
if ! command -v git &> /dev/null; then
    echo "Instalando git..."
    apt install -y git
fi

# Clonar ou baixar projeto
if [ -d "$PROJECT_DIR/.git" ]; then
    echo "Projeto já clonado. Atualizando..."
    git pull origin main
else
    echo "Clonando repositório..."
    git clone https://github.com/Marcelo1408/youtube-audio-extractor.git .
fi

# Se ainda não houver arquivos, baixar manualmente
if [ ! -f "package.json" ] && [ ! -f "server.js" ]; then
    echo "Criando estrutura básica..."
    
    # Criar package.json
    cat > package.json << 'EOF'
{
  "name": "youtube-audio-extractor-pro",
  "version": "1.0.0",
  "description": "YouTube Audio Extractor - Sistema de extração de áudio",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": ["youtube", "audio", "extractor", "mp3"],
  "author": "",
  "license": "MIT",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "dotenv": "^16.0.3",
    "ytdl-core": "^4.11.5",
    "fluent-ffmpeg": "^2.1.2",
    "mysql2": "^3.6.0",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "express-validator": "^7.0.1",
    "socket.io": "^4.7.2"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  },
  "engines": {
    "node": ">=18.0.0",
    "npm": ">=9.0.0"
  }
}
EOF

    # Criar server.js
    cat > server.js << 'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const ytdl = require('ytdl-core');
const ffmpeg = require('fluent-ffmpeg');
const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Criar diretórios
const directories = ['public', 'uploads/audio', 'uploads/video', 'logs'];
directories.forEach(dir => {
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
});

// Rota de status
app.get('/', (req, res) => {
    res.json({
        message: 'YouTube Audio Extractor Pro API',
        status: 'online',
        version: '1.0.0',
        endpoints: [
            '/api/health',
            '/api/video/info',
            '/api/audio/download'
        ]
    });
});

// Rota de saúde
app.get('/api/health', (req, res) => {
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        service: 'YouTube Audio Extractor',
        nodeVersion: process.version,
        uptime: process.uptime()
    });
});

// Rota para informações do vídeo
app.get('/api/video/info', async (req, res) => {
    try {
        const { url } = req.query;
        
        if (!url) {
            return res.status(400).json({
                success: false,
                error: 'URL do YouTube é obrigatória'
            });
        }
        
        const info = await ytdl.getInfo(url);
        
        res.json({
            success: true,
            title: info.videoDetails.title,
            duration: info.videoDetails.lengthSeconds,
            author: info.videoDetails.author.name,
            thumbnail: info.videoDetails.thumbnails[0].url,
            available: true
        });
        
    } catch (error) {
        res.status(500).json({
            success: false,
            error: 'Erro ao obter informações do vídeo',
            message: error.message
        });
    }
});

// Rota para download de áudio
app.get('/api/audio/download', async (req, res) => {
    try {
        const { url, format = 'mp3' } = req.query;
        
        if (!url) {
            return res.status(400).json({
                success: false,
                error: 'URL do YouTube é obrigatória'
            });
        }
        
        const videoId = ytdl.getVideoID(url);
        const info = await ytdl.getInfo(url);
        const title = info.videoDetails.title.replace(/[^\w\s]/gi, '');
        
        const timestamp = Date.now();
        const filename = `${title.substring(0, 50)}_${timestamp}.${format}`;
        const outputPath = path.join(__dirname, 'uploads', 'audio', filename);
        
        res.json({
            success: true,
            message: 'Download iniciado em segundo plano',
            filename: filename,
            downloadUrl: `/uploads/audio/${filename}`,
            title: title
        });
        
        // Download em segundo plano
        const audioStream = ytdl(url, { 
            filter: 'audioonly',
            quality: 'highestaudio' 
        });
        
        if (format === 'mp3') {
            ffmpeg(audioStream)
                .audioBitrate(128)
                .save(outputPath)
                .on('end', () => {
                    console.log(`✅ Áudio convertido: ${filename}`);
                });
        } else {
            const writeStream = fs.createWriteStream(outputPath);
            audioStream.pipe(writeStream);
        }
        
    } catch (error) {
        res.status(500).json({
            success: false,
            error: 'Erro no download do áudio',
            message: error.message
        });
    }
});

// Servir arquivos de upload
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Iniciar servidor
app.listen(port, () => {
    console.log(`🎵 YouTube Audio Extractor Pro`);
    console.log(`✅ Servidor rodando na porta ${port}`);
    console.log(`📁 Diretório: ${__dirname}`);
    console.log(`🌐 URL: http://localhost:${port}`);
    console.log(`⚡ Node.js: ${process.version}`);
    console.log(`🔧 Modo: ${process.env.NODE_ENV || 'development'}`);
});
EOF

    # Criar .env.example
    cat > .env.example << 'EOF'
# ==================== DATABASE ====================
DB_HOST=localhost
DB_PORT=3306
DB_NAME=youtube_extractor
DB_USER=youtube_user
DB_PASSWORD=YoutubePass123!

# ==================== SERVER ====================
PORT=3000
NODE_ENV=production
SESSION_SECRET=your_session_secret_here
JWT_SECRET=your_jwt_secret_here

# ==================== YOUTUBE ====================
YOUTUBE_API_KEY=your_youtube_api_key_here

# ==================== PATHS ====================
FFMPEG_PATH=/usr/bin/ffmpeg
UPLOAD_DIR=./uploads
MAX_FILE_SIZE=104857600
ALLOWED_FORMATS=mp3,wav,flac,m4a

# ==================== LIMITS ====================
DAILY_LIMIT=10
MAX_DURATION=3600
CONCURRENT_DOWNLOADS=3
EOF

    # Criar .env
    cp .env.example .env
    
    # Gerar chaves secretas
    sed -i "s/your_session_secret_here/$(openssl rand -hex 32)/" .env
    sed -i "s/your_jwt_secret_here/$(openssl rand -hex 32)/" .env
fi

# ==================== INSTALAR DEPENDÊNCIAS ====================
echo "📦 Instalando dependências do projeto..."
npm install

# Verificar instalação
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Dependências instaladas com sucesso!${NC}"
else
    echo -e "${YELLOW}⚠️  Tentando instalação com --legacy-peer-deps...${NC}"
    npm install --legacy-peer-deps
fi

# ==================== INSTALAR PM2 ====================
echo "⚡ Instalando PM2..."
npm install -g pm2

# ==================== INSTALAR FFMPEG ====================
echo "🎵 Verificando FFmpeg..."
if ! command -v ffmpeg &> /dev/null; then
    echo "Instalando FFmpeg..."
    apt install -y ffmpeg
fi

# ==================== CONFIGURAR BANCO DE DADOS ====================
echo "💾 Configurando banco de dados..."

# Instalar MariaDB se não estiver instalado
if ! command -v mysql &> /dev/null; then
    echo "Instalando MariaDB..."
    apt install -y mariadb-server
    systemctl start mariadb
    systemctl enable mariadb
fi

# Criar banco e usuário
mysql -e "CREATE DATABASE IF NOT EXISTS youtube_extractor;" 2>/dev/null || echo "Nota: Erro ao criar banco"
mysql -e "CREATE USER IF NOT EXISTS 'youtube_user'@'localhost' IDENTIFIED BY 'YoutubePass123!';" 2>/dev/null || echo "Nota: Erro ao criar usuário"
mysql -e "GRANT ALL PRIVILEGES ON youtube_extractor.* TO 'youtube_user'@'localhost';" 2>/dev/null || echo "Nota: Erro ao conceder privilégios"
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || echo "Nota: Erro ao atualizar privilégios"

# ==================== CRIAR DIRETÓRIOS ====================
echo "📁 Criando diretórios..."
mkdir -p uploads/audio uploads/video uploads/temp logs public
chmod -R 755 uploads

# ==================== INICIAR APLICAÇÃO ====================
echo "🚀 Iniciando aplicação..."

# Parar instância existente
pm2 delete youtube-extractor 2>/dev/null || true

# Iniciar com PM2
pm2 start server.js --name "youtube-extractor"
pm2 save

# Configurar startup
pm2 startup 2>/dev/null || echo "Nota: Configure PM2 startup manualmente"

# ==================== CONFIGURAR NGINX (OPCIONAL) ====================
read -p "🌐 Configurar Nginx como proxy reverso? (s/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo "Configurando Nginx..."
    
    apt install -y nginx
    
    cat > /etc/nginx/sites-available/youtube-extractor << 'EOF'
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /uploads/ {
        alias /opt/youtube-audio-extractor/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/youtube-extractor /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl restart nginx
fi

# ==================== FINALIZAÇÃO ====================
echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo "📁 Diretório do projeto: $PROJECT_DIR"
echo "🌐 URL da API: http://localhost:3000"
echo "🔧 Node.js: $(node --version)"
echo "📦 npm: $(npm --version)"
echo "⚡ PM2: $(pm2 --version 2>/dev/null || echo 'instalado')"
echo ""
echo "🛠️  Comandos úteis:"
echo "   cd $PROJECT_DIR"
echo "   pm2 logs youtube-extractor    # Ver logs"
echo "   pm2 restart youtube-extractor # Reiniciar"
echo "   pm2 status                    # Ver status"
echo ""
echo "⚠️  IMPORTANTE:"
echo "   1. Configure sua API Key do YouTube no arquivo .env"
echo "   2. Teste o sistema: curl http://localhost:3000/api/health"
echo ""
echo "✅ Para testar o sistema, abra no navegador:"
echo "   http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):3000"
echo ""
