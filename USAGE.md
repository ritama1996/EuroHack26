# cioverlap OpenMP scaling tools

Four scripts to measure and plot OpenMP strong-scaling of `cioverlap_fort`.

| Script | Role | You run it? |
|---|---|---|
| `run_scaling.sh` | Sweep thread counts for **one** system folder | Yes |
| `run_all_scaling.sh` | Discover **all** `NN_*` folders and sweep each | Yes |
| `plot_scaling.py` | Draw the plot for one sweep's `.dat` | No (called for you) |
| `collect_scaling.py` | Build the combined table + overlaid plot | No (called for you) |

You only ever invoke the two `.sh` files. The two `.py` files are helpers the
shell scripts call automatically; you'd run them by hand only to redraw a plot
from data you already have.

Keep all four files in the same directory.

---

## Folder naming convention

Each system lives in its own folder named:

```
NN_molecule_basis/
```

- `NN` — an index with **one or more leading digits** (zero-pad to two digits:
  `01`, `02`, … `10`, `11`, …). The auto-discovery matches any folder whose name
  is `<digits>_<anything>`.
- `molecule` and `basis` — parsed out of the name and used to label the plot
  and the master-table row.

Each folder must contain the run's input files: `cioverlap.input`,
`eivectors1`, `eivectors2`, `slaterfile`, `transmomin`.

Examples: `01_pyrazine_def2-SVP/`, `02_pyrazine_def2-TZVP/`,
`10_crystalpyrazine_DZVP-GPW/`.

---

## Quick start

Point the scripts at your binary once (edit the `BINARY=` line at the top of
both `.sh` files), or pass it on the command line as shown below.

**One system, default thread sweep:**
```bash
./run_scaling.sh 01_pyrazine_def2-SVP
```

**One system, threads 1–16:**
```bash
THREADS="1 2 4 8 16" ./run_scaling.sh 01_pyrazine_def2-SVP
```

**All systems in the current directory, in one go:**
```bash
./run_all_scaling.sh
```

**All systems under a specific parent directory:**
```bash
./run_all_scaling.sh /data/my_runs
```

---

## The command each run executes

Inside each folder, for every thread count `t` and repeat `r`:

```bash
cd <folder>
OMP_NUM_THREADS=<t> <BINARY> -s transmomin -a -t 5e-4 -e -1 \
    < cioverlap.input > cioverlap.out
```

The time is then read from the `TOTAL` line the program prints in its own
timing summary — not from an external timer — so the plotted number matches
what the code reports.

---

## Defaults

Set as variables at the top of the scripts; override any of them on the command
line (see next section).

| Variable | Default | Meaning |
|---|---|---|
| `BINARY` | `~/cioverlap/bin/cioverlap_fort` | Path to the executable |
| `ARGS` | `-s transmomin -a -t 5e-4 -e -1` | Fixed program flags |
| `INPUT` | `cioverlap.input` | Stdin file inside each folder |
| `OUTPUT` | `cioverlap.out` | Program stdout inside each folder |
| `THREADS` | `1 2 4 8 16 32` | Thread counts to sweep |
| `REPEATS` | `3` | Runs per thread count; the **best** is kept |
| `NUMRE` | `[0-9]+_.*` | (all-systems only) folder-name regex |
| `RESULTS_DIR` | *(unset → timestamped)* | Fixed output folder name if you set it |

Two behaviours worth knowing:

- **Physical cores are auto-detected** (via `lscpu`). Any thread count above the
  physical core count is tagged `oversubscribed(>N cores)` in the output and the
  data file. Hyperthreads rarely speed up this LU-heavy work, so treat the
  physical core count as your real ceiling.
- **Thread pinning** is set (`OMP_PROC_BIND=close`, `OMP_PLACES=cores`) so the OS
  doesn't migrate threads mid-run and blur the scaling. On a 2-socket node this
  fills the first socket before spilling to the second.

---

## Customizing a run

Override any default by prefixing the command with `VARIABLE=value`. This
changes nothing permanently — it applies to that one invocation.

