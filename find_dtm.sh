#!/bin/bash

# Script to find DTM name(s) that contain a given HiRISE image ID.
# Usage: ./find_dtm.sh <IMAGE_ID>
# Contact: <euibin@lpl.arizona.edu>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DTM_LIST="${SCRIPT_DIR}/dtm_list.csv"

show_help() {
	cat <<EOF
USAGE: $(basename "$0") <IMAGE_ID>

Find DTM name(s) that contain the given image ID.

ARGUMENTS:
  IMAGE_ID   HiRISE image ID (e.g., ESP_015947_1370) 

OPTIONS:
  -f, --file <CSV_FILE>     Use a custom CSV file instead of dtm_list.csv
  -h, --help                Show this help message

EXAMPLES:
  $(basename "$0") ESP_015947_1370
  $(basename "$0") -f custom_dtm_list.csv ESP_015947_1370
EOF
}

IMAGE_ID=""

while [[ $# -gt 0 ]]; do
	case $1 in
	-h | --help)
		show_help
		exit 0
		;;
	-f | --file)
		DTM_LIST="$2"
		shift 2
		;;
	*)
		if [[ -z "$IMAGE_ID" ]]; then
			IMAGE_ID="$1"
		else
			echo "Error: Unexpected argument: $1"
			show_help
			exit 1
		fi
		shift
		;;
	esac
done

if [[ -z "$IMAGE_ID" ]]; then
	echo "Error: IMAGE ID is required"
	show_help
	exit 1
fi

if [[ ! -f "$DTM_LIST" ]]; then
	echo "Error: DTM list file not found: $DTM_LIST"
	echo ""
	echo "Run ./fetch_dtm_list.sh first to generate the DTM list."
	exit 1
fi

# Search for matching entries in columns 2, 3
matches=$(awk -F',' -v id="$IMAGE_ID" '
  NR > 1 && ($2 == id || $3 == id) { print $1 }
' "$DTM_LIST")

if [[ -z "$matches" ]]; then
	echo "No DTM found for image ID: $IMAGE_ID"
	exit 1
fi

count=$(echo "$matches" | wc -l | tr -d ' ')
echo "Found $count DTM(s) for image ID: $IMAGE_ID"
echo ""
echo "$matches"
