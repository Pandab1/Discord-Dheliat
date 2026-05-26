#!/usr/bin/env bash

set -uo pipefail

DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"
if [[ -z "$DISCORD_WEBHOOK" ]]; then
    echo "[ERREUR] Variable DISCORD_WEBHOOK non définie." >&2
    exit 1
fi

CITY="Lille"
LOCATION="db749df24acdde958fc5a2c673b6ba1017b235853163a3c928af67f08127401e"
BASE_URL="https://weather.com/fr-FR/weather/today/l"
LYNX_OPTS="-dump -nolist -width=160 -accept_all_cookies"

# ── Helpers ────────────────────────────────────────────────────────────────

after_label() {
    LC_ALL=C awk -v pat="$1" '
        $0 ~ pat {
            while ((getline line) > 0) {
                sub(/^[[:space:]]+/, "", line)
                if (line != "" && line !~ /^\(BUTTON\)$/) { print line; exit }
            }
        }
    '
}

extract_int() { grep -oP -- '-?\d+' | head -1; }
trim()        { sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'; }

fetch() {
   lynx $LYNX_OPTS "${BASE_URL}/$1" 2>/dev/null | iconv -f latin1 -t utf-8 2>/dev/null
}

get_temp() {
    local raw="$1" label="$2"
    echo "$raw" | after_label "$label" | extract_int
}

get_field() {
    local raw="$1" label="$2"
    echo "$raw" | after_label "$label" | trim
}

fmt_temp() { [[ -n "$1" ]] && echo "${1}°C" || echo "N/A"; }
fmt_val()  { [[ -n "$1" ]] && echo "$1"     || echo "N/A"; }

# Échappe les caractères spéciaux JSON
json_esc() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])'; }

# ── Fetch & parse ──────────────────────────────────────────────────────────

echo "Récupération des données pour $CITY..." >&2
raw=$(fetch "$LOCATION")

if [[ -z "$raw" ]]; then
    echo "[ERREUR] Impossible de joindre weather.com." >&2
    exit 1
fi

matin=$(    get_temp "$raw" "^[[:space:]]*Matin$")
apm=$(      get_temp "$raw" "Apr.s-midi")
soir=$(     get_temp "$raw" "^[[:space:]]*Soir$")
nuit=$(     get_temp "$raw" "^[[:space:]]*Nuit$")
ressenti=$( echo "$raw" | LC_ALL=C grep -ia "ressentie" | grep -aoP -- '-?\d+' | head -1)
humidite=$( echo "$raw" | after_label "Humidit")
vent=$(     get_field "$raw" "^[[:space:]]*Vent$")
uv=$(       get_field "$raw" "Indice UV")
visibilite=$(echo "$raw" | after_label "Visibilit")

date_fr=$(LC_ALL=fr_FR.UTF-8 date '+%A %d %B %Y')

# ── Build Discord embed JSON ───────────────────────────────────────────────

payload=$(python3 << PYEOF
import json

embed = {
    "embeds": [{
        "title": "🌤️  Météo Lille — $(json_esc "$date_fr")",
        "color": 0x5865F2,
        "fields": [
            {
                "name": "🌡️  Températures",
                "value": (
                    "🌅 Matin       **$(fmt_temp "$matin")**\n"
                    "☀️  Après-midi  **$(fmt_temp "$apm")**\n"
                    "🌆 Soir        **$(fmt_temp "$soir")**\n"
                    "🌙 Nuit        **$(fmt_temp "$nuit")**"
                ),
                "inline": False
            },
            {
                "name": "🌬️  Conditions",
                "value": (
                    "🤔 Ressenti    **$(fmt_temp "$ressenti")**\n"
                    "💧 Humidité    **$(fmt_val  "$humidite")**\n"
                    "💨 Vent        **$(fmt_val  "$vent")**\n"
                    "☀️  Indice UV   **$(fmt_val  "$uv")**\n"
                    "👁️ Visibilité  **$(fmt_val  "$visibilite")**"
                ),
                "inline": False
            }
        ],
        "footer": {
            "text": "Source : weather.com  •  $(date '+%H:%M')"
        }
    }]
}
print(json.dumps(embed))
PYEOF
)

# ── Send to Discord ────────────────────────────────────────────────────────

response=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$payload" \
    "$DISCORD_WEBHOOK")

if [[ "$response" == "204" ]]; then
    echo "✓ Embed envoyé sur Discord (HTTP $response)."
else
    echo "[ERREUR] Discord a répondu HTTP $response." >&2
    echo "Payload envoyé :" >&2
    echo "$payload" >&2
    exit 1
fi
