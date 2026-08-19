# tools/

Outillage de développement : ce qui aide à construire Arch Colony sans faire partie
d'Arch Colony.

Rien de ce qui vit ici n'est livré à un utilisateur. Ce qui est livré est un paquet, dans
[`../packages/`](../packages/README.md).

## Prévu

- **Vérification de la règle d'or.** Un script qui compare les noms de `packages/` aux bases
  de données de `[core]`, `[extra]` et `[multilib]` et échoue en cas de collision. C'est
  [ADR-0002](../docs/decisions/0002-regle-de-non-recouvrement.md) rendue exécutable plutôt
  que laissée à la vigilance — à écrire tôt, l'intérêt d'une règle est qu'elle s'applique
  quand personne ne regarde.
- **Tests en VM.** Démarrage d'un ISO en QEMU, installation sans interaction, assertions sur
  l'état du système obtenu. Porte de sortie de release à partir de
  [J2](../docs/feuille-de-route.md#j2--installable-sur-disque).
