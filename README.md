# HDEM-Mars Setup Shell Scripts

Shell scripts for setting up and processing HiRISE DTM (Digital Terrain Model) data with HDEM-Mars.

**Contact:** euibin@lpl.arizona.edu

## Workflow Overview

```
1. fetch_dtm_list.sh   : Fetch all available DTMs from HiRISE PDS
▏        ↓
2. my_find_dtm.sh      : Find DTM name by image ID
▏        ↓
3. setup.sh            : Download DTM/orthoimage and set up project directory
▏        ↓
4. generate_conf.sh    : Generate configuration JSON for HDEM-Mars
```

---

## 1. fetch_dtm_list.sh

Fetches all available DTM names from the HiRISE PDS website and saves them to a CSV file.

Run this to create a local database of all available DTMs.

### Usage

```bash
./fetch_dtm_list.sh [OUTPUT_FILE]
```

### Arguments

- `OUTPUT_FILE` : Output CSV file name (default `dtm_list.csv`)

### Output CSV Format

| Column      | Description                              |
| ----------- | ---------------------------------------- |
| `dtm_name`  | DTM file name (without extension)        |
| `image_id1` | First image ID (e.g., `PSP_001336_1560`) |
| `image_id2` | Second image ID                          |
| `url`       | Direct download URL                      |

### Examples

```bash
./fetch_dtm_list.sh
./fetch_dtm_list.sh my_dtm_list.csv
```

### Notes

- May take several minutes while it crawls the HiRISE PDS directory structure

---

## 2. find_dtm.sh

Finds DTM name(s) that contain a given HiRISE image ID by searching the `dtm_list.csv` file.

Use this to findd which DTMs are availabe for your image of interest.

### Usage

```bash
./find_dtm.sh <IMAGE_ID> [OPTIONS]
```

### Arguments

- `IMAGE_ID` : HiRISE image ID (e.g., `ESP_015947_1370`)

### Options

| Option                  | Description                                     |
| ----------------------- | ----------------------------------------------- |
| `-f, --file <CSV_FILE>` | Use a custom CSV file instead of `dtm_list.csv` |
| `-h, --help`            | Show help message                               |

### Examples

```bash
./find_dtm.sh ESP_015947_1370
./find_dtm.sh -f my_dtm_list PSP_001336_1560
```

### Output

```
Found 2 DTM(s) for image ID: PSP_001336_1560

DTEEC_001336_1560_001535_1560_U01
DTEEC_001336_1560_002313_1560_A01
```

### Prerequisites

Run `fetch_dtm_list.sh` first to generate the `dtm_list.csv` file.

---

## 3. Setup.sh

Sets up a project directory for HDEM-Mars processing.

Downloads DTM and optionally orthoimage from HiRISE PDS, converts them to TIF format.

### Usage

```bash
./setup.sh <DTM_NAME> [OPTIONS]
```

### Arguments

- `DTM_NAME` : DTM file name (e.g., `DTEEC_001336_1560_002313_1560_A01`)
  - Can be provided with or without extension (`.tif` or `.IMG`)

### Options

| Option           | Description                                |
| ---------------- | ------------------------------------------ |
| `--image <1\|2>` | Download orthoimage for image 1 or image 2 |
| `-h, --help`     | Show help message                          |

### How it works

1. Check if DTM exists in current directory.
2. If not, check if a directory named `DTM_NAME` exists and look inside
3. If DTM not found, download from HiRISE PDS
4. Download orthoimage if `--image` is specified
5. Convert IMG (DTM) and JP2 (orthoimage) to TIF format using GDAL
6. Create project directory and move files + `generate_conf.sh` into it

### Examples

```bash
./setup.sh DTEEC_015947_1370_051036_1370_A01
./setup.sh DTEEC_001336_1560_002313_1560_A01 --image 1
./setup.sh DTEEC_001336_1560_002313_1560_A01.IMG --image 2
```

### Output Structure (./setup.sh DTEEC_015947_1370_051036_1370_A01 --image 1)

```
./DTEEC_015947_1370_051036_1370_A01/
├── DTEEC_015947_1370_051036_1370_A01.tif      # DTM file
├── ESP_015947_1370_RED_A01_ORTHO.tif          # Orthoimage
└── generate_conf.sh                           # Copy of config generator
```

### Dependencies

- `curl` : For downloading files
- `gdal_translate` : For format conversion (auto-installed if not available)

---

## 4. generate_conf.sh

Generates a configuration JSON file for HDEM-Mars based on a DEM file.

Automatically extracts geometry and scaling parameters from HiRISE label files.

### Configuration (Required)

Before running, edit the script to set the following paths at the top of the file:

```bash
PATH_ROOT="/path/to/hdem-mars/"
DATABASE_NAME="/path/to/Hapke-RTLSR.nc/"
ATMOSPHERIC_LUT="/path/to/LUT_derived_quantities_spectral_Wolff_V_highres.nc/"
```

- `PATH_ROOT` : Root directory of your HDEM-Mars installation
- `DATABASE_NAME` : Path to BRDF database file (relative to `PATH_ROOT`)
- `ATMOSPHERIC_lUT` : Path to atmospheric lookup table (relative to `PATH_ROOT`)

### Usage

```bash
./generate_conf.sh --dem-file <DEM_FILE> [OPTIONS]
```

### Required

- `--dem-file <DEM_FILE>` : Path to the DEM file (e.g., `./DTEEC_015947_1370_051036_1370_A01.tif`)

### DEM Filename Format

```
DTEab_cccccc_dddd_eeeeee_ffff_ghh[_SUFFIX].tif

- a: projection (E: Equirectangular, P: Polar Stereographic)
- b: grid spacing (A: 0.25 m, B: 0.5 m, C: 1 m, D: 2 m)
- cccccc: Image 1 orbit number (6 digits)
- dddd: Image 1 latitude bin
- eeeeee: Image 2 orbit number (6 digits)
- ffff: Image 2 latitude bin
- g: producing institution
- hh: version number (2 digits)
```

### Options

| Option                       | Description                | Default                      |
| ---------------------------- | -------------------------- | ---------------------------- |
| `-o, --output <FILE>`        | Output JSON file name      | Auto-generated               |
| `--use-image2`               | Use Image 2 for processing | Image 1                      |
| `--image-file <FILE>`        | Orthoimage file name       | Auto-generated with DEM name |
| `--mask-file <FILE>`         | Mask file name             | Same as orthoimage           |
| `--scale <VALUE>`            | Target scale factor        | 0                            |
| `--convol <VALUE>`           | Convolution kernel size    | 4                            |
| `--factor_bin <VALUE>`       | Binning factor             | 1                            |
| `--border_size <VALUE>`      | Border size in pixels      | 30                           |
| `--block_size <X>,<Y>`       | Block size for processing  | Auto-calculated              |
| `--phase1 <BOOL>`            | Enable phase 1 modeling    | true                         |
| `--phase2 <BOOL>`            | Enable phase 2 modeling    | false                        |
| `--phase3 <BOOL>`            | Enable phase 3 modeling    | false                        |
| `--restore_save_file <BOOL>` | Restore from previous save | false                        |

### Examples

```bash
./generate_conf.sh --dem-file DTEEC_015947_1370_051036_1370_A01.tif
./generate_conf.sh --dem-file DTEEC_015947_1370_051036_1370_A01.tif --use-image2
./generate_conf.sh --DTEEC_015947_1370_051036_1370_A01.tif -o my_config.json
```

### Dependencies

- `tiffinfo` : For reading DEM dimensions (auto-installed if not available)
- `curl` : For downloading label files
- `bc` : For arithmetic calculations
