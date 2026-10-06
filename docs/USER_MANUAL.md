# EE Calc user manual

Version 0.2.6. For EE Calc, the electronics bench calculator plugin for the
Omarchy Quattro bar.

## 1. What EE Calc does

EE Calc is a calculator panel that opens from an icon on your Omarchy bar.
It has two tabs:

- **E-series:** type a resistance and see the nearest standard value in
  each of the E3, E6, E12, E24, E48 and E96 series, how far off each one
  is, the best two-resistor combination, and real manufacturer part
  numbers.
- **Divider:** analyse a resistive voltage divider (with an optional load),
  or find standard resistor pairs that give the output voltage you need.
  Both show part numbers, and Analyse checks each resistor's power against
  its package rating.

![EE Calc: E-series, divider with a load, and divider design](../preview.png)

## 2. Install, enable, update and remove

You need Omarchy Quattro on a 64-bit (x86-64) PC. The calculator program
comes ready-built in the plugin, so nothing else is needed.

**Install.** In a terminal, run:

```
omarchy plugin add https://github.com/conree/omarchy-ee-calc.git
```

Omarchy shows a warning that plugins run with your permissions and asks you
to confirm. It then asks whether to switch the plugin on now: answer
**Yes** and choose where on the bar it goes, or **No** to look through it
first.

**Enable**, if you answered No:

```
omarchy plugin enable conree.ee-calc
```

A calculator icon appears on the right of your bar, or wherever you placed
it.
The panel header shows the installed version next to the name, for example
**EE Calc v0.2.6**.

**Update:**

```
omarchy plugin update conree.ee-calc
```

**Remove:**

```
omarchy plugin remove conree.ee-calc
```

## 3. Using the panel

- **Open and close** the panel by clicking the calculator icon. **Esc**
  also closes it, including while you are typing in a box.
- **Results update as you type.** Press **Enter** to recalculate at once.
- **The boxes open with example values** (for instance `4k99` on the
  E-series tab) so the panel shows a result straight away. Select a box and
  type over the value.
- **Remembered between sessions:** the tab you last used, and your Series,
  Package and Tolerance choices. The values in the boxes return to the
  examples when the Omarchy shell restarts.

## 4. Entering values

Values use engineering notation. Spaces are ignored, and a unit symbol at
the end is allowed but not needed.

| You type | Means | Notes |
|---|---|---|
| `4700`, `4.7k`, `4k7`, `4K7` | 4.7 kΩ | The prefix letter can stand in for the decimal point |
| `2R2`, `2r2` | 2.2 Ω | `R` marks the decimal point for ohms |
| `R47` | 0.47 Ω | Only `R` may start a value |
| `1M5` | 1.5 MΩ | Capital `M` is mega |
| `1m` | 0.001 | Lowercase `m` is milli |
| `100n`, `47u`, `47µ`, `10p` | nano, micro, pico | |
| `1G`, `1T` | giga, tera | |
| `1e3` | 1000 | Scientific notation |
| `10ohm`, `4k7Ω`, `3.3V` | 10 Ω, 4.7 kΩ, 3.3 | Trailing `Ω`, `ohm`, `ohms`, `V`, `A` or `W` is accepted |

Limits:

- Values must be between 1e-15 and 1e15 in size. Anything outside that, and
  text that is not a number, gives **"not a number"**.
- The E-series tab accepts targets from 1 mΩ to 100 GΩ.
- Resistances, voltages and loads must be above zero.

## 5. Series, Package and Tolerance

These three rows of buttons sit below the input boxes. Each choice is
remembered.

| Control | Choices | Used by |
|---|---|---|
| **Series** | E3, E6, E12, E24, E48, E96 | E-series tab: the two-part combinations and the part list. Divider Find values: the values it chooses from. Not shown on Analyse. |
| **Package** | 0402, 0603, 0805, 1206, ¼W, ½W | All tabs: the part numbers, and the power check on Analyse and Find values. ¼W and ½W are through-hole metal-film resistors. |
| **Tolerance** | 1 %, 5 % | All tabs: the part numbers. 5 % parts are made in E24 values only. |

## 6. The E-series tab

![The E-series tab](screenshots/e-series.png)

Type a resistance in **Value**. The table shows one row per series:

- **Nearest:** the closest standard value. "Closest" is judged by ratio,
  the way tolerances work, not by the difference in ohms. If a value falls
  exactly midway by ratio, the lower value is chosen.
- **Error:** how far the nearest value is from what you typed, as a
  percentage. **exact** means it is already a standard value.
  - Green: exact, or within 1 %.
  - Yellow: within 5 %.
  - Red: more than 5 % away.
