---
theme: ../theme
title: "Concevoir une machine : du code au monde physique"
author: Lucas Sifoni
favicon: /favicon.png
lang: fr
layout: cover
ribbon: Espace Brut
transition: fade
drawings:
  persist: false
duration: 35min
---

# Concevoir une interface 

Lucas Sifoni / Turing-Express · Espace Brut

---

<a href="mailto:contact@turing-express.fr">contact@turing-express.fr</a>

Code complet disponible le 25 octobre : <a href="https://github.com/lucassifoni">github.com/lucassifoni</a>

Site perso (articles, confs) -> <a href="https://lucassifoni.info">lucassifoni.info</a>  
Développement indépendant -> <a href="https://turing-express.fr">turing-express.fr</a>  
Logiciel pour acteurs de l'archi/bâtiment -> <a href="https://alzo.fr">alzo.fr</a>  
Métrologie optique -> <a href="https://chantepierre-optique.fr">chantepierre-optique.fr</a>  

---

# Fabrication matérielle

- 4 modules indépendants
- pas de PCB
- fabriquer soi-même
- impression 3D, découpe laser, composants DIP / TH et padboards
- old-school

---
layout: media
media: layout.png
fit: contain
---
4 modules indépendants
---
layout: media
media: img_4636.webp # 2026-06-25 14:49
---

---
layout: media
media: [img_4665.webp, img_4705-2.webp]
---

---
layout: media
media: [img_4708-3.webp, img_4710-2.webp]
---

---
layout: media
media: 80521696533__eea69c11-4f02-48f9-a037-d8e562667329.mp4 # 2026-07-08 15:22
fit: contain
---

---
layout: media
media: [img_4772.webp, img_4776.mp4]
---

---
layout: media
media: img_4779.webp # 2026-07-08 16:30
---

---
layout: media
fit: contain
media: img_4939.webp # 2026-07-20 08:17
---

---
layout: media
media: [img_4942.mp4, img_4949.mp4]
---

---
layout: media
media: img_4951.mp4 # 2026-07-20 14:29
---

---
layout: media
fit: contain
media: img_4952.mp4 # 2026-07-20 15:26
---

---
layout: media
media: 80639797136__8bbbed41-be2f-43d6-be83-b257483236ec.mp4 # 2026-07-22 07:26
---

---
layout: media
media: img_4971.webp # 2026-07-22 11:42
---

---
layout: media
media: [img_4988.webp, img_4996.mp4]
---

---
layout: media
media: img_5003.webp # 2026-07-24 12:45
---

---
layout: media
media: img_5012-2.webp # 2026-07-24 13:33
---

---
layout: media
media: img_5065-2.mp4 # 2026-07-27 14:03
---

---
layout: media
media: [img_5067-2.webp, img_5089.webp]
---

---
layout: media
fit: contain
media: img_5138.webp # 2026-07-31 12:00
---

---
layout: media
media: img_5233.webp # 2026-08-07 10:24
---

---
layout: media
media: [img_5404.webp, img_5411.webp]
---

---
layout: media
media: [img_5416-2.webp, img_5417-2.webp, img_5418.webp]
---

---
layout: media
media: img_5518-2.mp4 # 2026-09-06 13:11
---

---
layout: media
media: img_5519-2.mp4
---

---
layout: media
media: [img_5610.webp, img_5566.webp, img_5568.webp] 
---

---
layout: media
media: img_5633.webp # 2026-09-15 09:45
---

---
layout: media
media: img_5638.webp # 2026-09-16 09:47
---

---
layout: media
media: img_5641.webp # 2026-09-16 10:35
---

---
layout: media
media: img_5645.webp # 2026-09-16 13:31
---

---
layout: media
fit: contain
media: img_5661.webp # 2026-09-17 15:46
---

---
layout: media
fit: contain
media: img_5734.webp # 2026-09-21 14:21
---

---

# Où placer la complexité ? 

---
layout: media
fit: contain
media: img_5752.jpeg
filter: brightness(2) contrast(2)
---

---
layout: media
fit: contain
media: img_5754.jpeg
filter: brightness(2) contrast(2)
---

