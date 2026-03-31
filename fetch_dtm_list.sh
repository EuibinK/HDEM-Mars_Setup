#!/bin/bash

# Script to fetch available DTM files from the HiRISE DTM archive and save details to a CSV file.
# Usage: ./fetch_dtm_list.sh [output_file.csv]
# Contact: euibin@lpl.arizona.edu

set -e

BASE_URL="https://www.uahirise.org/PDS/DTM"
OUTPUT_FILE="${1:-dtm_list.csv}"

echo "dtm_name,image_id1,image_id2,url" >"$OUTPUT_FILE"

extract_links() {
	local url="$1"
	curl -s "$url" | grep -oE 'href="[^"]+/"' | sed 's/href="//;s/"//' | grep -v '^\.\.' | grep -v '^/'
}

extract_dtm_files() {
	local url="$1"
	curl -s "$url" | grep -oE 'href="DTE[^"]+\.IMG"' | sed 's/href="//;s/"//'
}

# Parse DTM name to extract components
parse_dtm_name() {
	local dtm_name="$1"
	local base_url="$2"

	local name="${dtm_name%.IMG}"

	if [[ "$name" =~ ^DTE([A-Z])([A-Z])_([0-9]{6})_([0-9]{4})_([0-9]{6})_([0-9]{4})_([A-Z])([0-9]{2})(.*)$ ]]; then
		local projection="${BASH_REMATCH[1]}"
		local grid_spacing="${BASH_REMATCH[2]}"
		local orbit1="${BASH_REMATCH[3]}"
		local latbin1="${BASH_REMATCH[4]}"
		local orbit2="${BASH_REMATCH[5]}"
		local latbin2="${BASH_REMATCH[6]}"
		local institution="${BASH_REMATCH[7]}"
		local version="${BASH_REMATCH[8]}"

		local orbit1_num=$((10#$orbit1))
		local orbit2_num=$((10#$orbit2))

		local prefix1="E"
		if [[ $orbit2_num -le 10999 ]]; then
			prefix1="P"
		fi

		local prefix2="E"
		if [[ $orbit1_num -le 10999 ]]; then
			prefix2="P"
		fi

		local image_id1="${prefix1}SP_${orbit1}_${latbin1}"
		local image_id2="${prefix2}SP_${orbit2}_${latbin2}"

		echo "${name},${image_id1},${image_id2},${base_url}"
	fi
}

total_dtms=0

echo "Scanning mission phases..."
phases=$(extract_links "$BASE_URL/")

for phase in $phases; do
	phase_name="${phase%/}"
	echo ""
	echo "Processing phase: $phase_name"

	orbit_ranges=$(extract_links "${BASE_URL}/${phase}")
	orbit_count=$(echo "$orbit_ranges" | wc -w)
	printf "\r    Found: %d orbit ranges\n" "$orbit_count"

	current_orbit=0
	for orbit_range in $orbit_ranges; do
		current_orbit=$((current_orbit + 1))
		orbit_range_name="${orbit_range%/}"

		# Get stereo pairs in this orbit range
		stereo_pairs=$(extract_links "${BASE_URL}/${phase}/${orbit_range}")

		for stereo_pair in $stereo_pairs; do
			stereo_pair_name="${stereo_pair%/}"
			pair_url="${BASE_URL}/${phase}${orbit_range}${stereo_pair}"

			dtm_files=$(extract_dtm_files "$pair_url")

			for dtm_file in $dtm_files; do
				csv_line=$(parse_dtm_name "$dtm_file" "$pair_url")
				if [[ -n "$csv_line" ]]; then
					echo "$csv_line" >>"$OUTPUT_FILE"
					total_dtms=$((total_dtms + 1))
				fi
			done
		done
		printf "\r Progress: %d/%d orbit ranges (%d DTMs found)" "$current_orbit" "$orbit_count" "$total_dtms"
	done
	echo ""
done

echo ""
echo "Completed!"
echo "Total DTMs found: $total_dtms"
echo "Output saved to: $OUTPUT_FILE"
