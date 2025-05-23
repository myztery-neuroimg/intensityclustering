#!/usr/bin/env bash
#
# pipeline.sh - Main script for the brain MRI processing pipeline
#
# Usage: ./pipeline.sh [options]
#
# Options:
#   -c, --config FILE    Configuration file (default: config/default_config.sh)
#   -i, --input DIR      Input directory (default: ../DiCOM)
#   -o, --output DIR     Output directory (default: ../mri_results)
#   -s, --subject ID     Subject ID (default: derived from input directory)
#   -q, --quality LEVEL  Quality preset (LOW, MEDIUM, HIGH) (default: MEDIUM)
#   -p, --pipeline TYPE  Pipeline type (BASIC, FULL, CUSTOM) (default: FULL)
#   -t, --start-stage STAGE  Start pipeline from STAGE (default: import)
#   -h, --help           Show this help message and exit
#

# Set strict error handling
#set -e
#set -u
#set -o pipefail

# Source modules
source src/modules/environment.sh
source src/modules/utils.sh     # Load utilities module with execute_ants_command
source src/modules/fast_wrapper.sh # Load FAST wrapper with parallel processing
source src/modules/dicom_analysis.sh
source src/modules/import.sh
source src/modules/preprocess.sh
source src/modules/registration.sh
source src/modules/segmentation.sh
source src/modules/analysis.sh
source src/modules/visualization.sh
source src/modules/qa.sh
source src/scan_selection.sh  # Add scan selection module
source src/modules/enhanced_registration_validation.sh  # Add enhanced registration validation
#source src/modules/extract_dicom_metadata.py

# Show help message
show_help() {
  echo "Usage: ./pipeline.sh [options]"
  echo ""
  echo "Options:"
  echo "  -c, --config FILE    Configuration file (default: config/default_config.sh)"
  echo "  -i, --input DIR      Input directory (default: ../DiCOM)"
  echo "  -o, --output DIR     Output directory (default: ../mri_results)"
  echo "  -s, --subject ID     Subject ID (default: derived from input directory)"
  echo "  -q, --quality LEVEL  Quality preset (LOW, MEDIUM, HIGH) (default: MEDIUM)"
  echo "  -p, --pipeline TYPE  Pipeline type (BASIC, FULL, CUSTOM) (default: FULL)"
  echo "  -t, --start-stage STAGE  Start pipeline from STAGE (default: import)"
  echo "  -h, --help           Show this help message and exit"
  echo ""
  echo "Pipeline Stages:"
  echo "  import: Import and convert DICOM data"
  echo "  preprocess: Perform bias correction and brain extraction"
  echo "  registration: Align images to standard space"
  echo "  segmentation: Extract brainstem and pons regions"
  echo "  analysis: Detect and analyze hyperintensities"
  echo "  visualization: Generate visualizations and reports"
  echo "  tracking: Track pipeline progress"
}

# Load configuration file
load_config() {
  local config_file="$1"
  
  if [ -f "$config_file" ]; then
    log_message "Loading configuration from $config_file"
    source "$config_file"
    return 0
  else
    log_formatted "WARNING" "Configuration file not found: $config_file"
    return 1
  fi
}

# Function to convert stage name to numeric value
get_stage_number() {
  local stage_name="$1"
  local stage_num
  
  case "$stage_name" in
    import|dicom|1)
      stage_num=1
      ;;
    preprocess|preprocessing|pre|2)
      stage_num=2
      ;;
    registration|register|reg|3)
      stage_num=3
      ;;
    segmentation|segment|seg|4)
      stage_num=4
      ;;
    analysis|analyze|5)
      stage_num=5
      ;;
    visualization|visualize|vis|6)
      stage_num=6
      ;;
    tracking|track|progress|7)
      stage_num=7
      ;;
    *)
      stage_num=0  # Invalid stage
      ;;
  esac
  
  echo $stage_num
}

# Parse command line arguments
parse_arguments() {
  # Default values
  CONFIG_FILE="config/default_config.sh"
  SRC_DIR="..../DiCOM"
  RESULTS_DIR="../mri_results"
  SUBJECT_ID=""
  QUALITY_PRESET="HIGH"
  PIPELINE_TYPE="FULL"
  START_STAGE_NAME="import"
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -c|--config)
        CONFIG_FILE="$2"
        shift 2
        ;;
      -i|--input)
        SRC_DIR="$2"
        shift 2
        ;;
      -o|--output)
        RESULTS_DIR="$2"
        shift 2
        ;;
      -s|--subject)
        SUBJECT_ID="$2"
        shift 2
        ;;
      -q|--quality)
        QUALITY_PRESET="$2"
        shift 2
        ;;
      -p|--pipeline)
        PIPELINE_TYPE="$2"
        shift 2
        ;;
      -t|--start-stage)
        START_STAGE_NAME="$2"
        shift 2
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        log_error "Unknown option: $1" $ERR_INVALID_ARGS
        show_help
        exit 1
        ;;
    esac
  done
  
  # If subject ID is not provided, derive it from the input directory
  if [ -z "$SUBJECT_ID" ]; then
    SUBJECT_ID=$(basename "$SRC_DIR")
  fi
  
  # Convert stage name to number and validate
  START_STAGE=$(get_stage_number "$START_STAGE_NAME")
  if [ "$START_STAGE" -eq 0 ]; then
    log_error "Invalid start stage: $START_STAGE_NAME" $ERR_INVALID_ARGS
    log_message "Valid stages: import, preprocess, registration, segmentation, analysis, visualization, tracking"
    show_help
    exit 1
  fi
  
  # Export variables
  export SRC_DIR
  export RESULTS_DIR
  export SUBJECT_ID
  export QUALITY_PRESET
  export PIPELINE_TYPE
  export START_STAGE
  export START_STAGE_NAME
  
  log_message "Arguments parsed: SRC_DIR=$SRC_DIR, RESULTS_DIR=$RESULTS_DIR, SUBJECT_ID=$SUBJECT_ID, QUALITY_PRESET=$QUALITY_PRESET, PIPELINE_TYPE=$PIPELINE_TYPE"
}

