#!/bin/bash
# Pasarify.sh - Safe semi-interactive migration script
# Migrate Marzban -> PasarGuard (MySQL or SQLite)
# Author: generated for you
set -euo pipefail
IFS=$'\n\t'

# ---------- CONFIG (adjust here if your paths differ) ----------
MARZBAN_PATH="/opt/marzban"
PASARGUARD_PATH="/opt/pasarguard"
MARZBAN_DATA="/var/lib/marzban"
PASARGUARD_DATA="/var/lib/pasarguard"
MYSQL_BASE="/var/lib/mysql"
MARZBAN_MYSQL_DIR="$MYSQL_BASE/marzban"
PASARGUARD_MYSQL_DIR="$MYSQL_BASE/pasarguard"
MARZBAN_CERTS="$MARZBAN_DATA/certs"
PASARGUARD_CERTS="$PASARGUARD_DATA/certs"
BACKUP_ROOT="/root/pasarify_backups"
TMP_SQL="/tmp/marzban.sql"
LOGFILE="/tmp/pasarify_$(date +%Y%m%d_%H%M%S).log"

# ---------- Colors ----------
RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; RESET=$'\e[0m'

# ---------- Helpers ----------
log() { echo -e "$@" | tee -a "$LOGFILE"; }
die() { echo -e "${RED}ERROR:${RESET} $@" | tee -a "$LOGFILE" >&2; exit 1; }
ask_yesno() {
  local prompt="$1"
  local default="${2:-y}"
  local ans
  while true; do
    read -rp "$prompt [y/n] (default: $default): " ans
    ans="${ans:-$default}"
    case "${ans,,}" in
      y|yes) return 0;;
      n|no) return 1;;
      *) echo " لطفاً y یا n وارد کن.";;
    esac
  done
}
retry_or_abort() {
  local msg="$1"
  echo
  log "${YELLOW}${msg}${RESET}"
  if ask_yesno "آیا می‌خوای تلاش مجدد کنی؟"; then
    return 0
  else
    die "کار متوقف شد به درخواست کاربر."
  fi
}

# ---------- Start ----------
log "${BLUE}=== شروع Pasarify: Marzban → PasarGuard ===${RESET}"
log "Log file: $LOGFILE"
echo ""

# ---------- Pre-checks ----------
command -v docker >/dev/null 2>&1 || die "docker نصب نیست. ابتدا docker را نصب کنید."
# docker compose: prefer native docker compose, otherwise check docker-compose
if command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
else
  die "docker compose یا docker-compose نصب نیست."
fi
log "Docker و Docker Compose موجود است. ($DOCKER_COMPOSE_CMD)"

# ---------- Confirm base paths ----------
log "بررسی مسیرها:"
log "  Marzban: $MARZBAN_PATH"
log "  Marzban data: $MARZBAN_DATA"
log "  PasarGuard: $PASARGUARD_PATH"
log "  PasarGuard data: $PASARGUARD_DATA"
log "  Marzban certs: $MARZBAN_CERTS"
log "  PasarGuard certs: $PASARGUARD_CERTS"
echo ""
if ! ask_yesno "آیا این مسیرها صحیح هستند و ادامه بدم؟"; then
  die "کاربر مسیرها را تایید نکرد. متوقف شدم."
fi

# ---------- Create backup directory ----------
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
log "ایجاد دایرکتوری بکاپ: $BACKUP_DIR"

# backup function
backup_file_or_dir() {
  local src="$1"
  local dest="$BACKUP_DIR/$(basename "$src").tgz"
  if [ -e "$src" ]; then
    log "📦 گرفتن بکاپ از $src ..."
    sudo tar -czf "$dest" -C "$(dirname "$src")" "$(basename "$src")" || log "⚠️ بکاپ گرفتن از $src با هشدار مواجه شد."
    log "   بکاپ ذخیره شد: $dest"
  else
    log "ℹ️ $src وجود ندارد، رد شد."
  fi
}

