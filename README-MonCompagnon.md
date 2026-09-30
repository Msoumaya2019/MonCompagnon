# MonCompagnon

Application iOS d'apprentissage du Coran, construite sur **QuranEngine** —
la bibliothèque open source (Apache 2.0) qui alimente l'application Quran.com.

Ce dépôt est un fork de [`quran/quran-ios`](https://github.com/quran/quran-ios).

---

## Ce que contient ce dépôt

| Élément | Valeur |
|---|---|
| Nom affiché | **MonCompagnon** |
| Bundle identifier | `com.moncompagnon.quran` |
| Projet Xcode | `Example/QuranEngineApp.xcodeproj` |
| Scheme | `QuranEngineApp` |
| Compilation | non signée (`CODE_SIGNING_REQUIRED=NO`) |
| Flux de publication | `.github/workflows/unsigned-ipa.yml` |

L'`Info.plist` ne porte plus aucune référence à l'identité de l'auteur d'origine.
Les chaînes internes `com.quran.*` qui subsistent dans le code sont des **clés de
préférences** et des **libellés de file d'attente** : elles ne sont pas visibles
par l'utilisateur, et les changer casserait la reprise des réglages d'une
installation existante.

---

## Obtenir l'IPA non signé

1. Poussez sur `main` (ou lancez le flux manuellement depuis l'onglet **Actions**).
2. Le flux `Unsigned IPA` construit l'archive et la publie en artefact
   **`MonCompagnon-unsigned-ipa`**.
3. Téléchargez et décompressez l'artefact : vous obtenez `MonCompagnon-unsigned.ipa`.
4. **Signez-le avec eSign** et installez-le sur l'appareil.

Aucun certificat Apple, aucun compte développeur et aucun secret ne sont
nécessaires côté GitHub : la compilation se fait entièrement en non signé.

### En local (sur un Mac)

```bash
make unsigned-ipa
# -> .build/DerivedData/no-sync/unsigned-ipa/MonCompagnon-unsigned.ipa
```

Prérequis : Xcode 26 (le projet utilise le format d'icône `.icon`), et `xcbeautify`
(`brew install xcbeautify`).

---

## Notes techniques

- La cible `unsigned-ipa` du `Makefile` archive avec
  `CODE_SIGNING_ALLOWED=NO`, puis reconstruit l'IPA à la main
  (`Payload/*.app` rezippé). C'est la méthode fiable pour produire un IPA
  réellement non signé : un simple `xcodebuild build` ne produit pas d'IPA.
- Les zones sûres (Dynamic Island, encoche, barre d'accueil) sont lues **au moment
  de l'exécution** via `UIWindowScene` ; aucune adaptation de cible n'est requise
  pour l'iPhone 17 Pro Max.
- Le flux vérifie après coup que le paquet **n'est pas signé** et qu'aucun
  profil de provisionnement n'est embarqué, afin qu'un échec de signature ne
  passe pas inaperçu.

---

## Licence et attribution

Le code d'origine est publié sous **Apache License 2.0** (voir `LICENSE`), ce qui
autorise la modification et la redistribution. En contrepartie, le fichier
`LICENSE` doit être conservé et les modifications signalées.

Point d'attention en cas de **publication sur l'App Store** : le nom « Quran »
et l'icône de Quran.com sont des marques de leurs détenteurs. L'application publiée
doit porter votre propre nom, votre propre bundle identifier et votre propre icône —
c'est déjà le cas ici pour le nom et le bundle identifier.
