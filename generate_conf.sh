#!/bin/bash

# Script to generate configuration JSON files for HDEM-Mars
# Usage: ./generate_conf.sh --dem-file <DEM_FILE> [options]
# Constact: euibin@lpl.arizona.edu

#############################################################################################
# Set PATHs
PATH_ROOT="/path/to/HDEM-Mars/"
DATABASE_NAME="Database/Data_exp/BRDF_963A_olivine_sand_Hapke-RTLSR_HiRISE.nc"
ATMOSPHERIC_LUT="Database/Data_atmos/LUT_derived_quantities_spectral_Wolff_V_highres.nc"
#############################################################################################

# Required parameter
DEM_NAME=""

USE_IMG2=false

# Default values
CHANNEL="_S_"
BAND_WAVE="0.7"

BCK_ABUNDANCE=0
FLAG_BCK_MACRO=1

CROP_BEGIN_X=1
CROP_END_X=1
CROP_BEGIN_Y=1
CROP_END_Y=1
GSD=0.25
NO_DATA_DEM="NaN"

# TODO: Optical_depth, atmospheric conditions #################
TAU_REF=0.87
HSCALE=11000
SPECT_SCALE_FACTOR="0.8401"
SPECT_PATH_RAD_EX="0.0971"
###############################################################

SZA=67
SUN_AZIMUTH=312
VZA=3.4
PHASE_ANGLE=64.6
THRESHOLD_SKY=0.9

ENV_EFFECTS=0
PHASE1=true
PHASE2=false
PHASE3=false
LAMBDA1=0.001
LAMBDA2=1e-9
FACT=0.75
SCALE=0
CONVOL=4
FACTOR_BIN=1

# TODO: Block size based on # cores ###########################
BLOCK_SIZE_X=2398
BLOCK_SIZE_Y=2771
###############################################################

BORDER_SIZE=30

MAXITERS_KL=30
MAXITERS_Z=500
MAX_TOL=0.05

RESTORE_SAVE_FILE=false
RESTITUTION_ALBEDO_HI=false

# TODO: Calibration factors from ORTHOIMAGE RED label #########
DU2FL=0
FLOFF=0
###############################################################

BOOST_FACTOR=1
NO_DATA_IMG=0

OUTPUT_FILE=""
IMAGE_FILE=""
MASK_FILE=""

# FUNCTIONS:
show_help() {
	cat <<EOF
Usage: $(basename "$0") --dem-file <DEM_FILE> [options]

Generate a configuration JSON file for HDEM-Mars based on the provided DEM file and optional parameters.

REQUIRED:

  --dem-file <DEM_FILE>             Path to the DEM file (e.g., ./DTEEC_015947_1370_051036_1370_A01_crop.tif)

                                    The filename must follow the format:
                                
                                      DTEab_cccccc_dddd_eeeeee_ffff_ghh[_SUFFIX].tif
                                    
                                        - a: projection. Most commonly,
                                          - E: Equirectangular
                                          - P: Polar Stereographic

                                        - b: grid spacing (pixel scale in meters)
                                          - A: 0.25 m
                                          - B: 0.5 m 
                                          - C: 1 m
                                          - D: 2 m

                                        - cccccc: Image 1 orbit number (6 digits)
                                        - dddd: Image 1 latitude bin

                                        - eeeeee: Image 2 orbit number (6 digits)
                                        - ffff: Image 2 latitude bin

                                        - g: producing institution

                                        - hh: 2 digit version number

                                    The script will read the file dimensions to set
                                    crop_begin_x, crop_end_x, crop_begin_y, crop_end_y.

OPTIONS:

  -o, --output <OUTPUT_FILE>        Output JSON file name (auto-generated if not provided)
  --use-image2                      Use Image 2 for processing  (default: Image 1)

  Image:
    --image-file <IMAGE_FILE>       Orthoimage file name (default: auto-generated based on DEM name)
    --mask-file <MASK_FILE>         Mask file name (default: Orthoimage file name)

  Modeling:
    --scale <VALUE>                 Target scale factor for the output (default: 0)
    --convol <VALUE>                Convolution kernel size (default: 4)
    --factor_bin <VALUE>            Binning factor (default: 1)
    --border_size <VALUE>           Border size in pixels (default: 30)
    --block_size <X>,<Y>            Block size for processing (default: determined based on DEM dimensions and number of cores)
    --phase1 <BOOL>                 Enable phase 1 modeling (default: true)
    --phase2 <BOOL>                 Enable phase 2 modeling (default: false)
    --phase3 <BOOL>                 Enable phase 3 modeling (default: false)
    --restore_save_file <BOOL>      Whether to restore from a previous save file (default: false)
    --restitution_albedo_hi <BOOL>  Whether to use restitution albedo for high incidence
EOF
}