# ---------- Backups ----------
log "${BLUE}--- بکاپ‌گیری از Marzban (توصیه‌شده) ---${RESET}"
backup_file_or_dir "$MARZBAN_PATH"
backup_file_or_dir "$MARZBAN_DATA"
if [ -d "$MARZBAN_MYSQL_DIR" ]; then
  backup_file_or_dir "$MARZBAN_MYSQL_DIR"
fi

# ---------- Stop Marzban containers ----------
if [ -d "$MARZBAN_PATH" ]; then
  log "⏹️ تلاش برای توقف کانتینرهای Marzban..."
  (cd "$MARZBAN_PATH" && $DOCKER_COMPOSE_CMD down) || log "⚠️ توقف کامل Marzban ممکن است با خطا مواجه شده باشد. ادامه می‌دیم."
else
  log "ℹ️ پوشه Marzban وجود ندارد: $MARZBAN_PATH (مرحله توقف رد شد)."
fi

# ---------- Ensure PasarGuard installed or install script ----------
if [ ! -d "$PASARGUARD_PATH" ]; then
  log "${YELLOW}پوشه PasarGuard یافت نشد. اسکریپت رسمی را اجرا کنم تا نصب پایه ایجاد شود؟${RESET}"
  if ask_yesno "می‌خوای من اسکریپت رسمی pasarguard.sh را اجرا کنم تا پوشه /opt/pasarguard ساخته شود؟"; then
    log "⬇️ اجرای اسکریپت رسمی نصب PasarGuard..."
    if ! sudo bash -c "$(curl -sL https://github.com/PasarGuard/scripts/raw/main/pasarguard.sh)" install; then
      log "⚠️ اجرای اسکریپت رسمی نصب pasarguard.sh با خطا مواجه شد."
      if ask_yesno "می‌خوای ادامه بدم بدون نصب خودکار (شما بعداً دستی نصب کن)؟"; then
        log "ادامه بدون اجرای نصب خودکار (ممکنه نیاز به تنظیملت دستی داشته باشی)."
      else
        die "نیاز به نصب PasarGuard. متوقف شدم."
      fi
    fi
  else
    die "برای ادامه باید PasarGuard نصب یا پوشه /opt/pasarguard وجود داشته باشه."
  fi
else
  log "✅ پوشه PasarGuard وجود دارد؛ از آن استفاده می‌کنیم."
fi

# ---------- Pull latest PasarGuard image ----------
log "⬇️ دانلود image پاسارگارد (pasarguard/panel:latest) ..."
if ! docker pull pasarguard/panel:latest; then
  log "⚠️ دانلود image با هشدار مواجه شد. اما ممکن است محلی موجود باشد."
fi

# ---------- Copy certs ----------
if [ -d "$MARZBAN_CERTS" ]; then
  log "🔐 انتقال سرتیفیکیت‌ها از $MARZBAN_CERTS به $PASARGUARD_CERTS ..."
  sudo mkdir -p "$PASARGUARD_CERTS"
  sudo cp -a "$MARZBAN_CERTS/." "$PASARGUARD_CERTS/" || log "⚠️ کپی سرتیفیکیت‌ها با هشدار مواجه شد."
  sudo chown -R root:root "$PASARGUARD_CERTS" || true
  log "✅ سرتیفیکیت‌ها کپی شدند."
else
  log "⚠️ پوشه سرتیفیکیت مرزبان وجود ندارد: $MARZBAN_CERTS — این مرحله رد شد."
fi

# ---------- Read .env files (if exist) ----------
MARZBAN_ENV="$MARZBAN_PATH/.env"
PASARGUARD_ENV="$PASARGUARD_PATH/.env"

read_env_value() {
  local file="$1" key="$2"
  if [ -f "$file" ]; then
    grep -E "^${key}=" "$file" | tail -n1 | cut -d'=' -f2- || true
  else
    true
  fi
}

