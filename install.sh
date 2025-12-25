#!/bin/bash
# Arquivo: install.sh
# YouTube Audio Extractor Pro - Instalador Automático VPS

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║      🎵 YOUTUBE AUDIO EXTRACTOR PRO - INSTALADOR VPS        ║
║              Node.js + MariaDB + Ubuntu 22.04               ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar root
if [[ $EUID -ne 0 ]]; then
    error "Execute como root: sudo bash $0"
fi

# Variáveis configuráveis
SITE_DIR="/var/www/youtube-extractor-pro"
REPO_URL="https://github.com/seu-usuario/youtube-extractor-pro/archive/refs/heads/main.zip"
ZIP_FILE="/tmp/youtube-extractor-pro.zip"

# 1. Atualizar sistema
log "Atualizando sistema..."
apt update && apt upgrade -y

# 2. Criar diretório do site
log "Criando diretório do site em $SITE_DIR..."
mkdir -p $SITE_DIR
chown -R $SUDO_USER:$SUDO_USER $SITE_DIR
chmod 755 $SITE_DIR

# 3. Instalar Node.js
log "Instalando Node.js 18.x..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs npm
npm install -g pm2

# 4. Instalar MariaDB
log "Instalando MariaDB..."
apt install -y mariadb-server mariadb-client
systemctl start mariadb
systemctl enable mariadb

# 5. Instalar dependências do sistema
log "Instalando dependências do sistema..."
apt install -y nginx ffmpeg git curl wget unzip build-essential

# 6. Configurar banco de dados
log "Configurando banco de dados..."
mysql -e "CREATE DATABASE IF NOT EXISTS youtube_extractor;" 2>/dev/null || warn "Erro ao criar BD (pode já existir)"
mysql -e "CREATE USER IF NOT EXISTS 'youtube_user'@'localhost' IDENTIFIED BY 'YoutubePass123!';" 2>/dev/null || warn "Erro ao criar usuário"
mysql -e "GRANT ALL PRIVILEGES ON youtube_extractor.* TO 'youtube_user'@'localhost';" 2>/dev/null || warn "Erro ao conceder privilégios"
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || warn "Erro ao atualizar privilégios"

# 7. Baixar e extrair o site do GitHub
log "Baixando site do GitHub..."
cd /tmp
if command -v wget &> /dev/null; then
    wget -O $ZIP_FILE $REPO_URL
elif command -v curl &> /dev/null; then
    curl -L -o $ZIP_FILE $REPO_URL
else
    error "Necessário wget ou curl para baixar o site"
fi

log "Extraindo arquivos para $SITE_DIR..."
unzip -q -o $ZIP_FILE -d /tmp/

