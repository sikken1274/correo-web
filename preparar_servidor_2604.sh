#!/bin/bash
# Prepara un Ubuntu Server 26.04 per a la UT2 de 0228 (Gestoria Sa Plaça).
# Versió per a Ubuntu 26.04, que porta Dovecot 2.4 (per a Ubuntu 24.04 i Dovecot 2.3: preparar_servidor.sh).
#
# Deixa instal·lat i configurat:
#   - el servidor de correu (Postfix + Dovecot) per al domini gestoriasaplaca.cat, només local:
#     el correu cap a altres dominis es rebutja;
#   - sis comptes de correu de la gestoria;
#   - Apache, PHP i MariaDB, amb les bases de dades buides per a Roundcube i Nextcloud.
# No instal·la Roundcube ni Nextcloud: és la feina de l'alumnat.
#
# Ús (com a root, en un Ubuntu Server 26.04 nou):  sudo bash preparar_servidor_2604.sh
set -euo pipefail

DOMINI="gestoriasaplaca.cat"
CONTRASENYA="Gestoria2026"
COMPTES="gerent recepcio anna joan marta pau"
export DEBIAN_FRONTEND=noninteractive

echo "== Nom de la màquina"
hostnamectl set-hostname mail
sed -i '/^127\.0\.1\.1/d' /etc/hosts
sed -i "1a 127.0.1.1 mail.${DOMINI} mail correu.${DOMINI} calendari.${DOMINI}" /etc/hosts

echo "== Paquets"
debconf-set-selections <<< "postfix postfix/mailname string ${DOMINI}"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get update
apt-get install -y \
  postfix dovecot-imapd dovecot-pop3d mailutils swaks \
  apache2 mariadb-server \
  php libapache2-mod-php php-mysql php-gd php-curl php-mbstring php-intl php-xml \
  php-zip php-bcmath php-gmp php-apcu php-imagick php-ldap \
  unzip bzip2 curl

echo "== Postfix"
postconf -e \
  "myhostname = mail.${DOMINI}" \
  "mydomain = ${DOMINI}" \
  "myorigin = \$mydomain" \
  "mydestination = \$myhostname, \$mydomain, localhost.\$mydomain, localhost" \
  "inet_interfaces = all" \
  "mynetworks = 127.0.0.0/8 [::1]/128" \
  "home_mailbox = Maildir/" \
  "default_transport = error:Correu extern desactivat al laboratori" \
  "relay_transport = error:Correu extern desactivat al laboratori" \
  "smtpd_sasl_type = dovecot" \
  "smtpd_sasl_path = private/auth" \
  "smtpd_sasl_auth_enable = yes" \
  "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"
postconf -M "submission/inet=submission inet n - y - - smtpd"
postconf -P \
  "submission/inet/syslog_name=postfix/submission" \
  "submission/inet/smtpd_tls_security_level=may" \
  "submission/inet/smtpd_sasl_auth_enable=yes" \
  "submission/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject"
cat >> /etc/aliases <<EOF
info: gerent, recepcio
EOF
newaliases

echo "== Dovecot"
cat > /etc/dovecot/conf.d/99-gestoria.conf <<'EOF'
# Laboratori 0228 (sintaxi de Dovecot 2.4): bústies Maildir a la carpeta de cada usuari (també la safata
# d'entrada: Ubuntu 26.04 la posa per defecte a /var/mail en format mbox), i autenticació
# sense xifratge permesa (només és accessible des de la mateixa màquina i la xarxa del laboratori).
mail_driver = maildir
mail_path = %{home}/Maildir
mail_inbox_path = %{home}/Maildir
auth_allow_cleartext = yes
auth_mechanisms = plain login
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF
doveconf -n > /dev/null

echo "== Comptes de correu"
for u in ${COMPTES}; do
  id "$u" >/dev/null 2>&1 || useradd -m -s /usr/sbin/nologin "$u"
  echo "${u}:${CONTRASENYA}" | chpasswd
done

echo "== MariaDB: bases de dades buides"
mysql <<EOF
CREATE DATABASE IF NOT EXISTS roundcube CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY '${CONTRASENYA}';
CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY '${CONTRASENYA}';
GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "== Apache i PHP"
a2enmod rewrite headers env dir mime
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
cat > "/etc/php/${PHPV}/apache2/conf.d/99-gestoria.ini" <<'EOF'
memory_limit = 512M
upload_max_filesize = 512M
post_max_size = 512M
max_execution_time = 300
date.timezone = Europe/Madrid
EOF
cat > /etc/apache2/conf-available/gestoria.conf <<'EOF'
<Directory /var/www/html>
    AllowOverride All
</Directory>
EOF
a2enconf gestoria
cat > /var/www/html/index.html <<EOF
<!doctype html>
<html lang="ca"><head><meta charset="utf-8"><title>Servidor de la Gestoria Sa Plaça</title></head>
<body style="font-family: sans-serif; max-width: 42em; margin: 2em auto;">
<h1>Servidor de la Gestoria Sa Plaça</h1>
<p>Apache, PHP ${PHPV} i MariaDB funcionen. El servidor de correu (Postfix i Dovecot) atén el domini <b>${DOMINI}</b>.</p>
<ul>
<li>Correu web (Roundcube): s'ha d'instal·lar a <code>/var/www/roundcube</code> i, amb un àlies d'Apache cap a <code>public_html</code>, serà a <a href="/roundcube/">/roundcube/</a>.</li>
<li>Calendari web (Nextcloud): s'ha d'instal·lar a <code>/var/www/html/nextcloud</code> i serà a <a href="/nextcloud/">/nextcloud/</a>.</li>
</ul>
</body></html>
EOF

echo "== Correu de benvinguda a cada compte"
systemctl restart postfix dovecot apache2 mariadb
sleep 3
for u in ${COMPTES}; do
  printf 'From: gerent@%s\nTo: %s@%s\nSubject: Benvinguda al correu de la gestoria\n\nAquest és el primer correu de la teva bústia %s@%s.\n' \
    "${DOMINI}" "$u" "${DOMINI}" "$u" "${DOMINI}" | /usr/sbin/sendmail -t
done

echo "== Fitxa d'accés"
cat > /etc/motd <<EOF

  Servidor de la Gestoria Sa Plaça (mail.${DOMINI})

  Administració:  usuari tecnic, contrasenya ${CONTRASENYA} (té sudo)
  Comptes de correu: ${COMPTES}
                     adreça <compte>@${DOMINI}, contrasenya ${CONTRASENYA}
  Àlies: info@${DOMINI} arriba a gerent i recepcio
  Correu: SMTP 25 i 587 (autenticat), IMAP 143, POP3 110. Només correu local.
  MariaDB: bases de dades roundcube i nextcloud
           usuaris roundcube i nextcloud, contrasenya ${CONTRASENYA}
  Web (des de l'ordinador: http://localhost:8080):
       Roundcube a /var/www/roundcube  -> http://localhost:8080/roundcube/
       Nextcloud a /var/www/html/nextcloud -> http://localhost:8080/nextcloud/

EOF

echo "== Comprovació"
sleep 5
for u in ${COMPTES}; do
  n=$(ls "/home/${u}/Maildir/new" 2>/dev/null | wc -l)
  echo "  ${u}: ${n} correu(s) a la bústia"
done
systemctl is-active postfix dovecot apache2 mariadb
echo "== Fet"
