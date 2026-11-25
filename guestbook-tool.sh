#!/bin/bash
# guestbook-tool.sh: проверка и инциденты для бизнес-задачи «Книга отзывов» (LAMP / LNMP)
# Запуск:  sudo bash guestbook-tool.sh check lamp | check lnmp | break lamp | break lnmp
set -u
TOOL_VERSION=1.0
APP=/var/www/guestbook
CONF=$APP/config.php
INDEX=$APP/public/index.php
STATE=/var/lib/guestbook-tool
SITE=guestbook.local

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите через sudo: sudo bash $0 ${*:-check lamp}"
    exit 1
fi
STUDENT=${SUDO_USER:-root}

# ---------- окружение: Ubuntu или Arch ----------
if [ -f /etc/arch-release ]; then
    DISTRO=Arch; APACHE=httpd; WEBUSER=http
else
    DISTRO=Ubuntu; APACHE=apache2; WEBUSER=www-data
fi
unit_exists() { systemctl list-unit-files --no-legend "$1.service" 2>/dev/null | grep -q "^$1\.service"; }
DBSVC=mysql
for s in mysql mariadb mysqld; do if unit_exists "$s"; then DBSVC=$s; break; fi; done
FPM=$(systemctl list-unit-files --no-legend 'php*-fpm.service' 2>/dev/null | awk '{print $1}' | sed 's/\.service$//' | head -n 1)
FPM=${FPM:-php-fpm}
DBC=$(command -v mysql || command -v mariadb || echo mysql)

