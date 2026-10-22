#!/bin/zsh
# Один раз создаёт в связке «Вход» сертификат «Notchly Dev» для подписи сборок.
# С ним подпись не меняется между сборками, и macOS перестаёт сбрасывать выданные доступы
# (Полный доступ к диску, Универсальный доступ, Связка ключей, Запись аудио).
set -euo pipefail
NAME="Notchly Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Сертификат «$NAME» уже есть."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CFG

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/cfg" 2>/dev/null
openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:island
security import "$TMP/id.p12" -k "$KEYCHAIN" -P island -T /usr/bin/codesign
echo "Сейчас macOS спросит пароль, чтобы доверять сертификату для подписи кода."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
echo "Готово. Пересоберите приложение: ./build.sh"
