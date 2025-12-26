#!/bin/bash
# install-final.sh - Instalação final com correção de npm

set -e

echo "🔧 Corrigindo instalação do Node.js/npm..."

# ==================== INSTALAR NODE.JS CORRETAMENTE ====================

# 1. Remover instalações problemáticas
apt remove --purge nodejs npm -y 2>/dev/null || true
apt autoremove -y

# 2. Limpar arquivos residuais
rm -rf /usr/local/bin/npm
rm -rf /usr/local/bin/node
rm -rf /usr/lib/node_modules/
rm -rf ~/.npm

# 3. Instalar via apt com força
apt update
apt install -y curl

# 4. Instalar Node.js 18.x via script oficial
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# 5. Verificar instalação
echo "Verificando Node.js: $(node --version 2>/dev/null || echo 'NÃO INSTALADO')"
echo "Verificando npm: $(npm --version 2>/dev/null || echo 'NÃO INSTALADO')"

# 6. Se ainda não funcionar, instalar npm separadamente
if ! command -v npm &> /dev/null; then
    echo "Instalando npm separadamente..."
    curl -L https://www.npmjs.com/install.sh | sh
fi

# 7. Corrigir permissões
mkdir -p ~/.npm
chown -R $SUDO_USER:$SUDO_USER ~/.npm 2>/dev/null || true

# ==================== CONTINUAR INSTALAÇÃO DO PROJETO ====================

PROJECT_DIR="/opt/youtube-audio-extractor"
cd "$PROJECT_DIR"

echo "📦 Instalando dependências do projeto em $PROJECT_DIR..."

# Verificar se package.json existe
if [ -f "package.json" ]; then
    echo "package.json encontrado. Instalando dependências..."
    
    # Instalar com opções para evitar problemas
    npm install --legacy-peer-deps --no-audit --fund false
    
    if [ $? -eq 0 ]; then
        echo "✅ Dependências instaladas com sucesso!"
    else
        echo "⚠️  Tentando instalação forçada..."
        npm cache clean --force
        npm install --force
    fi
else
    echo "❌ package.json não encontrado em $PROJECT_DIR"
    echo "Criando package.json básico..."
    
    cat > package.json << 'EOF'
{
  "name": "youtube-audio-extractor",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "ytdl-core": "^4.11.5"
  }
}
EOF
    
    npm install
fi

# ==================== VERIFICAR INSTALAÇÃO ====================
echo ""
echo "📊 Verificação final:"
echo "Node.js: $(node --version)"
echo "npm: $(npm --version)"
echo "Diretório: $(pwd)"
echo "Arquivos: $(ls -la | grep -E '(package|server)')"

# ==================== INICIAR APLICAÇÃO ====================
echo ""
echo "🚀 Iniciando aplicação..."

# Instalar PM2 se não estiver
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2
fi

# Parar instância existente
pm2 delete youtube-extractor 2>/dev/null || true

# Iniciar
if [ -f "server.js" ]; then
    pm2 start server.js --name "youtube-extractor"
elif [ -f "app.js" ]; then
    pm2 start app.js --name "youtube-extractor"
else
    # Criar server.js básico
    cat > server.js << 'EOF'
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
    res.json({
        message: 'YouTube Audio Extractor Pro',
        status: 'online',
        version: '1.0.0'
    });
});

app.listen(port, () => {
    console.log(`Servidor rodando na porta ${port}`);
});
EOF
    pm2 start server.js --name "youtube-extractor"
fi

pm2 save
pm2 startup 2>/dev/null || true

echo ""
echo "✅ Instalação finalizada!"
echo "🌐 Acesse: http://$(hostname -I | awk '{print $1}'):3000"
echo "📊 Status: pm2 status"
