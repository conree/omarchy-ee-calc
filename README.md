# EE Calc

An electronics bench calculator for the Omarchy Quattro bar.

![EE Calc: E-series, divider analysis and divider design panels](preview.png)

- **E-series:** type a resistance and see the nearest E3, E6, E12, E24, E48
  and E96 values, the values either side, and the error of each. It also
  finds the best two-part series and parallel combination from the series
  you pick.
- **Divider, Analyse:** Vin, R1, R2 and an optional load give Vout (loaded
  and unloaded), the ratio, current, the power in each part, and the
  source resistance R1 || R2.
- **Divider, Find values:** Vin and a target Vout give the best standard
  R1/R2 pairs from your chosen series, kept within a total-resistance
  range (default 10 kΩ to 1 MΩ).

## Screenshots

**E-series:** the nearest value in every series, with the error
colour-coded (green within 1 %, yellow within 5 %, red beyond), plus the
best two-part combination.

![E-series panel](docs/screenshots/e-series.png)

**Divider, Analyse:** a live schematic of the divider you entered, with
Vout, current, power and source resistance underneath. With a load across
R2, the schematic draws it in and the panel adds the unloaded Vout and the
load's current and power for comparison.

![Divider analysis panel with a load](docs/screenshots/divider-loaded.png)

**Divider, Find values:** the best standard R1/R2 pairs for a target
Vout, ranked by error, with the current each pair draws.

![Divider design panel](docs/screenshots/divider-find-values.png)

Shown with the Dracula Pro Van Helsing theme and the Comic Code Ligatures
font. The panel takes its colours from whichever Omarchy theme is active.

## Input

Values take engineering notation: `4k7`, `4.7k`, `2R2`, `R47`, `1M5`,
`100n`, `47u`. Lowercase `m` is milli and uppercase `M` is mega.

## How it works

The panel is QML. Every calculation is done by a small Zig program,
`bin/ee-calc`, which the panel runs as you type. The program prints one
JSON object and nothing else. It makes no network connections, needs no
privileges and writes no files. The panel itself writes only its own
entry in `shell.json` (the settings below).

The E-series tables are hard-coded from IEC 60063. E24 and the series
below it include the historical values (2.7, 3.0, 3.3 … 8.2) that the
10^(i/n) formula does not produce.

## Install

`omarchy plugin add` clones the repository but does not build anything,
so build the engine once after adding:

```
omarchy plugin add <repo-url>
cd ~/.config/omarchy/plugins/conree.ee-calc/engine
zig build --release
omarchy plugin enable conree.ee-calc
```

You need Zig 0.16.0 exactly: the engine uses the `std.process.Init` and
`std.Io` interfaces that arrived in 0.16, and `build.zig.zon` declares it.
The build writes `bin/ee-calc`, a static x86-64 binary of about 430 KB.
The binary is not committed; the repository is source only. Until it is
built, the panel says the engine is missing
rather than showing blank results.

Build somewhere other than the installed plugin folder if you can. The
shell watches `~/.config/omarchy/plugins/` and reloads plugins whenever a
file changes there, including Zig's build cache.

To run the engine's tests:

```
cd engine
zig build test
```

## Use

Click the calculator icon in the bar. Each field updates the result as
you type. **Enter** recalculates at once and **Esc** closes the panel.

The command line works on its own too:

```
bin/ee-calc eseries 4k99 --series E96
bin/ee-calc divider --vin 12 --r1 10k --r2 2k2 --rl 100k
bin/ee-calc divider-solve --vin 12 --vout 3.3 --series E24
bin/ee-calc help
```

## Settings

Stored on the widget's entry in `~/.config/omarchy/shell.json`:

| Key      | Default                | Meaning                                                    |
|----------|------------------------|------------------------------------------------------------|
| `series` | `E24`                  | Series for combinations and divider design                 |
| `tab`    | `E-series`             | Calculator the panel opens on; follows the last one used   |
| `font`   | `Comic Code Ligatures` | Panel font. Falls back to the shell font if not installed. |

Comic Code is a commercial font by Tabular Type Foundry. It is not
included here; the plugin only refers to it by name.

Colours come from the active Omarchy theme: the accent, the theme's red
for large errors, and its green and yellow (`color2` and `color3` in
`colors.toml`) for close and fair matches.

## Remove

```
omarchy plugin remove conree.ee-calc
```

## License

MIT. See `LICENSE`.