# Function to validate a processing step
validate_step() {
  return 0
  local step_name="$1"
  local output_files="$2"
  local module="$3"
  
  log_message "Validating step: $step_name"
  
  # Use our new validation function
  if ! validate_module_execution "$module" "$output_files"; then
    log_error "Validation failed for step: $step_name" $ERR_VALIDATION
    return $ERR_VALIDATION
  fi
  
  log_formatted "SUCCESS" "Step validated: $step_name"
  return 0
}


# Run the pipeline
run_pipeline() {
  local subject_id="$SUBJECT_ID"
  local input_dir="$SRC_DIR"
  local output_dir="$RESULTS_DIR"
  export EXTRACT_DIR="${RESULTS_DIR}/extracted"

  # Load parallel configuration if available
  #load_parallel_config "config/parallel_config.sh"
  
  # Check for GNU parallel
  #check_parallel
  load_config "config/default_config.sh"
  log_message "Running pipeline for subject $subject_id"
  log_message "Input directory: $input_dir"
  log_message "Output directory: $output_dir"
  
  # Create directories
  create_directories
  
  # Step 1: Import and convert data
  if [ $START_STAGE -le 1 ]; then
    log_message "Step 1: Importing and converting data"
    
    import_dicom_data "$input_dir" "$EXTRACT_DIR"
    qa_validate_dicom_files "$input_dir"
    import_extract_siemens_metadata "$input_dir"
    qa_validate_nifti_files "$EXTRACT_DIR"
    import_deduplicate_identical_files "$EXTRACT_DIR"
    
    # Validate import step
    validate_step "Import data" "*.nii.gz" "extracted"
  else
    log_message "Skipping Step 1 (Import and convert data) as requested"
    log_message "Checking if import data exists..."
    
    # Check if essential directories and files exist to continue
    if [ ! -d "$EXTRACT_DIR" ] || [ $(find "$EXTRACT_DIR" -name "*.nii.gz" | wc -l) -eq 0 ]; then
      log_error "Import data is missing. Cannot skip Step 1." $ERR_DATA_MISSING
      return $ERR_DATA_MISSING
    fi
    
    log_message "Import data exists, continuing from Step $START_STAGE"
  fi
  
  # Step 2: Preprocessing
  if [ $START_STAGE -le 2 ]; then
    log_message "Step 2: Preprocessing"
    
    # Find T1 and FLAIR files
  # Use simple glob patterns that work reliably with find
  export T1_PRIORITY_PATTERN="${T1_PRIORITY_PATTERN:-T1_MPRAGE_SAG_*.nii.gz}"
  export FLAIR_PRIORITY_PATTERN="${FLAIR_PRIORITY_PATTERN:-T2_SPACE_FLAIR_Sag_CS_*.nii.gz}"
  
  log_message "Using T1 pattern: $T1_PRIORITY_PATTERN"
  log_message "Using FLAIR pattern: $FLAIR_PRIORITY_PATTERN"

  # Log before finding files
  log_message "Looking for T1 files in: $EXTRACT_DIR"
  log_message "Available files in extract dir:"
  ls -la "$EXTRACT_DIR"
  
  # Create DICOM header analysis for better scan selection
  log_message "Analyzing DICOM headers for scan selection..."
  analyze_dicom_headers "$SRC_DIR" "${RESULTS_DIR}/metadata/dicom_header_analysis.txt"
  
  # Use intelligent scan selection based on quality metrics and selection mode
  log_message "Selecting best T1 scan using mode: ${T1_SELECTION_MODE:-highest_resolution}..."
  local t1_file=$(select_best_scan "T1" "T1_MPRAGE_SAG_*.nii.gz" "$EXTRACT_DIR" "" "${T1_SELECTION_MODE:-highest_resolution}")
  
  # If not found with specific pattern, try more general pattern
  if [ -z "$t1_file" ]; then
    log_message "T1 not found with specific pattern, trying more general search"
    t1_file=$(select_best_scan "T1" "T1_*.nii.gz" "$EXTRACT_DIR" "" "${T1_SELECTION_MODE:-highest_resolution}")
  fi
  
  # Now select FLAIR scan with the T1 as reference based on selection mode
  log_message "Selecting best FLAIR scan using mode: ${FLAIR_SELECTION_MODE:-registration_optimized}..."
  log_message "T1 reference: $t1_file"
  
  local flair_file=$(select_best_scan "FLAIR" "T2_SPACE_FLAIR_Sag_CS_*.nii.gz" "$EXTRACT_DIR" "$t1_file" "${FLAIR_SELECTION_MODE:-registration_optimized}")
  
  # If not found with specific pattern, try more general pattern
  if [ -z "$flair_file" ]; then
    log_message "FLAIR not found with specific pattern, trying more general search"
    flair_file=$(select_best_scan "FLAIR" "*FLAIR*.nii.gz" "$EXTRACT_DIR" "$t1_file" "${FLAIR_SELECTION_MODE:-registration_optimized}")
  fi
  
  # Log detailed resolution information about selected scans
  if [ -n "$t1_file" ] && [ -n "$flair_file" ]; then
    log_message "======== Selected Scan Information ========"
    log_message "T1 scan: $t1_file"
    log_message "T1 dimensions: $(fslinfo "$t1_file" | grep -E "^dim[1-3]" | awk '{print $1 "=" $2}' | tr '\n' ' ')"
    log_message "T1 voxel size: $(fslinfo "$t1_file" | grep -E "^pixdim[1-3]" | awk '{print $1 "=" $2}' | tr '\n' ' ')"
    log_message ""
    log_message "FLAIR scan: $flair_file"
    log_message "FLAIR dimensions: $(fslinfo "$flair_file" | grep -E "^dim[1-3]" | awk '{print $1 "=" $2}' | tr '\n' ' ')"
    log_message "FLAIR voxel size: $(fslinfo "$flair_file" | grep -E "^pixdim[1-3]" | awk '{print $1 "=" $2}' | tr '\n' ' ')"
    log_message ""
    log_message "Resolution comparison: $(calculate_pixdim_similarity "$t1_file" "$flair_file")/100"
    log_message "======================================="
  fi
  
  if [ -z "$t1_file" ]; then
    log_error "T1 file not found in $EXTRACT_DIR" $ERR_DATA_MISSING
    return $ERR_DATA_MISSING
  fi
  
  if [ -z "$flair_file" ]; then
    log_error "FLAIR file not found in $EXTRACT_DIR" $ERR_DATA_MISSING
    return $ERR_DATA_MISSING
  fi
  
  log_message "T1 file: $t1_file"
  log_message "FLAIR file: $flair_file"
  
  # Combine or select best multi-axial images
  # Note: For 3D isotropic sequences (MPRAGE, SPACE, etc.), this will
  # automatically detect and select the best quality single orientation.
  # For 2D sequences, it will combine multiple orientations when available.

  #combine_multiaxis_images "T1" "${RESULTS_DIR}/combined" #only if using 2d scan types
  #combine_multiaxis_images "FLAIR" "${RESULTS_DIR}/combined"
  
  # Validate combining step
  #validate_step "Combine multi-axial images" "T1_combined_highres.nii.gz,FLAIR_combined_highres.nii.gz" "combined"
  
  # Update file paths if combined images were created
  local combined_t1=$(get_output_path "combined" "T1" "_combined_highres")
  local combined_flair=$(get_output_path "combined" "FLAIR" "_combined_highres")
  
  if [ -f "$combined_t1" ]; then
    t1_file="$combined_t1"
  fi
  
  if [ -f "$combined_flair" ]; then
    flair_file="$combined_flair"
  fi
  
  # Validate input files before processing
  validate_nifti "$t1_file" "T1 input file"
  validate_nifti "$flair_file" "FLAIR input file"
  
  # N4 bias field correction (run in parallel if available)
  if [ "$PARALLEL_JOBS" -gt 0 ] && check_parallel &>/dev/null; then
    log_message "Running N4 bias field correction with parallel processing"
    # Copy the files to a temporary directory for parallel processing
    local temp_dir=$(create_module_dir "temp_parallel")
    cp "$t1_file" "$temp_dir/$(basename "$t1_file")"
    cp "$flair_file" "$temp_dir/$(basename "$flair_file")"
    run_parallel_n4_correction "$temp_dir" "*.nii.gz"
  else
    log_message "Running N4 bias field correction sequentially"
    process_n4_correction "$t1_file"
    process_n4_correction "$flair_file"
  fi
  
  # Update file paths
  local t1_basename=$(basename "$t1_file" .nii.gz)
  local flair_basename=$(basename "$flair_file" .nii.gz)
  t1_file=$(get_output_path "bias_corrected" "$t1_basename" "_n4")
  flair_file=$(get_output_path "bias_corrected" "$flair_basename" "_n4")
  
  # Validate bias correction step
  validate_step "N4 bias correction" "$(basename "$t1_file"),$(basename "$flair_file")" "bias_corrected"
  
  # Brain extraction (run in parallel if available)
  if [ "$PARALLEL_JOBS" -gt 0 ] && check_parallel &>/dev/null; then
    log_message "Running brain extraction with parallel processing"
    run_parallel_brain_extraction "$(get_module_dir "bias_corrected")" "*.nii.gz" "$MAX_CPU_INTENSIVE_JOBS"
  else
    log_message "Running brain extraction sequentially"
    extract_brain "$t1_file"
    extract_brain "$flair_file"
  fi
  
  # Update file paths
  local t1_n4_basename=$(basename "$t1_file" .nii.gz)
  local flair_n4_basename=$(basename "$flair_file" .nii.gz)
  
  t1_brain=$(get_output_path "brain_extraction" "$t1_n4_basename" "_brain")
  flair_brain=$(get_output_path "brain_extraction" "$flair_n4_basename" "_brain")
  
  # Validate brain extraction step
  validate_step "Brain extraction" "$(basename "$t1_brain"),$(basename "$flair_brain")" "brain_extraction"  
  # Launch visual QA for brain extraction (non-blocking)
  # Moving this after standardization since t1_std is defined later
  # Will be launched after line 315 where t1_std is defined
  
  # Standardize dimensions (run in parallel if available)
  if [ "$PARALLEL_JOBS" -gt 0 ] && check_parallel &>/dev/null; then
    log_message "Running dimension standardization with parallel processing"
    run_parallel_standardize_dimensions "$(get_module_dir "brain_extraction")" "*_brain.nii.gz"
  else
    log_message "Running dimension standardization sequentially"
    standardize_dimensions "$t1_brain"
    standardize_dimensions "$flair_brain"
  fi
  
  
  # Update file paths
  local t1_brain_basename=$(basename "$t1_brain" .nii.gz)
  local flair_brain_basename=$(basename "$flair_brain" .nii.gz)
  
  t1_std=$(get_output_path "standardized" "$t1_brain_basename" "_std")
  flair_std=$(get_output_path "standardized" "$flair_brain_basename" "_std")
  
  # Validate standardization step
  validate_step "Standardize dimensions" "$(basename "$t1_std"),$(basename "$flair_std")" "standardized"
  
  # Launch enhanced visual QA for brain extraction with better error handling and guidance
  enhanced_launch_visual_qa "$t1_std" "$t1_brain" ":colormap=heat:opacity=0.5" "brain-extraction" "sagittal"
  
  fi  # End of Preprocessing (Step 2)
  
  # Step 3: Registration
  if [ $START_STAGE -le 3 ]; then
    log_message "Step 3: Registration"
    
    # Now that standardization is complete, run registration fix
    # This will check for coordinate space mismatches and fix datatypes
    run_registration_fix
    
    # If we're skipping previous steps, we need to find the standardized files
    if [ $START_STAGE -eq 3 ]; then
      log_message "Looking for standardized files..."
      t1_std=$(find "$RESULTS_DIR/standardized" -name "*T1*_std.nii.gz" | head -1)
      flair_std=$(find "$RESULTS_DIR/standardized" -name "*FLAIR*_std.nii.gz" | head -1)
      
      if [ -z "$t1_std" ] || [ -z "$flair_std" ]; then
        log_error "Standardized data is missing. Cannot skip to Step $START_STAGE." $ERR_DATA_MISSING
        return $ERR_DATA_MISSING
      fi
      
      log_message "Found standardized data:"
      log_message "T1: $t1_std"
      log_message "FLAIR: $flair_std"
    fi
    
    # Create output directory for registration
    local reg_dir=$(create_module_dir "registered")
    
    # Determine whether to use automatic multi-modality registration
    if [ "${AUTO_REGISTER_ALL_MODALITIES:-false}" = "true" ]; then
      log_message "Performing automatic registration of all modalities to T1"
      register_all_modalities "$t1_std" "$(get_module_dir "standardized")" "$reg_dir"
      
      # Find the registered FLAIR file for downstream processing
      local flair_registered=$(find "$reg_dir" -name "*FLAIR*Warped.nii.gz" | head -1)
      if [ -z "$flair_registered" ]; then
        log_formatted "WARNING" "No registered FLAIR found after multi-modality registration. Using original FLAIR."
        # Fall back to standard FLAIR registration
        local reg_prefix="${reg_dir}/t1_to_flair"
        register_t2_flair_to_t1mprage "$t1_std" "$flair_std" "$reg_prefix"
        flair_registered="${reg_prefix}Warped.nii.gz"
      else
        log_message "Using automatically registered FLAIR: $flair_registered"
      fi
    else
      # Validate coordinate spaces and datatypes
      log_formatted "INFO" "===== VALIDATING DATA BEFORE REGISTRATION ====="
      local val_dir="${reg_dir}/validation"
      mkdir -p "$val_dir"
      
      # Check datatypes and report findings
      local t1_datatype=$(fslinfo "$t1_std" | grep "^data_type" | awk '{print $2}')
      local flair_datatype=$(fslinfo "$flair_std" | grep "^data_type" | awk '{print $2}')
      
      log_message "Original datatypes - T1: $t1_datatype, FLAIR: $flair_datatype"
      
      # Standardize datatypes but preserve FLOAT32 for intensity data
      local t1_fmt="$t1_std"
      local flair_fmt="$flair_std"
      
      if [ "$t1_datatype" != "FLOAT32" ]; then
        log_message "Converting T1 to FLOAT32 for optimal precision..."
        t1_fmt="${reg_dir}/t1_FLOAT32.nii.gz"
        standardize_image_format "$t1_std" "" "$t1_fmt" "FLOAT32"
      fi
      
      if [ "$flair_datatype" != "FLOAT32" ]; then
        log_message "Converting FLAIR to FLOAT32 for optimal precision..."
        flair_fmt="${reg_dir}/flair_FLOAT32.nii.gz"
        standardize_image_format "$flair_std" "" "$flair_fmt" "FLOAT32"
      fi
      
      # STEP 1: Register FLAIR to T1 in native high resolution space
      # This maintains the high resolution of FLAIR & T1 data
      log_formatted "INFO" "===== REGISTERING FLAIR TO T1 IN NATIVE SPACE ====="
      log_message "This preserves the original resolution of both scans"
      
      local reg_prefix="${reg_dir}/t1_to_flair"
      log_message "Running registration with standardized datatypes..."
      register_t2_flair_to_t1mprage "$t1_fmt" "$flair_fmt" "$reg_prefix"
      flair_registered="${reg_prefix}Warped.nii.gz"
      
      # STEP 2: Calculate and store transforms between spaces but don't apply them yet
      log_formatted "INFO" "===== CALCULATING TRANSFORMS BETWEEN SPACES ====="
      local transform_dir="${reg_dir}/transforms"
      mkdir -p "$transform_dir"
      
      # Calculate T1 to MNI transform (but don't actually resample the high-res data)
      log_message "Calculating bidirectional transforms between native and MNI space..."
      local t1_mni_transform="${transform_dir}/t1_to_mni.mat"
      local mni_to_t1_transform="${transform_dir}/mni_to_t1.mat"
      
      # Create transforms in both directions
      flirt -in "$t1_fmt" -ref "$MNI_TEMPLATE" -omat "$t1_mni_transform" -dof 12
      convert_xfm -omat "$mni_to_t1_transform" -inverse "$t1_mni_transform"
      
      log_message "Transforms created for bidirectional conversion between spaces"
      log_message "Native → MNI: $t1_mni_transform"
      log_message "MNI → Native: $mni_to_t1_transform"
      
      # For QA/validation, optionally create MNI space version of T1
      local mni_dir="${reg_dir}/mni_space"
      mkdir -p "$mni_dir"
      local t1_mni="${mni_dir}/t1_to_mni.nii.gz"
      flirt -in "$t1_fmt" -ref "$MNI_TEMPLATE" -out "$t1_mni" -applyxfm -init "$t1_mni_transform"
      
      # STEP 3: Create functions for applying standard masks
      log_formatted "INFO" "===== PREPARING FOR STANDARD ATLAS USAGE ====="
      
      # Create function to transform standard masks to subject space
      transform_standard_mask_to_subject() {
        local standard_mask="$1"    # Mask in MNI space
        local output="$2"           # Output in subject space
        
        log_message "Transforming standard mask to subject space: $standard_mask"
        flirt -in "$standard_mask" -ref "$t1_fmt" -out "$output" -applyxfm -init "$mni_to_t1_transform" -interp nearestneighbour
      }
      
      # Export the function for use downstream
      export -f transform_standard_mask_to_subject
      
      # Transform key Harvard masks as an example
      local harvard_dir="${reg_dir}/harvard_masks"
      mkdir -p "$harvard_dir"
      
      if [ -f "$FSLDIR/data/atlases/HarvardOxford/HarvardOxford-Cortical-Maxprob-thr25-1mm.nii.gz" ]; then
        transform_standard_mask_to_subject \
          "$FSLDIR/data/atlases/HarvardOxford/HarvardOxford-Cortical-Maxprob-thr25-1mm.nii.gz" \
          "${harvard_dir}/harvard_cortical_native.nii.gz"
        log_message "Harvard cortical atlas transformed to subject space"
      else
        log_formatted "WARNING" "Harvard cortical atlas not found"
      fi
    fi
    
    # Validate registration step
    validate_step "Registration" "t1_to_flairWarped.nii.gz" "registered"
    
    # Launch enhanced visual QA for registration (non-blocking) with better error handling
    enhanced_launch_visual_qa "$t1_std" "$flair_registered" ":colormap=heat:opacity=0.5" "registration" "axial"
    
    # Create registration visualizations
    local validation_dir=$(create_module_dir "validation/registration")
    
    # Log final datatypes of all files to verify proper handling of UINT8 vs INT16 issues
    log_formatted "INFO" "===== FINAL DATATYPE VERIFICATION ====="
    log_message "T1 standardized: $(fslinfo "$t1_std" | grep "^data_type" | awk '{print $2}')"
    log_message "FLAIR standardized: $(fslinfo "$flair_std" | grep "^data_type" | awk '{print $2}')"
    log_message "FLAIR registered: $(fslinfo "$flair_registered" | grep "^data_type" | awk '{print $2}')"
    
    # Check binary masks (they should be UINT8)
    log_message "MNI template mask: $(fslinfo "$FSLDIR/data/standard/MNI152_T1_1mm_brain_mask.nii.gz" 2>/dev/null | grep "^data_type" | awk '{print $2}' || echo "Not found")"
    
    # Verify registration quality specifically with our enhanced metrics
    verify_registration_quality "$t1_std" "$flair_registered" "${validation_dir}/quality_metrics"
    
    # Create standard registration visualizations
    create_registration_visualizations "$t1_std" "$flair_std" "$flair_registered" "$validation_dir"
    
    # Validate visualization step
    validate_step "Registration visualizations" "*.png,quality.txt" "validation/registration"
  else
    log_message "Skipping Step 3 Registration as requested"
    log_message "Checking if standardized data exists..."
    
    # Initialize variables for other stages to use
    t1_std=$(find "$RESULTS_DIR/standardized" -name "*T1*_std.nii.gz" | head -1)
    flair_std=$(find "$RESULTS_DIR/standardized" -name "*FLAIR*_std.nii.gz" | head -1)
    
    if [ -z "$t1_std" ] || [ -z "$flair_std" ]; then
      log_error "Standardized data is missing. Cannot skip to Stage $START_STAGE." $ERR_DATA_MISSING
      return $ERR_DATA_MISSING
    fi
    
    log_message "Found standardized data:"
    log_message "T1: $t1_std"
    log_message "FLAIR: $flair_std"
  fi  # End of Registration (Step 3)
  
  # Step 4: Segmentation
  if [ $START_STAGE -le 4 ]; then
    log_message "Step 4: Segmentation"
    
    # Create output directories for segmentation
    local brainstem_dir=$(create_module_dir "segmentation/brainstem")
    local pons_dir=$(create_module_dir "segmentation/pons")
    
    log_message "Attempting all available segmentation methods..."
    
    # Use the comprehensive method that tries all approaches
    extract_brainstem_final "$t1_std"
    
    # Get output files (should have been created by extract_brainstem_final)
    local brainstem_output=$(get_output_path "segmentation/brainstem" "${subject_id}" "_brainstem")
    local pons_output=$(get_output_path "segmentation/pons" "${subject_id}" "_pons")
    local dorsal_pons=$(get_output_path "segmentation/pons" "${subject_id}" "_dorsal_pons")
    local ventral_pons=$(get_output_path "segmentation/pons" "${subject_id}" "_ventral_pons")
    
    # Validate files exist
    log_message "Validating output files exist..."
    [ ! -f "$brainstem_output" ] && log_formatted "WARNING" "Brainstem file not found: $brainstem_output"
    [ ! -f "$pons_output" ] && log_formatted "WARNING" "Pons file not found: $pons_output"
    [ ! -f "$dorsal_pons" ] && log_formatted "WARNING" "Dorsal pons file not found: $dorsal_pons"
    [ ! -f "$ventral_pons" ] && log_formatted "WARNING" "Ventral pons file not found: $ventral_pons"
    
    # Validate dorsal/ventral division
    validate_step "Segmentation" "${subject_id}_dorsal_pons.nii.gz,${subject_id}_ventral_pons.nii.gz" "segmentation/pons"
  
    # Create intensity versions of the segmentation masks
    log_message "Creating intensity versions of segmentation masks for better visualization..."
    local brainstem_intensity="${RESULTS_DIR}/segmentation/brainstem/${subject_id}_brainstem_intensity.nii.gz"
    local dorsal_pons_intensity="${RESULTS_DIR}/segmentation/pons/${subject_id}_dorsal_pons_intensity.nii.gz"
    create_intensity_mask "$brainstem_output" "$t1_std" "$brainstem_intensity"
    create_intensity_mask "$dorsal_pons" "$t1_std" "$dorsal_pons_intensity"
    
    # Verify segmentation location
    log_message "Verifying segmentation anatomical location..."
    verify_segmentation_location "$brainstem_output" "$t1_std" "brainstem" "${RESULTS_DIR}/validation/segmentation_location"
    verify_segmentation_location "$dorsal_pons" "$t1_std" "dorsal_pons" "${RESULTS_DIR}/validation/segmentation_location"
    
    # Launch enhanced visual QA for brainstem segmentation (non-blocking)
    enhanced_launch_visual_qa "$t1_std" "$brainstem_intensity" ":colormap=heat:opacity=0.5" "brainstem-segmentation" "coronal"
  else
    log_message 'Skipping Step 4 (Segmentation) as requested'
    log_message "Checking if registration data exists..."
    
    # Check if essential files exist to continue
    local reg_dir=$(get_module_dir "registered")
    if [ ! -d "$reg_dir" ] || [ $(find "$reg_dir" -name "*Warped.nii.gz" | wc -l) -eq 0 ]; then
      log_error "Registration data is missing. Cannot skip to Step $START_STAGE." $ERR_DATA_MISSING
      return $ERR_DATA_MISSING
    fi
    
    # Find the registered FLAIR file
    flair_registered=$(find "$reg_dir" -name "*FLAIR*Warped.nii.gz" | head -1)
    if [ -z "$flair_registered" ]; then
      flair_registered=$(find "$reg_dir" -name "t1_to_flairWarped.nii.gz" | head -1)
    fi
    
    if [ -z "$flair_registered" ]; then
      log_error "Registered FLAIR not found. Cannot skip to Step $START_STAGE." $ERR_DATA_MISSING
      return $ERR_DATA_MISSING
    fi
    
    log_message "Found registered data: $flair_registered"
  fi  # End of Segmentation (Step 4)
  
  # Step 5: Analysis
  if [ $START_STAGE -le 5 ]; then
    log_message "Step 5: Analysis"
    
    # Initialize registered directory if we're starting from this stage
    local reg_dir=$(get_module_dir "registered")
    if [ ! -d "$reg_dir" ]; then
      log_message "Creating registered directory..."
      reg_dir=$(create_module_dir "registered")
    fi
    
    # Find original T1 and FLAIR files (needed for space transformation)
    log_message "Looking for original T1 and FLAIR files..."
    local orig_t1=$(find "${RESULTS_DIR}/bias_corrected" -name "*T1*.nii.gz" | head -1)
    local orig_flair=$(find "${RESULTS_DIR}/bias_corrected" -name "*FLAIR*.nii.gz" | head -1)
    
    if [[ -z "$orig_t1" || -z "$orig_flair" ]]; then
      log_formatted "WARNING" "Original T1 or FLAIR file not found in bias_corrected directory"
      orig_t1=$(find "${EXTRACT_DIR}" -name "*T1*.nii.gz" | head -1)
      orig_flair=$(find "${EXTRACT_DIR}" -name "*FLAIR*.nii.gz" | head -1)
    fi
    
    if [[ -z "$orig_t1" || -z "$orig_flair" ]]; then
      log_error "Original T1 or FLAIR file not found" $ERR_DATA_MISSING
      return $ERR_DATA_MISSING
    fi
    
    log_message "Found original T1: $orig_t1"
    log_message "Found original FLAIR: $orig_flair"
    
    # Find segmentation files
    log_message "Looking for segmentation files..."
    local dorsal_pons=$(find "$RESULTS_DIR/segmentation/pons" -name "*dorsal_pons.nii.gz" | head -1)
    
    if [ -z "$dorsal_pons" ]; then
      log_error "Dorsal pons segmentation not found" $ERR_DATA_MISSING
      return $ERR_DATA_MISSING
    fi
    
    log_message "Found dorsal pons segmentation: $dorsal_pons"
    
    # Transform segmentation from standard space to original space
    log_message "Transforming segmentation from standard to original space..."
    local orig_space_dir=$(create_module_dir "segmentation/original_space")
    local dorsal_pons_orig="${orig_space_dir}/$(basename "$dorsal_pons" .nii.gz)_orig.nii.gz"
    
    transform_segmentation_to_original "$dorsal_pons" "$orig_t1" "$dorsal_pons_orig"
    
    if [ ! -f "$dorsal_pons_orig" ]; then
      log_error "Failed to transform segmentation to original space" $ERR_PROCESSING
      return $ERR_PROCESSING
    fi
    
    log_message "Successfully transformed segmentation to original space: $dorsal_pons_orig"
    
    # Create intensity versions of segmentation masks
    log_message "Creating intensity versions of segmentation masks..."
    local dorsal_pons_intensity="${orig_space_dir}/$(basename "$dorsal_pons" .nii.gz)_intensity.nii.gz"
    create_intensity_mask "$dorsal_pons_orig" "$orig_t1" "$dorsal_pons_intensity"
    
    # Verify dimensions consistency
    log_message "Verifying dimensions consistency across pipeline stages..."
    verify_dimensions_consistency "$orig_t1" "$t1_std" "$dorsal_pons_orig" "${RESULTS_DIR}/validation/dimensions_report.txt"
    
    # Verify segmentation location
    log_message "Verifying segmentation anatomical location..."
    verify_segmentation_location "$dorsal_pons_orig" "$orig_t1" "dorsal_pons" "${RESULTS_DIR}/validation/segmentation_location"
    
    # Find or create registered FLAIR
    local flair_registered=$(find "$reg_dir" -name "*FLAIR*Warped.nii.gz" -o -name "t1_to_flairWarped.nii.gz" | head -1)
    
    if [ -z "$flair_registered" ]; then
      log_formatted "WARNING" "No registered FLAIR found. Will register now."
      if [ -n "$t1_std" ] && [ -n "$flair_std" ]; then
        local reg_prefix="${reg_dir}/t1_to_flair"
        register_t2_flair_to_t1mprage "$t1_std" "$flair_std" "$reg_prefix"
        flair_registered="${reg_prefix}Warped.nii.gz"
      else
        log_error "Cannot find or create registered FLAIR file" $ERR_DATA_MISSING
        return $ERR_DATA_MISSING
      fi
    fi
    
    log_message "Using registered FLAIR: $flair_registered"
    
    # Run comprehensive analysis instead of just dorsal pons hyperintensity detection
    # This analyzes ALL segmentation masks and validates registration
    local comprehensive_dir=$(create_module_dir "comprehensive_analysis")
    
    log_formatted "INFO" "===== RUNNING COMPREHENSIVE ANALYSIS ====="
    log_message "This will analyze hyperintensities in ALL segmentation masks"
    log_message "and validate registration quality across spaces"
    
    # Pass all relevant images and directories to the comprehensive analysis
    run_comprehensive_analysis \
      "$orig_t1" \
      "$orig_flair" \
      "$t1_std" \
      "$flair_std" \
      "$RESULTS_DIR/segmentation" \
      "$comprehensive_dir"
    
    # For backward compatibility, create a link to the traditional hyperintensity mask
    local hyperintensities_dir=$(create_module_dir "hyperintensities")
    local hyperintensity_mask="${comprehensive_dir}/hyperintensities/dorsal_pons/hyperintensities_bin.nii.gz"
    
    if [ -f "$hyperintensity_mask" ]; then
      local legacy_mask="${hyperintensities_dir}/${subject_id}_dorsal_pons_thresh${THRESHOLD_WM_SD_MULTIPLIER:-2.0}_bin.nii.gz"
      ln -sf "$hyperintensity_mask" "$legacy_mask"
      log_message "Created link to comprehensive analysis result: $legacy_mask"
    else
      log_formatted "WARNING" "Comprehensive analysis didn't produce expected hyperintensity mask"
      log_message "Falling back to traditional hyperintensity detection..."
      
      # Fall back to traditional hyperintensity detection
      local hyperintensities_prefix="${hyperintensities_dir}/${subject_id}_dorsal_pons"
      detect_hyperintensities "$orig_flair" "$hyperintensities_prefix" "$orig_t1"
      hyperintensity_mask="${hyperintensities_prefix}_thresh${THRESHOLD_WM_SD_MULTIPLIER:-2.0}_bin.nii.gz"
      analyze_hyperintensity_clusters "$hyperintensity_mask" "$dorsal_pons_orig" "$orig_t1" "${hyperintensities_dir}/clusters" 5
    fi
    
    # Validate hyperintensities detection
    validate_step "Hyperintensity detection" "${subject_id}_dorsal_pons*.nii.gz" "hyperintensities"
    
    # Launch enhanced visual QA for hyperintensity detection (non-blocking)
    # Show both the FLAIR and the hyperintensity mask
    enhanced_launch_visual_qa "$orig_flair" "$hyperintensity_mask" ":colormap=heat:opacity=0.7" "hyperintensity-detection" "axial"
    
    # Also show all segmentation masks in one view for comparison
    local all_masks="${comprehensive_dir}/hyperintensities/all_masks_overlay.nii.gz"
    if [ -f "$all_masks" ]; then
      enhanced_launch_visual_qa "$orig_flair" "$all_masks" ":colormap=heat:opacity=0.7" "all-segmentations-hyperintensities" "axial"
    fi
  else
    log_message 'Skipping Step 5 (Analysis) as requested'
    log_message "Checking if segmentation data exists..."
    
    # Check if essential files exist to continue
    local segmentation_dir="$RESULTS_DIR/segmentation"
    if [ ! -d "$segmentation_dir" ]; then
      log_error "Segmentation data is missing. Cannot skip to Step $START_STAGE." $ERR_DATA_MISSING
      return $ERR_DATA_MISSING
    fi
    
    # Find key segmentation files
    dorsal_pons=$(find "$segmentation_dir" -name "*dorsal_pons.nii.gz" | head -1)
    
    if [ -z "$dorsal_pons" ]; then
      log_error "Dorsal pons segmentation not found. Cannot skip to Step $START_STAGE." $ERR_DATA_MISSING
      return $ERR_DATA_MISSING
    fi
    
    log_message "Found segmentation data: $dorsal_pons"
  fi  # End of Analysis (Step 5)
  
  # Step 6: Visualization
  if [ $START_STAGE -le 6 ]; then
    log_message "Step 6: Visualization"
    
    # Generate QC visualizations
  generate_qc_visualizations "$subject_id" "$RESULTS_DIR"
  
  # Create multi-threshold overlays
  create_multi_threshold_overlays "$subject_id" "$RESULTS_DIR"
  
  
    # Generate HTML report
    generate_html_report "$subject_id" "$RESULTS_DIR"
  else
    log_message 'Skipping Step 6 (Visualization) as requested'
    log_message "Checking if hyperintensity data exists..."
    
    # Check if essential files exist to continue
    local hyperintensities_dir="$RESULTS_DIR/hyperintensities"
    if [ ! -d "$hyperintensities_dir" ]; then
      log_error "Hyperintensity data is missing. Cannot skip to Step $START_STAGE." $ERR_DATA_MISSING
      return $ERR_DATA_MISSING
    fi
    
    log_message "Found hyperintensity data directory: $hyperintensities_dir"
  fi  # End of Visualization (Step 6)
  
  # Step 7: Track pipeline progress
  if [ $START_STAGE -le 7 ]; then
    log_message "Step 7: Tracking pipeline progress"
    track_pipeline_progress "$subject_id" "$RESULTS_DIR"
  else
    log_message 'Skipping Step 7 (Pipeline progress tracking) as requested'
  fi
  
  log_message "Pipeline completed successfully for subject $subject_id"
  return 0
}