- **Below / above:** the standard values on either side.

The row for the series you chose under **Series** is highlighted in pink.

**Two parts.** Below the table, EE Calc gives the best combination of two
values from your chosen series:

- **In series:** two parts added together.
- **In parallel:** two parts in parallel, shown as `a || b`.

Each shows its error in the same colours. The search covers three decades
either side of your value. When two combinations are equally close, the one
with the more similar pair of values is shown.

**Part list.** At the bottom is the part list for the nearest value in your
chosen series, for the package and tolerance you chose. See
[section 9](#9-part-numbers).

## 7. Divider: Analyse

![Divider, Analyse, with a load](screenshots/divider-loaded.png)

Enter **Vin**, **R1 (top)** and **R2 (bottom)**. **Load** is optional; it
is a resistance across R2, the output.

The **schematic** redraws as you type: Vin at the top, R1, the output node
with its voltage, R2 to ground, and the load (dashed) when one is given.

The readings:

| Reading | Meaning |
|---|---|
| **Vout** | Output voltage, with the load connected if you gave one |
| **Vout without load** | Shown only when there is a load, for comparison |
| **Ratio** | Vout divided by Vin |
| **Current in R1** | The current from Vin, through R1 |
| **Power R1, Power R2** | Power each resistor dissipates, then the package rating and the share of it used, for example *96.7 mW of 100 mW (97 %)* |
| **Load current / power** | Shown only when there is a load |
| **Source resistance** | R1 \|\| R2: the resistance the output presents to a load. It does not include the load itself. |

The power colours:

- Green: up to half the package rating.
- Yellow: above half, up to the rating. The part works but runs hot.
- Red: above the rating. The part is overloaded.

A share below 1 % is shown as **(<1 %)**.

Below the readings are part lists for R1 and for R2, at your chosen package
and tolerance.

![Divider, Analyse, with R1 near its rating](screenshots/divider-analyse.png)

## 8. Divider: Find values

![Divider, Find values](screenshots/divider-find-values.png)

Enter **Vin** and the **Target Vout**. **Min R1+R2** and **Max R1+R2** set
the range the two resistors' total must fall in (10 kΩ and 1 MΩ to start
with). **Load** is optional.

EE Calc tries R1 and R2 values from your chosen **Series** and lists the
five best pairs:

- They are ranked by how close Vout comes to your target. Where two are
  equally close, the pair whose total is nearer the middle of your range
  comes first.
- Pairs with the same R1 : R2 ratio, such as 24k : 9.1k and 240k : 91k,
  give the same Vout without a load, so only one of them is listed.
- The best pair is shown in bold.
- If a resistor in a pair would dissipate more than its package rating, its
  value is shown in red.

Columns: **R1**, **R2**, **Vout** (with the load if you gave one),
**Error** (coloured as on the E-series tab), and **Current** through R1.

Below the list are part lists for the best pair.

If no pair from the series fits the total resistance range, the panel says
so. Target Vout must be below Vin.

## 9. Part numbers

EE Calc builds manufacturer part numbers from each manufacturer's published
ordering scheme. It does this offline: no internet connection, no account,
and no stock check. Check availability with your distributor as usual.

| Package | Manufacturers and families | Example: 4.99 kΩ, 1 % |
|---|---|---|
| 0402, 0603, 0805, 1206 | Yageo RC, Vishay CRCW e3, Panasonic ERJ | RC0603FR-074K99L, CRCW06034K99FKEA, ERJ3EKF4991V |
| ¼W, ½W through hole | Yageo MFR metal film | MFR-25FBF52-4K99 |

**Copying.** Click a part number to copy it to the clipboard. The power
figure next to it changes to **copied** for a moment.

**Each row shows** the manufacturer, that part's power rating, and the part
number.

**When there is no part,** the list says why:

| Message | Meaning |
|---|---|
| **No 5 % part / choose E24** | 5 % is chosen with the E48 or E96 series. 5 % parts come in E24 values only; choose E24 to see them. |
| **No part / not made at 5 % (E24 values only)** | The value is an E48 or E96 value, which is not made at 5 %. |
| **No part / outside every maker's range for this size** | No manufacturer makes this value in this package at this tolerance. |
| **No part / outside the 1 Ω to 4.7 MΩ range** | Through-hole parts are offered from 1 Ω to 4.7 MΩ. |

A manufacturer is also left out when only that one does not make the value.
For example, Panasonic's 1 % parts start at 10 Ω, so a 2.2 Ω part lists
only Yageo and Vishay.

**"not for new designs"** appears next to Panasonic 1206 parts, because
Panasonic marks those sizes "not recommended for new design".

