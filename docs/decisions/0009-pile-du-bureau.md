# ADR-0009 — Pile du bureau : ce qu'on réutilise, ce qu'on écrit

**Statut** : acceptée — 2026-08-20

## Contexte

La question « faut-il faire un environnement de bureau Colony ? » cache des coûts qui
varient d'un facteur cent selon où l'on place la frontière. Un compositeur Wayland écrit
depuis zéro — entrées, multi-écran, HiDPI, échelle fractionnaire, VRR, capture d'écran,
XWayland, verrouillage de session, puis la traîne des bugs matériels — représente des
années de travail, et c'est là que meurent les projets de bureau.

Le reste se réutilise, et deux des composants qui mériteraient d'être écrits tombent
exactement dans ce que l'écosystème Colony sait déjà faire : une application `iced` et un
système d'identité visuelle déjà généré depuis des tokens.

## Décision

On n'écrit **rien** de ce qui existe et fonctionne. La pile de l'édition Hyprland :

| Couche | Choix | Nature |
|---|---|---|
| Protocole | Wayland | amont |
| Compositeur | `hyprland` | amont, jamais forké |
| Shell | `noctalia` (transitoire) | amont, archivé dans l'organisation |
| Portails | `xdg-desktop-portal` + `-hyprland` + `-gtk` | amont, **les deux dorsales requises** |
| Agent polkit | `hyprpolkitagent` (édition Hyprland), `polkit-kde-agent` (édition Plasma) | amont |
| Session | `systemd-logind` | amont |
| Greeter | `sddm` | amont |
| Thème | `stellar_blade` / `lily` | Project-Colony-Resources |
| Réglages | reporté | à écrire plus tard |

## Sur les portails, parce que c'est contre-intuitif

`xdg-desktop-portal` **n'est pas un composant Wayland**. C'est une interface D-Bus par
laquelle une application confinée demande au bureau ce qu'elle ne peut pas prendre
elle-même : sélecteur de fichiers, capture d'écran, partage d'écran, ouverture d'URL. Elle
fonctionne aussi sous X11.

Elle compte davantage sous Wayland parce que la capture d'écran **doit** passer par elle —
il n'existe pas d'équivalent au « on lit le framebuffer » de X11.

Conséquence d'empaquetage, et c'est le piège : le portail générique ne fait rien seul, il
délègue à une **dorsale**. Il en faut deux, et pour des raisons différentes :

- `xdg-desktop-portal-hyprland` — capture et partage d'écran
- `xdg-desktop-portal-gtk` — sélecteur de fichiers, que la dorsale Hyprland n'implémente pas

Oublier la seconde donne un système où enregistrer un fichier depuis une application
confinée échoue sans message clair. Oublier la première casse le partage d'écran dans
SphereCord. Les deux sont des pannes silencieuses, donc les deux sont des dépendances
explicites du méta-paquet d'édition, jamais des dépendances optionnelles.

## Conséquences

Le bureau de l'édition Hyprland est presque entièrement composé de paquets d'Arch, assemblés
par un méta-paquet. Ce qui reste à nous : la configuration, le thème, et plus tard
Colony Shell puis l'application de réglages.

**Noctalia est explicitement transitoire.** Il est adopté parce qu'il fonctionne, pas parce
qu'il est définitif — voir le point ouvert de [ADR-0005](0005-deux-editions.md). La
conséquence pratique reste la même : la configuration de session doit être un paquet
séparable, pour que le remplacer soit un changement de dépendance et non une refonte.

**Arch Colony ne doit jamais dépendre de Colony Shell pour exister.** Lier les deux donne
une distribution qui attend un shell, et un shell bâclé pour tenir une date d'ISO. Dépôt
séparé, calendrier séparé.

## Alternatives écartées

- **Écrire un compositeur** — des années, pour reproduire ce que Hyprland fait déjà.
- **Environnement de bureau complet** (gestionnaire de fichiers, centre de contrôle, suite
  d'applications) — engagement pluriannuel de maintenance contre un écosystème Wayland
  mouvant. Le mot compte : « Colony Shell » promet une barre et une identité, « Colony
  Desktop Environment » promet dix ans d'entretien.
