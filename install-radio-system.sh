#!/bin/bash

set -e  # Выход при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для вывода
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Переменные
RADIO_USER="radio"
RADIO_HOME="/opt/radio-player"
SERVICE_NAME="vlc-radio.service"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Проверка прав
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт требует прав root. Запустите с sudo!"
        exit 1
    fi
}

# Проверка системы
check_system() {
    print_info "Проверка системы..."
    
    if ! command -v lsb_release &> /dev/null; then
        apt update && apt install -y lsb-release
    fi
    
    local os_id=$(lsb_release -is)
    local version=$(lsb_release -rs)
    
    if [[ "$os_id" != "Ubuntu" ]] && [[ "$os_id" != "Debian" ]]; then
        print_warning "Скрипт тестировался на Ubuntu/Debian. Продолжаем осторожно..."
    fi
    
    print_success "ОС: $os_id $version"
}

# Установка зависимостей
install_dependencies() {
    print_info "Установка зависимостей..."
    
    apt update
    apt install -y \
        vlc \
        pulseaudio \
        curl \
        wget \
        git \
        cron \
        sudo \
        jq
    
    print_success "Зависимости установлены"
}

# Создание пользователя и директорий
setup_environment() {
    print_info "Настройка окружения..."
    
    # Создаем пользователя radio если не существует
    if ! id "$RADIO_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d "$RADIO_HOME" -m "$RADIO_USER"
        print_success "Пользователь $RADIO_USER создан"
    else
        print_info "Пользователь $RADIO_USER уже существует"
    fi
    
    # ИСПРАВЛЕНО: Создаем структуру директорий правильно
    mkdir -p "$RADIO_HOME/scripts"
    mkdir -p "$RADIO_HOME/logs"
    mkdir -p "$RADIO_HOME/config"
    mkdir -p "$RADIO_HOME/backups"
    
    chown -R "$RADIO_USER":"$RADIO_USER" "$RADIO_HOME"
    chmod 755 "$RADIO_HOME"
    
    # Добавляем пользователя в группы audio
    usermod -a -G audio,pulse,pulse-access "$RADIO_USER"
    
    print_success "Окружение настроено"
}

