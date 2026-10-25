"""Assemble site/index.html à partir de tools/site.template.html et du catalogue réel de l'app.
Usage: /usr/bin/python3 tools/build_site.py <Mandarine.app> <version> [<url-dmg>]
Le catalogue (conversions, outils, actions, exemples) vient de `Mandarine --catalog` : le site ne peut pas annoncer ce que l'app ne fait pas.
"""
import json, subprocess, sys, html, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
app, version = sys.argv[1], sys.argv[2]
dmg = sys.argv[3] if len(sys.argv) > 3 else f"https://github.com/Agarthe-A/mandarine/releases/download/v{version}/Mandarine-{version}.dmg"

cat = json.loads(subprocess.run([f"{app}/Contents/MacOS/Mandarine", "--catalog"], capture_output=True, text=True, check=True).stdout)
assert cat["version"] == version, f"l'app est en {cat['version']}, pas {version}"
(root / "site" / "catalog.json").write_text(json.dumps(cat, ensure_ascii=False, indent=1))

# ce que Tangerine fait et pas Mandarine : liste tenue à la main, relue à chaque version
TODO = [
    "Éditer et annoter une photo",
    "Rogner librement (carré seulement)",
    "Couper une vidéo à des instants précis",
    "Flouter dans une vidéo",
    "Éditer les métadonnées (suppression seulement)",
    "PDF vers Word, PowerPoint, Excel",
    "Présentations et tableurs",
    "Archives RAR",
]

tpl = (root / "tools" / "site.template.html").read_text()
out = (tpl.replace("__DMG__", dmg).replace("__VERSION__", version)
          .replace("__TOOLS__", str(len(cat["tools"]))).replace("__PAIRS__", str(cat["conversionPairs"]))
          .replace("__TODO__", "".join(f"<li>{html.escape(t)}</li>" for t in TODO))
          .replace("__CATALOG__", json.dumps(cat, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")))
(root / "site" / "index.html").write_text(out)
print("site/index.html", len(out), "octets | outils", len(cat["tools"]), "| conversions", cat["conversionPairs"], "| dmg", dmg)