validate_bool() {
	local value="$1"
	local option="$2"
	if [[ "$value" != "true" && "$value" != "false" ]]; then
		echo "Error: $option must be 'true' or 'false'"
		exit 1
	fi
}

parse_dem_name() {
	local dem_name="$1"

	# keep filename only, remove path
	dem_name=$(basename "$dem_name")

	if [[ ! "$dem_name" =~ ^.{5}_([0-9]{6})_([0-9]{4})_([0-9]{6})_([0-9]{4})_([A_Z])([0-9]{2}) ]]; then
		echo "Error: Invalid DEM name format: $dem_name"
		echo "Expected format: DTEab_XXXXXX_YYYY_ZZZZZZ_WWWW_Ivv[_SUFFIX].tif"
		echo "Example: DTEEC_015947_1370_051036_1370_A01_crop.tif"
		exit 1
	fi

	ORBIT1="${BASH_REMATCH[1]}"
	LATBIN1="${BASH_REMATCH[2]}"
	ORBIT2="${BASH_REMATCH[3]}"
	LATBIN2="${BASH_REMATCH[4]}"
	INSTITUTION="${BASH_REMATCH[5]}"
	VERSION="${BASH_REMATCH[6]}"

	ORBIT_PREFIX1=$(get_orbit_prefix "$ORBIT1")
	ORBIT_PREFIX2=$(get_orbit_prefix "$ORBIT2")

	IMAGE_ID1="${ORBIT_PREFIX1}SP_${ORBIT1}_${LATBIN1}"
	IMAGE_ID2="${ORBIT_PREFIX2}SP_${ORBIT2}_${LATBIN2}"

	echo ""
	echo "0. Parsed DEM name: $dem_name"
	echo "  - Image 1: $IMAGE_ID1"
	echo "  - Image 2: $IMAGE_ID2"
}

# To get DEM file dimensions
# Install tiffinfo if not available:

install_tiffinfo() {
	echo "tiffinfo not found. Installing libtiff-tools..."

	# Detect operating system
	local os_type="$(uname -s)"

	case "$os_type" in
	Darwin)
		if command -v brew &>/dev/null; then
			echo "Installing libtiff-tools using Homebrew..."
			brew install libtiff
		else
			echo "Error: Homebrew is not installed. Please install Homebrew and try again."
			exit 1
		fi
		;;
	Linux)
		if command -v apt-get &>/dev/null; then
			echo "Installing libtiff-tools using apt-get..."
			sudo apt-get update && sudo apt-get install -y libtiff-tools
		elif command -v yum &>/dev/null; then
			echo "Installing libtiff-tools using yum..."
			sudo yum install -y libtiff-tools
		else
			echo "Error: Package manager not found. Please intall libtiff-tools manually and try again."
			exit 1
		fi
		;;
	*)
		echo "Error: Unsupported operating system: $os_type" >&2
		echo "Please install libtiff-tools manually and try again." >&2
		exit 1
		;;
	esac

	if ! command -v tiffinfo &>/dev/null; then
		echo "Error: tiffinfo installation failed. Please install libtiff-tools manually and try again." >&2
		exit 1
	fi

	echo "tiffinfo installed successfully."
}
get_dem_dimensions() {
	local dem_file="$1"

	echo ""
	echo "1. Reading DEM dimensions from: $dem_file"

	if [[ ! -f "$dem_file" ]]; then
		echo "Error: DEM file not found: $dem_file"
		exit 1
	fi

	# 1. Get dimensions using gdalinfo
	if ! command -v tiffinfo &>/dev/null; then
		install_tiffinfo
	fi

	local width=$(tiffinfo "$dem_file" 2>/dev/null | grep "Image Width" | head -1 | sed 's/.*Image Width: \([0-9]*\).*/\1/')
	local height=$(tiffinfo "$dem_file" 2>/dev/null | grep "Image Length" | head -1 | sed 's/.*Image Length: \([0-9]*\).*/\1/')

	if [[ -n "$width" && -n "$height" ]]; then
		CROP_END_X="$width"
		CROP_END_Y="$height"
	else
		echo "Error: Failed to read DEM dimensions from $dem_file"
		exit 1
	fi

}

