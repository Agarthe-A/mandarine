#!/bin/zsh
# Vérificateur de Mandarine : génère des fichiers réels, lance chaque conversion/outil en CLI,
# contrôle que la sortie existe, n'est pas vide, et que son format est le bon.
# Usage : ./verify.sh   (code de sortie 0 = tout passe)
cd "$(dirname "$0")" || exit 2
ROOT=$PWD
M=$ROOT/build/Mandarine.app/Contents/MacOS/Mandarine
FF=${FFMPEG:-$HOME/.hermes/tools/ffmpeg-9.0.1-darwin-arm64/ffmpeg}
[ -x "$M" ] || { echo "Mandarine.app absente: lancer ./build.sh"; exit 2; }
[ -x "$FF" ] || { echo "ffmpeg introuvable: $FF"; exit 2; }
"$M" --list convert /dev/null >/dev/null 2>&1 || true
T=$(mktemp -d "${TMPDIR:-/tmp}/mandarine-verify.XXXXXX"); trap '[ -n "$SRVPID" ] && kill $SRVPID 2>/dev/null; rm -rf "$T"' EXIT
cd "$T"
$FF -loglevel error -f lavfi -i testsrc=duration=2:size=640x360:rate=24 -f lavfi -i sine=frequency=440:duration=2 -c:v libx264 -pix_fmt yuv420p -c:a aac a.mp4
$FF -loglevel error -f lavfi -i sine=frequency=440:duration=2 s.wav
$FF -loglevel error -f lavfi -i testsrc=size=800x600 -frames:v 1 p.png
printf '# Titre\n\nBonjour **monde**\n' > n.md
pass=0; fail=0
# check <id> <type attendu (mot du résultat de `file`, ou "dir")> <fichiers…>
check() {
  local id=$1 want=$2; shift 2
  local out; out=$(perl -e 'alarm 120; exec { $ARGV[0] } @ARGV or die "exec: $!"' "$M" --run "$id" "$@" 2>&1); local rc=$?
  local last=$(echo "$out" | tail -1); LAST=$last
  if [ $rc -ne 0 ]; then echo "FAIL $id $*: $last"; fail=$((fail+1)); return; fi
  if [ "$want" = dir ]; then [ -d "$last" ] || { echo "FAIL $id: pas un dossier ($last)"; fail=$((fail+1)); return; }
  else
    [ -s "$last" ] || { echo "FAIL $id: sortie vide ($last)"; fail=$((fail+1)); return; }
    file -b "$last" | grep -qiE "$want" || { echo "FAIL $id: format inattendu: $(file -b "$last" | cut -c1-60)"; fail=$((fail+1)); return; }
  fi
  echo "ok   $id -> $(basename "$last")"; pass=$((pass+1))
}
for f in "jpg:JPEG" "webp:Web/P" "heic:ISO Media|HEIF|heic" "tiff:TIFF" "gif:GIF" "pdf:PDF" "avif:ISO Media|AVIF"; do check convert:${f%%:*} "${f#*:}" p.png; done
for f in "mov:ISO Media|QuickTime" "webm:WebM|Matroska" "gif:GIF" "mp3:MPEG|Audio|ID3" "mkv:Matroska"; do check convert:${f%%:*} "${f#*:}" a.mp4; done
for f in "mp3:MPEG|Audio|ID3" "m4a:ISO Media|M4A" "flac:FLAC" "opus:Ogg|Opus" "aiff:AIFF"; do check convert:${f%%:*} "${f#*:}" s.wav; done
for f in "docx:Microsoft|Zip" "pdf:PDF" "html:HTML" "epub:EPUB|Zip"; do check convert:${f%%:*} "${f#*:}" n.md; done
cp n.md n2.md; check convert:docx "Microsoft|Zip" n2.md
check convert:pdf PDF n.docx; check convert:txt "text" n.docx; check convert:md "text" n.docx
check convert:png PNG p.pdf
check convert:txt "text" n.pdf
grep -q "Bonjour" n.txt 2>/dev/null && { echo "ok   contenu du PDF retrouvé dans le .txt"; pass=$((pass+1)); } || { echo "FAIL texte du PDF absent du .txt"; fail=$((fail+1)); }
mkdir box && echo hello > box/f.txt
check convert:zip "Zip" box; check convert:tar.gz "gzip" box
check convert:extract dir box.zip
check tool:compress "JPEG" p.jpg; check tool:resize50 PNG p.png; check tool:strip "ISO Media" a.mp4
check tool:mute "ISO Media" a.mp4; check tool:compress "ISO Media" a.mp4
check tool:imagesToPDF PDF p.png p.jpg; check tool:mergePDF PDF p.pdf p.pdf
# --- v0.2 : nouveaux outils/conversions sans paramètre (format + contenu vérifiés) ---
dim() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/{printf "%s ", $2}'; }
vinfo() { $FF -i "$1" 2>&1 | grep -E "$2" | head -1; }
dur() { $FF -i "$1" 2>&1 | sed -n 's/.*Duration: 00:00:\([0-9.]*\),.*/\1/p' | head -1; }
assert() { # assert <libellé> <condition shell>
  if eval "$2"; then echo "ok   $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi
}
check tool:rotate90 PNG p.png; assert "rotate90 : 800x600 -> 600x800" '[ "$(dim "$LAST")" = "600 800 " ]'
check tool:rotate90 JPEG p.jpg
check tool:gray "grayscale" p.png
check tool:gray "JPEG" p.jpg; assert "gray jpg : 1 seule composante" 'file -b "$LAST" | grep -q "components 1"'
$FF -loglevel error -f lavfi -i testsrc=duration=2:size=1920x1080:rate=24 -f lavfi -i sine=frequency=440:duration=2 -c:v libx264 -pix_fmt yuv420p -c:a aac big.mp4
check tool:video720 "ISO Media" big.mp4; assert "video720 : 1080p -> 720p" 'vinfo "$LAST" Video: | grep -q "1280x720"'
check tool:video720 "ISO Media" a.mp4; assert "video720 : 360p non agrandi" 'vinfo "$LAST" Video: | grep -q "640x360"'
check tool:speed2 "ISO Media" a.mp4; assert "speed2 : durée ~2 s -> ~1 s" '[ "$(echo "$(dur "$LAST") < 1.3" | bc)" = 1 ]'
$FF -loglevel error -f lavfi -i testsrc=duration=2:size=320x240:rate=24 -c:v libx264 -pix_fmt yuv420p mute-only.mp4
check tool:speed2 "ISO Media" mute-only.mp4
$FF -loglevel error -filter_complex "anullsrc=r=44100:cl=mono:d=1[a];sine=frequency=440:duration=2:sample_rate=44100,volume=-30dB[b];anullsrc=r=44100:cl=mono:d=1[c];[a][b][c]concat=n=3:v=0:a=1" gap.wav
check tool:normalize "WAVE|RIFF" gap.wav
assert "normalize : crête -48 dB -> > -20 dB" '[ "$($FF -i "$LAST" -af volumedetect -f null - 2>&1 | sed -n "s/.*max_volume: \(-*[0-9.]*\) dB.*/\1/p" | head -1 | cut -d. -f1)" -gt -20 ]'
check tool:normalize "MPEG|Audio|ID3" s.mp3
check tool:trimSilence "WAVE|RIFF" gap.wav; assert "trimSilence : 4 s -> ~2 s" '[ "$(echo "$(dur "$LAST") < 2.3 && $(dur "$LAST") > 1.7" | bc)" = 1 ]'
# firstPage : un PDF de 2 pages doit donner un PDF d'1 page (vérifié avec PDFKit via convert:png : 1 page = 1 fichier, N pages = dossier)
$FF -loglevel error -f lavfi -i testsrc=size=640x480 -frames:v 1 p2.png
"$M" --run tool:imagesToPDF p.png p2.png >/dev/null 2>&1; cp p.pdf deux.pdf
mkdir -p mp && cp p.png mp/a.png && cp p2.png mp/b.png && "$M" --run tool:imagesToPDF mp/a.png mp/b.png >/dev/null 2>&1 && cp mp/a.pdf deux.pdf
assert "deux.pdf : 2 pages (convert:png -> dossier)" '[ -d "$("$M" --run convert:png deux.pdf | tail -1)" ]'
check tool:firstPage PDF deux.pdf
assert "firstPage : résultat = 1 seule page (convert:png -> fichier)" '[ -f "$("$M" --run convert:png "$LAST" | tail -1)" ]'
check tool:firstPage PDF p.pdf
if [ -x /opt/homebrew/bin/gs ]; then
  $FF -loglevel error -f lavfi -i testsrc2=size=3000x2000 -frames:v 1 big.png
  sips -s format pdf big.png --out bigimg.pdf >/dev/null 2>&1
  check tool:compressPDF PDF bigimg.pdf; assert "compressPDF : plus petit que l'original" '[ $(stat -f%z "$LAST") -lt $(stat -f%z bigimg.pdf) ]'
