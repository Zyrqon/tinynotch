# 100 функций TinyNotch — реестр и статус

Ровно 100. Статус: [x] реализовано, [~] в работе, [ ] в очереди. Реализация идёт по одной, на сервере (Mac оффлайн).

001. [x] `stripFormat` — Чистка вставленного текста от форматирования
002. [x] `charCount` — Счётчик символов, слов, строк
003. [x] `caseConvert` — Регистр текста: CAPS / строчные / Каждое Слово
004. [x] `translit` — Транслитерация RU → LAT
005. [x] `base64` — Base64 encode/decode
006. [x] `urlEncode` — URL-кодирование / декодирование
007. [x] `jsonFormat` — JSON-форматтер и валидатор
008. [x] `sha256` — Хеш SHA-256 текста
009. [x] `uuidGen` — Генератор UUID
010. [x] `passGen` — Генератор паролей (длина, символы)
011. [x] `unixTime` — Unix-время ↔ дата
012. [x] `regexTest` — Regex-тестер
013. [x] `textDiff` — Diff двух текстов
014. [x] `loremIpsum` — Lorem ipsum генератор
015. [x] `morse` — Морзе-переводчик
016. [x] `romanNumerals` — Римские ↔ арабские цифры
017. [x] `calculator` — Калькулятор с историей
018. [x] `unitConvert` — Конвертер единиц (длина/вес/температура)
019. [x] `currencyConvert` — Конвертер валют (кэш курсов)
020. [x] `percentCalc` — Проценты: скидка, чаевые, НДС
021. [x] `loanCalc` — Кредитный калькулятор (платёж)
022. [x] `randomPick` — Монетка / кубик / случайное число
023. [x] `randomFromList` — Случайный выбор из списка
024. [x] `qrGen` — Генератор QR-кода
025. [x] `colorPicker` — Пипетка цвета с экрана (hex)
026. [x] `hexRgb` — HEX ↔ RGB
027. [x] `paletteImg` — Палитра из картинки
028. [x] `screenRuler` — Экранная линейка
029. [x] `sysMonitors` — Монитор CPU/RAM/сети
030. [x] `diskSpace` — Свободное место на дисках
031. [x] `batteryInfo` — Батарея и циклы заряда
032. [x] `uptimeInfo` — Uptime системы
033. [x] `publicIP` — Публичный IP
034. [x] `pingHost` — Пинг до хоста
035. [x] `speedTest` — Скорость сети
036. [x] `folderSize` — Размер папки (drag&drop)
037. [x] `bigFiles` — Поиск больших файлов
038. [x] `emptyTrash` — Очистка корзины
039. [x] `caffeinate` — «Не спать» (caffeinate)
040. [x] `themeToggle` — Тёмная/светлая тема
041. [x] `dndToggle` — «Не беспокоить» (DND)
042. [x] `killProcess` — Топ процессов по памяти + убить
043. [x] `wifiList` — Список Wi-Fi и сила сигнала
044. [x] `shotArea` — Скриншот области на полку
045. [x] `shotWindow` — Скриншот окна
046. [x] `ocrShot` — OCR: текст со скриншота
047. [x] `micRecord` — Запись звука с микрофона
048. [x] `voiceNotes` — Диктофон-заметки
049. [x] `imgConvertExt` — Конвертер картинок: +HEIC/WebP/AVIF
050. [x] `pdfCompress` — Сжатие PDF
051. [x] `pdfMerge` — Слияние PDF
052. [x] `pdfSplit` — Разделение PDF
053. [x] `imgRotate` — Поворот/отражение картинки
054. [x] `imgWatermark` — Водяной знак
055. [x] `videoDownload` — Скачивание видео по ссылке
056. [x] `videoAudio` — Извлечение аудио из видео
057. [x] `videoGif` — GIF из видео
058. [x] `videoCompress` — Сжатие видео
059. [x] `batchRename` — Пакетное переименование файлов
060. [x] `gitStatus` — Git-статус папки
061. [x] `gitLog` — Последние коммиты
062. [x] `todoCount` — Счётчик TODO/FIXME
063. [x] `openEditor` — Открыть проект в редакторе
064. [x] `localServer` — Локальный HTTP-сервер на папке
065. [x] `portWho` — Кто слушает порт
066. [x] `ngrokTunnel` — Туннель ngrok
067. [x] `sqlSelect` — SQL-билдер запросов
068. [x] `sqlFormat` — SQL-форматтер
069. [x] `cronExplain` — Cron-расшифровка
070. [x] `weatherNow` — Погода
071. [x] `ratesLive` — Курсы валют в строке островка
072. [x] `quickSticky` — Стикер-заметка
073. [x] `shoppingList` — Чеклист покупок
074. [x] `rssFeed` — RSS-заголовки
075. [x] `hnFeed` — Лента Hacker News
076. [x] `birthdaysNear` — Ближайшие дни рождения
077. [x] `tgSelf` — Отправить себе в Telegram
078. [x] `scratchpad` — Черновик-блокнот с автосохранением
079. [x] `sysSchedule` — Расписание Систематики на сегодня
080. [x] `pomodoro` — Помодоро-таймер с циклами
081. [x] `metronome` — Метроном
082. [x] `stopwatch` — Секундомер с кругами
083. [x] `countdownDate` — Отсчёт до даты (дедлайн)
084. [x] `worldClock` — Мировые часы
085. [x] `backToTask` — Напоминание «вернись к задаче»
086. [x] `stretchReminder` — Стретчинг-напоминание
087. [x] `waterCounter` — Счётчик воды
088. [x] `breathe` — Дыхание 4-7-8
089. [x] `quoteOfDay` — Цитата дня
090. [x] `jokeOfDay` — Шутка дня
091. [x] `game2048` — Игра 2048
092. [x] `snake` — Змейка
093. [x] `mines` — Сапёр
094. [x] `tamagotchi` — Тамагочи-котик
095. [x] `siteBlocker` — Блокировщик отвлекающих сайтов
096. [x] `pomodoroStats` — Статистика фокуса за неделю
097. [x] `hotkeyCheat` — Шпаргалка горячих клавиш Mac
098. [x] `sizeConvert` — Конвертер размеров одежды и обуви
099. [x] `tzConvert` — Часовые пояса для встреч
100. [x] `pasteClean` — Умная вставка как чистый текст
