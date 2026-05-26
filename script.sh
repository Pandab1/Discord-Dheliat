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
    LC_ALL=C sed -n "/$1/{
        :next
        n
        s/^[[:space:]]*//
        /^$/b next
        /^(BUTTON)$/b next
        p
        q
    }"
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

get_pollen() {
    local line
    line=$(echo "$1" | after_label "pollen")
    if   echo "$line" | grep -qi "très élevé"; then echo "🔴 Très élevé"
    elif echo "$line" | grep -qi "élevé";       then echo "🟠 Élevé"
    elif echo "$line" | grep -qi "faible";     then echo "🟡 Faible"
    elif echo "$line" | grep -qi "pas";      then echo "🟢 Aucun"
    else echo "N/A"
    fi
}

get_condition() {
    LC_ALL=C sed -n '/partir de/{
        n
        :next
        n
        s/^[[:space:]]*//
        /^$/b next
        /^(BUTTON)$/b next
        p
        q
    }' <<< "$1"
}

get_color() {
    local cond="${1,,}"  # lowercase
    if   echo "$cond" | grep -qiE "neige"; then
        echo "16777215"
    elif echo "$cond" | grep -qiE "pluie|averses"; then
        echo "3447003"
    elif echo "$cond" | grep -qiE "ensoleillé|beau|dégagé"; then
        echo "16766720"
    else
        echo "5793266"
    fi
}

get_image_url() {
    local cond="${1,,}"
    if   echo "$cond" | grep -qiE "neige"; then
        echo "https://openweathermap.org/img/wn/13d@2x.png"
    elif echo "$cond" | grep -qiE "orage|tonnerre"; then
        echo "https://openweathermap.org/img/wn/11d@2x.png"
    elif echo "$cond" | grep -qiE "pluie|averses"; then
        echo "https://openweathermap.org/img/wn/10d@2x.png"
    elif echo "$cond" | grep -qiE "brouillard|brume"; then
        echo "https://openweathermap.org/img/wn/50d@2x.png"
    elif echo "$cond" | grep -qiE "ensoleillé|beau|dégagé"; then
        echo "https://openweathermap.org/img/wn/01d@2x.png"
    else
        echo "https://openweathermap.org/img/wn/03d@2x.png"
    fi
}

fmt_temp() { [[ -n "$1" ]] && echo "${1}°C" || echo "N/A"; }
fmt_val()  { [[ -n "$1" ]] && echo "$1"     || echo "N/A"; }

json_esc() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])'; }

# ── Fetch & parse ──────────────────────────────────────────────────────────

echo "Récupération des données pour $CITY..." >&2
raw=$(fetch "$LOCATION")

if [[ -z "$raw" ]]; then
    echo "[ERREUR] Impossible de joindre weather.com." >&2
    exit 1
fi

matin=$(get_temp "$raw" "Matin$")
apm=$(get_temp "$raw" "Après-midi$")
soir=$(get_temp "$raw" "Soir$")
nuit=$(get_temp "$raw" "Nuit$")
humidite=$(echo "$raw" | after_label "Humidité$")
vent=$(get_field "$raw" "Vent$")
uv=$(get_field "$raw" "Indice UV$")
visibilite=$(echo "$raw" | after_label "Visibilité$")
pollen=$(get_pollen "$raw")

condition=$(get_condition "$raw")
color=$(get_color "$condition")
image_url=$(get_image_url "$condition")
date_fr=$(LC_ALL=fr_FR.UTF-8 date '+%A %d %B %Y')

# ── Build Discord embed JSON ───────────────────────────────────────────────

payload=$(python3 << PYEOF
import json

embed = {
    "embeds": [{
        "title": "🌤️  Météo — Lille",
        "thumbnail": {"url": "$(json_esc "$image_url")"},
        "description": (
            "📅  **$(json_esc "$date_fr")**\n"
            "\u200b\n"
            "🌅  **Matin**            $(fmt_temp "$matin")\u2003\u2003\u2003"
            "☀️  **Après\u2011midi**  $(fmt_temp "$apm")\n"
            "🌆  **Soir**             $(fmt_temp "$soir")\u2003\u2003\u2003"
            "🌙  **Nuit**             $(fmt_temp "$nuit")\n"
        ),
        "color": $color,
        "fields": [
            {"name": "💧  Humidité",   "value": "$(fmt_val  "$humidite")",   "inline": True},
            {"name": "💨  Vent",       "value": "$(fmt_val  "$vent")",       "inline": True},
            {"name": "☀️  Indice UV",  "value": "$(fmt_val  "$uv")",         "inline": True},
            {"name": "👁️  Visibilité", "value": "$(fmt_val  "$visibilite")", "inline": True},
            {"name": "🌿  Pollen",     "value": "$(json_esc "$pollen")",     "inline": True},
        ],
        "footer": {
            "text": "Source : weather.com"
        },
        "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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
