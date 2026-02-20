#!/bin/bash
# Script para mover OpenClaw de ~/.openclaw para /var/www/openclaw

set -e

SOURCE_DIR="$HOME/.openclaw"
DEST_DIR="/var/www/openclaw"

echo "Movendo OpenClaw de $SOURCE_DIR para $DEST_DIR..."

# Criar diretório de destino com permissões corretas
sudo mkdir -p "$DEST_DIR"
sudo chown -R "$USER:$(id -gn)" "$DEST_DIR"

# Copiar arquivos preservando permissões e atributos estendidos
sudo rsync -avX "$SOURCE_DIR/" "$DEST_DIR/"

# Verificar se a cópia foi bem-sucedida
if [ $? -eq 0 ]; then
    echo "✓ Arquivos copiados com sucesso!"
    echo ""
    echo "Próximos passos:"
    echo "1. Atualize a configuração do OpenClaw para apontar para o novo diretório"
    echo "2. Execute: sudo chown -R $USER:$(id -gn) $DEST_DIR"
    echo "3. (Opcional) Remova o diretório antigo após verificar: rm -rf $SOURCE_DIR"
    echo ""
    echo "Para configurar o OpenClaw para usar o novo diretório, edite:"
    echo "  $DEST_DIR/openclaw.json"
    echo "  e ajuste 'agents.defaults.workspace' se necessário"
else
    echo "✗ Erro ao copiar arquivos"
    exit 1
fi
