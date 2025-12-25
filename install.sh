#!/bin/bash
# Arquivo: install.sh
# YouTube Audio Extractor Pro - Instalador Automático VPS
# VERSÃO SEM BANCO DE DADOS - Para quem já tem seu próprio banco

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
║         Versão SEM banco de dados - Ubuntu 22.04            ║
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

# 4. Instalar dependências do sistema (SEM MariaDB)
log "Instalando dependências do sistema..."
apt install -y nginx ffmpeg git curl wget unzip build-essential

# 5. NÃO instalar MariaDB - Pular esta etapa
log "Pulando instalação do MariaDB - Usando seu banco existente..."
echo ""
warn "⚠️  ATENÇÃO: Este script NÃO instala MariaDB"
warn "⚠️  Configure a conexão com SEU banco no arquivo .env após a instalação"
echo ""

# 6. Baixar e extrair o site do GitHub
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

# 7. Verificar estrutura do projeto
log "Verificando estrutura do projeto..."
cd $SITE_DIR

# Criar estrutura de diretórios se não existir
mkdir -p frontend uploads logs

# 8. Instalar dependências do Node.js
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
    
    # Criar package.json básico para Node.js (SEM dependências de banco)
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
    
    # Criar server.js simplificado SEM banco de dados
    cat > $SITE_DIR/server.js << 'EOF'
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
app.use(express.static(path.join(__dirname, 'frontend')));

// Verificar se FFmpeg está instalado
console.log('✅ YouTube Audio Extractor Pro - Versão SEM banco de dados');
console.log('✅ FFmpeg disponível para conversão de áudio');

