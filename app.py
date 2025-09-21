import streamlit as st
import pandas as pd
import sqlite3
import hashlib
import datetime
import json
from datetime import datetime, timedelta
import requests
import time

# Configuration de la page
st.set_page_config(
    page_title="ICT Pure Master - Admin",
    page_icon="🔒",
    layout="wide",
    initial_sidebar_state="expanded"
)


# Initialisation de la base de données
def init_db():
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    # Table des administrateurs
    c.execute('''CREATE TABLE IF NOT EXISTS admins
                 (id INTEGER PRIMARY KEY, username TEXT, password_hash TEXT)''')

    # Table des comptes autorisés
    c.execute('''CREATE TABLE IF NOT EXISTS authorized_accounts
                 (id INTEGER PRIMARY KEY, 
                  account_number TEXT UNIQUE, 
                  account_name TEXT,
                  broker TEXT,
                  status TEXT,
                  activation_date TEXT,
                  expiration_date TEXT,
                  last_connection TEXT)''')

    # Table des demandes d'accès
    c.execute('''CREATE TABLE IF NOT EXISTS access_requests
                 (id INTEGER PRIMARY KEY, 
                  account_number TEXT, 
                  account_name TEXT,
                  broker TEXT,
                  request_date TEXT,
                  status TEXT)''')

    # Table des logs d'activité
    c.execute('''CREATE TABLE IF NOT EXISTS activity_logs
                 (id INTEGER PRIMARY KEY, 
                  account_number TEXT, 
                  activity_type TEXT,
                  activity_date TEXT,
                  details TEXT)''')

    # Insertion de l'admin par défaut (à changer après la première connexion)
    c.execute("SELECT COUNT(*) FROM admins")
    if c.fetchone()[0] == 0:
        default_password = hashlib.sha256("admin123".encode()).hexdigest()
        c.execute("INSERT INTO admins (username, password_hash) VALUES (?, ?)",
                  ("admin", default_password))

    conn.commit()
    conn.close()


# Hashage des mots de passe
def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()


# Vérification de l'authentification
def check_auth(username, password):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()
    password_hash = hash_password(password)
    c.execute("SELECT * FROM admins WHERE username = ? AND password_hash = ?",
              (username, password_hash))
    result = c.fetchone()
    conn.close()
    return result is not None


# Fonction pour ajouter un compte autorisé
def add_authorized_account(account_number, account_name, broker, duration_days=30):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    activation_date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    expiration_date = (datetime.now() + timedelta(days=duration_days)).strftime("%Y-%m-%d %H:%M:%S")

    try:
        c.execute('''INSERT INTO authorized_accounts 
                    (account_number, account_name, broker, status, activation_date, expiration_date, last_connection)
                    VALUES (?, ?, ?, ?, ?, ?, ?)''',
                  (account_number, account_name, broker, "Active", activation_date, expiration_date, ""))
        conn.commit()

        # Ajouter une entrée dans les logs
        log_activity(account_number, "ACCOUNT_ACTIVATED",
                     f"Compte activé jusqu'au {expiration_date}")

        return True
    except sqlite3.IntegrityError:
        return False
    finally:
        conn.close()


# Fonction pour révoquer un compte
def revoke_account(account_number):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    c.execute("UPDATE authorized_accounts SET status = 'Revoked' WHERE account_number = ?",
              (account_number,))
    conn.commit()
    conn.close()

    # Ajouter une entrée dans les logs
    log_activity(account_number, "ACCOUNT_REVOKED", "Accès révoqué par l'administrateur")


# Fonction pour enregistrer les activités
def log_activity(account_number, activity_type, details):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    activity_date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    c.execute('''INSERT INTO activity_logs 
                (account_number, activity_type, activity_date, details)
                VALUES (?, ?, ?, ?)''',
              (account_number, activity_type, activity_date, details))

    conn.commit()
    conn.close()


# Fonction pour obtenir les comptes autorisés
def get_authorized_accounts():
    conn = sqlite3.connect('ict_master.db')
    df = pd.read_sql_query("SELECT * FROM authorized_accounts ORDER BY activation_date DESC", conn)
    conn.close()
    return df


