#!/usr/bin/env bash
set -euo pipefail

filter_trees_by_evalue(){
    tsv=$1
    evalue=$2
    folderin=$3
    folderout=$4
    
    tail -n+2 "$tsv" \
    | cut -f 1,5 \
    | awk -v evalue="$evalue" '$2 <= evalue' \
    | cut -f 1 \
    | sort -V -u \
    | xargs -I '{}' -n 1 cp "$folderin/{}.nwk" "$folderout/{}.nwk"

}


tsv=$1
evalue=$2
folderin=$3
folderout=$4

mkdir --parents "$folderout"

filter_trees_by_evalue "$tsv" "$evalue" "$folderin" "$folderout"