# Создание конфигурационных файлов
create_configs() {
    print_info "Создание конфигурационных файлов..."
    
    # Основной конфиг станций
    cat > "$RADIO_HOME/config/radio-stations.conf" << 'EOF'
# Конфигурация радиостанций
CURRENT_STATION_INDEX=0

RADIO_STATIONS=(
    "Record|https://radiorecord.hostingradio.ru/rr_main96.aacp"
    "Europa Plus|http://ep256.hostingradio.ru:8052/europaplus256.mp3"
    "Radio Record|http://air2.radiorecord.ru:805/rr_320"
    "DFM|http://dfm.hostingradio.ru/dfm96.aacp"
    "Relax FM|http://air2.relaxfm.ru:9000/relax_320"
    "FIP|http://icecast.radiofrance.fr/fip-hifi.aac"
)
EOF

    # Скрипт запуска радио
    cat > "$RADIO_HOME/scripts/start-radio.sh" << 'EOF'
#!/bin/bash

# Конфигурация
CONFIG_DIR="/opt/radio-player/config"
LOG_DIR="/opt/radio-player/logs"
CONFIG_FILE="${RADIO_CONFIG:-$CONFIG_DIR/radio-stations.conf}"
LOG_FILE="$LOG_DIR/radio-player.log"
PLAYER_LOG="$LOG_DIR/vlc-player.log"

# Импорт конфигурации
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ОШИБКА: Конфиг не найден: $CONFIG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

# Функция логирования
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

setup_audio_environment() {
    export PULSE_RUNTIME_PATH="/run/user/$(id -u)/pulse"
    export DISPLAY=:0
    export HOME=/opt/radio-player
    
    mkdir -p ~/.config/pulse
    echo "autospawn = yes" > ~/.config/pulse/client.conf
    echo "daemon-binary = /bin/false" >> ~/.config/pulse/client.conf
    
    log_message "Аудио окружение настроено"
}

start_radio() {
    log_message "=== ЗАПУСК РАДИО-ПЛЕЕРА ==="
    log_message "Используется конфиг: $CONFIG_FILE"
    
    # Настройка аудио
    setup_audio_environment
    
    # Ждем сеть
    log_message "Ожидание сети..."
    while ! ping -c1 -W3 8.8.8.8 > /dev/null 2>/dev/null; do
        sleep 5
    done
    log_message "Сеть готова"
    
    # Берем первую станцию из конфига (для совместимости)
    local station_info="${RADIO_STATIONS[0]}"
    IFS='|' read -r station_name stream_url <<< "$station_info"
    
    log_message "Запуск станции: $station_name"
    log_message "URL: $stream_url"
    
    # Запуск VLC
    exec cvlc \
        --no-video \
        --intf dummy \
        "$stream_url" \
        --loop \
        --network-caching=5000 \
        --sout-keep \
        2>> "$PLAYER_LOG"
}

# Создаем директорию для логов
mkdir -p "$LOG_DIR"

# Запускаем
start_radio
EOF

    # Скрипт контроллера
    cat > "$RADIO_HOME/scripts/radio-controller.sh" << 'EOF'
#!/bin/bash

# Конфигурация
CONFIG_DIR="/opt/radio-player/config"
LOG_DIR="/opt/radio-player/logs" 
CONFIG_FILE="$CONFIG_DIR/radio-stations.conf"
STATE_FILE="$CONFIG_DIR/current-state.conf"
LOG_FILE="$LOG_DIR/radio-controller.log"
CONTROL_PIPE="/tmp/radio-control.pipe"

# Импорт конфигурации
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ОШИБКА: Конфиг не найден: $CONFIG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

# Переменные
CURRENT_STATION_INDEX=0
IS_PLAYING=false
CONTROL_PID=0

# Функция логирования
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Функция сохранения состояния
save_state() {
    cat > "$STATE_FILE" << STATE_EOF
CURRENT_STATION_INDEX=$CURRENT_STATION_INDEX
IS_PLAYING=$IS_PLAYING
CURRENT_STATION_NAME="$CURRENT_STATION_NAME"
CURRENT_STATION_URL="$CURRENT_STATION_URL"
STATE_EOF
}

# Функция загрузки состояния
load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    else
        CURRENT_STATION_INDEX=0
        IS_PLAYING=false
        update_station_info
    fi
}

# Функция обновления информации о текущей станции
update_station_info() {
    local station_info="${RADIO_STATIONS[$CURRENT_STATION_INDEX]}"
    IFS='|' read -r CURRENT_STATION_NAME CURRENT_STATION_URL <<< "$station_info"
}

# Функция остановки радио
stop_radio() {
    log_message "Остановка радио..."
    pkill -f "start-radio.sh" || true
    pkill -f "cvlc.*--intf dummy" || true
    IS_PLAYING=false
    save_state
}

# Функция запуска радио с конкретной станцией
start_radio_with_station() {
    local station_index="$1"
    
    if [ "$station_index" -lt 0 ] || [ "$station_index" -ge "${#RADIO_STATIONS[@]}" ]; then
        log_message "ОШИБКА: Неверный индекс станции: $station_index"
        return 1
    fi
    
    stop_radio
    
    CURRENT_STATION_INDEX=$station_index
    update_station_info
    
    local temp_config="/tmp/radio-current.conf"
    cat > "$temp_config" << CONFIG_EOF
RADIO_STATIONS=(
    "$CURRENT_STATION_NAME|$CURRENT_STATION_URL"
)
CONFIG_EOF
    
    log_message "Запуск станции: $CURRENT_STATION_NAME (индекс: $station_index)"
    
    export RADIO_CONFIG="$temp_config"
    /opt/radio-player/scripts/start-radio.sh &
    
    IS_PLAYING=true
    save_state
    
    log_message "Радио запущено со станцией: $CURRENT_STATION_NAME"
    return 0
}