# To calculate optimal block sizes based on DEM dimensions and CPU cores
calculate_block_size() {
	local dem_width="$1"
	local dem_height="$2"
	local border_x="$3"
	local border_y="$4"

	local num_cores
	if [[ "$(uname -s)" == "Darwin" ]]; then
		num_cores=$(sysctl -n hw.ncpu)
	elif [[ "$(uname -s)" == "Linux" ]]; then
		num_cores=$(nproc)
	else
		echo "Error: Unsupported operating system for CPU core detection" >&2
		exit 1
	fi

	local best_nx=1
	local best_ny=$num_cores

	for ((nx = 1; nx * nx <= num_cores; nx++)); do
		if ((num_cores % nx == 0)); then
			local ny=$((num_cores / nx))

			if ((dem_width >= dem_height)); then
				if ((ny > nx)); then
					best_nx=$ny
					best_ny=$nx
				else
					best_nx=$nx
					best_ny=$ny
				fi
			else
				if ((ny > nx)); then
					best_nx=$nx
					best_ny=$ny
				else
					best_nx=$ny
					best_ny=$nx
				fi
			fi
		fi
	done

	BLOCK_SIZE_X=$(((dem_width + best_nx - 1) / best_nx + 2 * border_x))
	BLOCK_SIZE_Y=$(((dem_height + best_ny - 1) / best_ny + 2 * border_y))
}

