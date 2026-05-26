#!/bin/bash
#
# install.sh - Installation du script meteo.sh avec planification crontab sur Linux
#
# Usage : ./install.sh <URL_WEBHOOK_DISCORD>
#

set -e

# --- Vérification du paramètre ---
if [ $# -ne 1 ]; then
    echo "Usage : $0 <URL_WEBHOOK_DISCORD>"
    echo "Exemple : $0 https://discord.com/api/webhooks/123456789/abcdefg"
    exit 1
fi

WEBHOOK_URL="$1"

# --- Validation basique de l'URL ---
if [[ ! "$WEBHOOK_URL" =~ ^https://discord\.com/api/webhooks/ ]] && \
   [[ ! "$WEBHOOK_URL" =~ ^https://discordapp\.com/api/webhooks/ ]]; then
    echo "Erreur : l'URL ne ressemble pas à un webhook Discord valide."
    echo "Format attendu : https://discord.com/api/webhooks/..."
    exit 1
fi

# --- Définition des chemins ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/script.sh"
INSTALL_DIR="/usr/local/bin/discord-dheliat"
INSTALLED_SCRIPT="$INSTALL_DIR/script.sh"

# --- Vérification de la présence du script source ---
if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo "Erreur : le fichier script.sh est introuvable dans $SCRIPT_DIR"
    echo "Si cette erreur persiste essayez de recloner le projet depuis Git"
    exit 1
fi

# --- Vérification des droits (sudo nécessaire pour /usr/local/bin) ---
if [ ! -w "$INSTALL_DIR" ]; then
    echo "Installation dans $INSTALL_DIR (nécessite sudo)..."
    SUDO="sudo"
else
    SUDO=""
fi

# --- Copie du script et attribution des droits d'exécution ---
echo "Installation de script.sh dans $INSTALL_DIR..."
$SUDO rm -rf "$INSTALL_DIR"
$SUDO mkdir "$INSTALL_DIR"
$SUDO cp "$SOURCE_SCRIPT" "$INSTALLED_SCRIPT"
$SUDO chmod +x "$INSTALLED_SCRIPT"
echo "OK : $INSTALLED_SCRIPT"

# --- Préparation de la ligne crontab ---
# Exécution tous les jours à 7h00, l'URL est passée en variable d'environnement
CRON_LINE="0 7 * * * DISCORD_WEBHOOK='$WEBHOOK_URL' $INSTALLED_SCRIPT >> /tmp/meteo.log 2>&1"

# --- Ajout dans la crontab de l'utilisateur courant ---
echo "Ajout de la tâche dans la crontab..."

# Récupération de la crontab existante (sans erreur si vide)
EXISTING_CRON=$(crontab -l 2>/dev/null || true)

# Suppression d'une éventuelle ancienne ligne cron pour éviter les doublons
NEW_CRON=$(echo "$EXISTING_CRON" | grep -v "$INSTALLED_SCRIPT" || true)

# Ajout de la nouvelle ligne
{
    [ -n "$NEW_CRON" ] && echo "$NEW_CRON"
    echo "$CRON_LINE"
} | crontab -

echo ""
echo "Installation terminée avec succès !"
echo ""
echo "Récapitulatif :"
echo "  - Script installé : $INSTALLED_SCRIPT"
echo "  - Planification   : tous les jours à 07h00"
echo "  - Logs            : /tmp/meteo.log"
echo ""
echo "Vérifier la crontab : crontab -l"
echo "Tester manuellement : DISCORD_WEBHOOK='$WEBHOOK_URL' $INSTALLED_SCRIPT"