next_station() {
    local new_index=$(( (CURRENT_STATION_INDEX + 1) % ${#RADIO_STATIONS[@]} ))
    log_message "Переключение на следующую станцию: $new_index"
    start_radio_with_station "$new_index"
}

prev_station() {
    local new_index=$(( (CURRENT_STATION_INDEX - 1 + ${#RADIO_STATIONS[@]}) % ${#RADIO_STATIONS[@]} ))
    log_message "Переключение на предыдущую станцию: $new_index"
    start_radio_with_station "$new_index"
}

switch_station() {
    local index="$1"
    log_message "Переключение на станцию #$index"
    start_radio_with_station "$index"
}

get_status() {
    if $IS_PLAYING; then
        local status="playing"
    else
        local status="stopped"
    fi
    
    if $IS_PLAYING && ! pgrep -f "start-radio.sh" > /dev/null; then
        status="crashed"
        IS_PLAYING=false
        save_state
    fi
    
    cat << STATUS_EOF
{
    "station_index": $CURRENT_STATION_INDEX,
    "station_name": "$CURRENT_STATION_NAME",
    "station_url": "$CURRENT_STATION_URL",
    "status": "$status",
    "total_stations": ${#RADIO_STATIONS[@]}
}
STATUS_EOF
}

list_stations() {
    for i in "${!RADIO_STATIONS[@]}"; do
        IFS='|' read -r name url <<< "${RADIO_STATIONS[$i]}"
        echo "$i: $name"
    done
}

process_command() {
    local command="$1"
    local argument="$2"
    
    case "$command" in
        "start"|"play")
            if [ -n "$argument" ]; then
                switch_station "$argument"
            else
                start_radio_with_station "$CURRENT_STATION_INDEX"
            fi
            ;;
        "stop")
            stop_radio
            ;;
        "next")
            next_station
            ;;
        "prev")
            prev_station
            ;;
        "switch")
            switch_station "$argument"
            ;;
        "status")
            get_status
            ;;
        "list")
            list_stations
            ;;
        "restart")
            stop_radio
            sleep 2
            start_radio_with_station "$CURRENT_STATION_INDEX"
            ;;
        *)
            log_message "Неизвестная команда: $command"
            ;;
    esac
}

setup_control_pipe() {
    rm -f "$CONTROL_PIPE"
    mkfifo "$CONTROL_PIPE"
    chmod 666 "$CONTROL_PIPE"
    log_message "Control pipe создан: $CONTROL_PIPE"
}

start_command_loop() {
    log_message "Запуск цикла обработки команд..."
    while true; do
        if read -r line < "$CONTROL_PIPE" 2>/dev/null; then
            log_message "Получена команда: $line"
            IFS=' ' read -r command argument <<< "$line"
            process_command "$command" "$argument"
        fi
    done
}

initialize() {
    log_message "=== ИНИЦИАЛИЗАЦИЯ РАДИО-КОНТРОЛЛЕРА ==="
    
    # ИСПРАВЛЕНО: Создаем директории правильно
    mkdir -p "$LOG_DIR"
    mkdir -p "$CONFIG_DIR"
    
    load_state
    setup_control_pipe
    log_message "Контроллер инициализирован. Текущая станция: $CURRENT_STATION_INDEX"
}

cleanup() {
    log_message "Завершение работы контроллера..."
    stop_radio
    rm -f "$CONTROL_PIPE"
    kill $COMMAND_LOOP_PID 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

main() {
    initialize
    start_command_loop &
    COMMAND_LOOP_PID=$!
    
    log_message "Контроллер запущен. PID: $$, Command loop PID: $COMMAND_LOOP_PID"
    
    while true; do
        if ! kill -0 $COMMAND_LOOP_PID 2>/dev/null; then
            log_message "Command loop завершился, перезапуск..."
            start_command_loop &
            COMMAND_LOOP_PID=$!
        fi
        
        if $IS_PLAYING && ! pgrep -f "start-radio.sh" > /dev/null; then
            log_message "Воспроизведение остановилось неожиданно"
            IS_PLAYING=false
            save_state
        fi
        
        sleep 10
    done
}

main
EOF

    print_success "Конфигурационные файлы созданы"
}