# To determine prefix (P or E) based on orbit number.
get_orbit_prefix() {
	local orbit="$1"
	local orbit_num=$((10#$orbit))

	if [[ $orbit_num -ge 0 && $orbit_num -le 10901 ]]; then
		echo "P"
	elif [[ $orbit_num -ge 11261 ]]; then
		echo "E"
	else
		echo "Error: Orbit number $orbit is outside valid range" >&2
		exit 1
	fi
}

# To calculate orbit range (e.g., 015947 => [015900, 015999])
get_orbit_range() {
	local orbit="$1"
	local orbit_num=$((10#$orbit))

	local range_start=$(((orbit_num / 100) * 100))
	local range_end=$((range_start + 99))

	printf "%06d %06d" "$range_start" "$range_end"
}

# To download label files
download_labels() {
	local prefix1="$1"
	local orbit1="$2"
	local latbin1="$3"
	local prefix2="$4"
	local orbit2="$5"
	local latbin2="$6"
	local institution="$7"
	local version="$8"

	# Get orbit range
	read -r ORBIT_START ORBIT_END <<<"$(get_orbit_range "$orbit1")"

	# Build Image IDs
	IMAGE_ID1="${prefix1}SP_${orbit1}_${latbin1}"
	IMAGE_ID2="${prefix2}SP_${orbit2}_${latbin2}"
	PREFIX="HiRISE_${ORBIT1}"
	IMAGE_ORBIT="$orbit1"
	IMAGE_LATBIN="$latbin1"

	IMAGE_ID="$IMAGE_ID1"
	local IMG_ORBIT_START="$ORBIT_START"
	local IMG_ORBIT_END="$ORBIT_END"
	local IMG_PREFIX="$prefix1"
	if $USE_IMG2; then
		PREFIX="HiRISE_${ORBIT2}"
		IMAGE_ID="$IMAGE_ID2"
		IMAGE_ORBIT="$orbit2"
		IMAGE_LATBIN="$latbin2"
		IMG_PREFIX="$prefix2"
		read -r IMG_ORBIT_START IMG_ORBIT_END <<<"$(get_orbit_range "$orbit2")"
	fi

	# URL 1: Image B&W label
	URL_BW="https://hirise-pds.lpl.arizona.edu/PDS/RDR/${IMG_PREFIX}SP/ORB_${IMG_ORBIT_START}_${IMG_ORBIT_END}/${IMAGE_ID}/${IMAGE_ID}_RED.LBL"

	# URL 2: Orthoimage label
	# Naming convention: {IMAGE_ID}_RED_{GRID_SPACING}_{SEQUENCE}_ORTHO.LBL
	local BASE_ORTHO_URL="https://www.uahirise.org/PDS/DTM/${prefix1}SP/ORB_${ORBIT_START}_${ORBIT_END}/${IMAGE_ID1}_${IMAGE_ID2}"
	local sequence="01"

	echo ""
	echo "2. Downloading LBL files..."
	if curl -f -L -o "./${IMAGE_ID}_RED.LBL" "$URL_BW" 2>/dev/null; then
		echo "  - Downloaded: ./${IMAGE_ID}_RED.LBL"
		BW_LABEL_FILE="./${IMAGE_ID}_RED.LBL"
	else
		echo "  - Failed to download Image B&W label"
		BW_LABEL_FILE=""
	fi

	# Try grid spacings A, B, C, D, E in order for orthoimage label
	ORTHO_LABEL_FILE=""
	for grid_spacing in A B C D E; do
		local url_ortho="${BASE_ORTHO_URL}/${IMAGE_ID}_RED_${grid_spacing}_${sequence}_ORTHO.LBL"
		local label_file="./${IMAGE_ID}_RED_${grid_spacing}_${sequence}_ORTHO.LBL"
		if curl -f -L -o "$label_file" "$url_ortho" 2>/dev/null; then
			echo "  - Downloaded: $label_file"
			ORTHO_LABEL_FILE="$label_file"
			break
		fi
	done

	if [[ -z "$ORTHO_LABEL_FILE" ]]; then
		echo "  - Failed to download Orthoimage label (tried grid spacings A, B, C, D, E)"
	fi
}

# To extract geometry parameters from B&W label file
extract_geometry_from_label() {
	echo ""
	echo "3. Extracting geometry from: $BW_LABEL_FILE"

	if [[ -z "$BW_LABEL_FILE" || ! -f "$BW_LABEL_FILE" ]]; then
		echo "Warning: B&W label file NOT found."
		return 1
	fi

	local incidence=$(grep -w "INCIDENCE_ANGLE" "$BW_LABEL_FILE" | head -1 | sed 's/.*= *\([0-9.]*\).*/\1/')
	if [[ -n "$incidence" ]]; then
		SZA="$incidence"
	fi

	local emission=$(grep -w "EMISSION_ANGLE" "$BW_LABEL_FILE" | head -1 | sed 's/.*= *\([0-9.]*\).*/\1/')
	if [[ -n "$emission" ]]; then
		VZA="$emission"
	fi

	local phase=$(grep -w "PHASE_ANGLE" "$BW_LABEL_FILE" | head -1 | sed 's/.*= *\([0-9.]*\).*/\1/')
	if [[ -n "$phase" ]]; then
		PHASE_ANGLE="$phase"
	fi

	local sub_solar=$(grep -w "SUB_SOLAR_AZIMUTH" "$BW_LABEL_FILE" | head -1 | sed 's/.*= *\([0-9.]*\).*/\1/')
	local north_az=$(grep -w "NORTH_AZIMUTH" "$BW_LABEL_FILE" | head -1 | sed 's/.*= *\([0-9.]*\).*/\1/')

	if [[ -n "$sub_solar" && -n "$north_az" ]]; then
		SUN_AZIMUTH=$(echo "$sub_solar + $north_az - 180" | bc -l)
	fi

	rm -f "$BW_LABEL_FILE"

	return 0
}

# To extract scaling factor and offset from Orthoimage label file
extract_scaling_from_label() {
	echo ""
	echo "4. Extracting scaling factors from: $ORTHO_LABEL_FILE"

	if [[ -z "$ORTHO_LABEL_FILE" || ! -f "$ORTHO_LABEL_FILE" ]]; then
		echo "Warning: Orthoimage label file NOT found."
		return 1
	fi

	local du2fl=$(grep -w "SCALING_FACTOR" "$ORTHO_LABEL_FILE" | tail -1 | sed 's/.*= *\([0-9.]*\).*/\1/')
	local floff=$(grep -w "OFFSET" "$ORTHO_LABEL_FILE" | tail -1 | sed 's/.*= *\([0-9.]*\).*/\1/')

	if [[ -n "$du2fl" ]]; then
		DU2FL="$du2fl"
	fi

	if [[ -n "$floff" ]]; then
		FLOFF="$floff"
	fi

	rm -f "$ORTHO_LABEL_FILE"

	return 0
}

BLOCK_SIZE_MANUAL=false

while [[ $# -gt 0 ]]; do
	case $1 in
	--dem-file)
		DEM_FILE="$2"
		DEM_NAME=$(basename "$2")
		shift 2
		;;
	-o | --output)
		OUTPUT_FILE="$2"
		shift 2
		;;
	-h | --help)
		show_help
		exit 0
		;;
	--use-image2)
		USE_IMG2=true
		shift
		;;
	--image-file)
		IMAGE_FILE="$2"
		shift 2
		;;
	--mask-file)
		MASK_FILE="$2"
		shift 2
		;;
	--phase1)
		validate_bool "$2" "--phase1"
		PHASE1="$2"
		shift 2
		;;
	--phase2)
		validate_bool "$2" "--phase2"
		PHASE2="$2"
		shift 2
		;;
	--phase3)
		validate_bool "$2" "--phase3"
		PHASE3="$2"
		shift 2
		;;
	--restore_save_file)
		validate_bool "$2" "--restore_save_file"
		RESTORE_SAVE_FILE="$2"
		shift 2
		;;
	--restitution_albedo_hi)
		validate_bool "$2" "--restitution_albedo_hi"
		RESTITUTION_ALBEDO_HI="$2"
		shift 2
		;;
	--scale)
		SCALE="$2"
		shift 2
		;;
	--convol)
		CONVOL="$2"
		shift 2
		;;
	--factor_bin)
		FACTOR_BIN="$2"
		shift 2
		;;
	--border_size)
		BORDER_SIZE="$2"
		shift 2
		;;
	--block_size)
		IFS=',' read -r BLOCK_SIZE_X BLOCK_SIZE_Y <<<"$2"
		BLOCK_SIZE_MANUAL=true
		shift 2
		;;
	*)
		echo "Unrecognized option: $1"
		show_help
		exit 1
		;;
	esac
