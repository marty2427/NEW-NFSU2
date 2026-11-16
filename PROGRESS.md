# PROGRESS – stav projektu NEON WRECK

> Tento soubor si přečti na začátku každé práce na projektu.

## Aktuální stav
**Fáze 1b (5. kolo – velké město s nepravidelnými ulicemi, městský okruh 3,7 km, minimapa, nový tachometr, nový zvuk motoru): HOTOVO, čeká na otestování hráčem.**
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

## Zpětná vazba hráče k fázi 1b (a co se s ní udělalo)
- FPS: VYSOKÁ 100–120, ULTRA ~80 (RTX 3060 Ti) → rezerva na víc světla.
- Auta „vůbec nezatáčela“, jen ruční brzdou, hodně klouzala → nové řízení:
  natočení kol podle rychlosti (kola nepřejdou do smyku), auto se otáčí přesně podle volantu,
  arkádová přilnavost (auto jede tam, kam míří), drift jen ruční brzdou + plyn/protismyk,
  pojistka proti roztočení, po smyku/nárazu se auto samo srovná. ✅
  Naměřeno (všechna 3 auta): 60 km/h → poloměr 10–17 m, 100 km/h → ~52 m, slalom stabilní, bez smyku.
- Silvia „splašená“, Mustang se překrucoval → zadní přilnavost ≥ přední, menší vliv plynu na smyk. ✅
- Silvii se „motala kola“ → kola se otáčí kolem skutečné osy pneumatiky, brzdové třmeny se netočí. ✅
- Pořád moc tma, auto není vidět → expozice 1.45, ambient 1.5, silnější lampy, jemné světlo nad autem hráče,
  lak méně kovový (víc barvy). ✅
- Nápisy originálněji → vymyšlené podniky (česky/anglicky), 12 neonových písem, rámované cedule,
  svislé hotelové cedule, šipky s běžícím světlem, blikající neony, billboardy se žárovkami. ✅
- Kód NFSU2 není veřejný (EA), nelze ho použít – řízení je postavené na stejných arkádových principech.

## Zpětná vazba hráče – 3. kolo (a co se s ní udělalo)
- Auta pořád málo zatáčela, přední kola nebyla vidět natočená, zatáčelo se jen ruční brzdou,
  do driftu šla moc snadno a špatně z něj vyjížděla →
  - varianty řízení na F7: ARKÁDA (výchozí, ~2× ostřejší), SPORT (předchozí), DRIFT, EASY VEHICLE PHYSICS (převzaté, MIT),
  - přední kola jsou vidět natočená i v rychlosti (jen vzhled),
  - drift začne až po podržení ruční brzdy (0,3 s) v zatáčce nad 40 km/h; skončí, když hráč srovná volant
    nebo pustí plyn.
  Naměřeno (Octavia, 100 km/h, plný rejd): ARKÁDA R≈24 m, DRIFT ≈35 m, SPORT ≈52 m, EVP ≈35 m.
- Nový otáčkoměr ve stylu NFSU2 (moderně): kouřový ciferník, šikmé číslice, svítící oblouk otáček, převod
  se šipkou pro přeřazení, velká rychlost, modrý oblouk N2O nahoře vpravo, malý budík turba.
- Pro vývoj den (F8 přepne na noc s neony).
- Otázka Blender / jiný engine – zodpovězeno v chatu (Blender je na modely, Godot zůstává).

## 4. kolo – „vylaď to jako velmi dobře hratelnou arkádu“ (hráč dal volnou ruku)
- **Nové jádro řízení** (`scripts/car/car.gd`, část „Jizda v rovine“): žádné pneumatiky po kolech, ale arkádový model:
  volant → cílová rychlost otáčení auta (omezená `ostrost_zataceni` / rychlost a nejmenším poloměrem),
  boční síla drží auto ve směru jízdy do `prilnavost` (g); když se auto točí rychleji, než unese přilnavost,
  vybočí zadkem nejvýš o `max_uhel_smyku` a otáčení se přibrzdí (krátký smyk, ne roztočení).
  Drift: ruční brzda v zatáčce → menší přilnavost, volant řídí natočení, plyn drží rychlost, volant rovně = konec.
  Boční síla působí pod těžištěm → karoserie se naklání na pružinách.
- **Proč:** tři kola ladění hybridního modelu (síly pneumatik + asistenti) hráči nesedla („nezatáčí“).
  Nový model má pár srozumitelných čísel a jde měřit.