```bash
# different binary + a smaller thread set
BINARY=/opt/cioverlap/bin/cioverlap_fort THREADS="1 2 4 8 16 24" \
    ./run_scaling.sh 02_pyrazine_def2-TZVP

# a single clean run (no repeats), one thread only
THREADS="1" REPEATS=1 ./run_scaling.sh 01_pyrazine_def2-SVP

# a tighter screening threshold for this run
ARGS="-s transmomin -a -t 1e-4 -e -1" ./run_scaling.sh 01_pyrazine_def2-SVP

# the whole thread range 1..16 for a smooth curve (slow: many runs)
THREADS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16" \
    ./run_scaling.sh 01_pyrazine_def2-SVP

# fixed output folder that overwrites instead of timestamping
RESULTS_DIR=my_latest_run ./run_scaling.sh 01_pyrazine_def2-SVP
```

For `run_all_scaling.sh`, the same overrides pass through to every system:

```bash
BINARY=~/cioverlap/bin/cioverlap_fort THREADS="1 2 4 8 16 24" REPEATS=3 \
    ./run_all_scaling.sh
```

Recommended thread set for a **2-socket × 12-core** node (24 physical cores):
`THREADS="1 2 4 8 12 16 24"` — the `12` and `24` mark the one-socket and
two-socket boundaries.

---

## Output: why a new folder each time, and its format

**Each run creates a fresh, timestamped results folder on purpose** — so
repeating a sweep never overwrites earlier results and you keep a full history
to compare (e.g. before vs after a code change). The name is:

```
<system>_scaling_<YYYYMMDD_HHMMSS>/
```

for a single system, e.g. `02_pyrazine_def2-TZVP_scaling_20260825_164156/`, and

```
ALL_scaling_<YYYYMMDD_HHMMSS>/
```

for an all-systems run. The `YYYYMMDD_HHMMSS` is the date and time the sweep
started.

If you'd rather overwrite a fixed folder instead of accumulating timestamps,
set `RESULTS_DIR`:

```bash
RESULTS_DIR=pyrazine_svp ./run_scaling.sh 01_pyrazine_def2-SVP
```

### What each results folder contains

Single-system (`run_scaling.sh`):
- `<system>_scaling.dat` — the table (threads, total_s, accum_s, ideal_s, speedup, eff%, note)
- `<system>_scaling.csv` — the same data as CSV
- `<system>_scaling.png` — two panels: time-vs-threads and speedup-vs-threads
- `logs/` — the full program output of every individual run

All-systems (`run_all_scaling.sh`) additionally produces, in `ALL_scaling_*/`:
- `all_systems.csv` — every (system, threads) row combined
- `master_table_rows.tsv` — one `molecule / basis / t1 t2 t4 …` line per system,
  ready to paste into your master table's time columns
- `all_systems_speedup.png` — every system's speedup curve overlaid vs the ideal line
- a copy of each system's individual plot

The screen output of each sweep also ends with a paste-ready master-table row.

---

## Notes and troubleshooting

- **Comma vs dot decimals.** The scripts force `LC_ALL=C` so all computed numbers
  use a dot. If you have an *old* `.dat` from before this fix (with `19,83`), the
  plotter now tolerates commas, so you can still redraw it:
  ```bash
  python3 plot_scaling.py old_run/<system>_scaling.dat out.png "label"
  ```
- **"No TOTAL in run …"** means a run didn't finish or didn't print its timing
  summary — check the matching file in `logs/`.
- **Binary not found.** The scripts abort early if `BINARY` isn't executable.
  Set it correctly (a shared `bin/`, or `BINARY=./cioverlap_fort` if you keep a
  copy inside each folder, since the run happens after `cd` into the folder).
- **Runs are sequential.** Within one node the sweep runs one thread count at a
  time and waits — running them concurrently would make them fight for cores and
  ruin the timings. An all-systems sweep with `REPEATS=3` is an overnight batch,
  not an interactive wait.
- **Plotting needs** `python3` with `matplotlib`. If it's missing, the data files
  are still written; run the plotter later on a machine that has it.