done

if [[ -z "$DEM_FILE" ]]; then
	echo "Error: DEM file is required (--dem-file <DEM_FILE>)"
	show_help
	exit 1
fi

parse_dem_name "$DEM_NAME"

get_dem_dimensions "$DEM_FILE"

if [[ "$BLOCK_SIZE_MANUAL" = false ]]; then
	calculate_block_size "$CROP_END_X" "$CROP_END_Y" "$BORDER_SIZE" "$BORDER_SIZE"
fi

download_labels "$ORBIT_PREFIX1" "$ORBIT1" "$LATBIN1" "$ORBIT_PREFIX2" "$ORBIT2" "$LATBIN2" "$INSTITUTION" "$VERSION"

extract_geometry_from_label

extract_scaling_from_label

if [[ -z "$OUTPUT_FILE" ]]; then
	OUTPUT_FILE="conf_HDEM_${IMAGE_ORBIT}_${IMAGE_LATBIN}.json"
	echo ""
	echo "5. Auto-generated output file: $OUTPUT_FILE"
fi

if [[ -n "$IMAGE_FILE" ]]; then
	IMAGE_FILE_NAME="$IMAGE_FILE"
else
	IMAGE_FILE_NAME="${IMAGE_ID}_RED_${INSTITUTION}_${VERSION}_ORTHO.tif"
