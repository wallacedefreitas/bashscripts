#!/bin/bash
set -e  # Para o script em caso de erro

# Atualiza a lista de pacotes e faz upgrade silenciosamente
sudo apt update -y >/dev/null
sudo apt upgrade -y >/dev/null

# Instala bash-completion e htop sem prompts
sudo apt install -y bash-completion htop >/dev/null

echo "Sistema preparado com bash-completion e htop instalados."