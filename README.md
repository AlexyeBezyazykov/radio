# 🎵 Internet Radio Service for Ubuntu

Сервис для автоматического проигрывания интернет-радио на Ubuntu.  
Особенности:
- Автоматический запуск при старте системы
- Ежедневный перезапуск в 07:00
- Поддержка переключения станций
- Проверка доступности потоков
- Мониторинг через systemd

## 🚀 Установка


git clone https://github.com/<your-repo>/internet-radio.git
cd internet-radio
chmod +x install.sh
./install.sh
После установки сервис автоматически запустится. 


## 📋 Команды управления

Все команды выполняются через radioctl:


sudo radioctl list           # список станций
sudo radioctl status         # статус проигрывателя
sudo radioctl next           # следующая станция
sudo radioctl set 3          # выбор по номеру
sudo radioctl set "Chill-Out" # выбор по имени
sudo radioctl check          # проверка доступности всех потоков
sudo radioctl stop           # остановить проигрыватель
sudo radioctl play           # запустить снова


## 🔧 Управление сервисом

Проверка логов:

```journalctl -u radio.service -f```


Перезапуск вручную:

```sudo systemctl restart radio.service```


Отключение автозапуска:

```sudo systemctl disable --now radio.service```

## 📡 Добавление своих станций

Файл со станциями находится здесь:

```/etc/radio/stations.list


Формат:

Название|URL

## 🛠 Требования

Ubuntu / Debian

VLC (cvlc)

curl
