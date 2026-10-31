# NEON WRECK (pracovní název)

Arkádová závodní hra pro Windows: noční neonové město (styl NFS Underground 2),
demolice aut (styl FlatOut 2) a zbraně na trati (styl Mario Kart).

- Engine: **Godot 4.7** (Forward+), jazyk GDScript
- Stav projektu a plán: [PROGRESS.md](PROGRESS.md)
- Zdroje a licence: [CREDITS.md](CREDITS.md)
- Ladění jízdy aut: [tuning/auta.cfg](tuning/auta.cfg)

## Spuštění
1. Nainstaluj Godot 4.7 (standardní verze, ne .NET).
2. V Godotu: **Import** → vyber soubor `project.godot` v této složce → **Import & Edit**.
3. Stiskni **F5** (nebo trojúhelník ▶ vpravo nahoře).

## Struktura
- `scenes/` – scény (zatím testovací aréna)
- `scripts/car/` – auto: fyzika, vzhled, kamera, ovládání
- `scripts/fx/` – efekty (kouř, oheň, jiskry, výbuch)
- `scripts/ui/` – HUD
- `scripts/world/` – aréna / tratě
- `scripts/autoload/` – ovládání a nastavení grafiky
- `shaders/` – asfalt, budovy, efekty obrazovky
- `tuning/auta.cfg` – všechny hodnoty jízdy na jednom místě
