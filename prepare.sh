#!/bin/bash
# Подготовка приложения курьера для iPhone на сервере: servers.json (основной + регионы + демо для проверки Apple), иконка, choose.html →
# коммит → push в GitHub; сборку для симулятора делает GitHub Actions (.github/workflows/testflight.yml) на macOS.
# Новый регион или правка приложения → запустить снова. Доступа к Apple на сервере нет: ключ App Store Connect — только в секретах репозитория GitHub.
set -euo pipefail
cd "$(dirname "$0")"
BASE=$(dirname "$(pwd)")
"$BASE/.venv/bin/python" - <<'PY'
import json, sys
from pathlib import Path
base = Path.cwd().parent
url = next(l.split("=", 1)[1].strip().strip('"').rstrip("/") for l in (base / ".env").read_text(encoding="utf-8").splitlines() if l.startswith("WEB_URL="))
sys.path.insert(0, str(base))
import region
out = [{"name": "Москва и область", "url": url, "rests": list(region.RESTAURANTS)}]
reg = json.loads((base / "regions.json").read_text(encoding="utf-8")).get("regions", {})
for r in (reg.values() if isinstance(reg, dict) else reg):
    if r.get("domain") and r.get("deployed"):
        out.append({"name": r.get("name") or r["slug"], "url": "https://" + r["domain"], "rests": [x.get("name") for x in r.get("restaurants") or [] if x.get("name")]})
host = url.split("://", 1)[1]
out.append({"name": "Демо (знакомство, без настоящих заказов)", "url": f"https://demo.{host}", "rests": [], "start": "/courier"})
Path("Courier/servers.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
print("серверы:", ", ".join(s["name"] for s in out))

from PIL import Image, ImageDraw          # иконка 1024 без прозрачности (App Store), углы скругляет iOS
s = 1024
im = Image.new("RGB", (s, s), (42, 120, 214)); d = ImageDraw.Draw(im); fg = (255, 255, 255); w = s // 14; r = s * 0.15
for cx in (s * 0.27, s * 0.73):
    d.ellipse([cx - r, s * 0.68 - r, cx + r, s * 0.68 + r], outline=fg, width=w)
d.polygon([(s * 0.30, s * 0.62), (s * 0.70, s * 0.62), (s * 0.66, s * 0.48), (s * 0.40, s * 0.48)], fill=fg)
d.line([(s * 0.66, s * 0.50), (s * 0.74, s * 0.26)], fill=fg, width=w)
d.line([(s * 0.66, s * 0.26), (s * 0.82, s * 0.26)], fill=fg, width=w)
d.rectangle([s * 0.18, s * 0.30, s * 0.42, s * 0.46], fill=fg)
p = Path("Courier/Assets.xcassets/AppIcon.appiconset"); p.mkdir(parents=True, exist_ok=True)
im.save(p / "icon.png")
(p / "Contents.json").write_text(json.dumps({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                                             "info": {"author": "xcode", "version": 1}}))
Path("Courier/Assets.xcassets/Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
PY
cp ../courier_app/assets/choose.html Courier/choose.html
[ -d .git ] || { git init -q -b main; git config user.email "courier@mise"; git config user.name "Сервер склада"; }
git add -- Courier Courier.xcodeproj .github/workflows/testflight.yml .gitignore prepare.sh project.yml README.md
git diff --cached --quiet || git commit -q -m "Приложение курьера для iPhone: $(date '+%d.%m.%Y %H:%M')"
if git remote get-url origin >/dev/null 2>&1; then
  GIT_SSH_COMMAND="ssh -i $HOME/.ssh/courier_ios_deploy -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" git push -q origin main
  echo "отправлено в GitHub — проверка сборки запущена (вкладка Actions репозитория)"
else
  echo "репозиторий GitHub ещё не подключён: git remote add origin git@github.com:<владелец>/<репозиторий>.git"
fi