---

## Du matériel sans connaissance du logiciel
- Une matrice de boutons ne sait pas à quoi elle sert
- Un contrôleur de LED ne sait pas à quoi il réagit
- Se contenter d'être une entrée (ex: un bouton) ou une sortie (ex: une LED)

---

## Du logiciel sans connaissance de l'installation
### Parti-pris :
- Décrire chaque sorte d'élément physique :
  - Qu'est-ce qu'un bouton ?
  - Qu'est-ce qu'un joystick ?
  - Qu'est-ce qu'une jauge ?
- Ne pas décrire d'actions :
  - ~~"Si je pousse le joystick de taille de texte vers la droite, la taille du texte augmente"~~
  - ~~"Si je fais tourner la trackball, un mot aléatoire remplace le texte"~~
- Du code pur et donc déterministe
- Repousser les effets au bord de l'installation
- L'installation complète est décrite par les données et non par du code

---

## Du logiciel sans connaissance de l'installation
### Conséquences :
- Changer un module est simple
- Changer un comportement est simple
- La manière dont les instructions arrivent à l'installation n'a pas d'importance
- Les effets de bord sont contenus

---

## La simulation comme outil de conception
- Simuler le matériel aide à le comprendre et à le réaliser
- Le réaliser aide à affiner la simulation




### ∞ cycle vertueux

---
layout: media
fit: contain
media: sim0.png
---

---
layout: media
fit: contain
media: sim1.png
---

---
layout: media
fit: contain
media: sim2.png
---

---
layout: media
fit: contain
media: sim3.png
---

---

Petit tour dans le simulateur

---

## Points clés du système

`Composant` = `type` (état, réglages) + `instance` (adresse, traduit événements, transmet au coeur)  
Virtuel + physique = une seule instance partagée  
Instancier des composants = faire le pont entre logique et adressage physique

---

## Fonction de transition / réduction

ancien état + événement = nouvel état + instructions

---

## Quand j'appuie sur "texte à gauche", il se passe quoi ?

- J'appuie sur la touche *ou bien* sur sa contrepartie numérique.
- Un événement `bouton_2 appuyé` arrive dans le système.
- Il parvient à un composant appelé `bouton_2`.
- Le composant dit `je suis l'alignement à gauche` et transmet `alignement à gauche` au coeur
- `état 1 (texte centré)` + `alignement à gauche` = `état 2 (texte à gauche)` + `mise à jour des leds` 
- L'affichage se met à jour avec le nouvel état
- Les instructions sont communiquées au contrôleur des LEDs

-> Les LED sont synchronisées avec un état et non réactives à une action
-> Tout changement d'état est projeté vers d'éventuelles dépendances 

---

## Quand je fais rouler la trackball, il se passe quoi ?

- Je fais rouler la trackball *ou bien* la contrepartie numérique
- Un événement `roulement` arive dans le système
- Il parvient au composant `trackball` qui le transmet au coeur
- Avant d'entrer dans le coeur, cet état est augmenté d'un `mot aléatoire`, ex. "typography"
- `état 1 (ancien texte)` + `changer le texte (typography)` = `état 2 (typography)` + `mise à jour des leds`
- L'affichage se met à jour avec le nouvel état
- Les instructions sont communiquées au contrôleur des LEDs

-> La trackball ne sait rien du mot aléatoire, le texte et les LED ne savent rien de la trackball

---

## Tout est indépendant

Démo Mail + Mini Brutator

---
layout: end
ribbon: Espace Brut
---

<a href="mailto:contact@turing-express.fr">contact@turing-express.fr</a>

Code complet disponible le 25 octobre : github.com/lucassifoni

Site perso (articles, confs) -> <a href="https://lucassifoni.info">lucassifoni.info</a>  
Développement indépendant -> <a href="https://turing-express.fr">turing-express.fr</a>  
Logiciel pour acteurs de l'archi/bâtiment -> <a href="https://alzo.fr">alzo.fr</a>  
Métrologie optique -> <a href="https://chantepierre-optique.fr">chantepierre-optique.fr</a>