fi
printf '1\n00:00:01,000 --> 00:00:02,500\nBonjour\n\n2\n00:00:03,000 --> 00:00:04,000\nMonde\n' > s.srt
check convert:vtt "text" s.srt; assert "srt->vtt : en-tête WEBVTT + texte" 'head -1 "$LAST" | grep -q WEBVTT && grep -q Bonjour "$LAST"'
cp "$LAST" s2.vtt; check convert:srt "text" s2.vtt; assert "vtt->srt : texte et minutage retrouvés" 'grep -q "00:00:01,000 --> 00:00:02,500" "$LAST" && grep -q Monde "$LAST"'
printf 'nom,ville,note\n"Dupont, Jean",Paris,"dit ""bonjour"""\nMarie,Lyon,ok\n' > d.csv
check convert:tsv "text" d.csv; assert "csv->tsv : champ à virgule gardé, 3 colonnes" 'grep -q "^Dupont, Jean	Paris	dit \"bonjour\"$" "$LAST" && [ "$(awk -F"\t" "{print NF}" "$LAST" | sort -u)" = 3 ]'
cp "$LAST" t.tsv; check convert:csv "text" t.tsv; assert "tsv->csv : retour à l'identique" 'cmp -s "$LAST" d.csv'
# --list : les nouveaux ids n'apparaissent que pour les bons types
assert "--list tools png contient rotate90 et gray, pas speed2" '"$M" --list tools p.png | grep -q tool:rotate90 && "$M" --list tools p.png | grep -q tool:gray && ! "$M" --list tools p.png | grep -q tool:speed2'
assert "--list tools mp4 contient video720 et speed2, pas rotate90" '"$M" --list tools a.mp4 | grep -q tool:video720 && "$M" --list tools a.mp4 | grep -q tool:speed2 && ! "$M" --list tools a.mp4 | grep -q tool:rotate90'
assert "--list tools wav : normalize+trimSilence" '"$M" --list tools s.wav | grep -q tool:normalize && "$M" --list tools s.wav | grep -q tool:trimSilence'
assert "--list tools pdf : firstPage" '"$M" --list tools p.pdf | grep -q tool:firstPage'
assert "--list convert srt/csv" '"$M" --list convert s.srt | grep -q convert:vtt && "$M" --list convert d.csv | grep -q convert:tsv'
# --- v0.5 : nouveaux outils (format + contenu vérifiés) ---
check tool:cropSquare PNG p.png; assert "cropSquare image : 800x600 -> 600x600" '[ "$(dim "$LAST")" = "600 600 " ]'
check tool:cropSquare "ISO Media" a.mp4; assert "cropSquare vidéo : 640x360 -> 360x360" 'vinfo "$LAST" Video: | grep -q "360x360"'
check tool:background PNG p.png; assert "background : image plus grande que l'original (marges)" '[ "$(dim "$LAST" | cut -d" " -f1)" -gt 800 ]'
check tool:collage PNG p.png p2.png; assert "collage : une seule image PNG de sortie" '[ -f "$LAST" ] && [ "$(dim "$LAST" | cut -d" " -f1)" -gt 800 ]'
check tool:slow "ISO Media" a.mp4; assert "slow : durée ~2 s -> ~4 s" '[ "$(echo "$(dur "$LAST") > 3.6 && $(dur "$LAST") < 4.5" | bc)" = 1 ]'
check tool:slow "ISO Media" mute-only.mp4
cp a.mp4 b.mp4; check tool:joinVideos "ISO Media" a.mp4 b.mp4; assert "joinVideos : durée ~4 s (2 clips de 2 s)" '[ "$(echo "$(dur "$LAST") > 3.7 && $(dur "$LAST") < 4.4" | bc)" = 1 ]'
check tool:videoFrame PNG a.mp4
check tool:splitVideo dir a.mp4; assert "splitVideo : 2 parties de ~1 s" '[ "$(ls "$LAST" | wc -l | tr -d " ")" = 2 ] && [ "$(echo "$(dur "$LAST/partie-1.mp4") > 0.8 && $(dur "$LAST/partie-1.mp4") < 1.3" | bc)" = 1 ]'
check tool:mono "WAVE|RIFF" s.wav; assert "mono : 1 canal" 'vinfo "$LAST" Audio: | grep -q mono'
check tool:visualizer "ISO Media" s.wav; assert "visualizer : vidéo 1280x720" 'vinfo "$LAST" Video: | grep -q "1280x720"'
check tool:splitPDF dir deux.pdf; assert "splitPDF : 2 fichiers PDF" '[ "$(ls "$LAST" | wc -l | tr -d " ")" = 2 ]'
check tool:rotatePDF PDF deux.pdf
assert "rotatePDF : la page tourne de 90°" 'cd "$T" && cat > rot.swift <<EOS
import PDFKit
let d = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
print(d.page(at: 0)!.rotation)
EOS
[ "$(swift rot.swift "$LAST" 2>/dev/null)" = 90 ]'
assert "--list actions contient Flotter" '"$M" --list actions p.png | grep -q act:float'
assert "--list tools png : collage seulement avec 2+ images" '! "$M" --list tools p.png | grep -q tool:collage && "$M" --list tools p.png p2.png | grep -q tool:collage'
assert "--list tools mp4 : joinVideos seulement avec 2+ vidéos" '! "$M" --list tools a.mp4 | grep -q tool:joinVideos && "$M" --list tools a.mp4 b.mp4 | grep -q tool:joinVideos'
check convert:bmp "PC bitmap" p.png
check convert:avi "AVI" a.mp4; assert "avi : vidéo 640x360 relue par ffmpeg" 'vinfo "$LAST" Video: | grep -q "640x360"'
check convert:wmv "ASF" a.mp4; assert "wmv : durée ~2 s" '[ "$(echo "$(dur "$LAST") > 1.7 && $(dur "$LAST") < 2.4" | bc)" = 1 ]'
check convert:wma "ASF" s.wav; assert "wma : durée ~2 s" '[ "$(echo "$(dur "$LAST") > 1.7 && $(dur "$LAST") < 2.4" | bc)" = 1 ]'
$FF -loglevel error -f lavfi -i "color=c=white:s=900x400,drawtext=fontfile=/System/Library/Fonts/Helvetica.ttc:text=CONFIDENTIEL:fontsize=80:x=40:y=80:fontcolor=black" -frames:v 1 txt.png
$FF -loglevel error -f lavfi -i color=c=white:s=300x200 -frames:v 1 blank.png
check tool:redact PNG txt.png; assert "redact : le texte est modifié (sortie différente de l'original)" '! cmp -s "$LAST" txt.png'
assert "redact : zone sans texte intacte (coin bas-droit identique)" '[ "$($FF -loglevel error -i "$LAST" -vf crop=100:100:800:300,format=rgb24 -f md5 - )" = "$($FF -loglevel error -i txt.png -vf crop=100:100:800:300,format=rgb24 -f md5 - )" ]'
assert "redact : image sans visage ni texte refusée" '! "$M" --run tool:redact blank.png >/dev/null 2>&1'
# --- mise à jour depuis l'app : faux serveur local (jamais GitHub), dmg de test en version 99.0
SRV=$T/srv; mkdir -p $SRV $T/inst
mkfix() {  # mkfix <dossier-app-source> <nom.dmg> <version> <bundle-id>
  local d=$(mktemp -d "$T/fix.XXXXXX"); cp -R "$ROOT/build/Mandarine.app" $d/
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $3" -c "Set :CFBundleIdentifier $4" $d/Mandarine.app/Contents/Info.plist
  codesign --force --deep -s - $d/Mandarine.app >/dev/null 2>&1
  hdiutil create -quiet -volname Mandarine -srcfolder $d -format UDZO -ov "$SRV/$2" && rm -rf $d
}
mkjson() {  # mkjson <fichier.json> <tag> <dmg|""> <sha|""> : release factice au format GitHub
  python3 -I -c 'import sys,json;f,tag,dmg,sha,port=sys.argv[1:6];a=[{"name":dmg,"browser_download_url":"http://127.0.0.1:%s/%s"%(port,dmg)}] if dmg else [];open(f,"w").write(json.dumps({"tag_name":tag,"body":"Nouveautés de test"+((chr(10)+"SHA-256: "+sha) if sha else ""),"assets":a}))' "$SRV/$1" "$2" "$3" "$4" "$PORT"
}
PORT=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
mkfix x Mandarine-99.0.dmg 99.0 fr.julian.mandarine
mkfix x Mandarine-bad.dmg 99.0 evil.app
GOOD=$(shasum -a 256 $SRV/Mandarine-99.0.dmg | cut -d" " -f1); BADID=$(shasum -a 256 $SRV/Mandarine-bad.dmg | cut -d" " -f1)
mkjson ok.json v99.0 Mandarine-99.0.dmg $GOOD
mkjson badsha.json v99.0 Mandarine-99.0.dmg 0000000000000000000000000000000000000000000000000000000000000000
mkjson nosha.json v99.0 Mandarine-99.0.dmg ""
mkjson badid.json v99.0 Mandarine-bad.dmg $BADID
mkjson nodmg.json v99.0 "" ""
mkjson old.json v0.0.1 Mandarine-99.0.dmg $GOOD
mkjson ten.json v0.10.0 Mandarine-99.0.dmg $GOOD
python3 -I -m http.server $PORT --bind 127.0.0.1 --directory $SRV >/dev/null 2>&1 &
SRVPID=$!; sleep 1
U=http://127.0.0.1:$PORT
newapp() { rm -rf $T/inst/Mandarine.app; cp -R "$ROOT/build/Mandarine.app" $T/inst/; }
iv() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $T/inst/Mandarine.app/Contents/Info.plist; }
assert "maj : version plus récente détectée" '[ "$("$M" --check-update $U/ok.json)" = "nouvelle version 99.0" ]'
assert "maj : version plus ancienne = à jour" '"$M" --check-update $U/old.json | grep -q "^à jour"'
assert "maj : 0.10.0 est plus récent que la version actuelle (comparaison numérique)" '[ "$("$M" --check-update $U/ten.json)" = "nouvelle version 0.10.0" ]'
assert "maj : serveur injoignable = erreur propre" '! "$M" --check-update http://127.0.0.1:1/x.json >/dev/null 2>&1'
newapp; V0=$(iv)
assert "maj : empreinte fausse refusée, app intacte" '! "$M" --self-update $U/badsha.json $T/inst/Mandarine.app >/dev/null 2>&1 && [ "$(iv)" = "$V0" ]'
assert "maj : empreinte absente refusée, app intacte" '! "$M" --self-update $U/nosha.json $T/inst/Mandarine.app >/dev/null 2>&1 && [ "$(iv)" = "$V0" ]'
assert "maj : .dmg d'une autre app refusé, app intacte" '! "$M" --self-update $U/badid.json $T/inst/Mandarine.app >/dev/null 2>&1 && [ "$(iv)" = "$V0" ]'
assert "maj : release sans .dmg refusée" '! "$M" --self-update $U/nodmg.json $T/inst/Mandarine.app >/dev/null 2>&1 && [ "$(iv)" = "$V0" ]'
assert "maj : version déjà installée ou plus ancienne refusée" '! "$M" --self-update $U/old.json $T/inst/Mandarine.app >/dev/null 2>&1 && [ "$(iv)" = "$V0" ]'
assert "maj : installation réussie (version 99.0)" '"$M" --self-update $U/ok.json $T/inst/Mandarine.app | grep -q "installée 99.0" && [ "$(iv)" = "99.0" ]'
assert "maj : app installée valide (signature + démarre)" 'codesign --verify --deep --strict $T/inst/Mandarine.app && $T/inst/Mandarine.app/Contents/MacOS/Mandarine --list tools p.png | grep -q tool:rotate90'
assert "maj : aucun fichier temporaire laissé à côté de l'app" '[ -z "$(ls -A $T/inst | grep -v "^Mandarine.app$")" ]'
assert "maj : plus de volume monté" '! hdiutil info | grep -q mandarine-update'
assert "maj : deuxième passage = déjà à jour" '! "$M" --self-update $U/ok.json $T/inst/Mandarine.app >/dev/null 2>&1'
kill $SRVPID 2>/dev/null; SRVPID=
# capture d'écran -> presse-papiers (aucun fichier créé ; le contenu visuel n'est pas contrôlé : écran possiblement verrouillé)
DESK=$(ls ~/Desktop | wc -l); printf 'avant' | pbcopy
assert "capture : une image PNG arrive dans le presse-papiers" '"$M" --capture screen | grep -q "^ok" && osascript -e "clipboard info" 2>/dev/null | grep -q PNGf'
assert "capture : aucun fichier créé sur le bureau" '[ "$(ls ~/Desktop | wc -l)" = "$DESK" ]'
# cas d'erreur : un type de fichier inconnu doit échouer proprement (code ≠ 0), pas planter
echo x > z.xyz; if "$M" --run convert:png z.xyz >/dev/null 2>&1; then echo "FAIL fichier inconnu accepté"; fail=$((fail+1)); else echo "ok   fichier inconnu refusé"; pass=$((pass+1)); fi
echo; echo "résultat: $pass ok, $fail échec(s)"
[ $fail -eq 0 ]
