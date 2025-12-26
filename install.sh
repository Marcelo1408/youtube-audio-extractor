#!/bin/bash
# fix-npm-permanent.sh

set -e

echo "🔧 Instalando Node.js/npm de forma permanente..."

# 1. Remover tudo relacionado a Node.js
echo "Removendo instalações antigas..."
apt remove --purge nodejs npm -y 2>/dev/null || true
apt autoremove -y

# 2. Limpar completamente
rm -rf /usr/local/bin/npm
rm -rf /usr/local/bin/node
rm -rf /usr/local/bin/npx
rm -rf /usr/lib/node_modules/
rm -rf /usr/local/lib/node_modules/
rm -rf ~/.npm
rm -rf ~/.nvm 2>/dev/null || true

# 3. Atualizar sistema
apt update
apt upgrade -y

# 4. Instalar curl se não existir
apt install -y curl wget

# 5. Instalar Node.js 18.x via APT (mais estável)
echo "Instalando Node.js 18.x..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# 6. Verificar instalação
echo "Verificando Node.js..."
if ! command -v node &> /dev/null; then
    echo "Node.js não instalado. Tentando método alternativo..."
    
    # Método alternativo: Instalar via pacote binário
    cd /tmp
    wget https://nodejs.org/dist/v18.17.0/node-v18.17.0-linux-x64.tar.xz
    tar -xf node-v18.17.0-linux-x64.tar.xz
    mv node-v18.17.0-linux-x64 /usr/local/lib/nodejs
    ln -sf /usr/local/lib/nodejs/bin/node /usr/local/bin/node
    ln -sf /usr/local/lib/nodejs/bin/npm /usr/local/bin/npm
    ln -sf /usr/local/lib/nodejs/bin/npx /usr/local/bin/npx
    rm -f node-v18.17.0-linux-x64.tar.xz
    
    # Adicionar ao PATH
    echo 'export PATH=/usr/local/lib/nodejs/bin:$PATH' >> /etc/profile
    source /etc/profile
fi

# 7. Verificar npm
echo "Verificando npm..."
if ! command -v npm &> /dev/null; then
    echo "npm não encontrado. Instalando separadamente..."
    curl -L https://www.npmjs.com/install.sh | sh
fi

# 8. Corrigir permissões
echo "Corrigindo permissões..."
mkdir -p /usr/local/lib/node_modules
chmod -R 755 /usr/local/lib/node_modules
mkdir -p ~/.npm
chown -R $USER:$(id -gn $USER) ~/.npm

# 9. Verificar instalação final
echo ""
echo "✅ Verificação final:"
echo "Node.js: $(node --version 2>/dev/null || echo 'NÃO INSTALADO')"
echo "npm: $(npm --version 2>/dev/null || echo 'NÃO INSTALADO')"
echo "PATH: $PATH"
echo "which node: $(which node 2>/dev/null || echo 'não encontrado')"
echo "which npm: $(which npm 2>/dev/null || echo 'não encontrado')"

# 10. Testar npm
echo ""
echo "🧪 Testando npm..."
npm --version > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ npm funcionando corretamente!"
else
    echo "❌ npm ainda não funciona. Tentando último recurso..."
    
    # Criar symlinks manuais
    ln -sf $(which node) /usr/bin/node 2>/dev/null || true
    ln -sf $(find /usr -name "npm" -type f 2>/dev/null | head -1) /usr/bin/npm 2>/dev/null || true
    
    # Verificar novamente
    if command -v npm &> /dev/null; then
        echo "✅ npm corrigido via symlink"
    else
        echo "❌ Falha crítica. Instale manualmente:"
        echo "curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -"
        echo "sudo apt-get install -y nodejs"
        exit 1
    fi
fi

echo ""
echo "🎉 Node.js/npm instalados permanentemente!"
