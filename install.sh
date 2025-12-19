#!/bin/bash
set -e

echo "🎧 Установка radioctl..."

mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/systemd/user"
mkdir -p "$HOME/.config/radio"

cp radioctl "$HOME/.local/bin/"
cp stations.list "$HOME/.config/radio/"
cp radio.service "$HOME/.config/systemd/user/"

chmod +x "$HOME/.local/bin/radioctl"

systemctl --user daemon-reload
systemctl --user enable --now radio.service

echo "✅ Установка завершена"
echo "Команды:"
echo "  radioctl play"
echo "  radioctl stop"
echo "  radioctl next"
echo "  radioctl status"
