# 🎵 Radio System for Ubuntu

Автоматизированная система интернет-радио для Ubuntu с управлением станциями и автозапуском.

## ✨ Возможности

- 🎶 Автозапуск радио при загрузке системы
- 🔄 Управление станциями (play, stop, next, prev)
- 📻 Предустановленные популярные радиостанции
- ⏰ Ежедневная перезагрузка в 7:00
- 📊 Мониторинг и логирование
- 🛠️ Простое управление через команду `radioctl`

## 🚀 Быстрая установка

**Одной командой:**

```bash
curl -sSL [https://github.com/v/radio/blob/main/install-radio-system.sh] | sudo bash
Или вручную:

bash
git clone https://github.com/AlexyeBezyazykov/radio.git
cd radio
sudo ./install-radio-system.sh
🎛️ Управление
После установки используйте команду radioctl:

bash
# Запустить радио
radioctl start

# Следующая станция
radioctl next

# Предыдущая станция
radioctl prev

# Остановить радио
radioctl stop

# Показать статус
radioctl status

# Список станций
radioctl list

# Переключиться на станцию #2
radioctl switch 2

# Просмотр логов
radioctl logs
📡 Предустановленные станции
Record - Radio Record

Europa Plus - Europa Plus

Radio Record - Radio Record (альтернативный поток)

DFM - DFM

Relax FM - Relax FM

FIP - FIP (французское радио)

🛠️ Технические детали
Пользователь: radio

Директория: /opt/radio-player

Служба: vlc-radio.service

Логи: /opt/radio-player/logs/

🔧 Ручная установка
Если скрипт не работает, выполните шаги вручную:

Установите зависимости:

bash
sudo apt update && sudo apt install -y vlc pulseaudio curl cron
Скачайте и запустите установщик:

bash
wget https://raw.githubusercontent.com/yourusername/radio-system/main/install-radio-system.sh
chmod +x install-radio-system.sh
sudo ./install-radio-system.sh
📝 Логи
bash
# Логи контроллера
radioctl logs

# Логи плеера VLC
radioctl player-logs

# Логи systemd службы
journalctl -u vlc-radio.service -f
🐛 Решение проблем
Радио не запускается:

bash
sudo systemctl restart vlc-radio.service
journalctl -u vlc-radio.service -n 20
Нет звука:

bash
# Проверить аудио систему
pactl list sinks short

# Перезапустить PulseAudio
pulseaudio -k && pulseaudio --start