# ---------- помощники ----------
dbq() { "$DBC" -N -B -e "$1" 2>/dev/null; }
cfg() { [ -f "$CONF" ] && php -r '$c = @include $argv[1]; echo is_array($c) && isset($c[$argv[2]]) ? $c[$argv[2]] : "";' -- "$CONF" "$1" 2>/dev/null; }
# SQL от имени пользователя приложения (данные берутся из config.php): печатает OK или ERR:текст
app_sql() {
    php -r '
        $c = @include $argv[1];
        if (!is_array($c)) { echo "ERR:config.php не читается"; exit; }
        try {
            $p = new PDO("mysql:host=".$c["host"].";dbname=".$c["dbname"].";charset=utf8mb4", $c["user"], $c["pass"]);
            $p->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $p->query($argv[2]); echo "OK";
        } catch (Throwable $e) { echo "ERR:", $e->getMessage(); }' -- "$CONF" "$1" 2>/dev/null
}
http_code() { curl -s -o /dev/null -m 10 -w '%{http_code}' -H "Host: $SITE" "http://127.0.0.1$1"; }
page() { curl -s -m 10 -H "Host: $SITE" http://127.0.0.1/; }
server_header() { curl -sI -m 10 -H "Host: $SITE" http://127.0.0.1/ | tr -d '\r' | awk 'tolower($1)=="server:"{print $2}'; }
listens_by() { ss -tlnpH "( sport = :$1 )" 2>/dev/null | grep -q "\"$2\""; }
db_public() { ss -tlnH "( sport = :3306 )" 2>/dev/null | awk '{print $4}' | grep -vqE '^(127\.0\.0\.1|\[::1\]|\[::ffff:127\.0\.0\.1\]):'; }
sq() { printf "%s" "$1" | sed "s/'/''/g"; }
post_works() {
    local tag code n
    tag="check-$$-$RANDOM"
    code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' -H "Host: $SITE" \
        --data-urlencode "name=$tag" --data-urlencode "message=автопроверка" http://127.0.0.1/)
    n=$(dbq "SELECT COUNT(*) FROM guestbook.guests WHERE name='$tag'")
    dbq "DELETE FROM guestbook.guests WHERE name='$tag'"
    [ "$code" = 302 ] && [ "${n:-0}" = 1 ]
}
grants() { local h; h=$(dbq "SELECT host FROM mysql.user WHERE user='guest_app' LIMIT 1"); dbq "SHOW GRANTS FOR 'guest_app'@'${h:-localhost}'"; }
ufw_ok() {
    local s; s=$(ufw status 2>/dev/null) || return 1
    echo "$s" | grep -q 'Status: active' &&
    echo "$s" | grep -Eq '^(22(/tcp)?|OpenSSH) .*ALLOW' &&
    echo "$s" | grep -Eq '^(80(/tcp)?|80,443/tcp|Apache|Apache Full|Nginx HTTP|Nginx Full|WWW|WWW Full) .*ALLOW'
}
ufw_3306_closed() { ! ufw status 2>/dev/null | grep -Eq '^3306'; }

# ---------- вывод ----------
TOTAL_FAIL=0; SEC_FAIL=0; SEC_NAME=""; SUMMARY=""
ok()  { printf '  [ OK ]  %s\n' "$1"; }
bad() { printf '  [FAIL]  %s\n' "$1"; [ -n "${2:-}" ] && printf '          подсказка: %s\n' "$2"; SEC_FAIL=$((SEC_FAIL+1)); TOTAL_FAIL=$((TOTAL_FAIL+1)); }
check() { local d=$1 h=$2; shift 2; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d" "$h"; fi; }
section_end() {
    [ -z "$SEC_NAME" ] && return
    if [ "$SEC_FAIL" -eq 0 ]; then SUMMARY+="  $SEC_NAME: пройден"$'\n'; else SUMMARY+="  $SEC_NAME: НЕ пройден (ошибок: $SEC_FAIL)"$'\n'; fi
}
section() { section_end; SEC_NAME=$1; SEC_FAIL=0; echo; echo "=== $1. $2 ==="; }
header() {
    local code
    code=$( { cat /etc/machine-id 2>/dev/null; echo "$STUDENT"; } | sha256sum | cut -c1-8)
    echo "================================================================"
    echo " Проверка «Книга отзывов»: $1        guestbook-tool v$TOOL_VERSION"
    echo " Студент (SUDO_USER): $STUDENT    Компьютер: $(hostname)"
    echo " Система: $DISTRO    Дата: $(date '+%d.%m.%Y %H:%M')    Код рабочего места: $code"
    echo " Администратор в config.php: $(cfg admin)"
    echo "================================================================"
}
footer() {
    section_end
    echo; echo "---------------- ИТОГ ----------------"; printf '%s' "$SUMMARY"
    if [ "$TOTAL_FAIL" -eq 0 ]; then echo "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ"; else echo "Есть ошибки: $TOTAL_FAIL. Исправьте и запустите проверку снова."; fi
}
marker_info() { [ -f "$STATE/$1" ] && echo "инцидент запущен $(cat "$STATE/$1")"; }

# ---------- проверка LAMP ----------
check_lamp() {
    header "LAMP"
    section "Тикет #5101" "Сервер LAMP поднят"
    check "Apache ($APACHE) работает и включён в автозапуск" "systemctl enable --now $APACHE" \
        bash -c "systemctl is-active --quiet $APACHE && systemctl is-enabled --quiet $APACHE"
    check "порт 80 слушает Apache" "sudo ss -tlnp | grep :80" listens_by 80 "$APACHE"
    check "СУБД ($DBSVC) работает" "systemctl status $DBSVC" systemctl is-active --quiet "$DBSVC"
    check "MySQL недоступен снаружи (порт 3306 только на 127.0.0.1)" "bind-address = 127.0.0.1" bash -c "! db_public"
    check "PHP установлен: $(php -r 'echo PHP_VERSION;' 2>/dev/null)" "установите php" command -v php
    check "файервол: ufw активен, открыты 22 и 80" "ufw allow 22, ufw allow 80, ufw enable" ufw_ok
    check "файервол: порт 3306 не открыт" "ufw delete allow 3306" ufw_3306_closed
    check "файлов с phpinfo() на сервере нет" "удалите info.php" bash -c "! grep -rlsF 'phpinfo(' /var/www /srv/http"

    section "Тикет #5102" "База отзывов"
    check "база guestbook существует" "CREATE DATABASE guestbook ..." test "$(dbq "SHOW DATABASES LIKE 'guestbook'")" = guestbook
    local cols n admin
    cols=$(dbq "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='guestbook' AND table_name='guests' AND column_name IN ('id','name','message','created_at')")
    check "таблица guests со столбцами id, name, message, created_at" "CREATE TABLE guests (...)" test "${cols:-0}" = 4
    check "пользователь guest_app существует" "CREATE USER 'guest_app'@'localhost' ..." test -n "$(grants)"
    check "guest_app входит с паролем из config.php и читает отзывы" "проверьте пароль в config.php и GRANT SELECT" \
        test "$(app_sql 'SELECT COUNT(*) FROM guests')" = OK
    n=$(dbq "SELECT COUNT(*) FROM guestbook.guests"); admin=$(cfg admin)
    check "в базе не меньше 3 отзывов (сейчас: ${n:-0})" "INSERT INTO guests ..." test "${n:-0}" -ge 3
    check "есть отзыв от администратора «$admin»" "добавьте отзыв с именем из config.php" \
        test "$(dbq "SELECT COUNT(*) FROM guestbook.guests WHERE name='$(sq "$admin")'")" -ge 1
    check "у guest_app есть права SELECT и INSERT" "GRANT SELECT, INSERT ON guestbook.* TO ..." \
        bash -c "g=\$(cat); echo \"\$g\" | grep -q SELECT && echo \"\$g\" | grep -q INSERT" <<<"$(grants)"
    check "guest_app не может удалять отзывы (DELETE запрещён)" "выдавайте только SELECT, INSERT" \
        bash -c "case \"\$1\" in ERR:*denied*) exit 0;; *) exit 1;; esac" _ "$(app_sql 'DELETE FROM guests WHERE 1=0')"

    section "Тикет #5103" "Сайт опубликован"
    check "в /etc/hosts есть guestbook.local" "127.0.0.1 guestbook.local" grep -Eq "^[[:space:]]*127\.[0-9.]+[[:space:]].*\bguestbook\.local\b" /etc/hosts
    check "config.php лежит вне public/" "/var/www/guestbook/config.php" test -f "$CONF"
    check "http://guestbook.local/ отвечает 200" "смотрите error.log Apache" test "$(http_code /)" = 200
    check "страница собрана PHP под Apache (apache2handler)" "проверьте VirtualHost и mod_php" \
        bash -c "p=\$(cat); echo \"\$p\" | grep -q 'Отзывы клиентов' && echo \"\$p\" | grep -q apache2handler" <<<"$(page)"
    check "форма сохраняет отзыв (POST → 302, запись в базе)" "смотрите error.log Apache" post_works
    check "config.php не открывается из браузера (404)" "DocumentRoot должен быть .../public" test "$(http_code /config.php)" = 404

    section "Тикет #5104" "Инцидент после обновления"
    local m; m=$(marker_info lamp-broken)
    check "${m:-инцидент не запускался}" "sudo bash guestbook-tool.sh break lamp" test -n "$m"
    check "веб-сервер ($WEBUSER) может прочитать index.php" "права на каталоги: ls -ld, chmod" runuser -u "$WEBUSER" -- test -r "$INDEX"
    check "index.php без ошибок в коде" "смотрите error.log: PHP Fatal error" bash -c "php -l '$INDEX' && ! grep -q 'htmlspecialchar(' '$INDEX'"
    check "главная страница отвечает 200" "смотрите error.log Apache" test "$(http_code /)" = 200
    check "новые отзывы сохраняются" "смотрите error.log: ... command denied" post_works
    footer
}

# ---------- проверка LNMP ----------
check_lnmp() {
    header "LNMP"
    section "Тикет #5201" "Переезд на nginx"
    check "Apache остановлен и убран из автозапуска" "systemctl disable --now $APACHE" \
        bash -c "! systemctl is-active --quiet $APACHE && ! systemctl is-enabled --quiet $APACHE"
    check "nginx работает и включён в автозапуск" "systemctl enable --now nginx" \
        bash -c "systemctl is-active --quiet nginx && systemctl is-enabled --quiet nginx"
    check "порт 80 слушает nginx" "sudo ss -tlnp | grep :80" listens_by 80 nginx
    check "$FPM работает и включён в автозапуск" "systemctl enable --now $FPM" \
        bash -c "systemctl is-active --quiet $FPM && systemctl is-enabled --quiet $FPM"
    local sh; sh=$(server_header)
    check "nginx не показывает версию (Server: ${sh:-нет ответа})" "server_tokens off;" test "$sh" = nginx

    section "Тикет #5202" "Сайт работает на nginx"
    check "конфигурация nginx без ошибок (nginx -t)" "sudo nginx -t" nginx -t
    check "http://guestbook.local/ отвечает 200" "смотрите /var/log/nginx/error.log" test "$(http_code /)" = 200
    check "страница собрана PHP через php-fpm (fpm-fcgi)" "fastcgi_pass на сокет php-fpm" \
        bash -c "p=\$(cat); echo \"\$p\" | grep -q 'Отзывы клиентов' && echo \"\$p\" | grep -q fpm-fcgi" <<<"$(page)"
    local admin; admin=$(cfg admin)
    check "старые отзывы на месте (отзыв от «$admin»)" "база должна быть та же" \
        test "$(dbq "SELECT COUNT(*) FROM guestbook.guests WHERE name='$(sq "$admin")'")" -ge 1
    check "есть отзыв о переезде (в тексте есть слово nginx)" "оставьте отзыв через форму" \
        test "$(dbq "SELECT COUNT(*) FROM guestbook.guests WHERE message LIKE '%nginx%'")" -ge 1
    check "форма сохраняет отзыв (POST → 302, запись в базе)" "смотрите /var/log/nginx/error.log" post_works
    check "config.php не открывается из браузера (404)" "root должен быть .../public" test "$(http_code /config.php)" = 404

    section "Тикет #5203" "Инцидент: 502 Bad Gateway"
    local m; m=$(marker_info lnmp-broken)
    check "${m:-инцидент не запускался}" "sudo bash guestbook-tool.sh break lnmp" test -n "$m"
    check "$FPM включён в автозапуск" "systemctl enable $FPM" systemctl is-enabled --quiet "$FPM"
    check "в config.php правильное имя базы" "в error.log nginx ошибка называет имя базы" test "$(cfg dbname)" = guestbook
    check "главная страница отвечает 200" "смотрите /var/log/nginx/error.log" test "$(http_code /)" = 200
    footer
}

# ---------- инциденты ----------
need_working_site() {
    if [ "$(http_code /)" != 200 ] || ! post_works; then
        echo "Сайт http://guestbook.local/ сейчас не работает полностью."
        echo "Инцидент запускается только на исправном сайте: сначала выполните предыдущие тикеты."
        exit 1
    fi
}
break_lamp() {
    systemctl is-active --quiet "$APACHE" || { echo "Apache не запущен: сначала выполните тикеты #5101-#5103."; exit 1; }
    need_working_site
    grep -q 'htmlspecialchars(' "$INDEX" || { echo "index.php не похож на файл из задания. Используйте код из задания."; exit 1; }
    local h; h=$(dbq "SELECT host FROM mysql.user WHERE user='guest_app' LIMIT 1")
    chown root:root "$APP/public" && chmod 700 "$APP/public"
    sed -i '0,/htmlspecialchars(/s//htmlspecialchar(/' "$INDEX"
    dbq "REVOKE INSERT ON guestbook.* FROM 'guest_app'@'${h:-localhost}'"
    mkdir -p "$STATE"; date '+%d.%m.%Y %H:%M' > "$STATE/lamp-broken"
    echo "Ночное обновление от подрядчика установлено."
    echo "Утром поддержка пишет: «Сайт отзывов не открывается». Тикет #5104 ваш."
}
break_lnmp() {
    systemctl is-active --quiet nginx || { echo "nginx не запущен: сначала выполните тикеты #5201-#5202."; exit 1; }
    need_working_site
    grep -q "'dbname' *=> *'guestbook'" "$CONF" || { echo "config.php не похож на файл из задания."; exit 1; }
    systemctl disable --now "$FPM" >/dev/null 2>&1
    sed -i "s/'dbname' *=> *'guestbook'/'dbname' => 'guestbook_old'/" "$CONF"
    mkdir -p "$STATE"; date '+%d.%m.%Y %H:%M' > "$STATE/lnmp-broken"
    echo "Подрядчик «оптимизировал» сервер после переезда."
    echo "Мониторинг: «guestbook.local отвечает 502 Bad Gateway». Тикет #5203 ваш."
}

export -f app_sql cfg dbq db_public
export CONF DBC
case "${1:-} ${2:-}" in
    "check lamp") check_lamp ;;
    "check lnmp") check_lnmp ;;
    "break lamp") break_lamp ;;
    "break lnmp") break_lnmp ;;
    *) echo "Использование: sudo bash $0 check lamp | check lnmp | break lamp | break lnmp"; exit 1 ;;
esac