fi

if [[ -n "$MASK_FILE" ]]; then
	MASK_FILE_NAME="$MASK_FILE"
else
	MASK_FILE_NAME="$IMAGE_FILE_NAME"
fi

# Generate the tab_aod array (from 0.1 to 1.92)
TAB_AOD=""
for i in $(seq 0 26); do
	val=$(echo "0.1 + $i * 0.07" | bc -l)
	formatted=$(printf "%.2f" "$val")
	if [[ -n "$TAB_AOD" ]]; then
		TAB_AOD="$TAB_AOD,
    $formatted"
	else
		TAB_AOD="$formatted"
	fi
done

# Generate JSON
cat >"$OUTPUT_FILE" <<EOF
{
  "path_root": "$PATH_ROOT",
  "prefix": "$PREFIX",
  "sensor": {
    "spsf_names": "",
    "channel": "$CHANNEL",
    "tab_ww_data": {
      "start": 1,
      "step": 1,
      "end": 1
    },
    "band_wave": [
      $BAND_WAVE
    ]
  },
  "materials": {
    "database_name": "$DATABASE_NAME",
    "select_macro_mixt": "",
    "select_intim_mixt": "",
    "bck_abundance": $BCK_ABUNDANCE,
    "flag_bck_macro": $FLAG_BCK_MACRO,
    "namecubprop": "",
    "select_background": "'data_exp',[2]",
    "map_texture_name": ""
  },
  "terrain": {
    "DEM_file_name": "$DEM_FILE",
    "crop_begin_x": $CROP_BEGIN_X,
    "crop_end_x": $CROP_END_X,
    "crop_begin_y": $CROP_BEGIN_Y,
    "crop_end_y": $CROP_END_Y,
    "gsd": $GSD,
    "geo_aux_cube_name": "",
    "no_data_DEM": "$NO_DATA_DEM",
    "molafilename": ""
  },
  "atmosphere": {
    "tau_ref": $TAU_REF,
    "tab_aod": [
      $TAB_AOD
    ],
    "regress_line": [
      0,
      $TAU_REF
    ],
    "Hscale": $HSCALE,
    "atmospheric_LUT": "$ATMOSPHERIC_LUT"
},
  "geometry": {
    "SZA": $SZA,
    "sun_azimuth": $SUN_AZIMUTH,
    "VZA": $VZA,
    "phase_angle": $PHASE_ANGLE,
    "threshold_sky": $THRESHOLD_SKY
  },
  "modeling": {
    "env_effects": $ENV_EFFECTS,
    "phase1": $PHASE1,
    "phase2": $PHASE2,
    "phase3": $PHASE3,
    "lambda1": $LAMBDA1,
    "lambda2": $LAMBDA2,
    "fact": $FACT,
    "scale": $SCALE,
    "convol": $CONVOL,
    "factor_bin": $FACTOR_BIN,
    "block_size": [
      $BLOCK_SIZE_Y,
      $BLOCK_SIZE_X
    ],
    "BorderSize": [
      $BORDER_SIZE,
      $BORDER_SIZE
    ],
    "maxiters_kL": $MAXITERS_KL,
    "maxiters_z": $MAXITERS_Z,
    "max_tol": $MAX_TOL,
    "spect_scale_factor": [
      $SPECT_SCALE_FACTOR
    ],
    "spect_path_rad_ex": [
      $SPECT_PATH_RAD_EX
    ],
    "restore_save_file": $RESTORE_SAVE_FILE,
    "restitution_albedo_hi": $RESTITUTION_ALBEDO_HI
  },
  "image": {
    "image_file_name": "$IMAGE_FILE_NAME",
    "mask_file_name": "$MASK_FILE_NAME",
    "DU2FL": $DU2FL,
    "FLOFF": $FLOFF,
    "boost_factor": $BOOST_FACTOR,
    "no_data_img": $NO_DATA_IMG
  }
}
EOF
