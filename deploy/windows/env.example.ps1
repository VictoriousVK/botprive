# Réglages de la plateforme (copié en .env.ps1 par install.ps1). NE PAS partager ce fichier.

# --- MetaTrader 5 ---
# Laissez vide pour utiliser le terminal MT5 déjà ouvert et connecté sur ce PC (recommandé).
$env:MT5_PATH = ""            # ex. "C:\Program Files\MetaTrader 5\terminal64.exe"
$env:MT5_LOGIN = ""           # numéro de compte (optionnel)
$env:MT5_PASSWORD = ""        # mot de passe du compte (optionnel)
$env:MT5_SERVER = ""          # ex. "VotreBroker-Demo" (optionnel)
$env:MT5_SERVER_UTC_OFFSET_HOURS = "2"   # décalage horaire du serveur du broker (souvent 2 ou 3), utilisé marché fermé

# --- Plateforme web ---
$env:HF_FEED = "auto"         # auto | mt5 | simulation
$env:HF_HOST = "127.0.0.1"    # ne changez pas : exposez via Cloudflare Tunnel ou Caddy (HTTPS)
$env:HF_PORT = "8000"
$env:HF_COOKIE_SECURE = "1"   # mettez "0" UNIQUEMENT pour un accès local en http://127.0.0.1
$env:HF_PUBLIC_HOST = ""      # ex. "trading.mondomaine.com" si servi derrière un proxy/tunnel
$env:HF_TRUST_PROXY = "0"     # "1" si derrière Cloudflare Tunnel / Caddy (IP réelle pour l'anti-bruteforce)

# --- Site Liberté Financière (voir docs/SITE.md) ---
$env:LF_PUBLIC_URL = ""            # ex. "https://liberte-financiere.com" (https obligatoire pour Wave)
$env:LF_WAVE_API_KEY = ""          # clé API Wave Checkout (vide = paiement Wave manuel, validé dans /admin/)
$env:LF_WAVE_WEBHOOK_SECRET = ""   # secret du webhook Wave (https://votredomaine/api/webhooks/wave)
$env:LF_REGISTRATION = "1"         # "0" pour fermer les inscriptions
$env:LF_COPYTRADING = "demo"       # off | demo (la copie réelle attend l'avis juridique)
$env:LF_MEDIA_HOSTS = ""           # domaines autorisés pour des fichiers vidéo .mp4 (sinon Bunny/Mux/Vimeo…)

# --- Argent réel ---
# Laisser à "0" tant que vous n'avez pas validé plusieurs semaines en démo.
$env:HF_ALLOW_REAL_TRADING = "0"

# --- Alertes (optionnel) : URL de webhook Slack/Discord-compatible ({"text": ...}) ---
$env:ALERT_WEBHOOK_URL = ""

# --- Recherche Opus (optionnel, payant) ---
# $env:ANTHROPIC_API_KEY = "sk-ant-..."
