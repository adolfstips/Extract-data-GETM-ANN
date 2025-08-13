# Extract-data-GETM-ANN

Shell script for extracting model data from GETM for developing ANN forecasting TTI



\#=============================================================================

\# SCRIPT: blacksea\_netcdf\_data\_extration\_ANN.sh

\#

\# DESCRIPTION:

\# This script extracts, processes, and aggregates data from monthly 3D

\# NetCDF model output files. This version is simplified based on user

\# feedback and uses NCO to handle dimension squeezing.

\#

\# WORKFLOW:

\# 1. For each month in a given year range:

\#    a. Extracts the bottom level (level 1) for oxygen.

\#    b. Uses 'ncwa' to remove the singleton level dimension, creating a 2D field.

\#    c. Renames the bottom oxygen variable to avoid naming conflicts.

\#    d. Regrids the top 20 meters of the water column using 'gvc2zax'.

\#    e. Calculates the vertical mean (0-20m) for a list of surface variables.

\#    f. Merges the 2D bottom oxygen and 2D surface means into a single monthly file.

\# 2. For each year, merges the 12 monthly files into a single timeseries file.

\# 3. Calculates the annual mean from that yearly timeseries file.

\# 4. Concatenates all annual mean files into a single final time-series file.

\#

\# REQUIREMENTS:

\# - CDO (Climate Data Operators)

\# - NCO (NetCDF Operators), specifically 'ncwa'

\# - gvc2zax (custom tool for vertical regridding)

\#

\# USAGE:

\# ./process\_model\_output.sh

\#=============================================================================



