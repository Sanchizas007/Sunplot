#!/bin/zsh
# Общая проверка после каждой фичи: движок, сборка, тесты приложения.
# Прогонять до коммита — конфликты между фичами всплывают здесь, а не в сторе.
#
#   ./Tools/check.sh
#
cd "$(dirname "$0")/.."
LOG=$(mktemp -t sunspot-check)
FAILED=()

step() { print -n "── $1 "; }
ok()   { print "✅"; }
bad()  { print "❌"; FAILED+=("$1"); }

step "движок SolarCore      "
if (cd Packages/SolarCore && swift test) > "$LOG" 2>&1; then
  print -n "$(grep -oE 'Test run with [0-9]+ tests' "$LOG" | tail -1)  "; ok
else
  bad "SolarCore"; grep -E "error:|✘" "$LOG" | head -10
fi

step "сборка приложения     "
if xcodebuild -project Sunspot.xcodeproj -scheme Sunspot \
     -destination 'generic/platform=iOS Simulator' build > "$LOG" 2>&1; then
  WARNINGS=$(grep -c "warning:" "$LOG")
  print -n "предупреждений: $WARNINGS  "; ok
else
  bad "сборка"; grep -E "error:" "$LOG" | sort -u | head -10
fi

step "конфигурация покупок  "
python3 - <<'PYEOF' > "$LOG" 2>&1
import json, re, sys, pathlib
root = pathlib.Path(".")
problems = []

# Ссылка из схемы должна называть файл, который существует.
scheme = (root / "Sunspot.xcodeproj/xcshareddata/xcschemes/Sunspot.xcscheme").read_text()
refs = re.findall(r'StoreKitConfigurationFileReference\s*\n?\s*identifier\s*=\s*"([^"]+)"', scheme)
if not refs:
    problems.append("схема не называет ни одного StoreKit-конфига")
for ref in refs:
    name = ref.rsplit("/", 1)[-1]
    if not (root / "Config" / name).exists():
        problems.append(f"схема ссылается на {name}, а Config/{name} нет")

# Сам конфиг должен продавать ровно то, что ждёт код.
cfg = json.loads((root / "Config/Sunspot.storekit").read_text())
products = cfg.get("products", [])
if len(products) != 1:
    problems.append(f"товаров в конфиге {len(products)}, ожидается один")
else:
    p = products[0]
    if p.get("productID") != "app.sunplot.full":
        problems.append(f"productID в конфиге {p.get('productID')}, код ждёт app.sunplot.full")
    if p.get("type") != "NonConsumable":
        problems.append(f"тип {p.get('type')}, ожидается NonConsumable")
    if p.get("displayPrice") != "5.99":
        problems.append(f"цена {p.get('displayPrice')}, ожидается 5.99")
if cfg.get("subscriptionGroups"):
    problems.append("в конфиге есть подписки, а весь смысл в том, что их нет")

# Без витрины и локали сессия поднимается пустой и товаров не отдаёт — молча.
settings = cfg.get("settings", {})
for key in ("_storefront", "_locale"):
    if not settings.get(key):
        problems.append(f"в settings нет {key} — тестовый магазин поднимется пустым")

# Код и конфиг не должны разъехаться по идентификатору.
code = (root / "Sunspot/Core/Purchases.swift").read_text()
m = re.search(r'productID\s*=\s*"([^"]+)"', code)
if m and products and m.group(1) != products[0].get("productID"):
    problems.append("идентификатор в коде и в конфиге разъехались")

if problems:
    print("\n".join(problems)); sys.exit(1)
print("ссылка, товар и цена совпадают")
PYEOF
if [[ $? -eq 0 ]]; then print -n "$(tail -1 "$LOG")  "; ok; else bad "конфигурация покупок"; cat "$LOG"; fi

step "локализация          "
# Каталоги пишутся из Tools/strings/, поэтому проверка одна: совпадают ли они с таблицами.
# Сами таблицы проверяются при генерации — подстановки, переносы, письменность, пропуски.
if python3 Tools/strings.py --check > "$LOG" 2>&1 && python3 Tools/check-localisation.py >> "$LOG" 2>&1; then
  print -n "$(grep -m1 'catalogs match' "$LOG" | sed 's/catalogs match Tools\/strings\/ — //')  "; ok
else
  bad "локализация"; cat "$LOG"
fi

step "тесты приложения      "
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for rt in sorted(d, reverse=True):
    if 'iOS' not in rt: continue
    for dev in d[rt]:
        if 'iPhone' in dev['name']: print(dev['udid']); sys.exit()
")
if [[ -z "$UDID" ]]; then
  print "⚠ нет симулятора iPhone — пропущено"
# Язык тестов задан явно: они сверяют английские строки, а симулятор берёт язык системы —
# с четырнадцатью языками в сборке тот же тест падал бы на русской машине и проходил на
# английской.
elif xcodebuild -project Sunspot.xcodeproj -scheme Sunspot \
       -destination "id=$UDID" -testLanguage en -testRegion GB test > "$LOG" 2>&1; then
  print -n "$(grep -oE 'Test run with [0-9]+ tests' "$LOG" | tail -1)  "; ok
else
  bad "тесты приложения"; grep -E "error:|✘|failed" "$LOG" | sort -u | head -10
fi

rm -f "$LOG"
print ""
if (( ${#FAILED} == 0 )); then
  print "✅ общая проверка пройдена"
else
  print "❌ провалено: ${(j:, :)FAILED}"
  exit 1
fi
