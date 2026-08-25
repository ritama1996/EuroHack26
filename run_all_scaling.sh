#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Discover every  0N_molecule_basis/  folder in the current directory (or a
# given parent), run the OpenMP scaling sweep on each, and collect results:
#   - a combined CSV with one row per (system, threads)
#   - a paste-ready master-table block (molecule, basis, best time per thread)
#   - one overlaid speedup plot across all systems
# Delegates the per-system sweep to run_scaling.sh (same folder).
# ----------------------------------------------------------------------------
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"

PARENT="${1:-.}"                                   # where the 0N_* folders live
NUMRE="${NUMRE:-[0-9]+_.*}"                        # folder = <digits>_molecule_basis (01_, 10_, 123_, ...)
export BINARY ARGS INPUT OUTPUT THREADS REPEATS    # pass config through to run_scaling.sh

cd "$PARENT" || { echo "ERROR: cannot cd to '$PARENT'"; exit 1; }

# collect matching directories, sorted (01_, 02_, ...)
mapfile -t SYSTEMS < <(find . -maxdepth 1 -type d -regextype posix-extended -regex "\./$NUMRE" -printf '%f\n' 2>/dev/null | sort -V)
(( ${#SYSTEMS[@]} > 0 )) || { echo "No <digits>_* folders (regex '$NUMRE') in $(pwd)"; exit 1; }

echo "Found ${#SYSTEMS[@]} system(s):"; printf '  %s\n' "${SYSTEMS[@]}"; echo

STAMP=$(date +%Y%m%d_%H%M%S)
ALLDIR="ALL_scaling_${STAMP}"; mkdir -p "$ALLDIR"
COMBINED="$ALLDIR/all_systems.csv"
TABLE="$ALLDIR/master_table_rows.tsv"
echo "system,molecule,basis,threads,total_s,accum_s,ideal_s,speedup,efficiency_pct,note" > "$COMBINED"
: > "$TABLE"

for sys in "${SYSTEMS[@]}"; do
  echo "==================================================================="
  echo ">> $sys"
  echo "==================================================================="
  "$HERE/run_scaling.sh" "$sys" || { echo "  (sweep failed for $sys, continuing)"; continue; }

  # newest results dir this sweep produced for this system
  rd=$(ls -dt "${sys}"_scaling_* 2>/dev/null | head -1)
  [[ -z "$rd" ]] && continue
  csv="$rd/${sys}_scaling.csv"
  # molecule/basis from the folder name
  IFS='_' read -r -a P <<< "$sys"; mol="${P[1]:-$sys}"; bas=""
  (( ${#P[@]} >= 3 )) && bas=$(IFS='_'; echo "${P[*]:2}")
  # append each threads-row into the combined CSV, prefixed with system identity
  if [[ -f "$csv" ]]; then
    tail -n +2 "$csv" | while IFS= read -r line; do
      echo "$sys,$mol,$bas,$line"
    done >> "$COMBINED"
  fi
  # copy the per-system plot into the combined dir for convenience
  cp "$rd/${sys}_scaling.png" "$ALLDIR/" 2>/dev/null
  # append the master-table row (grep the line run_scaling already computed)
done

# rebuild master-table rows straight from the combined CSV (best total per thread)
if command -v python3 >/dev/null; then
  python3 "$HERE/collect_scaling.py" "$COMBINED" "$TABLE" "$ALLDIR/all_systems_speedup.png" \
    && echo && echo "Combined table rows -> $TABLE" \
    && echo "Overlaid plot        -> $ALLDIR/all_systems_speedup.png"
fi
echo "Combined CSV -> $COMBINED"
echo "All results  -> $ALLDIR/"
