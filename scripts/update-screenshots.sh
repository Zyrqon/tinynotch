#!/bin/zsh
# Перерисовывает скриншоты для README на английском и русском: docs/screenshots/{en,ru}/.
# Всё рендерится офлайн (Notchly --snapshots), экран и доступы не нужны.
set -euo pipefail
cd "$(dirname "$0")/.."

# Кадры, которые используют README.md, README.ru.md и PRIVACY.md.
SHOTS=(
    1-compact 3-hud
    4-home 5-home-no-music 4-home-airpods 4-music 5-empty
    4-notes 4-notes-tasks 11-task-detail
    4-timer 12-focus-home 12-focus-compact 12-focus-event
    13-timer-seconds 13-countdown-compact 13-timer-alarm 13-alarm
    10-reminder 10-reminder-calendar 10-notification
    8-airpods-compact 8-airpods 9-max 7-charging
    4-controls 4-shelf
    4-clipboard 4-clipboard-shots 4-clipboard-vault
    4-notifications
    14-settings-0 14-settings-1 14-settings-2
)

swift build
for lang in en ru; do
    tmp="build/snapshots-$lang"
    rm -rf "$tmp"
    .build/debug/Notchly --snapshots "$tmp" --lang "$lang"
    out="docs/screenshots/$lang"
    rm -rf "$out"
    mkdir -p "$out"
    for name in $SHOTS; do
        cp "$tmp/$name.png" "$out/$name.png"
    done
done
echo "Готово: docs/screenshots/en, docs/screenshots/ru"
