#!/bin/bash

# Script to set up HDEM-Mars project directory with DEM name.
# Usage: ./setup.sh <DEM_NAME>
# Contact: euibin@lpl.arizona.edu

# Exit immediately if a command exits with a non-zero value
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
	cat <<EOF
Usage: $(basename "$0") <DEM_NAME>

Set up a project directory for HDEM-Mars processing.

ARGUMENTS:
    DEM_NAME        DEM file name as listed on the HiRISE website. (e.g., DTEEC_015947_1370_051036_1370_A01)
                    Can be provided with or without extension (.tif or .IMG)

OPTIONS:
    -h, --help      Show this help message and exit
    --image <1|2> Download orthoimage for image1 or image2 (default: none)

EXAMPLES:
    $(basename "$0") DTEEC_015947_1370_051036_1370_A01 
    $(basename "$0") DTEEC_015947_1370_051036_1370_A01 --image 1
    $(basename "$0") DTEEC_015947_1370_051036_1370_A01.tif --image 2

EOF
}

# install GDAL if not available (for gdal_translate)
install_gdal() {
	echo "      - gdal_translate not found. Installing GDAL..."

	local os_type="$(uname -s)"

	case "$os_type" in
	Darwin)
		if command -v brew &>/dev/null; then
			echo "      - Installing GDAL using Homebrew..."
			brew install gdal
		else
			echo "      - Error: Homebrew is NOT installed. Please install Homebrew first."
			exit 1
		fi
		;;
	Linux)
		if command -v apt-get &>/dev/null; then
			echo "      - Installing GDAL using apt-get..."
			sudo apt-get update && sudo apt-get install -y gdal-bin
		elif command -v yum &>/dev/null; then
			echo "      - Installing GDAL using yum..."
			sudo yum install -y gdal
		else
			echo "      - Error: Package manager NOT found. Please install GDAL manually."
			exit 1
		fi
		;;
	*)
		echo "      - error: Unsupported OS: $os_type"
		echo "      - Plese install GDAL manually."
		exit 1
		;;
	esac

	if ! command -v gdal_translate &>/dev/null; then
		echo "      - Error: GDAL installation failed. Please install GDAL manually."
		exit 1
	fi

	echo "      - GDAL installed successfully."
}

# Check if gdal_translate is available, install if not
check_gdal() {
	if ! command -v gdal_translate &>/dev/null; then
		install_gdal
	fi
}

# Check if gdal_translate is available
check_gdal() {
	if ! command -v gdal_translate &>/dev/null; then
		echo "      - Error: gdal_translate not found."
		echo "      - Please install GDAL."
	fi
}

# Remove file extension from DTM name
strip_extension() {
	local name="$1"
	name="${name%.tif}"
	name="${name%.TIF}"
	name="${name%.img}"
	name="${name%.IMG}"
	name="${name%.jp2}"
	name="${name%.JP2}"
	echo "$name"
}

# Parse DTM name to extract orbit information (needed to download the DEM if needed)
parse_dem_name() {
	local name="$1"

	# Remove extension if present
	dem_name=$(strip_extension "$name")

	if [[ ! "$dem_name" =~ ^DTE([A-Z])([A-Z])_([0-9]{6})_([0-9]{4})_([0-9]{6})_([0-9]{4})_([A-Z])([0-9]{2})(.*)$ ]]; then
		echo "Error: Invalid DEM name format: $dem_name"
		echo "Expected format: DTEab_XXXXXX_YYYY_ZZZZZZ_WWWW_Ivv[_SUFFIX]"
		echo "Example: DTEEC_015947_1370_051036_1370_A01"
		exit 1
	fi

	PROJECTION="${BASH_REMATCH[1]}"
	GRID_SPACING="${BASH_REMATCH[2]}"
	ORBIT1="${BASH_REMATCH[3]}"
	LATBIN1="${BASH_REMATCH[4]}"
	ORBIT2="${BASH_REMATCH[5]}"
	LATBIN2="${BASH_REMATCH[6]}"
	INSTITUTION="${BASH_REMATCH[7]}"
	VERSION="${BASH_REMATCH[8]}"
	SUFFIX="${BASH_REMATCH[9]}"

	PREFIX1=$(get_orbit_prefix "$ORBIT1")
	PREFIX2=$(get_orbit_prefix "$ORBIT2")

	# Build image IDs
	IMAGE_ID1="${PREFIX1}SP_${ORBIT1}_${LATBIN1}"
	IMAGE_ID2="${PREFIX2}SP_${ORBIT2}_${LATBIN2}"
}

