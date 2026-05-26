# Discord Dhéliat

Un bot météo écrit en Bash qui publie chaque matin la météo de **Lille** dans un salon Discord, via un webhook.

# Présentation du projet 

## À quoi ça sert ?

Le projet automatise une routine simple : tous les jours à 7h00, un script récupère la météo du jour sur [weather.com](https://weather.com), met en forme les informations, et les envoie sous forme d'embed dans un salon Discord.

L'embed contient :

- 🌡️ Les températures (matin, après-midi, soir, nuit)
- 💧 L'humidité
- 💨 Le vent
- ☀️ L'indice UV
- 👁️ La visibilité

## Structure du projet

```txt
discord-dheliat/
│── script.sh        # Script principal météo
│── install.sh       # Script d'installation
│── README.md        # Documentation
│── LICENSE          # Licence du projet
```

## Comment ça marche ?

Le projet contient deux scripts :

### [`script.sh`](script.sh)

Le script principal. Il :

1. Récupération des données météo Lille avec `lynx` (navigateur en mode texte).
2. Extrait les valeurs utiles (températures, humidité, vent, etc.) avec `grep` et `sed`.
3. Construit un payload JSON pour Discord à l'aide de `python3`.
4. Envoie le tout au webhook Discord avec `curl`.

L'URL du webhook est lue depuis la variable d'environnement `DISCORD_WEBHOOK`.

### [`install.sh`](install.sh)

Le script d'installation. Il :

1. Copie `script.sh` dans `/usr/local/bin/discord-dheliat/` (avec `sudo` si nécessaire).
2. Ajoute une ligne dans la **crontab** de l'utilisateur pour exécuter le script chaque jour à 7h00.
3. Redirige les logs d'exécution vers `/tmp/meteo.log` pour faciliter le débogage.

## Installation

```bash
./install.sh <URL_WEBHOOK_DISCORD>
```

Exemple :

```bash
./install.sh https://discord.com/api/webhooks/123456789/abcdefg
```

## Utilisation manuelle

Pour tester sans passer par le cron :

```bash
DISCORD_WEBHOOK='https://discord.com/api/webhooks/...' ./script.sh
```

## Dépendances

- `bash`
- `lynx`
- `curl`
- `python3`
- `iconv`
- `cron` (pour la planification automatique)

## Licence

Voir [LICENSE](LICENSE).
