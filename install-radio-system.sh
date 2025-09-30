#!/bin/bash
set -e

echo "=== Установка Internet Radio Service ==="

# 1. Установка зависимостей
echo "[1/6] Устанавливаю VLC и curl..."
sudo apt update
sudo apt install -y vlc curl

# 2. Создание пользователя
echo "[2/6] Создаю системного пользователя radio..."
if ! id "radio" &>/dev/null; then
    sudo adduser --system --group radio
fi

# 3. Настройка директорий
echo "[3/6] Настраиваю каталоги..."
sudo mkdir -p /etc/radio /var/lib/radio /var/log
sudo chown -R radio:radio /var/lib/radio
sudo touch /var/log/radio.log
sudo chmod 666 /var/log/radio.log

# 4. Файл станций
echo "[4/6] Создаю список радиостанций..."
cat <<EOF | sudo tee /etc/radio/stations.list >/dev/null
Record|https://radiorecord.hostingradio.ru/rr_main96.aacp
Chill-Out|https://radiorecord.hostingradio.ru/chil96.aacp
Chill House|https://radiorecord.hostingradio.ru/chillhouse96.aacp
Summer Lounge|https://radiorecord.hostingradio.ru/summerlounge96.aacp
Summer Dance|https://radiorecord.hostingradio.ru/summerparty96.aacp
Lo-Fi House|https://radiorecord.hostingradio.ru/lofihouse96.aacp
Christmas|https://radiorecord.hostingradio.ru/christmas96.aacp
EOF

# 5. Скрипт управления
echo "[5/6] Устанавливаю radioctl..."
cat <<'EOF' | sudo tee /usr/local/bin/radioctl >/dev/null
#!/bin/bash
STATIONS_FILE="/etc/radio/stations.list"
CURRENT_INDEX_FILE="/var/lib/radio/current_station"
PID_FILE="/var/lib/radio/radio.pid"
LOG_FILE="/var/log/radio.log"

mkdir -p /var/lib/radio
touch "$CURRENT_INDEX_FILE"

get_station() {
    INDEX=$(cat "$CURRENT_INDEX_FILE" 2>/dev/null || echo 1)
    LINE=$(sed -n "${INDEX}p" "$STATIONS_FILE")
    NAME=$(echo "$LINE" | cut -d'|' -f1)
    URL=$(echo "$LINE" | cut -d'|' -f2)
    echo "$NAME|$URL"
}

list_stations() {
    nl -w2 -s'. ' "$STATIONS_FILE" | sed 's/|/ -> /'
}

play() {
    STATION=$(get_station)
    NAME=$(echo "$STATION" | cut -d'|' -f1)
    URL=$(echo "$STATION" | cut -d'|' -f2)

    echo "Запуск: $NAME ($URL)" | tee -a "$LOG_FILE"

    stop

    cvlc --quiet --intf dummy "$URL" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
}

stop() {
    if [ -f "$PID_FILE" ]; then
        kill "$(cat $PID_FILE)" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo "Радио остановлено" | tee -a "$LOG_FILE"
    fi
}

next() {
    TOTAL=$(wc -l < "$STATIONS_FILE")
    INDEX=$(cat "$CURRENT_INDEX_FILE" 2>/dev/null || echo 1)
    NEXT=$((INDEX % TOTAL + 1))
    echo $NEXT > "$CURRENT_INDEX_FILE"
    play
}

set_station() {
    ARG="$1"
    if [[ "$ARG" =~ ^[0-9]+$ ]]; then
        echo "$ARG" > "$CURRENT_INDEX_FILE"
    else
        LINE=$(grep -n "^$ARG|" "$STATIONS_FILE" | cut -d: -f1)
        [ -n "$LINE" ] && echo "$LINE" > "$CURRENT_INDEX_FILE"
    fi
    play
}

status() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        STATION=$(get_station)
        NAME=$(echo "$STATION" | cut -d'|' -f1)
        echo "▶ Играет: $NAME (PID $(cat $PID_FILE))"
    else
        echo "⏹ Радио не играет"
    fi
}

check() {
    echo "Проверка доступности станций..."
    while IFS='|' read -r NAME URL; do
        if curl -s --max-time 5 "$URL" -o /dev/null; then
            echo "✅ $NAME доступна"
        else
            echo "❌ $NAME недоступна"
        fi
    done < "$STATIONS_FILE"
}

case "$1" in
    play) play ;;
    stop) stop ;;
    next) next ;;
    list) list_stations ;;
    set) set_station "$2" ;;
    status) status ;;
    check) check ;;
    *) echo "Использование: $0 {play|stop|next|list|set <имя/номер>|status|check}" ;;
esac
EOF

sudo chmod +x /usr/local/bin/radioctl

# 6. Сервис и таймер
echo "[6/6] Настраиваю systemd сервис и таймер..."
cat <<EOF | sudo tee /etc/systemd/system/radio.service >/dev/null
[Unit]
Description=Internet Radio Player
After=network.target sound.target

[Service]
ExecStart=/usr/local/bin/radioctl play
ExecStop=/usr/local/bin/radioctl stop
Restart=always
User=radio

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | sudo tee /etc/systemd/system/radio-restart.service >/dev/null
[Unit]
Description=Restart Internet Radio

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart radio.service
EOF

cat <<EOF | sudo tee /etc/systemd/system/radio-restart.timer >/dev/null
[Unit]
Description=Daily restart of Internet Radio

[Timer]
OnCalendar=*-*-* 07:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now radio.service
sudo systemctl enable --now radio-restart.timer

echo "=== Установка завершена! ==="
echo "Используйте команду: sudo radioctl status"