# get DB info
MB_DB_DRIVER=$(read_env_value "$MARZBAN_ENV" "SQLALCHEMY_DATABASE_URL")
MB_DB_NAME=$(read_env_value "$MARZBAN_ENV" "MYSQL_DATABASE" || echo "marzban")
MB_DB_USER=$(read_env_value "$MARZBAN_ENV" "MYSQL_USER" || echo "marzban")
MB_DB_PASS=$(read_env_value "$MARZBAN_ENV" "MYSQL_PASSWORD" || echo "")
MB_DB_ROOT=$(read_env_value "$MARZBAN_ENV" "MYSQL_ROOT_PASSWORD" || echo "")

PG_DB_DRIVER=$(read_env_value "$PASARGUARD_ENV" "SQLALCHEMY_DATABASE_URL")
PG_DB_NAME=$(read_env_value "$PASARGUARD_ENV" "MYSQL_DATABASE" || echo "pasarguard")
PG_DB_USER=$(read_env_value "$PASARGUARD_ENV" "MYSQL_USER" || echo "pasarguard")
PG_DB_PASS=$(read_env_value "$PASARGUARD_ENV" "MYSQL_PASSWORD" || echo "")
PG_DB_ROOT=$(read_env_value "$PASARGUARD_ENV" "MYSQL_ROOT_PASSWORD" || echo "")

# Determine DB type
is_sqlite=false
if [[ "$MB_DB_DRIVER" == sqlite* || -z "$MB_DB_DRIVER" ]]; then
  is_sqlite=true
fi

if $is_sqlite; then
  log "${YELLOW}تشخیص SQLite برای Marzban — مراحل MySQL نادیده گرفته می‌شود.${RESET}"
else
  log "تشخیص MySQL برای Marzban (db: ${MB_DB_NAME})"
fi