- **Měření řízení počítačovým jezdcem** (`scripts/car/ai_driver.gd`): jede po zaoblené stopě s rychlostním profilem,
  volant ovládá jako klávesnice (jen vlevo/vpravo/nic). Výsledek (okruh 1080 m, 8 zatáček):
  všechna 3 auta kolo ~40–41 s, odchylka od stopy ≤ 1,2 m, 0 nárazů, zatáčky v ~70 km/h, smyk do 12°.
  Při přehnané rychlosti auto vyjede ven (nedotáčivě), neroztočí se. Jezdec poslouží ve fázi 4 jako soupeř.
- **Okruh** (`scripts/world/circuit.gd`): trasa přes 8 křižovatek, svítící šipky, brána START/CÍL, čas kola v HUD,
  klávesa T postaví auto na start.
- **Lampy jdou porazit** (v rychlosti nad 25 km/h), hydranty odstrčit; menší tření o zdi (auto se o zeď otře a jede dál).
- **Kamera:** dívá se ve směru jízdy (je vidět natočení auta v zatáčce a ve smyku), při brzdění se přiblíží,
  při zrychlení a nitru zaostane, nevleze do budov.
- **Zvuky** (`scripts/car/car_audio.gd`, `tools/generuj_zvuky.py`): vše syntetické – motor (R4 / V8, dvě vrstvy podle otáček),
  kvílení pneumatik podle smyku, nitro, vítr, nárazy, škrábání, řazení, odfuk turba. Klávesa M = ztlumit.
  Pozor: zvuk nešlo v cloudu poslechnout, jen změřit (hlasitost, frekvence) – čeká na ohlas hráče.
- **Aktualizace bez stahování ZIPu:** `AKTUALIZOVAT.bat` (git fetch + reset, případně nainstaluje Git přes winget),
  `HRAT.bat` spustí hru přímo bez editoru.
- Varianty F7: ARKÁDA (výchozí), SPORT, DRIFT násobí hodnoty auta (`x_...` v auta.cfg); EVP = převzaté řízení.

## 5. kolo – velké město, okruh, zvuk motoru, tachometr (přání hráče)
- **Velké město** (`scripts/world/city_map.gd` = plán, `city_builder.gd` = stavba): graf ulic místo mřížky –
  22 křižovatek, 42 ulic, 16 km silnic, průměr ~1,7 km. Okružní bulvár (široký, plynulé oblouky), vnitřní okruh,
  paprsky, centrum s úhlopříčkami (nepravidelné úhly, vlásenky až 124°). ~1800 domů (dvě řady, v centru věžáky),
  ~315 lamp, ~680 cedulí. Zdi podél ulic jsou jedna souvislá kolize (auto se neodráží o spáry).
  Úprava plánu: stačí změnit `NODES` / `EDGES` v city_map.gd; kontrola `godot --headless --path . -s res://scripts/dev/map_check.gd`.
- **Tréninková plocha**: blok bez domů (~58 000 m²) severozápadně od centra – rampy, kontejnery, sudy, sklad „NITRO GARÁŽ“.
- **Městský okruh** (`circuit.gd`): 3,7 km, 10 křižovatek (bulvár → vnitřní okruh → centrum → zpět), svítící šipky,
  brána START/CÍL, průjezdní body. Auto začíná na startu; T = zpět na start.
- **Minimapa** (`scripts/ui/minimap.gd`) vlevo dole: natáčí se podle auta, okruh azurově, zelená tečka = kam jet.
- **Počítačový jezdec** má závodní stopu (`Circuit.racing_line()`: zatáčky najíždí zvenku, poloměr podle šířky ulice).
  Naměřeno (g = 1,5, klávesnicové řízení): Octavia 1:43, Mustang 1:41, Silvia 1:41, 0 nárazů, zatáčky od 63 km/h, max ~205 km/h.
- **Tachometr přepracován** (`scripts/ui/tachometer.gd`): moderní digitální přístrojovka, písmo Oxanium, rovné číslice,
  svítící oblouk otáček, uprostřed rychlost, dole převod (zeleně = přeřaď), vpravo modrý oblouk N2O. Budík turba zrušen.
- **Zvuk motoru znovu** (`tools/motor_synth.py`): model výfukových pulsů → svody → potrubí → tlumič + šum sání a mechaniky.
  3 motory: `r4` (Octavia, kultivovaný), `r4s` (Silvia, chraplavý, praská do výfuku), `v8` (Mustang, bublavý).
  Pro každý 5 smyček pod plynem + 3 bez plynu, hra mezi nimi prolíná (malé přelaďování = přirozenější), hvizd turba.
  Volně dostupné nahrávky (OpenGameArt, CC0) jsem zkoušel – jen hluboké bručení, nepoužitelné.
  Starý zvuk měl 95 % energie v pásmu 80–200 Hz (proto zněl jako bzučení), nový má harmonické do ~2–4 kHz.
  Pozor: pořád nešlo poslechnout, jen změřit. Když nebude stačit → skutečné nahrávky přes Cowork (např. Freesound).
