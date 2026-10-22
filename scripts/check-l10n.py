#!/usr/bin/env python3
"""Проверка перевода: у каждой строки L("…") должен быть английский вариант в English.swift.
Заодно показывает русские строки вне L(…) — среди них не должно быть текста интерфейса.
Запуск: python3 scripts/check-l10n.py"""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent / "Sources" / "Notchly"
table = (root / "English.swift").read_text()
known = set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)":', table, re.M))
# Ключи, которые попадают в L() через переменную (rawValue разделов).
dynamic = set()
for f in root.rglob("*.swift"):
    src = f.read_text()
    for m in re.finditer(r'case\s+\w+\s*=\s*"([^"]*[А-Яа-яЁё][^"]*)"', src):
        dynamic.add(m.group(1))

missing, loose = set(), []
service = re.compile(r'NSLog\(|print\(|\bdone\(|lines\.append|var lines|label ==|label:|device_battery|'
                     r'contains \{ lower|"description":|requestBody\(for:|tasks\.add\(|fired\.append|report\.append')
for f in sorted(root.rglob("*.swift")):
    if f.name in ("English.swift", "Localization.swift", "Snapshots.swift", "Bench.swift"):
        continue
    for n, line in enumerate(f.read_text().splitlines(), 1):
        code = line.split("//")[0] if not line.strip().startswith('"') else line
        for key in re.findall(r'\bL\("((?:[^"\\]|\\.)*)"', code):
            if re.search('[А-Яа-яЁё]', key) and key not in known:
                missing.add(key)
        rest = re.sub(r'\bL\("(?:[^"\\]|\\.)*"', '', code)
        if re.search(r'"[^"]*[А-Яа-яЁё][^"]*"', rest) and not service.search(line) \
                and not re.search(r'case\s+\w+\s*=|Loc\.(pick|plural)', line):
            loose.append(f"{f.relative_to(root)}:{n}: {line.strip()[:110]}")

missing |= {k for k in dynamic if k not in known and k not in ("Левый", "Правый", "Кейс")}
for k in sorted(missing):
    print("нет перевода:", k)
for l in loose:
    print("строка без L():", l)
print(f"Итого: без перевода {len(missing)}, без L() {len(loose)}")
sys.exit(1 if missing else 0)
