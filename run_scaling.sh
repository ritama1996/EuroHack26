#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# OpenMP strong-scaling sweep for cioverlap_fort.
# Folders are named  0N_molecule_basis/  and contain the input files.
# Each run is:  cioverlap_fort -s transmomin -a -t 5e-4 -e -1 < cioverlap.input > cioverlap.out
# The script sweeps thread counts, keeps the best of REPEATS runs, extracts the
# time the program itself reports, writes a data table + CSV, and plots
# actual vs ideal scaling.
# ----------------------------------------------------------------------------
set -u
export LC_ALL=C   # dot decimal separator, so awk + the plotter agree

# ---------------------- configuration (edit or override) --------------------
BINARY="${BINARY:-$HOME/Softwares/cioverlap/bin/cioverlap_fort}"     # path to the executable
ARGS="${ARGS:--s transmomin -a -t 5e-4 -e -1}"             # fixed program flags
INPUT="${INPUT:-cioverlap.input}"                          # stdin file in the folder
OUTPUT="${OUTPUT:-cioverlap.out}"                          # program stdout in the folder
THREADS="${THREADS:-1 2 4 8 12 16 24}"                     # thread counts to sweep
REPEATS="${REPEATS:-3}"                                    # runs per thread count (keep best)
# ----------------------------------------------------------------------------

SYSTEM="${1:-}"
if [[ -z "$SYSTEM" ]]; then read -rp "System folder (e.g. 01_pyrazine_def2-SVP): " SYSTEM; fi
SYSTEM="${SYSTEM%/}"
[[ -d "$SYSTEM" ]] || { echo "ERROR: directory '$SYSTEM' not found"; exit 1; }
[[ -x "$BINARY" ]] || { echo "ERROR: binary '$BINARY' not found/executable (set BINARY=...)"; exit 1; }
[[ -f "$SYSTEM/$INPUT" ]] || { echo "ERROR: '$SYSTEM/$INPUT' not found"; exit 1; }

# parse 0N_molecule_basis  ->  idx / molecule / basis (basis keeps any trailing _parts)
IFS='_' read -r -a P <<< "$SYSTEM"
IDX="${P[0]:-}"; MOLECULE="${P[1]:-$SYSTEM}"; BASIS=""
if (( ${#P[@]} >= 3 )); then BASIS=$(IFS='_'; echo "${P[*]:2}"); fi
LABEL="$MOLECULE${BASIS:+ / $BASIS}"

# physical cores, to flag oversubscription (hyperthreads rarely speed up LU work)
CORES=$( { lscpu -p=Core,Socket 2>/dev/null | grep -v '^#' | sort -u | wc -l; } 2>/dev/null )
[[ "$CORES" =~ ^[0-9]+$ && "$CORES" -gt 0 ]] || CORES=$(nproc 2>/dev/null || echo 0)

export OMP_PROC_BIND=close
export OMP_PLACES=cores

STAMP=$(date +%Y%m%d_%H%M%S)
OUT="${RESULTS_DIR:-${SYSTEM}_scaling_${STAMP}}"
mkdir -p "$OUT/logs"
DAT="$OUT/${SYSTEM}_scaling.dat"
CSV="$OUT/${SYSTEM}_scaling.csv"
{
  echo "# system=$SYSTEM  molecule=$MOLECULE  basis=$BASIS  cores_detected=$CORES  repeats=$REPEATS  $(date)"
  echo "# cmd: $BINARY $ARGS < $INPUT"
  echo "# threads   total_s     accum_s     ideal_s    speedup   eff%   note"
} > "$DAT"
echo "threads,total_s,accum_s,ideal_s,speedup,efficiency_pct,note" > "$CSV"

extract() { grep -E "$2" "$1" | grep -oE '[0-9]+\.[0-9]+' | head -1; }

declare -A BEST_TOTAL
T1=""
echo; echo "System: $SYSTEM   ($LABEL)   cores=$CORES"
printf "%-8s %-11s %-11s %-9s %-8s %-6s %s\n" threads total_s accum_s ideal_s speedup eff% note
for t in $THREADS; do
  note=""; (( CORES > 0 && t > CORES )) && note="oversubscribed(>$CORES cores)"
  best=""; bestacc=""
  for r in $(seq 1 "$REPEATS"); do
    ( cd "$SYSTEM" && OMP_NUM_THREADS="$t" "$BINARY" $ARGS < "$INPUT" > "$OUTPUT" 2>&1 )
    log="$OUT/logs/${SYSTEM}_t${t}_r${r}.log"; cp "$SYSTEM/$OUTPUT" "$log"
    tot=$(extract "$log" '^[[:space:]]*TOTAL[[:space:]]')
    acc=$(extract "$log" 'CI overlap accumulation')
    [[ -z "$tot" ]] && { echo "  WARN: no TOTAL in run t=$t r=$r (see $log)"; continue; }
    if [[ -z "$best" ]] || awk "BEGIN{exit !($tot < $best)}"; then best="$tot"; bestacc="$acc"; fi
  done
  [[ -z "$best" ]] && { echo "  skipping t=$t (all runs failed)"; continue; }
  BEST_TOTAL[$t]="$best"; [[ -z "$T1" ]] && T1="$best"
  ideal=$(awk "BEGIN{printf \"%.2f\", $T1/$t}")
  sp=$(awk "BEGIN{printf \"%.2f\", $T1/$best}")
  eff=$(awk "BEGIN{printf \"%.1f\", 100*$T1/$best/$t}")
  printf "%-8s %-11s %-11s %-9s %-8s %-6s %s\n" "$t" "$best" "${bestacc:-NA}" "$ideal" "$sp" "$eff" "$note"
  printf "%-8s %-11s %-11s %-9s %-8s %-6s %s\n" "$t" "$best" "${bestacc:-NA}" "$ideal" "$sp" "$eff" "$note" >> "$DAT"
  echo "$t,$best,${bestacc:-NA},$ideal,$sp,$eff,$note" >> "$CSV"
done

# paste-ready row for the master table: molecule, basis, then best times per thread
row="$MOLECULE\t$BASIS"; for t in $THREADS; do row+="\t${BEST_TOTAL[$t]:-}"; done
echo -e "\nMaster-table row (molecule, basis, times for threads [$THREADS]):"
echo -e "$row"

if command -v python3 >/dev/null && python3 -c "import matplotlib" 2>/dev/null; then
  python3 "$(dirname "$0")/plot_scaling.py" "$DAT" "$OUT/${SYSTEM}_scaling.png" "$LABEL" && \
    echo "Plot: $OUT/${SYSTEM}_scaling.png"
else
  echo "(matplotlib not found — data in $DAT/$CSV; run plot_scaling.py where it is available)"
fi
echo "Done. Results in $OUT/"