# ---------- If MySQL, perform dump/import ----------
if ! $is_sqlite; then
  # Start mysql in PasarGuard (so we can import later)
  if [ -d "$PASARGUARD_PATH" ]; then
    log "🚀 بالا آوردن سرویس mysql در PasarGuard..."
    (cd "$PASARGUARD_PATH" && $DOCKER_COMPOSE_CMD up -d mysql) || retry_or_abort "بالا آوردن mysql در PasarGuard با خطا مواجه شد."
  else
    die "پوشه PasarGuard موجود نیست؛ نمی‌توان mysql آن را بالا آورد."
  fi

  # Start mysql in Marzban (to get dump)
  if [ -d "$MARZBAN_PATH" ]; then
    log "🚀 بالا آوردن سرویس mysql در Marzban..."
    (cd "$MARZBAN_PATH" && $DOCKER_COMPOSE_CMD up -d mysql) || log "⚠️ بالا آوردن mysql مرزبان ممکن است با خطا مواجه باشد (اگر mysql نداشته باشد)."
  fi

  # Wait small time & check
  sleep 4

  # Try to dump
  log "🗄️ گرفتن dump از دیتابیس Marzban..."
  rm -f "$TMP_SQL" || true

  # Prefer root if available
  dump_succeeded=false
  if [ -n "$MB_DB_ROOT" ]; then
    if (cd "$MARZBAN_PATH" && $DOCKER_COMPOSE_CMD ps | grep -i mysql >/dev/null 2>&1); then
      if (cd "$MARZBAN_PATH" && $DOCKER_COMPOSE_CMD exec -T mysql mysqldump -u root -p"$MB_DB_ROOT" -h 127.0.0.1 --databases "$MB_DB_NAME" > "$TMP_SQL"); then
        dump_succeeded=true
      fi
    fi
  fi

  # fallback to non-root user
  if ! $dump_succeeded; then
    if [ -n "$MB_DB_PASS" ]; then
      if (cd "$MARZBAN_PATH" && $DOCKER_COMPOSE_CMD exec -T mysql mysqldump -u "$MB_DB_USER" -p"$MB_DB_PASS" -h 127.0.0.1 --databases "$MB_DB_NAME" > "$TMP_SQL"); then
        dump_succeeded=true
      fi
    else
      if (cd "$MARZBAN_PATH" && $DOCKER_COMPOSE_CMD exec -T mysql mysqldump -u "$MB_DB_USER" -h 127.0.0.1 --databases "$MB_DB_NAME" > "$TMP_SQL"); then
        dump_succeeded=true
      fi
    fi
  fi

  if [ ! -s "$TMP_SQL" ]; then
    die "❌ گرفتن dump از دیتابیس مرزبان موفق نبود. فایل $TMP_SQL ایجاد نشده یا خالی است. لاگ‌ها را بررسی کن."
  fi
  log "✅ dump ذخیره شد: $TMP_SQL"

  # replace DB name in dump (CREATE DATABASE / USE)
  log "🔁 تغییر نام دیتابیس در SQL ($MB_DB_NAME -> $PG_DB_NAME)..."
  sed -i "/^CREATE DATABASE/s/${MB_DB_NAME}/${PG_DB_NAME}/; /^USE/s/${MB_DB_NAME}/${PG_DB_NAME}/" "$TMP_SQL" || true

  # Import into PasarGuard
  log "📥 وارد کردن dump به دیتابیس PasarGuard..."
  # Ensure mysql container running
  (cd "$PASARGUARD_PATH" && $DOCKER_COMPOSE_CMD ps | grep -i mysql >/dev/null 2>&1) || retry_or_abort "سرویس mysql در پوشه PasarGuard اجرا نشده است."

  # Try root then user
  import_done=false
  if [ -n "$PG_DB_ROOT" ]; then
    if (cd "$PASARGUARD_PATH" && $DOCKER_COMPOSE_CMD exec -T mysql mysql -u root -p"$PG_DB_ROOT" -h 127.0.0.1 < "$TMP_SQL"); then
      import_done=true
    fi
  fi
  if ! $import_done; then
    if [ -n "$PG_DB_PASS" ]; then
      if (cd "$PASARGUARD_PATH" && $DOCKER_COMPOSE_CMD exec -T mysql mysql -u "$PG_DB_USER" -p"$PG_DB_PASS" -h 127.0.0.1 "$PG_DB_NAME" < "$TMP_SQL"); then
        import_done=true
      fi
    fi
  fi

  if ! $import_done; then
    log "❌ وارد کردن دیتابیس به PasarGuard شکست خورد."
    if ask_yesno "می‌خوای خطاها (docker compose logs mysql) رو ببینم و سپس تلاش مجدد کنیم؟"; then
      log "---- PasarGuard mysql logs ----"
      (cd "$PASARGUARD_PATH" && $DOCKER_COMPOSE_CMD logs mysql --tail=200) | tee -a "$LOGFILE"
      if ask_yesno "تلاش مجدد import انجام شود؟"; then
        if (cd "$PASARGUARD_PATH" && $DOCKER_COMPOSE_CMD exec -T mysql mysql -u root -p"$PG_DB_ROOT" -h 127.0.0.1 < "$TMP_SQL"); then
          import_done=true
        fi
      fi
    fi
  fi

  if ! $import_done; then
    die "وارد کردن دیتابیس ناموفق ماند — باید به صورت دستی بررسی کنی. لاگ: $LOGFILE"
  fi
  log "✅ دیتابیس وارد شد."

  # Optional: remove dump file
  if ask_yesno "می‌خوای فایل dump محلی ($TMP_SQL) حذف بشه؟"; then
    rm -f "$TMP_SQL"
    log "فایل dump حذف شد."
  else
    log "فایل dump در $TMP_SQL باقی موند."
  fi
fi # end if mysql