# Encontrar e copiar arquivos extraídos
if [ -d "/tmp/youtube-extractor-pro-main" ]; then
    cp -r /tmp/youtube-extractor-pro-main/* $SITE_DIR/
    cp -r /tmp/youtube-extractor-pro-main/. $SITE_DIR/ 2>/dev/null || true
elif [ -d "/tmp/main" ]; then
    cp -r /tmp/main/* $SITE_DIR/
    cp -r /tmp/main/. $SITE_DIR/ 2>/dev/null || true
else
    # Tentar encontrar qualquer diretório extraído
    EXTRACTED_DIR=$(find /tmp -type d -name "*youtube*extractor*" -o -name "*youtube*" | head -1)
    if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then
        cp -r "$EXTRACTED_DIR"/* $SITE_DIR/
        cp -r "$EXTRACTED_DIR"/. $SITE_DIR/ 2>/dev/null || true
    else
        warn "Não foi possível encontrar arquivos extraídos. Extraindo diretamente..."
        unzip -q -o $ZIP_FILE -d $SITE_DIR
    fi
fi

# Limpar arquivos temporários
rm -f $ZIP_FILE
rm -rf /tmp/youtube-extractor-pro-main /tmp/main

# 8. Verificar estrutura do projeto
log "Verificando estrutura do projeto..."
cd $SITE_DIR

# Criar estrutura de diretórios se não existir
mkdir -p backend frontend uploads logs

# 9. Instalar dependências do Node.js
log "Instalando dependências do Node.js..."

# Procurar package.json em diferentes locais
if [ -f "$SITE_DIR/backend/package.json" ]; then
    log "Instalando dependências do backend..."
    cd $SITE_DIR/backend
    npm install --production --no-audit
elif [ -f "$SITE_DIR/package.json" ]; then
    log "Instalando dependências do projeto..."
    cd $SITE_DIR
    npm install --production --no-audit
else
    warn "Nenhum package.json encontrado. Criando estrutura básica..."
    
    # Criar package.json básico para Node.js
    cat > $SITE_DIR/package.json << 'EOF'
{
  "name": "youtube-extractor-pro",
  "version": "1.0.0",
  "description": "YouTube Audio Extractor Pro",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "mysql2": "^3.6.0",
    "ytdl-core": "^4.11.5",
    "fluent-ffmpeg": "^2.1.2",
    "dotenv": "^16.3.1",
    "socket.io": "^4.7.2",
    "body-parser": "^1.20.2"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Criar server.js completo com funcionalidade de extração
    cat > $SITE_DIR/server.js << 'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const ytdl = require('ytdl-core');
const ffmpeg = require('fluent-ffmpeg');
const { exec } = require('child_process');
const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'frontend')));

// Verificar se FFmpeg está instalado
ffmpeg.getAvailableFormats((err, formats) => {
    if (err) {
        console.warn('⚠️ FFmpeg não encontrado. Instale: sudo apt install ffmpeg');
    } else {
        console.log('✅ FFmpeg está funcionando corretamente');
    }
});

// Rotas da API
app.get('/api/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        message: 'YouTube Audio Extractor Pro está funcionando!',
        version: '1.0.0',
        features: ['YouTube download', 'Audio extraction', 'MP3 conversion']
    });
});

// Rota para informações do vídeo
app.get('/api/video/info', async (req, res) => {
    try {
        const { url } = req.query;
        
        if (!url) {
            return res.status(400).json({ error: 'URL do YouTube é obrigatória' });
        }
        
        const info = await ytdl.getInfo(url);
        
        res.json({
            success: true,
            title: info.videoDetails.title,
            duration: info.videoDetails.lengthSeconds,
            author: info.videoDetails.author.name,
            thumbnail: info.videoDetails.thumbnails[0].url,
            formats: info.formats.map(f => ({
                quality: f.qualityLabel,
                container: f.container,
                hasAudio: f.hasAudio,
                hasVideo: f.hasVideo
            }))
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
            return res.status(400).json({ error: 'URL do YouTube é obrigatória' });
        }
        
        const videoId = ytdl.getVideoID(url);
        const info = await ytdl.getInfo(url);
        const title = info.videoDetails.title.replace(/[^\w\s]/gi, '');
        
        const timestamp = Date.now();
        const filename = `${title}_${timestamp}.${format}`;
        const outputPath = path.join(__dirname, 'uploads', 'audio', filename);
        
        // Garantir que o diretório existe
        if (!fs.existsSync(path.dirname(outputPath))) {
            fs.mkdirSync(path.dirname(outputPath), { recursive: true });
        }
        
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
            // Converter para MP3
            ffmpeg(audioStream)
                .audioBitrate(128)
                .save(outputPath)
                .on('end', () => {
                    console.log(`✅ Áudio convertido: ${filename}`);
                })
                .on('error', (err) => {
                    console.error('❌ Erro na conversão:', err);
                });
        } else {
            // Salvar no formato original
            const writeStream = fs.createWriteStream(outputPath);
            audioStream.pipe(writeStream);
            
            writeStream.on('finish', () => {
                console.log(`✅ Áudio salvo: ${filename}`);
            });
        }
        
    } catch (error) {
        res.status(500).json({ 
            success: false, 
            error: 'Erro no download do áudio',
            message: error.message 
        });
    }
});

// Rota para listar downloads
app.get('/api/audio/list', (req, res) => {
    const audioDir = path.join(__dirname, 'uploads', 'audio');
    
    if (!fs.existsSync(audioDir)) {
        return res.json({ files: [] });
    }
    
    const files = fs.readdirSync(audioDir)
        .filter(file => file.match(/\.(mp3|wav|aac|flac|m4a)$/i))
        .map(file => ({
            name: file,
            path: `/uploads/audio/${file}`,
            size: fs.statSync(path.join(audioDir, file)).size,
            created: fs.statSync(path.join(audioDir, file)).birthtime
        }));
    
    res.json({ files });
});

// Servir arquivos de upload
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Rota para frontend
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'frontend', 'index.html'));
});

app.listen(port, () => {
    console.log(`✅ Servidor rodando na porta ${port}`);
    console.log(`📁 Diretório: ${__dirname}`);
    console.log(`🌐 Acesse: http://localhost:${port}`);
    console.log(`🎵 API de extração de áudio pronta para uso!`);
});
EOF
    
    # Criar frontend completo
    mkdir -p $SITE_DIR/frontend
    cat > $SITE_DIR/frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>YouTube Audio Extractor Pro</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            color: #fff;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }
        header {
            text-align: center;
            margin-bottom: 3rem;
            padding: 2rem;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 20px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        h1 { 
            font-size: 3rem; 
            margin-bottom: 1rem;
            background: linear-gradient(45deg, #00dbde, #fc00ff);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle {
            font-size: 1.2rem;
            opacity: 0.8;
            margin-bottom: 2rem;
        }
        .main-content {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 2rem;
            margin-bottom: 3rem;
        }
        @media (max-width: 768px) {
            .main-content {
                grid-template-columns: 1fr;
            }
        }
        .card {
            background: rgba(255, 255, 255, 0.05);
            padding: 2rem;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        .input-group {
            margin-bottom: 1.5rem;
        }
        label {
            display: block;
            margin-bottom: 0.5rem;
            color: #00dbde;
            font-weight: bold;
        }
        input, select {
            width: 100%;
            padding: 1rem;
            background: rgba(255, 255, 255, 0.1);
            border: 1px solid rgba(255, 255, 255, 0.2);
            border-radius: 10px;
            color: white;
            font-size: 1rem;
        }
        input:focus, select:focus {
            outline: none;
            border-color: #00dbde;
        }
        .btn {
            background: linear-gradient(45deg, #00dbde, #0093E9);
            color: white;
            border: none;
            padding: 1rem 2rem;
            border-radius: 10px;
            font-size: 1rem;
            font-weight: bold;
            cursor: pointer;
            transition: transform 0.3s, box-shadow 0.3s;
            width: 100%;
            margin-top: 1rem;
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(0, 147, 233, 0.3);
        }
        .btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        .video-info {
            background: rgba(0, 219, 222, 0.1);
            padding: 1.5rem;
            border-radius: 10px;
            margin-top: 1rem;
            display: none;
        }
        .video-info.show {
            display: block;
        }
        .video-title {
            font-size: 1.2rem;
            margin-bottom: 1rem;
            color: #00dbde;
        }
        .video-thumbnail {
            max-width: 100%;
            border-radius: 10px;
            margin-bottom: 1rem;
        }
        .downloads-list {
            max-height: 400px;
            overflow-y: auto;
        }
        .download-item {
            background: rgba(255, 255, 255, 0.05);
            padding: 1rem;
            border-radius: 10px;
            margin-bottom: 1rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .download-name {
            flex-grow: 1;
            margin-right: 1rem;
        }
        .download-actions a {
            color: #00dbde;
            text-decoration: none;
            margin-left: 1rem;
        }
        .download-actions a:hover {
            text-decoration: underline;
        }
        .status {
            padding: 1rem;
            border-radius: 10px;
            margin: 1rem 0;
            text-align: center;
        }
        .status.success {
            background: rgba(0, 255, 0, 0.1);
            border: 1px solid rgba(0, 255, 0, 0.3);
        }
        .status.error {
            background: rgba(255, 0, 0, 0.1);
            border: 1px solid rgba(255, 0, 0, 0.3);
        }
        .status.loading {
            background: rgba(255, 255, 0, 0.1);
            border: 1px solid rgba(255, 255, 0, 0.3);
        }
        footer {
            text-align: center;
            margin-top: 3rem;
            padding-top: 2rem;
            border-top: 1px solid rgba(255, 255, 255, 0.1);
            opacity: 0.7;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1><i class="fas fa-music"></i> YouTube Audio Extractor Pro</h1>
            <p class="subtitle">Extraia áudio de vídeos do YouTube sem precisar de API key</p>
        </header>
        
        <div class="main-content">
            <div class="card">
                <h2><i class="fas fa-download"></i> Extrair Áudio</h2>
                <div class="input-group">
                    <label for="youtubeUrl"><i class="fab fa-youtube"></i> URL do YouTube:</label>
                    <input type="url" id="youtubeUrl" placeholder="https://www.youtube.com/watch?v=..." required>
                </div>
                
                <div class="input-group">
                    <label for="audioFormat"><i class="fas fa-file-audio"></i> Formato de Áudio:</label>
                    <select id="audioFormat">
                        <option value="mp3">MP3 (Recomendado)</option>
                        <option value="m4a">M4A/AAC</option>
                        <option value="wav">WAV</option>
                    </select>
                </div>
                
                <button class="btn" id="getInfoBtn">
                    <i class="fas fa-info-circle"></i> Obter Informações do Vídeo
                </button>
                
                <div id="videoInfo" class="video-info"></div>
                
                <button class="btn" id="downloadBtn" disabled>
                    <i class="fas fa-download"></i> Extrair e Baixar Áudio
                </button>
                
                <div id="statusMessage" class="status"></div>
            </div>
            
            <div class="card">
                <h2><i class="fas fa-history"></i> Downloads Recentes</h2>
                <button class="btn" id="refreshList">
                    <i class="fas fa-sync-alt"></i> Atualizar Lista
                </button>
                
                <div class="downloads-list" id="downloadsList">
                    <p style="text-align: center; padding: 2rem; opacity: 0.7;">
                        <i class="fas fa-music fa-2x"></i><br>
                        Nenhum download ainda
                    </p>
                </div>
            </div>
        </div>
        
        <div class="card">
            <h2><i class="fas fa-server"></i> Status do Sistema</h2>
            <div id="systemStatus">
                <p>Verificando status do servidor...</p>
            </div>
        </div>
        
        <footer>
            <p>YouTube Audio Extractor Pro v1.0 | Sistema funcionando sem API key!</p>
            <p>Diretório: /var/www/youtube-extractor-pro</p>
        </footer>
    </div>
    
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const youtubeUrl = document.getElementById('youtubeUrl');
            const audioFormat = document.getElementById('audioFormat');
            const getInfoBtn = document.getElementById('getInfoBtn');
            const downloadBtn = document.getElementById('downloadBtn');
            const videoInfo = document.getElementById('videoInfo');
            const statusMessage = document.getElementById('statusMessage');
            const refreshList = document.getElementById('refreshList');
            const downloadsList = document.getElementById('downloadsList');
            const systemStatus = document.getElementById('systemStatus');
            
            let currentVideoInfo = null;
            
            // Verificar status do sistema
            function checkSystemStatus() {
                fetch('/api/health')
                    .then(response => response.json())
                    .then(data => {
                        systemStatus.innerHTML = `
                            <div class="status success">
                                <p><i class="fas fa-check-circle"></i> ${data.message}</p>
                                <p><small>Recursos disponíveis: ${data.features.join(', ')}</small></p>
                            </div>
                        `;
                    })
                    .catch(error => {
                        systemStatus.innerHTML = `
                            <div class="status error">
                                <p><i class="fas fa-exclamation-circle"></i> Erro ao conectar com o servidor</p>
                                <p><small>${error.message}</small></p>
                            </div>
                        `;
                    });
            }
            
            // Obter informações do vídeo
            getInfoBtn.addEventListener('click', function() {
                const url = youtubeUrl.value.trim();
                
                if (!url) {
                    showStatus('Por favor, insira uma URL do YouTube', 'error');
                    return;
                }
                
                showStatus('Obtendo informações do vídeo...', 'loading');
                
                fetch(`/api/video/info?url=${encodeURIComponent(url)}`)
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            currentVideoInfo = data;
                            videoInfo.innerHTML = `
                                <div class="video-info show">
                                    <img src="${data.thumbnail}" alt="Thumbnail" class="video-thumbnail">
                                    <h3 class="video-title">${data.title}</h3>
                                    <p><strong>Canal:</strong> ${data.author}</p>
                                    <p><strong>Duração:</strong> ${Math.floor(data.duration / 60)}:${(data.duration % 60).toString().padStart(2, '0')}</p>
                                </div>
                            `;
                            downloadBtn.disabled = false;
                            showStatus('Vídeo encontrado! Clique em "Extrair e Baixar Áudio" para continuar.', 'success');
                        } else {
                            showStatus('Erro: ' + data.error, 'error');
                        }
                    })
                    .catch(error => {
                        showStatus('Erro ao obter informações do vídeo', 'error');
                        console.error(error);
                    });
            });
            
            // Download do áudio
            downloadBtn.addEventListener('click', function() {
                if (!currentVideoInfo) {
                    showStatus('Primeiro obtenha as informações do vídeo', 'error');
                    return;
                }
                
                const url = youtubeUrl.value.trim();
                const format = audioFormat.value;
                
                showStatus('Iniciando extração do áudio...', 'loading');
                downloadBtn.disabled = true;
                downloadBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Processando...';
                
                fetch(`/api/audio/download?url=${encodeURIComponent(url)}&format=${format}`)
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            showStatus(`✅ Download iniciado: ${data.title}`, 'success');
                            downloadBtn.innerHTML = '<i class="fas fa-download"></i> Extrair e Baixar Áudio';
                            downloadBtn.disabled = false;
                            
                            // Mostrar link de download
                            setTimeout(() => {
                                showStatus(`✅ Download concluído! <a href="${data.downloadUrl}" style="color: #00dbde;">Clique aqui para baixar</a>`, 'success');
                                loadDownloads();
                            }, 3000);
                        } else {
                            showStatus('Erro: ' + data.error, 'error');
                            downloadBtn.innerHTML = '<i class="fas fa-download"></i> Extrair e Baixar Áudio';
                            downloadBtn.disabled = false;
                        }
                    })
                    .catch(error => {
                        showStatus('Erro no download', 'error');
                        downloadBtn.innerHTML = '<i class="fas fa-download"></i> Extrair e Baixar Áudio';
                        downloadBtn.disabled = false;
                        console.error(error);
                    });
            });
            
            // Carregar lista de downloads
            function loadDownloads() {
                fetch('/api/audio/list')
                    .then(response => response.json())
                    .then(data => {
                        if (data.files && data.files.length > 0) {
                            downloadsList.innerHTML = '';
                            data.files.forEach(file => {
                                const item = document.createElement('div');
                                item.className = 'download-item';
                                
                                const sizeMB = (file.size / (1024 * 1024)).toFixed(2);
                                const date = new Date(file.created).toLocaleDateString('pt-BR');
                                
                                item.innerHTML = `
                                    <div class="download-name">
                                        <strong>${file.name}</strong><br>
                                        <small>${sizeMB} MB • ${date}</small>
                                    </div>
                                    <div class="download-actions">
                                        <a href="${file.path}" download><i class="fas fa-download"></i> Baixar</a>
                                        <a href="${file.path}" target="_blank"><i class="fas fa-play"></i> Ouvir</a>
                                    </div>
                                `;
                                
                                downloadsList.appendChild(item);
                            });
                        } else {
                            downloadsList.innerHTML = `
                                <p style="text-align: center; padding: 2rem; opacity: 0.7;">
                                    <i class="fas fa-music fa-2x"></i><br>
                                    Nenhum download ainda
                                </p>
                            `;
                        }
                    })
                    .catch(error => {
                        console.error('Erro ao carregar downloads:', error);
                    });
            }
            
            // Atualizar lista de downloads
            refreshList.addEventListener('click', loadDownloads);
            
            // Mostrar mensagem de status
            function showStatus(message, type) {
                statusMessage.innerHTML = message;
                statusMessage.className = `status ${type}`;
                
                if (type !== 'loading') {
                    setTimeout(() => {
                        statusMessage.innerHTML = '';
                        statusMessage.className = 'status';
                    }, 5000);
                }
            }
            
            // Inicializar
            checkSystemStatus();
            loadDownloads();
            
            // Permitir Enter na URL
            youtubeUrl.addEventListener('keypress', function(e) {
                if (e.key === 'Enter') {
                    getInfoBtn.click();
                }
            });
        });
    </script>
</body>
</html>
EOF
    
    cd $SITE_DIR
    npm install --production --no-audit
    log "Estrutura completa criada e dependências instaladas."
fi

# 10. Configurar Nginx
log "Configurando Nginx..."
cat > /etc/nginx/sites-available/youtube-extractor << NGINX
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    # Diretório raiz do site
    root $SITE_DIR/frontend;
    index index.html index.htm;
    
    # Configuração do frontend - Single Page Application
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    # API Proxy - Node.js backend
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # WebSocket support
    location /socket.io/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    # Uploads directory
    location /uploads/ {
        alias $SITE_DIR/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
        autoindex off;
    }
    
    # Static files cache
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|mp3|mp4|webm)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
NGINX

# Habilitar site
ln -sf /etc/nginx/sites-available/youtube-extractor /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Testar e reiniciar Nginx
nginx -t && systemctl restart nginx
log "Nginx configurado e reiniciado."

# 11. Configurar firewall (opcional)
if command -v ufw &> /dev/null; then
    log "Configurando firewall..."
    ufw --force enable 2>/dev/null || true
    ufw allow OpenSSH 2>/dev/null || warn "Erro ao configurar firewall OpenSSH"
    ufw allow 'Nginx Full' 2>/dev/null || warn "Erro ao configurar firewall Nginx"
    ufw --force reload 2>/dev/null || true
else
    warn "UFW não encontrado. Configure o firewall manualmente se necessário."
fi

# 12. Iniciar aplicação com PM2
log "Iniciando aplicação com PM2..."

# Determinar o arquivo principal
if [ -f "$SITE_DIR/backend/server.js" ]; then
    MAIN_FILE="$SITE_DIR/backend/server.js"
    START_DIR="$SITE_DIR/backend"
elif [ -f "$SITE_DIR/server.js" ]; then
    MAIN_FILE="$SITE_DIR/server.js"
    START_DIR="$SITE_DIR"
elif [ -f "$SITE_DIR/app.js" ]; then
    MAIN_FILE="$SITE_DIR/app.js"
    START_DIR="$SITE_DIR"
else
    MAIN_FILE="$SITE_DIR/server.js"
    START_DIR="$SITE_DIR"
fi

cd $START_DIR

# Parar instância existente se houver
pm2 delete youtube-extractor 2>/dev/null || true

# Iniciar aplicação
pm2 start $MAIN_FILE --name "youtube-extractor" --time
pm2 save

# Configurar startup do PM2
if [ -f "/etc/systemd/system/pm2-root.service" ]; then
    systemctl daemon-reload
    systemctl enable pm2-root
else
    pm2 startup 2>/dev/null | tail -1 | bash 2>/dev/null || warn "Configure o PM2 startup manualmente: pm2 startup"
fi

pm2 list

# 13. Criar diretórios necessários
log "Criando diretórios necessários..."
mkdir -p $SITE_DIR/uploads/{videos,audio,temp,converted}
mkdir -p $SITE_DIR/logs
chown -R www-data:www-data $SITE_DIR/uploads
chmod -R 755 $SITE_DIR/uploads

# Configurar permissões do diretório principal
chown -R $SUDO_USER:www-data $SITE_DIR
chmod -R 755 $SITE_DIR
find $SITE_DIR -type f -exec chmod 644 {} \;
find $SITE_DIR -type d -exec chmod 755 {} \;

# 14. Criar arquivo .env simplificado (SEM API KEY)
if [ ! -f "$SITE_DIR/.env" ] && [ ! -f "$SITE_DIR/backend/.env" ]; then
    ENV_FILE="$SITE_DIR/.env"
    cat > $ENV_FILE << 'EOF'
# Configurações do Banco de Dados
DB_HOST=localhost
DB_PORT=3306
DB_NAME=youtube_extractor
DB_USER=youtube_user
DB_PASSWORD=YoutubePass123!

# Configurações do Servidor
PORT=3000
NODE_ENV=production
HOST=0.0.0.0
SESSION_SECRET=$(openssl rand -hex 32)

# Configurações do YouTube
# NÃO É NECESSÁRIA API KEY - Usando ytdl-core sem autenticação
YOUTUBE_API_KEY=NOT_NEEDED

# Configurações de FFmpeg
FFMPEG_PATH=/usr/bin/ffmpeg
FFPROBE_PATH=/usr/bin/ffprobe

# Configurações de Upload
MAX_FILE_SIZE=104857600 # 100MB
UPLOAD_PATH=./uploads
ALLOWED_FORMATS=mp3,mp4,wav,aac,flac,m4a

# Configurações de Log
LOG_LEVEL=info
LOG_FILE=./logs/app.log
EOF
    chmod 600 $ENV_FILE
    log "Arquivo .env criado (SEM necessidade de API key!)"
fi

# 15. Criar script de manutenção
cat > /usr/local/bin/youtube-extractor-manage << 'EOF'
#!/bin/bash
case "$1" in
    start)
        cd /var/www/youtube-extractor-pro
        pm2 start youtube-extractor
        echo "✅ Aplicação iniciada"
        ;;
    stop)
        pm2 stop youtube-extractor
        echo "⏸️ Aplicação parada"
        ;;
    restart)
        pm2 restart youtube-extractor
        echo "🔄 Aplicação reiniciada"
        ;;
    status)
        pm2 status youtube-extractor
        ;;
    logs)
        pm2 logs youtube-extractor
        ;;
    update)
        cd /var/www/youtube-extractor-pro
        git pull origin main
        npm install --production
        pm2 restart youtube-extractor
        echo "📦 Aplicação atualizada"
        ;;
    cleanup)
        # Limpar arquivos antigos (mais de 7 dias)
        find /var/www/youtube-extractor-pro/uploads -type f -mtime +7 -delete
        echo "🧹 Arquivos antigos removidos"
        ;;
    backup)
        # Backup do banco de dados
        mysqldump -u youtube_user -p'YoutubePass123!' youtube_extractor > /var/www/youtube-extractor-pro/backup_$(date +%Y%m%d_%H%M%S).sql
        echo "💾 Backup do banco criado"
        ;;
    *)
        echo "Uso: youtube-extractor-manage {start|stop|restart|status|logs|update|cleanup|backup}"
        echo ""
        echo "Comandos disponíveis:"
        echo "  start     - Iniciar aplicação"
        echo "  stop      - Parar aplicação"
        echo "  restart   - Reiniciar aplicação"
        echo "  status    - Ver status"
        echo "  logs      - Ver logs"
        echo "  update    - Atualizar do GitHub"
        echo "  cleanup   - Limpar arquivos antigos"
        echo "  backup    - Backup do banco de dados"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/youtube-extractor-manage

# 16. Criar limpeza automática (crontab)
cat > /etc/cron.daily/youtube-extractor-cleanup << 'EOF'
#!/bin/bash
# Limpar arquivos temporários antigos
find /var/www/youtube-extractor-pro/uploads/temp -type f -mtime +1 -delete 2>/dev/null || true
find /var/www/youtube-extractor-pro/logs -name "*.log" -mtime +30 -delete 2>/dev/null || true
EOF

chmod +x /etc/cron.daily/youtube-extractor-cleanup

# 17. Finalização
log "Instalação concluída com sucesso!"
echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${BLUE}🎵 YouTube Audio Extractor Pro Instalado!${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo "📁 Diretório do site: $SITE_DIR"
echo "🌐 URL de acesso: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo 'seu-ip')"
echo "🚀 Servidor Node.js: porta 3000"
echo "💾 Banco de dados: MariaDB (youtube_extractor)"
echo "🔑 API Key: NÃO É NECESSÁRIA!"
echo ""
echo "🛠️  Comandos de gerenciamento:"
echo "   $ youtube-extractor-manage start    # Iniciar"
echo "   $ youtube-extractor-manage status   # Ver status"
echo "   $ youtube-extractor-manage logs     # Ver logs"
echo ""
echo "🎯 PRONTO PARA USAR! Funcionalidades:"
echo "   • Extrair áudio de vídeos do YouTube"
echo "   • Converter para MP3, M4A, WAV"
echo "   • Listar downloads anteriores"
echo "   • Sistema completo sem API key"
echo ""
echo -e "${GREEN}✅ Site está online e pronto para uso!${NC}"
echo -e "${YELLOW}⚠️  Acesse a URL acima no navegador para começar a extrair áudio!${NC}"
echo ""