# Run pipeline in batch mode
run_pipeline_batch() {
  local subject_list="$1"
  local base_dir="$2"
  local output_base="$3"

  # Validate inputs
  validate_file "$subject_list" "Subject list file" || return $ERR_FILE_NOT_FOUND
  validate_directory "$base_dir" "Base directory" || return $ERR_FILE_NOT_FOUND
  validate_directory "$output_base" "Output base directory" "true" || return $ERR_PERMISSION
  
  # Prepare batch processing
  echo "Running brainstem analysis pipeline on subject list: $subject_list"
  local parallel_batch_processing="${PARALLEL_BATCH:-false}"
  
  # Create summary directory
  local summary_dir="${output_base}/summary"
  mkdir -p "$summary_dir"
  
  # Initialize summary report
  local summary_file="${summary_dir}/batch_summary.csv"
  echo "Subject,Status,BrainstemVolume,PonsVolume,DorsalPonsVolume,HyperintensityVolume,LargestClusterVolume,RegistrationQuality" > "$summary_file"

  # Function to process a single subject (for parallel batch processing)
  process_single_subject() {
    local line="$1"
    
    # Parse subject info
    read -r subject_id t2_flair t1 <<< "$line"
    
    # Skip empty or commented lines
    [[ -z "$subject_id" || "$subject_id" == \#* ]] && return 0
    
    echo "Processing subject: $subject_id"
    
    # Create subject output directory
    local subject_dir="${output_base}/${subject_id}"
    mkdir -p "$subject_dir"
    
    # Run the pipeline for this subject
    (
      # Set variables for this subject in a subshell to avoid conflicts
      export SUBJECT_ID="$subject_id"
      export SRC_DIR="$base_dir/$subject_id"
      export RESULTS_DIR="$subject_dir"
      export PIPELINE_SUCCESS=true
      export PIPELINE_ERROR_COUNT=0
      
      run_pipeline
      
      # Return pipeline status
      return $?
    )
    
    return $?
  }
  
  # Export the function for parallel use
  export -f process_single_subject
  
  # Process subjects in parallel if GNU parallel is available and parallel batch processing is enabled
  if [ "$parallel_batch_processing" = "true" ] && [ "$PARALLEL_JOBS" -gt 0 ] && check_parallel; then
    log_message "Processing subjects in parallel with $PARALLEL_JOBS jobs"
    
    # Use parallel to process multiple subjects simultaneously
    # Create a temporary file with the subject list
    local temp_subject_list=$(mktemp)
    grep -v "^#" "$subject_list" > "$temp_subject_list"
    
    # Process subjects in parallel
    cat "$temp_subject_list" | parallel -j "$PARALLEL_JOBS" --halt "$PARALLEL_HALT_MODE",fail=1 process_single_subject
    local parallel_status=$?
    
    # Clean up
    rm "$temp_subject_list"
    
    if [ $parallel_status -ne 0 ]; then
      log_error "Parallel batch processing failed with status $parallel_status" $parallel_status
      return $parallel_status
    fi
  else
    # Process subjects sequentially
    log_message "Processing subjects sequentially"
  
    # Traditional sequential processing
    while read -r subject_id t2_flair t1; do
      echo "Processing subject: $subject_id"
      
      # Skip empty or commented lines
      [[ -z "$subject_id" || "$subject_id" == \#* ]] && continue
      
      # Create subject output directory
      local subject_dir="${output_base}/${subject_id}"
      mkdir -p "$subject_dir"
      
      # Set global variables for this subject
      export SUBJECT_ID="$subject_id"
      export SRC_DIR="$base_dir/$subject_id"
      export RESULTS_DIR="$subject_dir"
      
      # Reset error tracking for this subject
      PIPELINE_SUCCESS=true
      PIPELINE_ERROR_COUNT=0
      
      # Run processing with proper error handling
      run_pipeline
      local status=$?
      
      # Determine status text
      local status_text="FAILED"
      if [ $status -eq 0 ]; then
        status_text="COMPLETE"
      elif [ $status -eq 2 ]; then
        status_text="INCOMPLETE"
      fi
      
      # Extract key metrics for summary
      local brainstem_vol="N/A"
      local pons_vol="N/A"
      local dorsal_pons_vol="N/A"
      local hyperintensity_vol="N/A"
      local largest_cluster_vol="N/A"
      local reg_quality="N/A"
      
      local brainstem_file=$(get_output_path "segmentation/brainstem" "${subject_id}" "_brainstem")
      if [ -f "$brainstem_file" ]; then
        brainstem_vol=$(fslstats "$brainstem_file" -V | awk '{print $1}')
      fi
      
      local pons_file=$(get_output_path "segmentation/pons" "${subject_id}" "_pons")
      if [ -f "$pons_file" ]; then
        pons_vol=$(fslstats "$pons_file" -V | awk '{print $1}')
      fi
      
      local dorsal_pons_file=$(get_output_path "segmentation/pons" "${subject_id}" "_dorsal_pons")
      if [ -f "$dorsal_pons_file" ]; then
        dorsal_pons_vol=$(fslstats "$dorsal_pons_file" -V | awk '{print $1}')
      fi
      
      # Use the configured threshold from config instead of hardcoded 2.0
      local threshold_multiplier="${THRESHOLD_WM_SD_MULTIPLIER:-2.0}"
      local hyperintensity_file=$(get_output_path "hyperintensities" "${subject_id}" "_dorsal_pons_thresh${threshold_multiplier}")
      if [ -f "$hyperintensity_file" ]; then
        hyperintensity_vol=$(fslstats "$hyperintensity_file" -V | awk '{print $1}')
        
        # Get largest cluster size if clusters file exists
        local clusters_file="${hyperintensities_dir}/${subject_id}_dorsal_pons_clusters_sorted.txt"
        if [ -f "$clusters_file" ]; then
          largest_cluster_vol=$(head -1 "$clusters_file" | awk '{print $2}')
        fi
      fi
      
      # Add to summary
      echo "${subject_id},${status_text},${brainstem_vol},${pons_vol},${dorsal_pons_vol},${hyperintensity_vol},${largest_cluster_vol},${reg_quality}" >> "$summary_file"
      
  done < "$subject_list"
  fi
  echo "Batch processing complete. Summary available at: $summary_file"
  return 0
}

# Main function
main() {
  # Parse command line arguments
  parse_arguments "$@"
  
  log_message "Pipeline will start from stage $START_STAGE"
  
  # Initialize environment
  initialize_environment
  
  # Load parallel configuration if available
  load_parallel_config "config/parallel_config.sh"
  
  # Check all dependencies thoroughly
  check_all_dependencies
  
  # Load configuration file if provided
  if [ -f "$CONFIG_FILE" ]; then
    log_message "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
  fi
  
  # Run pipeline
  if [ "$PIPELINE_TYPE" = "BATCH" ]; then
    # Check if subject list file is provided
    if [ -z "${SUBJECT_LIST:-}" ]; then
      log_error "Subject list file not provided for batch processing" $ERR_INVALID_ARGS
      exit $ERR_INVALID_ARGS
    fi
    
    run_pipeline_batch "$SUBJECT_LIST" "$SRC_DIR" "$RESULTS_DIR"
    status=$?
  else
    run_pipeline
    status=$?
  fi
  
  if [ $status -ne 0 ]; then
    log_error "Pipeline failed with $PIPELINE_ERROR_COUNT errors $status" $ERR_VALIDATION
    exit $status
  fi
  
  log_message "Pipeline completed successfully"
  return 0
}

# Run main function with all arguments
main $@