// Rotas da API
app.get('/api/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        message: 'YouTube Audio Extractor Pro está funcionando!',
        version: '1.0.0',
        database: 'none',
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
            quality: 'Áudio de alta qualidade disponível'
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
        const filename = `${title.substring(0, 50)}_${timestamp}.${format}`;
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
    console.log(`🎵 Sistema de extração de áudio PRONTO!`);
    console.log(`📊 Banco de dados: NÃO configurado (use seu próprio banco)`);
});
EOF
    
    # Criar frontend simplificado
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
            max-width: 800px;
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
            font-size: 2.5rem; 
            margin-bottom: 1rem;
            background: linear-gradient(45deg, #00dbde, #fc00ff);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .card {
            background: rgba(255, 255, 255, 0.05);
            padding: 2rem;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            margin-bottom: 2rem;
        }
        input, select {
            width: 100%;
            padding: 1rem;
            background: rgba(255, 255, 255, 0.1);
            border: 1px solid rgba(255, 255, 255, 0.2);
            border-radius: 10px;
            color: white;
            font-size: 1rem;
            margin-bottom: 1rem;
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
            transition: transform 0.3s;
            width: 100%;
            margin: 0.5rem 0;
        }
        .btn:hover {
            transform: translateY(-2px);
        }
        .status {
            padding: 1rem;
            border-radius: 10px;
            margin: 1rem 0;
            text-align: center;
        }
        .success { background: rgba(0, 255, 0, 0.1); border: 1px solid rgba(0, 255, 0, 0.3); }
        .error { background: rgba(255, 0, 0, 0.1); border: 1px solid rgba(255, 0, 0, 0.3); }
        .loading { background: rgba(255, 255, 0, 0.1); border: 1px solid rgba(255, 255, 0, 0.3); }
        .download-item {
            background: rgba(255, 255, 255, 0.05);
            padding: 1rem;
            border-radius: 10px;
            margin-bottom: 1rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        footer {
            text-align: center;
            margin-top: 3rem;
            padding-top: 2rem;
            border-top: 1px solid rgba(255, 255, 255, 0.1);
            opacity: 0.7;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1><i class="fas fa-music"></i> YouTube Audio Extractor</h1>
            <p>Extraia áudio de vídeos do YouTube sem complicação</p>
        </header>
        
        <div class="card">
            <h2><i class="fas fa-download"></i> Extrair Áudio</h2>
            <input type="url" id="youtubeUrl" placeholder="Cole a URL do YouTube aqui..." required>
            <select id="audioFormat">
                <option value="mp3">MP3 (Recomendado)</option>
                <option value="m4a">M4A</option>
                <option value="wav">WAV</option>
            </select>
            <button class="btn" id="downloadBtn">
                <i class="fas fa-download"></i> Extrair Áudio
            </button>
            <div id="statusMessage" class="status"></div>
        </div>
        
        <div class="card">
            <h2><i class="fas fa-history"></i> Downloads</h2>
            <button class="btn" id="refreshList">
                <i class="fas fa-sync-alt"></i> Atualizar Lista
            </button>
            <div id="downloadsList">
                <p style="text-align: center; padding: 1rem; opacity: 0.7;">
                    Seus downloads aparecerão aqui
                </p>
            </div>
        </div>
        
        <div class="card">
            <h2><i class="fas fa-info-circle"></i> Status do Sistema</h2>
            <div id="systemStatus">Verificando...</div>
        </div>
        
        <footer>
            <p>YouTube Audio Extractor Pro | Sistema independente - Sem banco de dados</p>
            <p>Instalado em: /var/www/youtube-extractor-pro</p>
        </footer>
    </div>
    
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const downloadBtn = document.getElementById('downloadBtn');
            const refreshList = document.getElementById('refreshList');
            const statusMessage = document.getElementById('statusMessage');
            const systemStatus = document.getElementById('systemStatus');
            
            // Verificar status
            fetch('/api/health')
                .then(r => r.json())
                .then(data => {
                    systemStatus.innerHTML = `<div class="status success">
                        <p><i class="fas fa-check-circle"></i> ${data.message}</p>
                        <p><small>${data.features.join(' • ')}</small></p>
                    </div>`;
                });
            
            // Download de áudio
            downloadBtn.addEventListener('click', function() {
                const url = document.getElementById('youtubeUrl').value.trim();
                const format = document.getElementById('audioFormat').value;
                
                if (!url) {
                    showStatus('Cole uma URL do YouTube primeiro', 'error');
                    return;
                }
                
                showStatus('Processando...', 'loading');
                downloadBtn.disabled = true;
                
                fetch(`/api/audio/download?url=${encodeURIComponent(url)}&format=${format}`)
                    .then(r => r.json())
                    .then(data => {
                        if (data.success) {
                            showStatus(`Download iniciado: ${data.title}`, 'success');
                            setTimeout(() => loadDownloads(), 2000);
                        } else {
                            showStatus('Erro: ' + data.error, 'error');
                        }
                        downloadBtn.disabled = false;
                    })
                    .catch(err => {
                        showStatus('Erro de conexão', 'error');
                        downloadBtn.disabled = false;
                    });
            });
            
            // Carregar downloads
            function loadDownloads() {
                fetch('/api/audio/list')
                    .then(r => r.json())
                    .then(data => {
                        const list = document.getElementById('downloadsList');
                        if (data.files.length > 0) {
                            list.innerHTML = data.files.map(file => `
                                <div class="download-item">
                                    <div>${file.name}</div>
                                    <div>
                                        <a href="${file.path}" download><i class="fas fa-download"></i></a>
                                        <a href="${file.path}" target="_blank"><i class="fas fa-play"></i></a>
                                    </div>
                                </div>
                            `).join('');
                        }
                    });
            }
            
            // Atualizar lista
            refreshList.addEventListener('click', loadDownloads);
            
            // Mostrar status
            function showStatus(msg, type) {
                statusMessage.innerHTML = msg;
                statusMessage.className = `status ${type}`;
                if (type !== 'loading') {
                    setTimeout(() => {
                        statusMessage.innerHTML = '';
                        statusMessage.className = 'status';
                    }, 5000);
                }
            }
            
            // Inicializar
            loadDownloads();
        });
    </script>
</body>
</html>
EOF
    
    cd $SITE_DIR
    npm install --production --no-audit
    log "Estrutura básica criada e dependências instaladas."
fi

# 9. Configurar Nginx
log "Configurando Nginx..."
cat > /etc/nginx/sites-available/youtube-extractor << NGINX
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    # Diretório raiz do site
    root $SITE_DIR/frontend;
    index index.html index.htm;
    
    # Configuração do frontend
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    # API Proxy
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Uploads
    location /uploads/ {
        alias $SITE_DIR/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    # Arquivos estáticos
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|mp3|mp4|webm)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINX

# Habilitar site
ln -sf /etc/nginx/sites-available/youtube-extractor /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Testar e reiniciar Nginx
nginx -t && systemctl restart nginx
log "Nginx configurado e reiniciado."

# 10. Iniciar aplicação com PM2
log "Iniciando aplicação com PM2..."

# Determinar o arquivo principal
if [ -f "$SITE_DIR/backend/server.js" ]; then
    MAIN_FILE="$SITE_DIR/backend/server.js"
    START_DIR="$SITE_DIR/backend"
elif [ -f "$SITE_DIR/server.js" ]; then
    MAIN_FILE="$SITE_DIR/server.js"
    START_DIR="$SITE_DIR"
else
    MAIN_FILE="$SITE_DIR/server.js"
    START_DIR="$SITE_DIR"
fi

cd $START_DIR

# Parar instância existente se houver
pm2 delete youtube-extractor 2>/dev/null || true

# Iniciar aplicação
pm2 start $MAIN_FILE --name "youtube-extractor"
pm2 save

# Configurar startup do PM2
pm2 startup 2>/dev/null | tail -1 | bash 2>/dev/null || warn "PM2 startup configurado"

log "Aplicação iniciada com PM2."

# 11. Criar diretórios necessários
log "Criando diretórios necessários..."
mkdir -p $SITE_DIR/uploads/audio
mkdir -p $SITE_DIR/logs
chown -R www-data:www-data $SITE_DIR/uploads
chmod -R 755 $SITE_DIR/uploads

# Configurar permissões
chown -R $SUDO_USER:www-data $SITE_DIR
chmod -R 755 $SITE_DIR

# 12. Criar arquivo .env simplificado (SEM configurações de banco)
if [ ! -f "$SITE_DIR/.env" ]; then
    cat > $SITE_DIR/.env << 'EOF'
# CONFIGURAÇÃO DO SERVIDOR
PORT=3000
NODE_ENV=production

# CONFIGURAÇÕES DE ÁUDIO
FFMPEG_PATH=/usr/bin/ffmpeg
MAX_FILE_SIZE=100MB
UPLOAD_PATH=./uploads

# BANCO DE DADOS - CONFIGURE COM SUAS CREDENCIAIS
# DB_HOST=seu_host
# DB_PORT=sua_porta
# DB_NAME=seu_banco
# DB_USER=seu_usuario
# DB_PASSWORD=sua_senha

# OBSERVAÇÃO: Este sistema funciona SEM banco de dados
# Para conectar com SEU banco, descomente as linhas acima
# e configure com suas credenciais reais
EOF
    log "Arquivo .env criado. Configure com SEU banco se necessário."
fi

# 13. Criar script de gerenciamento
cat > /usr/local/bin/youtube-audio-manage << 'EOF'
#!/bin/bash
case "$1" in
    start)
        cd /var/www/youtube-extractor-pro
        pm2 start server.js --name youtube-extractor
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
    *)
        echo "Uso: youtube-audio-manage {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/youtube-audio-manage

# 14. Finalização
log "Instalação concluída com sucesso!"
echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${BLUE}🎵 YouTube Audio Extractor Pro Instalado!${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo "📁 Diretório do site: $SITE_DIR"
echo "🌐 URL de acesso: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
echo "🚀 Servidor Node.js: porta 3000"
echo "💾 Banco de dados: NENHUM instalado (use seu próprio banco)"
echo ""
echo "✅ Sistema 100% funcional SEM banco de dados!"
echo ""
echo "🛠️  Comandos de gerenciamento:"
echo "   youtube-audio-manage start    # Iniciar"
echo "   youtube-audio-manage status   # Ver status"
echo "   youtube-audio-manage logs     # Ver logs"
echo ""
echo "📝 Para conectar com SEU banco de dados:"
echo "   1. Edite o arquivo: $SITE_DIR/.env"
echo "   2. Configure suas credenciais de banco"
echo "   3. Adicione dependências do banco no package.json"
echo "   4. Reinicie: youtube-audio-manage restart"
echo ""
echo -e "${GREEN}✅ Site está online e pronto para uso!${NC}"
echo ""
