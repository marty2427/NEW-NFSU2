# PROGRESS – stav projektu NEON WRECK

> Tento soubor si přečti na začátku každé práce na projektu.

## Aktuální stav
**Fáze 1 – Základ: HOTOVO, čeká na otestování hráčem.**

## Fáze
| # | Fáze | Stav |
|---|------|------|
| 1 | Základ: projekt, auto v aréně, jízda, kamera, základní poškození a výbuch | ✅ hotovo (čeká na zpětnou vazbu) |
| 2 | Plná demolice: deformace, odpadávající díly, kouř/oheň, rozbitné okolí, zvuky | ⏳ další |
| 3 | Zbraně a nástrahy | – |
| 4 | Soupeři (AI) | – |
| 5 | Neonové město a tratě, HUD závodu | – |
| 6 | Garáž a kariéra | – |
| 7 | Doladění, menu, nastavení, gamepad, export .exe | – |

## Co je hotovo (fáze 1)
- Projekt Godot 4.7, renderer Forward+, fyzika Jolt, 120 fyzikálních kroků/s.
- **Auto** (`scripts/car/car.gd`): vlastní arkádová fyzika přes paprsky (raycast odpružení),
  přilnavost s rozložením váhy, ruční brzda, drift s asistencí (drží rychlost, pojistka proti roztočení),
  nitro (dobíjí se i driftováním), couvání, aerodynamický přítlak, samo se postaví na kola.
- **3 auta** s rozdílnými vlastnostmi (klávesy 1/2/3): ulični (zadní náhon), svalovec (těžký, silný), rally (4x4, lehké).
- **Ladění jízdy** v jednom souboru `tuning/auta.cfg` (česky okomentované), F6 = znovu načíst bez restartu.
- **Vzhled auta** z jednoduchých tvarů, každý díl samostatně (kapota, kufr, dveře, nárazníky, spoiler, kola) –
  připraveno na demolici. Světlomety se stíny, brzdová světla, neonové podsvícení.
- **Kamera**: 3 pohledy (C), pohled vzad (Q), zoom zorného pole s rychlostí a nitrem, otřesy při nárazu.
- **Poškození**: podle síly nárazu (změna rychlosti), jiskry, lak tmavne, od 35 % kouř, od 70 % černý kouř,
  od 85 % oheň, auto hůř zatáčí, zpomaluje a táhne do strany. Při 100 % výbuch (ohnivá koule, kouř,
  záblesk, tlaková vlna, odhozené díly, ohořelý vrak). Nové auto po 4 s.
- **HUD**: rychlost, nitro, poškození, drift, FPS, kvalita grafiky, nápověda ovládání (F1).
- **Testovací aréna**: noční parkoviště, mokrý asfalt s kalužemi (odrazy), neonové pruhy, budovy s okny,
  barevné lampy, rampy, betonové bloky, kontejnery, sudy, pneumatiky, kužely, neonové nápisy.
- **Grafika**: SDFGI, objemová mlha, SSR, SSAO/SSIL, bloom, měkké stíny, rozmazání v rychlosti (vlastní shader).
  Předvolby NÍZKÁ / STŘEDNÍ / VYSOKÁ / ULTRA (F5), výchozí VYSOKÁ.
- **Ovládání**: klávesnice + gamepad (Xbox rozložení) už teď.

## Důležitá rozhodnutí
- **Vývoj běží v cloudu (Claude Code na webu)**, ne přímo na PC Monster. Godot pro Windows instaluje hráč sám
  (winget příkaz v návodu). Kód se předává přes GitHub (repo `marty2427/NEW-NFSU2`, větev `claude/intelligent-pasteur-j1fblf`).
  V cloudu testuji Godot 4.7.2 pro Linux: kontrola skriptů + automatický jízdní test + snímky obrazovky (softwarové vykreslování).
- Vlastní fyzika auta (RigidBody3D + paprsky) místo VehicleBody3D – lépe se ladí arkádový drift.
- Scény se staví převážně v kódu (méně křehké .tscn soubory, snazší úpravy).
- Ovládání se registruje v kódu (`scripts/autoload/input_setup.gd`) – ve fázi 7 přibude přenastavení kláves.
- Godot nemá vestavěný motion blur → zatím radiální „speed blur“ shader; skutečný motion blur
  (Compositor efekt) zvážit ve fázi 7.
- Všechny modely zatím z jednoduchých tvarů (nic ke stažení, žádné licence k řešení).

## Další krok
- Počkat na zpětnou vazbu k fázi 1 (jízda, drift, kamera, poškození, výkon/FPS na PC Monster).
- Pak fáze 2: deformace karoserie (posun vrcholů meshe v místě nárazu), odpadávání dílů podle poškození,
  rozbitné okolí (ploty, sudy, pneumatiky, sloupky, kužely), zvuky motoru a nárazů (CC0).

## Vývojářské poznámky
- Automatický test: `godot --path . -- --autotest [--shots=SLOZKA]` (jízda, drift, nitro, poškození, výbuch, náraz do zdi).
- Snímek auta z boku: `godot --path . -- --snapshot=soubor.png`.
- Ladicí klávesa K = +25 % poškození.