# Fonction pour obtenir les demandes d'accès
def get_access_requests():
    conn = sqlite3.connect('ict_master.db')
    df = pd.read_sql_query("SELECT * FROM access_requests WHERE status = 'Pending' ORDER BY request_date DESC", conn)
    conn.close()
    return df


# Fonction pour obtenir les logs d'activité
def get_activity_logs(limit=100):
    conn = sqlite3.connect('ict_master.db')
    df = pd.read_sql_query(f"SELECT * FROM activity_logs ORDER BY activity_date DESC LIMIT {limit}", conn)
    conn.close()
    return df


# Fonction pour mettre à jour la dernière connexion
def update_last_connection(account_number):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    last_connection = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    c.execute("UPDATE authorized_accounts SET last_connection = ? WHERE account_number = ?",
              (last_connection, account_number))

    conn.commit()
    conn.close()

    # Ajouter une entrée dans les logs
    log_activity(account_number, "BOT_CONNECTION", "Connexion au bot ICT Pure Master")


# Fonction pour vérifier si un compte est autorisé
def is_account_authorized(account_number):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    c.execute('''SELECT status, expiration_date FROM authorized_accounts 
                 WHERE account_number = ? AND status = "Active"''', (account_number,))
    result = c.fetchone()
    conn.close()

    if result:
        status, expiration_date = result
        # Vérifier si la licence a expiré
        exp_date = datetime.strptime(expiration_date, "%Y-%m-%d %H:%M:%S")
        if datetime.now() > exp_date:
            # Mettre à jour le statut comme expiré
            conn = sqlite3.connect('ict_master.db')
            c = conn.cursor()
            c.execute("UPDATE authorized_accounts SET status = 'Expired' WHERE account_number = ?",
                      (account_number,))
            conn.commit()
            conn.close()

            # Ajouter une entrée dans les logs
            log_activity(account_number, "LICENSE_EXPIRED", "La licence a expiré")
            return False

        return True
    return False


# Interface de connexion
# Interface de connexion
def login_section():
    st.sidebar.title("Connexion Admin")
    username = st.sidebar.text_input("Nom d'utilisateur")
    password = st.sidebar.text_input("Mot de passe", type="password")

    if st.sidebar.button("Se connecter"):
        if check_auth(username, password):
            st.session_state.authenticated = True
            st.session_state.username = username
            st.sidebar.success("Connexion réussie!")
            st.rerun()  # CORRECTION ICI
        else:
            st.sidebar.error("Identifiants incorrects")


# Interface principale de l'admin
def admin_dashboard():
    st.title("🔒 ICT Pure Master - Administration")

    # Menu sidebar
    st.sidebar.title(f"Bienvenue, {st.session_state.username}")
    menu_option = st.sidebar.radio("Navigation",
                                   ["Tableau de bord", "Gestion des comptes", "Demandes d'accès", "Logs d'activité",
                                    "Paramètres"])

    if menu_option == "Tableau de bord":
        show_dashboard()
    elif menu_option == "Gestion des comptes":
        show_account_management()
    elif menu_option == "Demandes d'accès":
        show_access_requests()
    elif menu_option == "Logs d'activité":
        show_activity_logs()
    elif menu_option == "Paramètres":
        show_settings()


# Tableau de bord
def show_dashboard():
    st.header("📊 Tableau de bord")

    # Récupérer les données
    authorized_accounts = get_authorized_accounts()
    activity_logs = get_activity_logs(10)

    # Métriques
    col1, col2, col3, col4 = st.columns(4)

    active_accounts = authorized_accounts[authorized_accounts['status'] == 'Active'].shape[0]
    expired_accounts = authorized_accounts[authorized_accounts['status'] == 'Expired'].shape[0]
    revoked_accounts = authorized_accounts[authorized_accounts['status'] == 'Revoked'].shape[0]
    total_accounts = authorized_accounts.shape[0]

    col1.metric("Comptes actifs", active_accounts)
    col2.metric("Comptes expirés", expired_accounts)
    col3.metric("Comptes révoqués", revoked_accounts)
    col4.metric("Total comptes", total_accounts)

    # Graphique des comptes par statut
    st.subheader("Répartition des comptes")
    status_counts = authorized_accounts['status'].value_counts()
    st.bar_chart(status_counts)

    # Dernières activités
    st.subheader("Dernières activités")
    st.dataframe(activity_logs)


