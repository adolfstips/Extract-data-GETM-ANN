#!/bin/bash

#=============================================================================
# SCRIPT: process_model_output.sh
#
# DESCRIPTION:
# This script extracts, processes, and aggregates data from monthly 3D
# NetCDF model output files. This version is simplified based on user
# feedback and uses NCO to handle dimension squeezing.
#
# WORKFLOW:
# 1. For each month in a given year range:
#    a. Extracts the bottom level (level 1) for oxygen.
#    b. Uses 'ncwa' to remove the singleton level dimension, creating a 2D field.
#    c. Renames the bottom oxygen variable to avoid naming conflicts.
#    d. Regrids the top 20 meters of the water column using 'gvc2zax'.
#    e. Calculates the vertical mean (0-20m) for a list of surface variables.
#    f. Merges the 2D bottom oxygen and 2D surface means into a single monthly file.
# 2. For each year, merges the 12 monthly files into a single timeseries file.
# 3. Calculates the annual mean from that yearly timeseries file.
# 4. Concatenates all annual mean files into a single final time-series file.
#
# REQUIREMENTS:
# - CDO (Climate Data Operators)
# - NCO (NetCDF Operators), specifically 'ncwa'
# - gvc2zax (custom tool for vertical regridding)
#
# USAGE:
# ./process_model_output.sh
#=============================================================================

# --- Strict Mode ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u

#=============================================================================
# --- CONFIGURATION ---
# Adjust these variables to match your setup.
#=============================================================================

REGION="Blacksea"

# Time period
FIRST_YEAR=2000
LAST_YEAR=2005

# Time period
FIRST_YEAR=2010
LAST_YEAR=2010

# Directory structure
# IMPORTANT: Assumes your input files are in INPUT_DIR/
# Example input file path: /path/to/data/model_output_200001.nc
INPUT_DIR="./Blacksea_data/"
# Directory for intermediate and final files
OUTPUT_DIR="./ann_data"
# A prefix for your input files if they have one
FILE_PREFIX="NO3_PO4_PL_PS_O2_TEMP_SALT_hmean_"

# Path to the bathymetry file required by gvc2zax
BATHY_FILE="./Blacksea_data/Blacksea_bathymetry.nc"

# Variables to process
# Note: CDO expects a comma-separated list with no spaces.
VARS_SURF_MEAN="nitrate,oxygen,phosphate,phytolarge,phytosmall,temperature,salinity"
VARS_SURF_MEAN="jrc_bsem_ni,jrc_bsem_o2,jrc_bsem_po,jrc_bsem_pl,jrc_bsem_ps,tempmean,saltmean"
VAR_BOTTOM="jrc_bsem_o2"

# Model levels, Level = 1 = Bottom, (level 0 not used!)
# As per the prompt, the model has 69 levels. This is for reference.
N_LEVELS=69

#=============================================================================
# --- SCRIPT SETUP ---
#=============================================================================

echo "--- Starting NetCDF Processing Script ---"

# Create the output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"
echo "Output will be saved in: ${OUTPUT_DIR}"

# Create a temporary directory for intermediate monthly files
TEMP_DIR=$(mktemp -d)
#TEMP_DIR="./temp_dir/"
echo "Temporary files will be stored in: ${TEMP_DIR}"

# Function to clean up temporary directory on exit
cleanup() {
    echo "Cleaning up temporary directory..."
    rm -rf "${TEMP_DIR}"
    echo "Cleanup complete."
}
trap cleanup EXIT

# Check for required command-line tools
command -v cdo >/dev/null 2>&1 || { echo >&2 "CDO is not installed. Aborting."; exit 1; }
command -v ncwa >/dev/null 2>&1 || { echo >&2 "NCO (ncwa) is not installed. Aborting."; exit 1; }
command -v gvc2zax >/dev/null 2>&1 || { echo >&2 "gvc2zax is not found in your PATH. Aborting."; exit 1; }
echo "Required tools (cdo, ncwa, gvc2zax) found."


#=============================================================================
# --- MAIN PROCESSING LOOP ---
#=============================================================================

