# Attribution

This repo bundles third-party work so the desktop reproduces exactly. Nothing here is mine except
the installer, the wizard, the autostart scripts, and my own configuration values.

Licences below were read out of each skin's own `[Metadata]` blocks, not assumed. Where a suite
declares more than one licence across its skins, every one found is listed.

---

## Rainmeter skins

Installed to `Documents\Rainmeter\Skins\`.

| Suite | Author | Declared licence |
|---|---|---|
| **Refract** | Immanuel Smith (`smithxtt`) | Creative Commons BY-NC-SA 3.0 |
| **BigSur** | Xyrfo and fediaFedia — weather mod by JSMorley, original skin by Shivaism | CC BY-NC-SA 3.0, CC BY-NC-ND 3.0 (varies per skin) |
| **Monterey** | Creewick | CC BY-NC-SA 4.0 |
| **RKS Illusions** | Ritukalpa Saikia | none declared |
| **cmd.exe** | lynxNZL | none declared |

### What those licences mean here

- **NC (NonCommercial)** — none of these skins may be used commercially. This repo is a personal
  desktop configuration; keep it that way.
- **SA (ShareAlike)** — derivatives must carry the same licence.
- **ND (NoDerivatives)** — parts of BigSur forbid distributing *modified* versions. Those skins are
  redistributed here **unmodified**. If you change them, do not redistribute the result.
- **"none declared"** — no licence was stated by the author. Redistribution here is a good-faith
  mirror for reproducibility. If you are one of these authors and want it removed, open an issue
  and it will be taken down.

My customisation lives in `config/rainmeter/Rainmeter.ini` (which skins load, and where) and in the
skins' `UserVariables.inc` files — not in the skin logic itself.

---

## Wallpapers

`config/rainmeter/skins/BigSur/@Resources/Graphics/Slideshow/Sample/` — cycled by the slideshow
widget. Mixed provenance:

**Public domain** (author died >70 years ago, works long out of copyright):

- `Starry_Night_Van_Gogh.jpg` — Vincent van Gogh, *The Starry Night*, 1889
- `Kanagawa_Great_Wave_Off.jpg` — Katsushika Hokusai, *The Great Wave off Kanagawa*, c. 1831
- `Michelangelo_God_and_Adam.jpg` — Michelangelo, *The Creation of Adam*, c. 1512
- `arnoldboecklin-fiedelndertod.jpg` — Arnold Böcklin, *Self-Portrait with Death Playing the
  Fiddle*, 1872

**Unknown provenance** — collected wallpapers with no identified author or licence:

- `Black And White Aesthetic Bloomed Flowers Wallpaper.jpg`
- `Greek Mythology Blackberry Wallpaper HD Pics.jpg`
- `Mochipanko Desktop Wallpaper Art Cute.jpg`
- `Off-White_Digital_Art.jpg`
- `Porsche 911 GT3 RS driving racetrack wallpaper desktop 2.jpg`
- `anat_collage.jpg`, `anat_collage_2.jpg`
- `full-moon-dark-background-cloudy-sky-stars-digital-art-5k-8k-7000x4000-5589.jpg`

Those in the second group are included so the slideshow widget works out of the box and to show
what the desktop actually looks like. They are **not** licensed for redistribution by me, and some
are likely under copyright — `Off-White_Digital_Art.jpg` and the Porsche wallpaper in particular
involve trademarked brands. If you own one of these and want it gone, open an issue.

If you would rather not carry them, delete the `Sample` folder and point `PicturesFolder` in
`BigSur\Widgets\Slideshow\UserVariables.inc` at your own directory.

---

## Software

Installed by winget, not redistributed here. Configuration only.

| Project | Author | Licence |
|---|---|---|
| [komorebi](https://github.com/LGUG2Z/komorebi) | LGUG2Z | Komorebi Personal Use Licence — [commercial use requires a licence](https://lgug2z.com/software/komorebi) |
| [whkd](https://github.com/LGUG2Z/whkd) | LGUG2Z | MIT |
| [YASB](https://github.com/amnweb/yasb) | amnweb | MIT |
| [AutoHotkey](https://www.autohotkey.com/) | AutoHotkey Foundation | GPL-2.0 |
| [Rainmeter](https://www.rainmeter.net/) | Rainmeter team | GPL-2.0 |
| [Windhawk](https://windhawk.net/) | Ramen Software | GPL-3.0 |
| [Flow Launcher](https://www.flowlauncher.com/) | Flow Launcher team | MIT |
| [Windows Terminal](https://github.com/microsoft/terminal) | Microsoft | MIT |
| [JetBrainsMono Nerd Font](https://www.nerdfonts.com/) | JetBrains / Nerd Fonts | OFL-1.1 |

> **komorebi is not free for commercial use.** If you run this desktop at work you need a
> [commercial licence](https://lgug2z.com/software/komorebi). Nothing in this repo grants one.

---

## Windhawk mods

`config/windhawk/enabled-mods.json` records mod ids, versions and my settings — no mod source is
copied. Each mod is authored by its own developer and published at
[windhawk.net/mods](https://windhawk.net/mods) under its own licence. The installer only writes
settings for mods you have already installed through the Windhawk UI.