# Gestion des comptes
def show_account_management():
    st.header("👥 Gestion des comptes")

    # Ajouter un nouveau compte
    with st.expander("➕ Ajouter un nouveau compte"):
        col1, col2 = st.columns(2)
        with col1:
            new_account = st.text_input("Numéro de compte MT5")
            account_name = st.text_input("Nom du compte")
        with col2:
            broker = st.text_input("Broker")
            duration_days = st.slider("Durée de licence (jours)", 30, 365, 30)

        if st.button("Activer le compte"):
            if new_account and account_name and broker:
                if add_authorized_account(new_account, account_name, broker, duration_days):
                    st.success(f"Compte {new_account} activé avec succès!")
                else:
                    st.error("Ce compte existe déjà dans la base de données.")
            else:
                st.warning("Veuillez remplir tous les champs.")

    # Liste des comptes existants
    st.subheader("Comptes autorisés")
    accounts_df = get_authorized_accounts()

    if not accounts_df.empty:
        # Formatage des dates pour l'affichage
        display_df = accounts_df.copy()
        display_df['activation_date'] = pd.to_datetime(display_df['activation_date']).dt.strftime('%Y-%m-%d')
        display_df['expiration_date'] = pd.to_datetime(display_df['expiration_date']).dt.strftime('%Y-%m-%d')
        display_df['last_connection'] = pd.to_datetime(display_df['last_connection']).dt.strftime('%Y-%m-%d %H:%M') \
            if display_df['last_connection'].iloc[0] != "" else "Jamais"

        st.dataframe(display_df)

        # Options de gestion par compte
        st.subheader("Actions sur les comptes")
        selected_account = st.selectbox("Sélectionner un compte", accounts_df['account_number'].tolist())

        if selected_account:
            account_info = accounts_df[accounts_df['account_number'] == selected_account].iloc[0]

            col1, col2, col3 = st.columns(3)

            with col1:
                st.write(f"**Statut:** {account_info['status']}")
                st.write(f"**Broker:** {account_info['broker']}")

            with col2:
                st.write(f"**Activation:** {account_info['activation_date']}")
                st.write(f"**Expiration:** {account_info['expiration_date']}")

            with col3:
                st.write(
                    f"**Dernière connexion:** {account_info['last_connection'] if account_info['last_connection'] else 'Jamais'}")

            # Actions
            if account_info['status'] == 'Active':
                if st.button("🔒 Révoquer l'accès", key="revoke_btn"):
                    revoke_account(selected_account)
                    st.success(f"Accès révoqué pour le compte {selected_account}")
                    st.experimental_rerun()
            else:
                if st.button("✅ Réactiver l'accès", key="reactivate_btn"):
                    reactivate_account(selected_account)
                    st.success(f"Accès réactivé pour le compte {selected_account}")
                    st.experimental_rerun()

            # Prolonger la licence
            if st.button("⏱️ Prolonger la licence", key="extend_btn"):
                extend_license(selected_account)
                st.success(f"Licence prolongée pour le compte {selected_account}")
                st.experimental_rerun()
    else:
        st.info("Aucun compte autorisé pour le moment.")