# Loop over each year
for YEAR in $(seq "${FIRST_YEAR}" "${LAST_YEAR}"); do
    echo "----------------------------------------"
    echo "Processing Year: ${YEAR}"
    echo "----------------------------------------"

    # Loop over each month (01, 02, ..., 12)
    for MONTH in $(seq -w 1 12); do
        echo "  - Processing Month: ${MONTH}"

        # --- Define file paths ---
        IFILE="${INPUT_DIR}/${FILE_PREFIX}${YEAR}_${MONTH}.mean.nc"

        # Check if input file exists
        if [ ! -f "${IFILE}" ]; then
            echo "    WARNING: Input file not found, skipping: ${IFILE}"
            continue
        fi

        # Intermediate files for this month
        ifile_with_bathy="${TEMP_DIR}/ifile_with_bathy_${YEAR}${MONTH}.nc"
        temp_oxy_with_level="${TEMP_DIR}/temp_oxy_lev_${YEAR}${MONTH}.nc"
        temp_oxy_squeezed="${TEMP_DIR}/temp_oxy_squeezed_${YEAR}${MONTH}.nc"
        local_bottom_oxy="${TEMP_DIR}/bottom_oxy_${YEAR}${MONTH}.nc"
        local_regridded_surf="${TEMP_DIR}/regridded_surf_${YEAR}${MONTH}.nc"
        local_vertmean_surf="${TEMP_DIR}/vertmean_surf_${YEAR}${MONTH}.nc"
        monthly_merged_file="${TEMP_DIR}/merged_2d_${YEAR}${MONTH}.nc"

        # --- Step 1: Extract and process bottom level oxygen ---
        echo "    Step 1: Extracting and processing bottom oxygen..."
        # a) Select the bottom level (level 1)
        cdo -sellevel,1 -selname,"${VAR_BOTTOM}" "${IFILE}" "${temp_oxy_with_level}"
        # b) Remove the singleton 'level' dimension using NCO's ncwa
        ncwa -O -a level "${temp_oxy_with_level}" "${temp_oxy_squeezed}"
        # c) Rename the variable to avoid conflicts
        cdo -chname,"${VAR_BOTTOM},${VAR_BOTTOM}_bottom" "${temp_oxy_squeezed}" "${local_bottom_oxy}"

        # ---  Step 2: Add bathymetry data, should be redundant---
        echo "    Step 2: Adding bathymetry data..."
        # Now merge the two files, which have identical gridls anndefinition
        cdo merge "${IFILE}" "${BATHY_FILE}" "${ifile_with_bathy}"

        # --- Step 2: Regrid surface layer (0-20m) using gvc2zax ---
        # Assuming the input file now contains the necessary bathymetry variable.
        echo "    Step 2: Regridding surface layer with gvc2zax..."
        #gvc2zax -z 20,0.5,40 -p -s -i "${IFILE}" "${local_regridded_surf}"

        gvc2zax -z 20,0.5,40 -p -s -i "${ifile_with_bathy}" "${local_regridded_surf}"

        # --- Step 3: Calculate vertical mean for surface variables ---
        echo "    Step 3: Calculating vertical mean of surface variables..."
        cdo -vertmean -selname,"${VARS_SURF_MEAN}" "${local_regridded_surf}" "${local_vertmean_surf}"
        
        # --- Step 4: Merge bottom oxygen and surface means ---
        # Both files are now 2D, so they will merge into a single timestep.
        echo "    Step 4: Merging into a single monthly 2D file..."
        cdo merge "${local_vertmean_surf}" "${local_bottom_oxy}" "${monthly_merged_file}"

    done # End of month loop

    # --- Step 5 & 6: Calculate annual mean (two-step process) ---
    # Check if any monthly files were created for the year before proceeding
    if [ -n "$(find "${TEMP_DIR}" -name "merged_2d_${YEAR}*.nc")" ]; then
        echo "Calculating annual mean for ${YEAR}..."
        yearly_timeseries_file="${TEMP_DIR}/timeseries_${YEAR}.nc"
        annual_mean_file="${OUTPUT_DIR}/annual_mean_${YEAR}.nc"

        # Step 5: Merge all monthly files for the year into one file
        cdo mergetime "${TEMP_DIR}/merged_2d_${YEAR}"*.nc "${yearly_timeseries_file}"

        # Step 6: Calculate the yearmean from the single timeseries file
        cdo --timestat_date middle timselmean,12 "${yearly_timeseries_file}" "${annual_mean_file}"
        
        echo "Generated annual mean file: ${annual_mean_file}"
    else
        echo "No monthly files processed for ${YEAR}. Cannot create annual mean."
    fi

done # End of year loop


# --- Step 7: Concatenate all annual files into one time series ---
echo "----------------------------------------"
echo "Finalizing: Concatenating all annual files..."
final_output_file="${OUTPUT_DIR}/${REGION}_timeseries_${FIRST_YEAR}-${LAST_YEAR}.nc"

# Check if any annual files were created before proceeding
if [ -n "$(find "${OUTPUT_DIR}" -name "annual_mean_*.nc")" ]; then
    cdo mergetime "${OUTPUT_DIR}/annual_mean_"*.nc "${final_output_file}"
    echo "Successfully created final output file: ${final_output_file}"

    # Optional: Clean up the intermediate annual files
    echo "Cleaning up intermediate annual files..."
    rm -f "${OUTPUT_DIR}/annual_mean_"*.nc
else
    echo "No annual mean files found. Final concatenation skipped."
fi

echo "----------------------------------------"
echo "--- Script finished successfully! ---"
echo "----------------------------------------"



