#!/bin/bash
set -e

echo "🛡 شروع مهاجرت کامل خودکار از Marzban به PasarGuard..."

# مسیرهای پیش‌فرض
MARZBAN_PATH="/opt/marzban"
PASARGUARD_PATH="/opt/pasarguard"
MARZBAN_DATA="/var/lib/marzban"
PASARGUARD_DATA="/var/lib/pasarguard"
MARZBAN_MYSQL="/var/lib/mysql/marzban"
PASARGUARD_MYSQL="/var/lib/mysql/pasarguard"
XRAY_CONFIG="$PASARGUARD_PATH/xray_config.json"

# 1. توقف سرویس‌های Marzban
if [ -d "$MARZBAN_PATH" ]; then
    echo "⏹ توقف سرویس‌های Marzban..."
    cd "$MARZBAN_PATH"
    docker compose down || true
else
    echo "پوشه Marzban پیدا نشد، مرحله توقف رد شد."
fi

# 2. تغییر نام پوشه‌ها
echo "📁 تغییر نام پوشه‌ها..."
sudo rm -rf "$PASARGUARD_PATH" "$PASARGUARD_DATA" "$PASARGUARD_MYSQL" || true
[ -d "$MARZBAN_PATH" ] && sudo mv "$MARZBAN_PATH" "$PASARGUARD_PATH"
[ -d "$MARZBAN_DATA" ] && sudo mv "$MARZBAN_DATA" "$PASARGUARD_DATA"

# 3. تغییر نام پوشه MySQL
if [ -d "$MARZBAN_MYSQL" ]; then
    sudo mv "$MARZBAN_MYSQL" "$PASARGUARD_MYSQL"
else
    sudo mkdir -p "$PASARGUARD_MYSQL"
    sudo mv "$PASARGUARD_DATA/mysql/"* "$PASARGUARD_MYSQL" 2>/dev/null || true
    sudo rm -rf "$PASARGUARD_DATA/mysql"
fi

# 4. به‌روزرسانی .env
echo "📝 به‌روزرسانی فایل .env..."
cd "$PASARGUARD_PATH"
sudo sed -i "s|$MARZBAN_DATA|$PASARGUARD_DATA|g" .env
if grep -q 'SQLALCHEMY_DATABASE_URL = "sqlite:///' .env; then
    sudo sed -i 's|sqlite:///db.sqlite3|sqlite+aiosqlite:///db.sqlite3|g' .env
fi

# 5. تغییر تمپلیت v2ray به xray
if [ -d "/var/lib/pasarguard/templates/v2ray" ]; then
    sudo mv /var/lib/pasarguard/templates/v2ray /var/lib/pasarguard/templates/xray
fi

# 6. اصلاح مسیرهای TLS و Xray در xray_config.json
if [ -f "$XRAY_CONFIG" ]; then
    echo "🔧 اصلاح مسیرهای TLS و Xray در xray_config.json..."
    sudo sed -i "s|/var/lib/marzban|/var/lib/pasarguard|g" "$XRAY_CONFIG"
fi

# 7. مهاجرت MySQL (اگر موجود باشد)
MYSQL_USER=$(grep -E '^MYSQL_USER=' .env | cut -d '=' -f2)
MYSQL_PASSWORD=$(grep -E '^MYSQL_PASSWORD=' .env | cut -d '=' -f2)
MYSQL_ROOT_PASSWORD=$(grep -E '^MYSQL_ROOT_PASSWORD=' .env | cut -d '=' -f2)
MYSQL_DB=$(grep -E '^MYSQL_DATABASE=' .env | cut -d '=' -f2)

if [ -n "$MYSQL_DB" ]; then
    echo "🗄 مهاجرت دیتابیس MySQL..."
    docker compose up -d mysql
    docker compose exec mysql mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -h 127.0.0.1 --databases marzban > "$PASARGUARD_PATH/marzban.sql"
    sed -i '/^CREATE DATABASE/s/marzban/pasarguard/;/^USE/s/marzban/pasarguard/' "$PASARGUARD_PATH/marzban.sql"
    docker compose exec -T mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD" -h 127.0.0.1 < "$PASARGUARD_PATH/marzban.sql"
    rm "$PASARGUARD_PATH/marzban.sql"
fi

# 8. نصب اسکریپت مدیریت PasarGuard
echo "🔧 نصب اسکریپت مدیریت PasarGuard..."
sudo bash -c "$(curl -sL https://github.com/PasarGuard/scripts/raw/main/pasarguard.sh)" @ install-script

# 9. راه‌اندازی PasarGuard
echo "🚀 راه‌اندازی PasarGuard..."
pasarguard restart || true

# 10. بررسی وضعیت
echo "✅ بررسی وضعیت سرویس‌ها..."
pasarguard status || true

echo "🎉 مهاجرت کامل شد! لطفاً تست نهایی پنل و سرویس‌ها را انجام دهید."