# Fonction pour réactiver un compte
def reactivate_account(account_number):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    expiration_date = (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d %H:%M:%S")
    c.execute('''UPDATE authorized_accounts 
                 SET status = 'Active', expiration_date = ?
                 WHERE account_number = ?''',
              (expiration_date, account_number))

    conn.commit()
    conn.close()

    # Ajouter une entrée dans les logs
    log_activity(account_number, "ACCOUNT_REACTIVATED", "Compte réactivé par l'administrateur")


# Fonction pour prolonger une licence
def extend_license(account_number, days=30):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    # Récupérer la date d'expiration actuelle
    c.execute("SELECT expiration_date FROM authorized_accounts WHERE account_number = ?", (account_number,))
    current_expiration = c.fetchone()[0]

    if current_expiration:
        # Convertir en datetime et ajouter des jours
        new_expiration = (datetime.strptime(current_expiration, "%Y-%m-%d %H:%M:%S") + timedelta(days=days)) \
            .strftime("%Y-%m-%d %H:%M:%S")
    else:
        # Si pas de date d'expiration, créer une nouvelle
        new_expiration = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")

    # Mettre à jour la base de données
    c.execute('''UPDATE authorized_accounts 
                 SET expiration_date = ?, status = 'Active'
                 WHERE account_number = ?''',
              (new_expiration, account_number))

    conn.commit()
    conn.close()

    # Ajouter une entrée dans les logs
    log_activity(account_number, "LICENSE_EXTENDED", f"Licence prolongée de {days} jours")


# Demandes d'accès
def show_access_requests():
    st.header("📨 Demandes d'accès")

    requests_df = get_access_requests()

    if not requests_df.empty:
        for _, req in requests_df.iterrows():
            with st.expander(f"Demande de {req['account_name']} ({req['account_number']})"):
                st.write(f"**Broker:** {req['broker']}")
                st.write(f"**Date de demande:** {req['request_date']}")

                col1, col2 = st.columns(2)
                with col1:
                    if st.button(f"✅ Accepter {req['account_number']}", key=f"accept_{req['id']}"):
                        # Ajouter le compte aux comptes autorisés
                        if add_authorized_account(req['account_number'], req['account_name'], req['broker']):
                            # Mettre à jour le statut de la demande
                            update_request_status(req['id'], "Approved")
                            st.success("Demande acceptée et compte activé!")
                            st.experimental_rerun()
                        else:
                            st.error("Erreur lors de l'activation du compte.")

                with col2:
                    if st.button(f"❌ Refuser {req['account_number']}", key=f"reject_{req['id']}"):
                        update_request_status(req['id'], "Rejected")
                        st.success("Demande refusée!")
                        st.experimental_rerun()
    else:
        st.info("Aucune demande d'accès en attente.")


# Mettre à jour le statut d'une demande
def update_request_status(request_id, status):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    c.execute("UPDATE access_requests SET status = ? WHERE id = ?", (status, request_id))
    conn.commit()
    conn.close()

    # Ajouter une entrée dans les logs
    c.execute("SELECT account_number FROM access_requests WHERE id = ?", (request_id,))
    account_number = c.fetchone()[0]
    log_activity(account_number, "REQUEST_PROCESSED", f"Demande {status.lower()}")


# Logs d'activité
def show_activity_logs():
    st.header("📋 Logs d'activité")

    # Options de filtrage
    col1, col2 = st.columns(2)
    with col1:
        log_limit = st.slider("Nombre de logs à afficher", 10, 500, 100)
    with col2:
        account_filter = st.text_input("Filtrer par numéro de compte")

    # Récupérer les logs
    logs_df = get_activity_logs(log_limit)

    if account_filter:
        logs_df = logs_df[logs_df['account_number'].str.contains(account_filter, na=False)]

    if not logs_df.empty:
        st.dataframe(logs_df)

        # Option d'export
        if st.button("Exporter les logs"):
            csv = logs_df.to_csv(index=False)
            st.download_button(
                label="Télécharger les logs CSV",
                data=csv,
                file_name=f"ict_master_logs_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv",
                mime="text/csv"
            )
    else:
        st.info("Aucun log d'activité à afficher.")


# Paramètres
def show_settings():
    st.header("⚙️ Paramètres")

    st.subheader("Changer le mot de passe admin")
    current_pass = st.text_input("Mot de passe actuel", type="password")
    new_pass = st.text_input("Nouveau mot de passe", type="password")
    confirm_pass = st.text_input("Confirmer le nouveau mot de passe", type="password")

    if st.button("Changer le mot de passe"):
        if current_pass and new_pass and confirm_pass:
            if new_pass == confirm_pass:
                if change_admin_password(st.session_state.username, current_pass, new_pass):
                    st.success("Mot de passe changé avec succès!")
                else:
                    st.error("Mot de passe actuel incorrect!")
            else:
                st.error("Les nouveaux mots de passe ne correspondent pas!")
        else:
            st.warning("Veuillez remplir tous les champs!")

    st.subheader("Sauvegarde des données")
    if st.button("Sauvegarder la base de données"):
        backup_database()

    st.subheader("Statut du système")
    st.info(f"Dernière initialisation: {get_database_info()}")


# Changer le mot de passe admin
def change_admin_password(username, current_password, new_password):
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    # Vérifier le mot de passe actuel
    current_hash = hash_password(current_password)
    c.execute("SELECT * FROM admins WHERE username = ? AND password_hash = ?",
              (username, current_hash))

    if c.fetchone():
        # Mettre à jour avec le nouveau mot de passe
        new_hash = hash_password(new_password)
        c.execute("UPDATE admins SET password_hash = ? WHERE username = ?",
                  (new_hash, username))
        conn.commit()
        conn.close()
        return True

    conn.close()
    return False


# Sauvegarde de la base de données
def backup_database():
    # Cette fonction créerait une sauvegarde de la base de données
    # Dans une implémentation réelle, vous voudriez copier le fichier de base de données
    # vers un emplacement de sauvegarde
    st.info("Fonction de sauvegarde à implémenter selon votre environnement de déploiement")


# Information sur la base de données
def get_database_info():
    conn = sqlite3.connect('ict_master.db')
    c = conn.cursor()

    # Compter le nombre de tables
    c.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table'")
    table_count = c.fetchone()[0]

    # Obtenir la date de création de la base de données (approximative)
    c.execute("SELECT MIN(activation_date) FROM authorized_accounts")
    min_date = c.fetchone()[0]

    conn.close()

    return f"{table_count} tables, données depuis: {min_date if min_date else 'N/A'}"


# API pour la validation des comptes (pour le bot MQL5)
def setup_api():
    st.header("🌐 API d'intégration")

    st.info("""
    Votre bot MQL5 peut valider les comptes en envoyant une requête à cette API.
    Utilisez l'endpoint suivant dans votre code MQL5:
    """)

    st.code("""
    // Exemple de code MQL5 pour valider un compte
    bool ValidateAccount(int account_number) {
        string url = "https://votre-app-streamlit.herokuapp.com/api/validate";
        string data = "account=" + IntegerToString(account_number) + "&secret=YOUR_SECRET_KEY";

        char post[];
        ArrayResize(post, StringToCharArray(data, post, 0, WHOLE_ARRAY, CP_UTF8)-1);

        char result[];
        string headers;
        int res = WebRequest("POST", url, headers, 5000, post, result, headers);

        if(res == 200) {
            string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
            return (response == "VALID");
        }

        return false;
    }
    """)

    st.warning(
        "⚠️ Remplacez YOUR_SECRET_KEY par une clé secrète que vous définirez dans les paramètres de votre application.")


# Point d'entrée principal de l'application
def main():
    # Initialiser la base de données
    init_db()

    # Initialiser l'état de session
    if 'authenticated' not in st.session_state:
        st.session_state.authenticated = False

    # Afficher l'interface appropriée
    if not st.session_state.authenticated:
        login_section()
        st.info("""
        # ICT Pure Master - Système d'administration
        Cette application vous permet de gérer les accès à votre bot trading ICT Pure Master.

        ### Fonctionnalités:
        - Contrôle des comptes MT5 autorisés
        - Gestion des licences et des durées d'accès
        - Surveillance des connexions au bot
        - Historique détaillé des activités

        Connectez-vous avec vos identifiants administrateur pour commencer.
        """)
    else:
        admin_dashboard()


if __name__ == "__main__":
    main()