- Ve dne okna a výlohy svítí jen slabě (v noci naplno).

## Co je hotovo
- **Auta** (`scripts/car/car.gd`, `car_model.gd`): 3D modely .glb, nastavení modelů v `data/modely_aut.cfg`
  (kola, materiály, světla, díly pro demolici, opravy modelu). Lak s clearcoatem, brzdová světla, reflektory se stínem.
- **Fyzika**: raycast odpružení, plynulý model pneumatik (smyk, kruh přilnavosti), motor podle výkonu v kW,
  automatická převodovka s otáčkami, odpor vzduchu dopočítaný z max. rychlosti, nitro, drift s asistencí,
  brzdění motorem, samo se postaví na kola. Výchozí útlum Godotu je vypnutý (jinak auta jela max ~115 km/h).
- Naměřeno (bez nitra): Octavia 0–100 za 5,1 s, Mustang 4,6 s, Silvia 4,7 s; 0–200 za 19–22 s.
- **Ladění jízdy**: `tuning/auta.cfg` (česky okomentované), F6 = znovu načíst.
- **Poškození**: práh ~7 m/s, násobek 0.6 / odolnost; kouř od 50 %, černý kouř od 75 %, oheň od 90 %, výbuch 100 %.
- **Mapa**: viz 5. kolo výše (velké město z grafu ulic). Budovy s texturami, okny a výlohami (jeden shader,
  hodnoty na dům), neonové nápisy, reklamy na střechách, lampy (MultiMesh + světla s dosahem podle kvality).
  Silnice: jeden mesh a shader s vodorovným značením a kalužemi.
- **Kamera**: nízko za autem, při zrychlení zaostává, v rychlosti se vzdálí a chvěje, FOV roste, nitro přidá.
- **HUD**: digitální přístrojovka (vpravo dole), minimapa (vlevo dole), čas kola, body za drift, název auta, FPS.
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
- Promáčkliny karoserie a odpadávání dílů během jízdy – fáze 2 (díly jsou už v modelech označené).
- Skutečný motion blur (Compositor efekt) zvážit ve fázi 7.
- Výkon na PC Monster ověřit na novém městě (1800 domů, víc cedulí a lamp); případně zkrátit dohled cedulí
  (`signs.set_view_distance`) a dosah lamp v `graphics.gd`, nebo domy sloučit do MultiMesh.
- Okolí za městem je prázdná rovina (z ulic není vidět, jen z výšky).
- Zatím bez provozu, chodců a bez výškových rozdílů (mosty, tunely) – nápad do fáze 5.

## Další krok
- Počkat na zpětnou vazbu k 5. kolu (mapa, okruh, zvuk, tachometr, řízení), opravit chyby, pak fáze 2.

## Vývojářské poznámky
- Automatický test: `godot --path . -- --autotest [--shots=SLOZKA] [--rychle]`
- Test řízení: `godot --headless --path . -- [--profil=arkada|sport|drift|gevp] --handlingtest=octavia`
- Test okruhu s počítačovým jezdcem: `godot --headless --fixed-fps 120 --path . -- --lap=octavia --g=1.5`
  (`--fixed-fps` = běží rychleji než skutečný čas, `--analog` = plynulý volant, `--r=2` = odstup od obrubníku, `LAPDEBUG=1` = podrobný výpis)
- Kontrola plánu města: `godot --headless --path . -s res://scripts/dev/map_check.gd`; počty: `-- --statistika`
- Zvuky znovu vygenerovat: `python3 tools/generuj_zvuky.py` (numpy, scipy); motor se ladí v `tools/motor_synth.py` (slovník ENGINES),
  otáčky smyček musí sedět s tabulkou v `scripts/car/car_audio.gd`
- Nahrávka se zvukem: `godot --path . --write-movie slozka/f.png --fixed-fps 20 -- --kvalita=0 --lap=mustang`
- Noc místo dne: přidat `--noc`
- Měření zrychlení: `godot --headless --path . -- --speedtest=octavia`
- Prohlížeč modelu: `godot --path . res://scenes/dev/model_viewer.tscn -- --view=res://cesta.glb --out=/slozka/prefix`
  nebo s `--car=octavia` (hotové auto).
- Snímky města: `godot --path . -- --snapshot=SLOZKA [--pohledy=mapa,start,plocha,okruh0..7] [--tacho=otacky,rychlost,nitro] [--noc]`
- Ladicí klávesa K = +25 % poškození.
