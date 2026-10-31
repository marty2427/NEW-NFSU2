# NEON WRECK (pracovní název)

Arkádová závodní hra pro Windows: noční neonové město (inspirace NFS Underground 2),
demolice aut (inspirace FlatOut 2) a zbraně na trati (inspirace Mario Kart).

- Engine: **Godot 4.7** (Forward+), jazyk GDScript
- Stav projektu a plán: [PROGRESS.md](PROGRESS.md)
- Zdroje a licence: [CREDITS.md](CREDITS.md)
- Ladění jízdy aut: [tuning/auta.cfg](tuning/auta.cfg)

## Spuštění
1. Nainstaluj Godot 4.7 (standardní verze, ne .NET).
2. V Godotu: **Import** → vyber soubor `project.godot` v této složce → **Import & Edit**.
   Při prvním otevření Godot chvíli načítá modely a textury.
3. Stiskni **F5** (nebo trojúhelník ▶ vpravo nahoře).

## Struktura
- `assets/` – 3D modely aut (`cars`), textury, obloha (`hdri`), rekvizity (`props`)
- `data/modely_aut.cfg` – technické nastavení 3D modelů aut
- `tuning/auta.cfg` – všechny hodnoty jízdy na jednom místě
- `scenes/` – scény (testovací město; `dev/` = vývojářské nástroje)
- `scripts/car/` – auto: fyzika, model, kamera, ovládání
- `scripts/world/` – mapa (město + parkoviště)
- `scripts/fx/` – efekty (kouř, oheň, jiskry, výbuch, nitro)
- `scripts/ui/` – HUD a otáčkoměr
- `scripts/autoload/` – ovládání a nastavení grafiky
- `shaders/` – silnice, budovy, efekty obrazovky