# Создание systemd службы
create_systemd_service() {
    print_info "Создание systemd службы..."
    
    cat > "/etc/systemd/system/$SERVICE_NAME" << EOF
[Unit]
Description=VLC Internet Radio Player with Station Control
After=network.target sound.target
Wants=network.target
Requires=network.target

[Service]
Type=simple
User=$RADIO_USER
Group=$RADIO_USER
WorkingDirectory=$RADIO_HOME
Environment=DISPLAY=:0
Environment=HOME=$RADIO_HOME
ExecStart=$RADIO_HOME/scripts/radio-controller.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Безопасность
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$RADIO_HOME/logs $RADIO_HOME/config /tmp
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "Systemd служба создана"
}

# Настройка cron задач
setup_cron() {
    print_info "Настройка планировщика задач..."
    
    # Ежедневная перезагрузка в 7:00
    (crontab -l 2>/dev/null | grep -v "vlc-radio"; echo "0 7 * * * /bin/systemctl restart vlc-radio.service") | crontab -
    
    # Мониторинг каждые 5 минут
    (crontab -l 2>/dev/null | grep -v "radio-monitor"; echo "*/5 * * * * /usr/local/bin/radioctl status > /dev/null 2>&1") | crontab -
    
    print_success "Cron задачи настроены"
}

# Настройка прав
setup_permissions() {
    print_info "Настройка прав доступа..."
    
    chown -R "$RADIO_USER":"$RADIO_USER" "$RADIO_HOME"
    chmod +x "$RADIO_HOME/scripts/"*.sh
    chmod +x /usr/local/bin/radioctl
    chmod 644 "$RADIO_HOME/config/"*.conf
    
    print_success "Права доступа настроены"
}

# Запуск сервиса
start_services() {
    print_info "Запуск сервисов..."
    
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    
    sleep 3  # Даем время на запуск
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Сервис $SERVICE_NAME запущен"
    else
        print_error "Не удалось запустить сервис $SERVICE_NAME"
        journalctl -u "$SERVICE_NAME" -n 10 --no-pager
        return 1
    fi
}

# Финальная проверка
final_check() {
    print_info "Финальная проверка..."
    
    echo ""
    print_success "=== УСТАНОВКА ЗАВЕРШЕНА ==="
    echo ""
    echo "📻 Radio System успешно установлена!"
    echo ""
    echo "Основные команды:"
    echo "  radioctl start      - запустить радио"
    echo "  radioctl stop       - остановить радио" 
    echo "  radioctl next       - следующая станция"
    echo "  radioctl status     - статус системы"
    echo "  radioctl list       - список станций"
    echo ""
    echo "Логи:"
    echo "  radioctl logs       - логи контроллера"
    echo "  radioctl player-logs - логи плеера"
    echo "  journalctl -u vlc-radio.service -f - логи службы"
    echo ""
    echo "Управление службой:"
    echo "  sudo systemctl stop vlc-radio.service"
    echo "  sudo systemctl start vlc-radio.service"
    echo "  sudo systemctl restart vlc-radio.service"
    echo ""
    echo "Автоперезагрузка: ежедневно в 7:00"
    echo ""
    
    # Быстрая проверка статуса
    if command -v radioctl &> /dev/null; then
        echo "Текущий статус:"
        radioctl status
    fi
}

# Главная функция
main() {
    print_info "Начало установки Radio System..."
    echo ""
    
    check_privileges
    check_system
    install_dependencies
    setup_environment
    create_configs
    create_systemd_service
    setup_cron
    setup_permissions
    start_services
    final_check
}

# Обработка аргументов командной строки
case "${1:-}" in
    "-h"|"--help")
        echo "Установщик Radio System"
        echo ""
        echo "Использование: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -h, --help     Показать эту справку"
        echo "  -v, --version  Показать версию"
        echo "  --uninstall    Удалить Radio System"
        echo ""
        echo "Пример:"
        echo "  sudo $0        # Установить систему"
        echo "  sudo $0 --uninstall # Удалить систему"
        exit 0
        ;;
    "-v"|"--version")
        echo "Radio System Installer v1.0.0"
        exit 0
        ;;
    "--uninstall")
        # Функция удаления (можно добавить позже)
        echo "Функция удаления будет добавлена в будущих версиях"
        exit 0
        ;;
    *)
        main
        ;;
esac