**The power rating used by the power check** is the lowest standard rating
among the manufacturers for that package, so a pass holds whichever part
you buy:

| Package | Rating used |
|---|---|
| 0402 | 62.5 mW |
| 0603 | 100 mW |
| 0805 | 125 mW |
| 1206 | 250 mW |
| ¼W through hole | 250 mW |
| ½W through hole | 500 mW |

**Sources.** The ordering schemes, ranges and ratings come from the
manufacturers' datasheets: Yageo RC_L (V.14, November 2025), Vishay D/CRCW
e3 (document 20035, April 2026), Panasonic ERJ ±1 % (AOA0000C304, May 2025)
and ±5 % (AOA0000C301, December 2022), and Yageo MFR (V.4, April 2024).

## 10. Settings

EE Calc keeps its settings in the plugin's entry in
`~/.config/omarchy/shell.json`. The panel updates them for you; you only
need to edit them by hand for the font.

| Setting | Default | Meaning |
|---|---|---|
| `series` | `E24` | Series for combinations and divider design |
| `tab` | `E-series` | The tab the panel opens on; follows the last one used |
| `packageCode` | `0603` | Package for part numbers and the power check |
| `tolerance` | `1` | Tolerance in percent, `1` or `5` |
| `font` | `Comic Code Ligatures` | Panel font. If it is blank or not installed, the panel uses the Omarchy shell font. |

Colours come from the active Omarchy theme, so the panel follows theme
changes.

## 11. Command line

The calculator program inside the plugin also works on its own. From the
plugin folder, `~/.config/omarchy/plugins/conree.ee-calc/`:

```
bin/ee-calc eseries 4k99 --series E96
bin/ee-calc divider --vin 12 --r1 10k --r2 2k2 --rl 100k
bin/ee-calc divider-solve --vin 12 --vout 3.3 --series E24
bin/ee-calc parts 4k99 --package 0603 --tolerance 1
bin/ee-calc help
```

Each command prints one line of JSON. `eseries`, `divider` and
`divider-solve` also take `--package` (0402, 0603, 0805, 1206, tht-quarter,
tht-half) and `--tolerance` (1 or 5) to add part numbers and power checks.
`divider-solve` also takes `--rmin`, `--rmax`, `--rl` and `--count` (1 to
20).

## 12. Troubleshooting

| What you see | What it means | What to do |
|---|---|---|
| *The calculator program bin/ee-calc is missing.* | The plugin's program file is not there. | Remove the plugin and add it again (section 2). |
| *The engine could not be started* | The program file is there but would not run. | Remove and add the plugin again. |
| *The engine did not answer* | The program took longer than 3 seconds. | Change a value to try again. If it keeps happening, restart the shell with `omarchy-restart-shell`. |
| *No answer from the engine*, *Engine returned unreadable output* | The program's reply was empty or garbled. | As above. |
| *not a number* | The value could not be read. | Check it against section 4. |
| *value must be between 1 m and 100 G* | E-series value out of range. | Use a value from 1 mΩ to 100 GΩ. |
| *Vout must be below Vin* | Find values target is too high. | Use a target below Vin. |
| *no pair from this series fits the total resistance range* | No pair's total falls between Min and Max R1+R2. | Widen the range or choose a denser series. |
| *R1 must be above zero* (and similar) | A resistance, voltage or load is zero or negative. | Enter a positive value. |
| *Type a value…*, *Enter Vin…* | A required box is empty. | Fill it in. |

## 13. Accuracy and limits

**How the results were checked.**

- 26 automated tests in the calculator program, including the example part
  numbers printed in the manufacturers' datasheets.
- An independent reference calculator, written separately, compared against
  140 hand-written cases and 600 random ones. Every computed value agreed.
- About 6,000 combinations of value, package, tolerance and manufacturer
  compared against an independently written part-number builder. All part
  numbers, ranges and ratings agreed.

**What it does not do yet.** These are planned:

- E192 series (0.1 % to 0.5 % values)
- SMT marking codes (3- and 4-digit, EIA-96) and colour bands, in both
  directions
- LED series resistor and Ohm's law
- RC time constant and cutoff, LC resonance

**Keep in mind:**

- Part numbers show what a manufacturer's ordering scheme defines, not what
  is in stock. Check with your distributor.
- Power ratings are at 70 °C, as the datasheets state them. Hotter
  surroundings or a crowded board reduce what a resistor can safely
  dissipate.
- The divider assumes ideal resistors at their nominal values. Real parts
  vary within their tolerance.

---

EE Calc is © 2026 conree, released under the MIT licence.
