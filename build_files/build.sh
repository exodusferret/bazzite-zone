# ==========================================
# 5. Decky Loader + Plugins vorinstallieren
# ==========================================
echo "-> Installiere Decky Loader..."
# Offizieller Installer (non-interactive, für SteamOS/Bazzite geeignet)
curl -L "https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/install_release.sh" | sh

echo "-> Lade Decky Plugins herunter..."
PLUGIN_DIR="/usr/share/decky-plugins-staging"
mkdir -p "$PLUGIN_DIR"
cd "$PLUGIN_DIR"

PLUGINS=(
    "rr1111/decky-zotaccontrol"
    "AAGaming00/unifydeck"
    "aarron-lee/SimpleDeckTDP"
    "xXJSONDeruloXx/Decky-Framegen"
    "xXJSONDeruloXx/decky-lsfg-vk"
    "moi952/decky-proton-launch"
    "koffcheck/potato-deals"
    "Threshold-Labs/deckydecks"
    "Wurielle/decky-launch-options"
    "jacobdonahoe/decky-game-optimizer"
    "Starkka15/junkstore"
    "moraroy/NonSteamLaunchersDecky"
    "sebet/decky-nonsteam-badges"
    "totallynotbakadestroyer/Decky-Achievement"
    "pns-sh/SteamHuntersDeckyPlugin"
    "cat-in-a-box/Decky-Translator"
    "lobinuxsoft/decky-capydeploy"
    "Lui92/decky-protondb-collections"
    "kEnder242/decky-trailers"
    "ebdevag/optideck-deckdeals"
    "samedayhurt/reshady"
    "Echarnus/DeckyMetacritic"
    "jwhitlow45/free-loader"
    "itsOwen/playcount-decky"
    "SteamGridDB/decky-steamgriddb"
    "DeckThemes/decky-theme-loader"
    "Tormak9970/TabMaster"
)

for repo in "${PLUGINS[@]}"; do
    DOWNLOAD_URL=$(curl -sf "https://api.github.com/repos/$repo/releases/latest" \
        | grep 'browser_download_url.*\.tar\.gz' | cut -d '"' -f 4 | head -n 1)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "WARN: Kein Release (.tar.gz) gefunden für $repo – überspringe"
        continue
    fi

    if ! wget -q --show-progress "$DOWNLOAD_URL"; then
        echo "WARN: $repo konnte nicht geladen werden – überspringe"
        continue
    fi
done

for f in *.tar.gz; do
    [ -f "$f" ] && tar -xzf "$f" && rm "$f"
done

mkdir -p /usr/etc/profile.d/
cat > /usr/etc/profile.d/decky-zotac-sync.sh << 'EOF'
#!/bin/bash
USER_PLUGIN_DIR="$HOME/homebrew/plugins"
if [ -d "/usr/share/decky-plugins-staging" ]; then
    mkdir -p "$USER_PLUGIN_DIR"
    cp -rn /usr/share/decky-plugins-staging/* "$USER_PLUGIN_DIR/"
fi
EOF
chmod +x /usr/etc/profile.d/decky-zotac-sync.sh
