# No diretório do projeto
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
    "ytdl-core": "^4.11.5"
  }
}
EOF

# Instalar
npm install
