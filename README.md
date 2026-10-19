# Mandarine 🍊
Clone perso de Tangerine (tangerineformac.com) : glisse un fichier, tape une touche, dépose sur la roue.
- ⇧ Maj → convertir · ⌘ Cmd → outils · ⌃ Ctrl → actions (copier chemin, copier, AirDrop, déplacer, Terminal) · Échap annule
- Build : `./build.sh` → `build/Mandarine.app` (ffmpeg embarqué, signature ad-hoc, icône 🍊 dans la barre de menus)
- CLI de test : `Mandarine --list convert|tools|actions <fichiers>` · `Mandarine --run convert:png <fichiers>`
- Moteur : sips, ffmpeg, PDFKit, Core Text, textutil, pandoc (md/epub), ditto/tar
## État (2026-10-17)
- Conversions testées en CLI : image (jpg/png/webp/heic/tiff/avif/gif/pdf), vidéo (mp4/mov/mkv/webm/gif/mp3), audio (mp3/m4a/wav/flac/opus/aiff), docs (docx/pdf/html/md/epub/txt/rtf), PDF→png/jpg/txt, zip/extraction, outils (compresser, réduire, sans métadonnées, couper le son, images→PDF, fusion PDF)
- Roue : rendu hors écran vérifié (`--render`), hit-test des tranches OK (7 et 4 tranches)
- NON testé : détection réelle du glisser + touches ⇧⌘⌃ + dépôt — l'écran du Mac mini est verrouillé (capture noire), à tester par Julian
- Manque vs Tangerine : rogner/annoter/éditer photo, trim/split vidéo, flou visages, PDF→docx/pptx/xlsx, slides, tableurs, sous-titres, RAR
## Page vitrine (2026-10-19)
`site/index.html` : une seule page autonome (HTML/CSS/JS, aucune dépendance), à ouvrir directement dans un navigateur. Roue interactive (⇧ ⌘ ⌃ + type de fichier) dont les listes viennent de `Mandarine --list`. Vérifiée : bureau 1400 px et mobile 390 px, sans débordement. Pas encore publiée ; pas de téléchargement du .app (signature ad-hoc, build local).

## Compiler
Prérequis : macOS 13+, Swift 5.9+. `./build.sh` embarque un `ffmpeg` si tu en as un (variable `FFMPEG=/chemin/vers/ffmpeg`, sinon l'app utilise celui du système s'il existe). Le binaire ffmpeg n'est pas distribué dans ce dépôt.
Premier lancement : clic droit → Ouvrir (signature ad-hoc).

## Page vitrine
`site/index.html` (+ `presentation.mp4`). Vidéo générée par `tools/make_video.py` ; `tools/serve.py` sert la page avec les requêtes Range que Safari exige pour lire une vidéo.