# ---------- Update .env and docker-compose in PasarGuard ----------
if [ -d "$PASARGUARD_PATH" ]; then
  log "🔧 به‌روزرسانی .env و docker-compose.yml در PasarGuard (اگر وجود داشته باشند)..."
  if [ -f "$PASARGUARD_PATH/.env" ]; then
    sudo sed -i "s|/var/lib/marzban|/var/lib/pasarguard|g" "$PASARGUARD_PATH/.env" || true
    if grep -q 'SQLALCHEMY_DATABASE_URL = "sqlite:///' "$PASARGUARD_PATH/.env" 2>/dev/null; then
      sudo sed -i 's|sqlite:///db.sqlite3|sqlite+aiosqlite:///db.sqlite3|g' "$PASARGUARD_PATH/.env" || true
    fi
    log "  .env آپدیت شد."
  else
    log "  ℹ️ .env در PasarGuard پیدا نشد؛ لطفاً دستی بررسی کن."
  fi

  if [ -f "$PASARGUARD_PATH/docker-compose.yml" ]; then
    # replace image and marzban -> pasarguard where safe (word boundaries)
    sudo sed -i 's|gozargah/marzban:latest|pasarguard/panel:latest|g' "$PASARGUARD_PATH/docker-compose.yml" || true
    sudo sed -i 's|\bmarzban\b|pasarguard|g' "$PASARGUARD_PATH/docker-compose.yml" || true
    sudo sed -i "s|/var/lib/mysql/marzban:/var/lib/mysql|/var/lib/mysql/pasarguard:/var/lib/mysql|g" "$PASARGUARD_PATH/docker-compose.yml" || true
    log "  docker-compose.yml به‌روزرسانی شد (ممکن است نیاز به بازبینی دستی داشته باشد)."
  else
    log "  ℹ️ docker-compose.yml در PasarGuard پیدا نشد؛ لطفاً دستی بررسی کن."
  fi
else
  log "⚠️ PasarGuard path وجود ندارد؛ آپدیت .env/docker-compose رد شد."
fi

# ---------- Move templates v2ray -> xray ----------
if [ -d "$PASARGUARD_DATA/templates/v2ray" ]; then
  sudo mv "$PASARGUARD_DATA/templates/v2ray" "$PASARGUARD_DATA/templates/xray" || true
  log "🔁 تمپلیت v2ray -> xray منتقل شد."
fi

# ---------- Final start PasarGuard ----------
log "🔁 راه‌اندازی PasarGuard (docker compose up -d) ..."
if [ -d "$PASARGUARD_PATH" ]; then
  (cd "$PASARGUARD_PATH" && $DOCKER_COMPOSE_CMD up -d --remove-orphans) || log "⚠️ راه‌اندازی نهایی ممکن است با خطا مواجه شده باشد."
  # If pasarguard helper available, call restart/status
  if command -v pasarguard >/dev/null 2>&1; then
    pasarguard restart || true
    pasarguard status || true
  fi
else
  log "⚠️ پوشه PasarGuard موجود نیست؛ نمی‌توانم آن را بالا بیاورم."
fi

# ---------- Wrap up ----------
log ""
log "${GREEN}=== مهاجرت انجام شد (تا جایی که اسکریپت توانست) ===${RESET}"
log "لطفاً موارد زیر را حتماً بررسی کن:"
log "  1) وارد پنل PasarGuard شو و چک کن اکانت‌ها و تنظیمات منتقل شده باشند."
log "  2) اگر از MySQL استفاده کردی، لاگ‌های mysql و containerها را بررسی کن:"
log "       cd $PASARGUARD_PATH && $DOCKER_COMPOSE_CMD logs mysql --tail=200"
log "  3) اطمینان حاصل کن که فایل‌های certs در $PASARGUARD_CERTS هستند."
log "  4) در صورتی که همه چیز اوکی بود و خواستی Marzban را حذف کنی، ابتدا بکاپ‌ها را چک کن و سپس دستی حذف کن:"
log "       sudo rm -rf $MARZBAN_PATH $MARZBAN_DATA"
log ""
log "بکاپ‌ها در: $BACKUP_DIR"
log "لاگ‌ها: $LOGFILE"
log "${GREEN}کار تمام شد. اگر خواستی نسخه non-interactive یا اضافه کردن healthcheck دقیق‌تر بسازم، بگو.${RESET}"