# Determine orbit prefix (P or E) based on orbit number
get_orbit_prefix() {
	local orbit="$1"
	local orbit_num=$((10#$orbit))

	if [[ $orbit_num -ge 0 && orbit_num -le 10901 ]]; then
		echo "P"
	elif [[ $orbit_num -ge 11200 ]]; then
		echo "E"
	else
		echo "Error: Orbit number $orbit is outside valid range" >&2
		exit 1
	fi
}

# Calculate orbit range for URL construction
get_orbit_range() {
	local orbit="$1"
	local orbit_num=$((10#$orbit))

	local range_start=$(((orbit_num / 100) * 100))
	local range_end=$((range_start + 99))

	printf "%06d_%06d" "$range_start" "$range_end"
}

# Download DEM from HiRISE PDS
download_dem() {
	local dem_base="$1"
	local output_file="$2"

	parse_dem_name "$dem_base"

	local orbit_range
	orbit_range=$(get_orbit_range "$ORBIT1")

	local url="https://www.uahirise.org/PDS/DTM/${PREFIX1}SP/ORB_${orbit_range}/${IMAGE_ID1}_${IMAGE_ID2}/${dem_base}.IMG"

	echo "      - Downloading DEM from: $url"

	if curl -f -L --progress-bar -o "$output_file" "$url"; then
		echo "      - Successfully downloaded DEM: $output_file"
		return 0
	else
		echo "      - Error: Failed to download DEM from $url"
		return 1
	fi
}

# Download orthoimage from HiRISE PDS
# Naming convention: {IMAGE_ID}_RED_{GRID_SPACING}_{SEQUENCE}_ORTHO.JP2
#   GRID_SPACING: A=0.25m, B=0.5m, C=1.0m, D=2.0m
#   SEQUENCE: typically 01
# Outputs the downloaded filename to stdout
download_orthoimage() {
	local dem_base="$1"
	local image_num="$2"
	local output_dir="$3"

	parse_dem_name "$dem_base"

	local orbit_range
	orbit_range=$(get_orbit_range "$ORBIT1")

	local image_id
	if [[ "$image_num" == "1" ]]; then
		image_id="${IMAGE_ID1}"
	else
		image_id="${IMAGE_ID2}"
	fi

	local base_url="https://www.uahirise.org/PDS/DTM/${PREFIX1}SP/ORB_${orbit_range}/${IMAGE_ID1}_${IMAGE_ID2}"
	local sequence="01"

	# Try grid spacings A, B, C, D, E in order
	for grid_spacing in A B C D E; do
		local filename="${image_id}_RED_${grid_spacing}_${sequence}_ORTHO.JP2"
		local url="${base_url}/${filename}"
		local output_file="${output_dir}/${filename}"

		# Check if file exists before downloading (silent check)
		if curl -f -s -I "$url" >/dev/null 2>&1; then
			echo "      - Downloading orthoimage (grid spacing ${grid_spacing})..." >&2
			echo "        $url" >&2
			if curl -f -L --progress-bar -o "$output_file" "$url"; then
				echo "" >&2
				echo "      - Successfully downloaded orthoimage: $output_file" >&2
				echo "$output_file"
				return 0
			fi
		fi
	done

	echo "      - Error: Failed to download orthoimage (tried grid spacings A, B, C, D, E)" >&2
	return 1
}

# Convert IMG to TIF
convert_img_to_tif() {
	local input_file="$1"
	local output_file="$2"

	echo "      - Converting IMG to TIF: $input_file -> $output_file"

	if gdal_translate -of GTiff "$input_file" "$output_file"; then
		echo "      - Successfully converted to: $output_file"
		rm -f "$input_file"
		return 0
	else
		echo "      Error: Failed to convert $input_file to TIF"
		return 1
	fi
}

# Convert JP2 to TIF
convert_jp2_to_tif() {
	local input_file="$1"
	local output_file="$2"

	echo "      - Converting JP2 to TIF: $input_file -> $output_file"

	if gdal_translate -of GTiff "$input_file" "$output_file"; then
		echo "      - Successfully converted to: $output_file"
		rm -f "$input_file"
		return 0
	else
		echo "      Error: Failed to convert $input_file to TIF"
		return 1
	fi
}

# Check if DEM file exists locally (with or without extension)
find_dem_file() {
	local dir="$1"
	local base="$2"

	for ext in ".tif" ".TIF" ".img" ".IMG"; do
		if [[ -f "${dir}/${base}${ext}" ]]; then
			echo "${dir}/${base}${ext}"
			return 0
		fi
	done
	return 1
}

# Find orthoimage file with any supported extension
find_ortho_file() {
	local dir="$1"
	local base="$2"

	for ext in ".tif" ".TIF" ".jp2" ".JP2" ".img" ".IMG"; do
		if [[ -f "${dir}/${base}${ext}" ]]; then
			echo "${dir}/${base}${ext}"
			return 0
		fi
	done
	return 1
}

if [[ $# -lt 1 ]]; then
	show_help
	exit 0
fi

DEM_INPUT=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		show_help
		exit 0
		;;
	--image)
		if [[ "$2" != "1" && "$2" != "2" ]]; then
			echo "Error: --image must be 1 or 2"
			exit 1
		fi
		DOWNLOAD_IMAGE="$2"
		shift 2
		;;
	*)
		if [[ -z "$DEM_INPUT" ]]; then
			DEM_INPUT="$1"
		else
			echo "Error: Unexpected argument: $1"
			show_help
			exit 1
		fi
		shift
		;;
	esac
done

if [[ -z "$DEM_INPUT" ]]; then
	echo "Error: DEM name is required"
	show_help
	exit 1
fi

parse_dem_name "$DEM_INPUT"

DEM_BASE=$(strip_extension "$DEM_INPUT")

echo ""
echo "Setting up project directory for: $DEM_BASE"
if [[ -n "$DOWNLOAD_IMAGE" ]]; then
	echo "Will also download orthoimage for image $DOWNLOAD_IMAGE"
fi
echo ""

DEM_FOUND=false
DEM_PATH=""

# 1. Check if DEM exists in current directory (with or without extension)
if DEM_PATH=$(find_dem_file "." "$DEM_BASE"); then
	echo "[1/6] DEM found in current directory: $DEM_PATH"
	echo "[2/6] Skipping directory check (DEM already exists)"
	DEM_FOUND=true
else
	echo "[1/6] DEM NOT found in current directory."

	# 2. Check if directory named DEM_BASE exists
	if [[ -d "./${DEM_BASE}" ]]; then
		echo "[2/6] Found directory: ./${DEM_BASE}"

		# Check if DEM file exists inside that directory
		if DEM_PATH=$(find_dem_file "./${DEM_BASE}" "$DEM_BASE"); then
			echo "      - DEM found inside directory: $DEM_PATH"
			DEM_FOUND=true
		else
			echo "      - DEM NOT found inside directory"
		fi
	else
		echo "[2/6] Directory ./${DEM_BASE} does NOT exist"
	fi
fi

# 3. Download DEM if not found
if [[ "$DEM_FOUND" = false ]]; then
	echo "[3/6] Downloading DEM..."
	DEM_FILE="${DEM_BASE}.IMG"
	if download_dem "$DEM_BASE" "./${DEM_FILE}"; then
		DEM_FOUND=true
		DEM_PATH="./${DEM_FILE}"
	else
		echo "      - Failed to download DEM. Exiting..."
		exit 1
	fi
else
	echo "[3/6] Skipping download (DEM already exists)"
fi

# 4. Download orthoimage if requested
ORTHO_PATH=""
if [[ -n "$DOWNLOAD_IMAGE" ]]; then
	echo "[4/6] Downloading orthoimage..."

	# Build orthoimage base pattern for searching (try all grid spacings)
	if [[ "$DOWNLOAD_IMAGE" == "1" ]]; then
		ORTHO_IMAGE_ID="${IMAGE_ID1}"
	else
		ORTHO_IMAGE_ID="${IMAGE_ID2}"
	fi

	# Check if orthoimage already exists (any grid spacing)
	ORTHO_FOUND=false
	for gs in A B C D E; do
		ORTHO_BASE="${ORTHO_IMAGE_ID}_RED_${gs}_01_ORTHO"
		if ORTHO_PATH=$(find_ortho_file "." "$ORTHO_BASE") || ORTHO_PATH=$(find_ortho_file "./${DEM_BASE}" "$ORTHO_BASE"); then
			echo "      - Orthoimage already exists: $ORTHO_PATH"
			ORTHO_FOUND=true
			break
		fi
	done

	if [[ "$ORTHO_FOUND" = false ]]; then
		if ORTHO_PATH=$(download_orthoimage "$DEM_BASE" "$DOWNLOAD_IMAGE" "."); then
			: # Success, ORTHO_PATH is set
		else
			echo "      - Failed to download orthoimage."
			ORTHO_PATH=""
		fi
	fi
else
	echo "[4/6] Skipping orthoimage download (not requested)"
fi

# 5. Convert files to TIF
echo "[5/6] Converting files to TIF format..."
check_gdal

# DEM: IMG ->> TIF
if [[ "$DEM_PATH" == *.IMG || "$DEM_PATH" == *.img ]]; then
	DEM_TIF_PATH="${DEM_PATH%.IMG}"
	DEM_TIF_PATH="${DEM_TIF_PATH%.img}.tif"
	convert_img_to_tif "$DEM_PATH" "$DEM_TIF_PATH"
	DEM_PATH="$DEM_TIF_PATH"
else
	echo "      - DEM is already in TIF format"
fi

# Orthoimage: JP@ ->> TIF (check if it exists)
if [[ -n "$ORTHO_PATH" ]]; then
	if [[ "$ORTHO_PATH" == *.JP2 || "$ORTHO_PATH" == *.jp2 ]]; then
		ORTHO_TIF_PATH="${ORTHO_PATH%.JP2}"
		ORTHO_TIF_PATH="${ORTHO_TIF_PATH%.jp2}.tif"
		convert_jp2_to_tif "$ORTHO_PATH" "$ORTHO_TIF_PATH"
		ORTHO_PATH="$ORTHO_TIF_PATH"
	else
		echo "      - Orthoimage is already in TIF format"
	fi
fi

# 6. Create project directory and move files
echo "[6/6] Setting up project directory..."

PROJECT_DIR="./${DEM_BASE}"
DEM_FILENAME=$(basename "$DEM_PATH")

if [[ -d "$PROJECT_DIR" ]]; then
	echo "      - Directory $PROJECT_DIR already exists"
else
	echo "      - Creating directory: $PROJECT_DIR"
	mkdir "$PROJECT_DIR"
fi

# Move DEM to project directory if it's not already there
if [[ "$DEM_PATH" != "./${DEM_BASE}/${DEM_FILENAME}" ]]; then
	echo "      - Moving DEM to project directory..."
	mv "$DEM_PATH" "${PROJECT_DIR}/${DEM_FILENAME}"
else
	echo "      - DEM is already in the project directory"
fi

# Move orthoimage to project directory if it exists and is not already there
if [[ -n "$ORTHO_PATH" && -f "$ORTHO_PATH" ]]; then
	ORTHO_FILENAME=$(basename "$ORTHO_PATH")
	if [[ "$ORTHO_PATH" != "./${DEM_BASE}/${ORTHO_FILENAME}" ]]; then
		echo "      - Moving orthoimage to project directory..."
		mv "$ORTHO_PATH" "${PROJECT_DIR}/${ORTHO_FILENAME}"
	else
		echo "      - Orthoimage is already in the project directory"
	fi
fi

# Copy generate_conf.sh to project directory
GENERATE_CONF_SRC="${SCRIPT_DIR}/generate_conf.sh"
if [[ -f "$GENERATE_CONF_SRC" ]]; then
	if [[ -f "${PROJECT_DIR}/generate_conf.sh" ]]; then
		echo "      - generate_conf.sh is already in the project directory."
	else
		echo "      - Copying generate_conf.sh to project directory..."
		cp "$GENERATE_CONF_SRC" "${PROJECT_DIR}/"
		chmod +x "${PROJECT_DIR}/generate_conf.sh"
	fi
else
	echo "      - Warning: generate_conf.sh not found in script directory. Skipping copy."
fi

echo ""
echo "Setup complete!"
echo "  Project directory: ${PROJECT_DIR}"
