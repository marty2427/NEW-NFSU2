# PROGRESS – stav projektu NEON WRECK

> Tento soubor si přečti na začátku každé práce na projektu.

## Aktuální stav
**Fáze 1b – přepracování podle zpětné vazby: HOTOVO, čeká na otestování hráčem.**
(Fáze 2 – plná demolice – začne až po souhlasu.)

## Fáze
| # | Fáze | Stav |
|---|------|------|
| 1 | Základ: projekt, auto, jízda, kamera, základní poškození a výbuch | ✅ hotovo |
| 1b | Přepracování: skutečná auta, styl NFSU2, velká mapa, tachometr, nová fyzika | ✅ hotovo (čeká na zpětnou vazbu) |
| 2 | Plná demolice: deformace, odpadávající díly, kouř/oheň, rozbitné okolí, zvuky | ⏳ další |
| 3 | Zbraně a nástrahy | – |
| 4 | Soupeři (AI) | – |
| 5 | Neonové město a tratě, HUD závodu | – |
| 6 | Garáž a kariéra | – |
| 7 | Doladění, menu, nastavení, gamepad, export .exe | – |

## Zpětná vazba hráče k fázi 1 (a co se s ní udělalo)
- Drift se „zasekával“ na 12° → nový plynulý model pneumatik + auto se bez volantu samo srovná. ✅
- Na mokru málo klouže → `mokra_silnice = 0.78`, menší přilnavost ve smyku. ✅
- Auta příliš křehká → poškození až od ~25 km/h, náraz 100 km/h ≈ 10–14 %. ✅
- Chce styl a pocit co nejblíž NFSU2 → noční město, mokré ulice, sodíkové lampy, neony, mlha,
  nízká kamera, rozmazání v rychlosti, nitro plameny, body za drift. ✅ (bez kopírování obsahu hry)
- Bylo moc tma → mnohem světlejší (lampy, okna, výlohy, obloha, expozice). ✅
- Hranaté ošklivé auto → skutečné 3D modely (Octavia, Mustang, Silvia, CC BY). ✅
- Skutečná auta a značky jsou OK (soukromý projekt) → výkon/hmotnost/pohon podle skutečných aut. ✅
- Větší trať: parkoviště + město s ulicemi. ✅
- Bez pruhu poškození v HUD; poškození vidět na autě. ✅ (zatím kouř/oheň/matný lak, promáčkliny ve fázi 2)
- Moderní tachometr vpravo dole. ✅
- Začít Octavií. ✅ (výchozí auto)

## Co je hotovo
- **Auta** (`scripts/car/car.gd`, `car_model.gd`): 3D modely .glb, nastavení modelů v `data/modely_aut.cfg`
  (kola, materiály, světla, díly pro demolici, opravy modelu). Lak s clearcoatem, brzdová světla, reflektory se stínem.
- **Fyzika**: raycast odpružení, plynulý model pneumatik (smyk, kruh přilnavosti), motor podle výkonu v kW,
  automatická převodovka s otáčkami, odpor vzduchu dopočítaný z max. rychlosti, nitro, drift s asistencí,
  brzdění motorem, samo se postaví na kola. Výchozí útlum Godotu je vypnutý (jinak auta jela max ~115 km/h).
- Naměřeno (bez nitra): Octavia 0–100 za 5,1 s, Mustang 4,6 s, Silvia 4,7 s; 0–200 za 19–22 s.
- **Ladění jízdy**: `tuning/auta.cfg` (česky okomentované), F6 = znovu načíst.
- **Poškození**: práh ~7 m/s, násobek 0.6 / odolnost; kouř od 50 %, černý kouř od 75 %, oheň od 90 %, výbuch 100 %.
- **Mapa** (`scripts/world/test_city.gd`, `city_builder.gd`): městská čtvrť 4×4 bloky (ulice po 90 m, vozovka 16 m,
  chodníky s obrubníkem), budovy s texturami, okny a výlohami, neonové nápisy, reklamy na střechách,
  ~190 pouličních lamp (MultiMesh + spot světla s dosahem podle kvality), parkoviště 210×220 m se sklady,
  kontejnery, rampami, zábranami, sudy a bednami. Silnice: jeden shader s vodorovným značením a kalužemi.
- **Kamera**: nízko za autem, při zrychlení zaostává, v rychlosti se vzdálí a chvěje, FOV roste, nitro přidá.
- **HUD**: kulatý otáčkoměr + tachometr + stupeň + nitro (vpravo dole), body za drift, název auta, FPS.
- **Efekty**: radiální rozmazání v rychlosti, čáry při nitru, modré plameny z výfuku, kouř pneumatik, jiskry, výbuch.
- **Grafika**: Forward+, SDFGI, objemová mlha, SSR, SSAO/SSIL, bloom; předvolby NÍZKÁ–ULTRA (F5).

## Důležitá rozhodnutí
- **Vývoj běží v cloudu (Claude Code na webu)**, ne přímo na PC Monster. Kód se předává přes GitHub
  (repo `marty2427/NEW-NFSU2`, větev `claude/intelligent-pasteur-j1fblf`). Hráč stahuje ZIP a otevírá v Godotu 4.7.
- V cloudu testuji Godot 4.7.2 (Linux): kontrola skriptů, automatický jízdní test, měření zrychlení,
  snímky obrazovky přes softwarové vykreslování (FPS tam nejde změřit).
- Cloud má plný přístup k internetu (nastavil hráč). Modely ze Sketchfabu stahuje Cowork (vyžaduje přihlášení).
- Vlastní fyzika auta (RigidBody3D + paprsky) místo VehicleBody3D – lépe se ladí arkádový drift.
- Scény se staví převážně v kódu (méně křehké .tscn soubory).
- Styl NFSU2 = inspirace atmosférou a pocitem, ne kopie mapy, HUD 1:1 ani obsahu původní hry.
- Textury v `assets/textures` mají v `.import` zapnuté mipmapy a VRAM kompresi (normal mapy jako normal map).

## Známé nedostatky / nápady na později
- Silvia: model je „výstavní“, dveře a kapota se zavírají v kódu (`transformace`, `reset_deti` v modely_aut.cfg).
- Zatím žádné zvuky (fáze 2).
- Promáčkliny karoserie a odpadávání dílů během jízdy – fáze 2 (díly jsou už v modelech označené).
- Skutečný motion blur (Compositor efekt) zvážit ve fázi 7.
- Výkon na PC Monster ověřit (hodně světel + objemová mlha); případně snížit dosah lamp v `graphics.gd`.

## Další krok
- Počkat na zpětnou vazbu k fázi 1b, opravit chyby, pak fáze 2.

## Vývojářské poznámky
- Automatický test: `godot --path . -- --autotest [--shots=SLOZKA]`
- Měření zrychlení: `godot --headless --path . -- --speedtest=octavia`
- Prohlížeč modelu: `godot --path . res://scenes/dev/model_viewer.tscn -- --view=res://cesta.glb --out=/slozka/prefix`
  nebo s `--car=octavia` (hotové auto).
- Snímek auta z boku: `godot --path . -- --snapshot=soubor.png`
- Ladicí klávesa K = +25 % poškození.
