#!/usr/bin/env bash
# Levenshtein edit distance — standard DP table.
# Usage: levenshtein.sh <a> <b>
# Prints distance to stdout.

set -euo pipefail

a="${1:-}"
b="${2:-}"

la=${#a}
lb=${#b}

if (( la == 0 )); then echo "$lb"; exit 0; fi
if (( lb == 0 )); then echo "$la"; exit 0; fi

declare -a row
for (( j=0; j<=lb; j++ )); do row[j]=$j; done

for (( i=1; i<=la; i++ )); do
  prev=$((i-1))
  row[0]=$i
  prev_diag=$prev
  for (( j=1; j<=lb; j++ )); do
    cost=1
    if [[ "${a:i-1:1}" == "${b:j-1:1}" ]]; then
      cost=0
    fi
    del=$(( row[j] + 1 ))
    ins=$(( row[j-1] + 1 ))
    sub=$(( prev_diag + cost ))
    min=$del
    (( ins < min )) && min=$ins
    (( sub < min )) && min=$sub
    prev_diag=${row[j]}
    row[j]=$min
  done
done

echo "${row[lb]}"
