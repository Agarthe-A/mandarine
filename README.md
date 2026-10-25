# Mandarine 🍊

Convertisseur de fichiers pour Mac, hors ligne. Glisse un fichier, tape une touche, dépose-le sur la roue. Inspiré de [Tangerine](https://tangerineformac.com), sans lien avec ses auteurs.

| Touche pendant le glisser | Roue |
| --- | --- |
| ⇧ Maj | Convertir (286 conversions : images, vidéo, audio, documents, PDF, sous-titres, tableaux, archives) |
| ⌘ Cmd | Outils (26 : compresser, recadrer, flouter visages et texte, collage, assembler des vidéos, onde audio, pages PDF…) |
| ⌃ Ctrl | Actions (AirDrop, flotter, copier, copier le chemin, déplacer, Terminal) |
| Échap | Annuler |

Capture d'écran dans le presse-papiers, sans fichier sur le Bureau : ⌃⇧4 (zone), ⌃⇧3 (écran).

## Installer
Télécharge le `.dmg` dans les [releases](https://github.com/Agarthe-A/mandarine/releases/latest), glisse Mandarine dans Applications. Mac Apple Silicon, macOS 13 ou plus. L'app n'est pas notarisée : premier lancement par clic droit, Ouvrir (ou `xattr -cr /Applications/Mandarine.app`). Les mises à jour se font ensuite depuis le menu de la barre.

## Compiler
Swift 5.9+, macOS 13+. `./build.sh` produit `build/Mandarine.app` (variables `VERSION`, `BUILD`, `FFMPEG=/chemin/vers/ffmpeg` pour l'embarquer). L'icône est dessinée par l'app elle-même (`--icon`).

## Vérifier
`./verify.sh` génère de vrais fichiers, lance chaque conversion et chaque outil en ligne de commande, puis contrôle le format et le contenu de la sortie, y compris la mise à jour (faux serveur local). Code de sortie 0 = tout passe.

```
Mandarine --list convert|tools|actions <fichiers>   ce que propose la roue
Mandarine --run convert:png <fichiers>              lance une conversion
Mandarine --run tool:compress <fichiers>            lance un outil
Mandarine --render tools out.png <fichiers>         dessine la roue hors écran (HOVER=n, SCALE=n)
Mandarine --catalog                                 catalogue réel en JSON (alimente le site)
```

## Ajouter un outil
Une entrée dans `Tools.all` (`Sources/Tools.swift`), son code dans `Sources/ToolsMedia.swift`, un pictogramme dans `Sources/Icons.swift`, un test dans `verify.sh`. Un nouveau type de fichier : un `Converter` dans `Sources/Converters.swift`.

## Site
`tools/build_site.py <Mandarine.app> <version>` assemble `site/index.html` à partir du catalogue de l'app : le site ne peut pas annoncer ce que l'app ne fait pas. `tools/make_video.py` rend la vidéo de présentation avec les roues dessinées par l'app.

## Licence
FFmpeg (GPL v3) est embarqué dans le `.dmg`.
