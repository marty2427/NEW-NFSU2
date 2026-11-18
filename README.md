# NEON WRECK (pracovní název)

Arkádová závodní hra pro Windows: noční neonové město (inspirace NFS Underground 2),
demolice aut (inspirace FlatOut 2) a zbraně na trati (inspirace Mario Kart).

- Engine: **Godot 4.7** (Forward+), jazyk GDScript
- Stav projektu a plán: [PROGRESS.md](PROGRESS.md)
- Zdroje a licence: [CREDITS.md](CREDITS.md)
- Ladění jízdy aut: [tuning/auta.cfg](tuning/auta.cfg)

## Spuštění a aktualizace (Windows)
- **AKTUALIZOVAT.bat** – dvojklik stáhne z GitHubu jen změny (poprvé si případně nainstaluje Git).
- **HRAT.bat** – dvojklik spustí hru přímo, bez editoru. Hledá Godot v `C:\Hry\Godot` nebo v této složce.
- Ručně: v Godotu 4.7 **Import** → `project.godot` → **F5**.

## Struktura
- `assets/` – 3D modely aut (`cars`), textury, obloha (`hdri`), rekvizity (`props`)
- `data/modely_aut.cfg` – technické nastavení 3D modelů aut
- `data/mesto.json` – plán města (generuje `tools/generuj_mesto.py`)
- `tuning/auta.cfg` – všechny hodnoty jízdy na jednom místě
- `scenes/` – scény (testovací město; `dev/` = vývojářské nástroje)
- `scripts/car/` – auto: fyzika, model, kamera, ovládání
- `scripts/world/` – mapa: plán města (`city_map.gd`), stavba (`city_builder.gd`), okruh (`circuit.gd`)
- `scripts/fx/` – efekty (kouř, oheň, jiskry, výbuch, nitro)
- `assets/sounds/` + `tools/generuj_zvuky.py`, `tools/motor_synth.py` – syntetické zvuky
- `scripts/ui/` – HUD, tachometr, minimapa, velká mapa
- `scripts/autoload/` – ovládání a nastavení grafiky
- `shaders/` – silnice, budovy, efekty obrazovky
