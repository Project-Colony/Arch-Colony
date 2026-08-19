# ADR-0005 — Deux éditions : Hyprland et KDE Plasma

**Statut** : acceptée — 2026-08-19

## Contexte

L'écosystème Colony possède déjà `hyprland-colony` : une configuration Hyprland complète avec
son script d'installation. C'est l'identité visuelle naturelle du projet. Mais Hyprland
suppose un utilisateur à l'aise avec un gestionnaire de fenêtres en mosaïque configuré par
fichier, ce qui restreint fortement le public.

## Décision

Deux éditions, produisant deux ISO depuis des profils `archiso` partageant tout ce qui peut
l'être :

- **Hyprland** — l'édition d'identité, dérivée de `hyprland-colony`.
- **KDE Plasma** — l'édition complète, thémable proprement via Qt.

Les deux installent le même `colony-base` et se distinguent uniquement par leur méta-paquet
de bureau.

## Conséquences

Le pipeline de thème doit viser deux cibles au lieu d'une : les fragments de configuration
Hyprland/waybar d'un côté, les thèmes Qt/Plasma de l'autre. Conformément au
[principe 4](../principes.md#4-une-couleur-ne-sécrit-quune-fois), les deux sont des sorties
du générateur de `Project-Colony-Resources`, pas des fichiers écrits à la main.

Le coût réel n'est pas la construction des deux ISO — c'est le test des deux. Toute
fonctionnalité système touchant la session doit être validée deux fois.

`hyprland-colony` devient `colony-desktop-hyprland`, un paquet, conformément à
[ADR-0007](0007-configuration-en-paquets.md). Le dépôt d'origine reste utilisable hors
d'Arch Colony ; seul l'empaquetage change.

## Alternatives écartées

- **Hyprland seul** — l'option la plus économique, écartée parce qu'elle réduit la
  distribution à un public déjà capable de se la construire.
- **Plasma seul** — n'exploite pas le travail existant et efface l'identité visuelle.
- **GNOME** — le plus difficile à thémer proprement et le plus éloigné des conventions de
  l'écosystème.
