#!/usr/bin/env bash
#
# enhanced_registration_validation.sh - Improved registration and hyperintensity analysis
#
# This module provides:
# 1. Enhanced registration validation metrics
# 2. Comprehensive hyperintensity analysis across all segmentation masks
# 3. Cross-validation of results in both standard and original space
# 4. Coordinate space and datatype validation
#

# Constants for standard MNI template
MNI_TEMPLATE="${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz"
MNI_BRAIN="${FSLDIR}/data/standard/MNI152_T1_1mm_brain.nii.gz"

# Function to validate and standardize coordinate space
validate_coordinate_space() {
    local image="$1"
    local reference="${2:-$MNI_TEMPLATE}"
    local output_dir="${3:-./space_validation}"
    
    log_formatted "INFO" "===== VALIDATING COORDINATE SPACE ====="
    log_message "Image: $image"
    log_message "Reference: $reference"
    
    mkdir -p "$output_dir"
    
    # Get image information
    local img_info=$(fslinfo "$image")
    local ref_info=$(fslinfo "$reference")
    
    # Extract dimensions and voxel sizes
    local img_dims=($(echo "$img_info" | grep -E "^dim[1-3]" | awk '{print $2}'))
    local ref_dims=($(echo "$ref_info" | grep -E "^dim[1-3]" | awk '{print $2}'))
    
    local img_pixdims=($(echo "$img_info" | grep -E "^pixdim[1-3]" | awk '{print $2}'))
    local ref_pixdims=($(echo "$ref_info" | grep -E "^pixdim[1-3]" | awk '{print $2}'))
    
    local img_datatype=$(echo "$img_info" | grep "^data_type" | awk '{print $2}')
    local ref_datatype=$(echo "$ref_info" | grep "^data_type" | awk '{print $2}')
    
    # Create report
    {
        echo "Coordinate Space Validation Report"
        echo "=================================="
        echo "Date: $(date)"
        echo ""
        echo "Image: $image"
        echo "  Dimensions: ${img_dims[0]} x ${img_dims[1]} x ${img_dims[2]}"
        echo "  Voxel size: ${img_pixdims[0]} x ${img_pixdims[1]} x ${img_pixdims[2]} mm"
        echo "  Data type: $img_datatype"
        echo ""
        echo "Reference: $reference"
        echo "  Dimensions: ${ref_dims[0]} x ${ref_dims[1]} x ${ref_dims[2]}"
        echo "  Voxel size: ${ref_pixdims[0]} x ${ref_pixdims[1]} x ${ref_pixdims[2]} mm"
        echo "  Data type: $ref_datatype"
        echo ""
        echo "Compatibility Analysis:"
        
        # Check dimensions
        if [ "${img_dims[0]}" -eq "${ref_dims[0]}" ] && \
           [ "${img_dims[1]}" -eq "${ref_dims[1]}" ] && \
           [ "${img_dims[2]}" -eq "${ref_dims[2]}" ]; then
            echo "  Dimensions: COMPATIBLE - Exact match"
        else
            echo "  Dimensions: MISMATCH - Registration required"
            echo "    Image: ${img_dims[0]} x ${img_dims[1]} x ${img_dims[2]}"
            echo "    Reference: ${ref_dims[0]} x ${ref_dims[1]} x ${ref_dims[2]}"
        fi
        
        # Check voxel sizes
        local voxel_diff=$(echo "scale=6; sqrt((${img_pixdims[0]} - ${ref_pixdims[0]})^2 + (${img_pixdims[1]} - ${ref_pixdims[1]})^2 + (${img_pixdims[2]} - ${ref_pixdims[2]})^2)" | bc)
        
        if (( $(echo "$voxel_diff < 0.01" | bc -l) )); then
            echo "  Voxel size: COMPATIBLE - Close match (diff: $voxel_diff mm)"
        else
            echo "  Voxel size: MISMATCH - Resampling required (diff: $voxel_diff mm)"
            echo "    Image: ${img_pixdims[0]} x ${img_pixdims[1]} x ${img_pixdims[2]} mm"
            echo "    Reference: ${ref_pixdims[0]} x ${ref_pixdims[1]} x ${ref_pixdims[2]} mm"
        fi
        
        # Check datatype
        if [ "$img_datatype" = "$ref_datatype" ]; then
            echo "  Data type: COMPATIBLE - Exact match ($img_datatype)"
        else
            echo "  Data type: MISMATCH - Conversion required"
            echo "    Image: $img_datatype"
            echo "    Reference: $ref_datatype"
        fi
        
        echo ""
        echo "Registration Recommendation:"
        if [ "${img_dims[0]}" -ne "${ref_dims[0]}" ] || \
           [ "${img_dims[1]}" -ne "${ref_dims[1]}" ] || \
           [ "${img_dims[2]}" -ne "${ref_dims[2]}" ] || \
           (( $(echo "$voxel_diff >= 0.01" | bc -l) )); then
            echo "  REGISTRATION REQUIRED: Images are in different coordinate spaces"
            echo "  Recommended registration command:"
            echo "    mkdir -p $(dirname ${output_dir}/$(basename "$image" .nii.gz)_reg.nii.gz)"
            echo "    execute_ants_command \"direct_syn\" \"Direct ANTs SyN registration without WM guidance\" \\"
            echo "      antsRegistrationSyN.sh \\"
            echo "      -d 3 \\"
            echo "      -f $reference \\"
            echo "      -m $image \\"
            echo "      -o ${output_dir}/$(basename "$image" .nii.gz)_reg_ \\"
            echo "      -t s \\"
            echo "      -n 12 \\"
            echo "      -p f \\"
            echo "      -x MI"
        else
            echo "  NO REGISTRATION NEEDED: Images are already in compatible spaces"
        fi
    } > "${output_dir}/space_validation_report.txt"
    
    log_message "Coordinate space validation complete"
    cat "${output_dir}/space_validation_report.txt"
    
    return 0
}

# Function to standardize image format for compatibility
standardize_image_format() {
    local image="$1"
    local reference="${2:-$MNI_TEMPLATE}"
    local output="${3:-$(dirname "$image")/$(basename "$image" .nii.gz)_std.nii.gz}"
    local datatype="${4:-}"  # Optional datatype override
    
    log_formatted "INFO" "===== STANDARDIZING IMAGE FORMAT ====="
    log_message "Image: $image"
    log_message "Reference: $reference"
    log_message "Output: $output"
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output")"
    
    # Get reference datatype if not specified
    if [ -z "$datatype" ]; then
        datatype=$(fslinfo "$reference" | grep "^data_type" | awk '{print $2}')
        log_message "Using reference datatype: $datatype"
    fi
    
    # IMPROVED BINARY MASK DETECTION
    # Check if file is a binary mask using multiple criteria
    local is_binary=false
    local filename=$(basename "$image")
    
    # 1. First check: Does the filename contain mask-related keywords?
    if [[ "$filename" =~ (mask|bin|binary|brain_mask|seg|label) ]]; then
        log_message "Filename suggests this might be a binary mask: $filename"
        
        # 2. Second check: Verify with intensity statistics
        local range=$(fslstats "$image" -R)
        local min_val=$(echo "$range" | awk '{print $1}')
        local max_val=$(echo "$range" | awk '{print $2}')
        local unique_values=$(echo "$max_val - $min_val" | bc)
        
        # 3. Check unique values and range
        if (( $(echo "$unique_values <= 1.01" | bc -l) )); then
            # Likely a 0-1 binary mask
            is_binary=true
            log_message "File appears to be a binary 0-1 mask (range: $min_val to $max_val)"
        elif (( $(echo "$min_val >= -0.01" | bc -l) )) && (( $(echo "$max_val <= 5.01" | bc -l) )); then
            # Check if we have very few unique values (segmentation or probability mask)
            local num_unique=$(fslstats "$image" -H 10 0 10 | awk '{sum+=$1} END {print NR}')
            
            if [ "$num_unique" -lt 7 ]; then
                is_binary=true
                log_message "File appears to be a segmentation mask with $num_unique unique values"
            else
                is_binary=false
                log_message "File has multiple intensity values ($num_unique), treating as intensity image"
            fi
        else
            is_binary=false
            log_message "File intensity range suggests this is NOT a binary mask: $min_val to $max_val"
        fi
    else
        # Not likely a mask based on filename
        is_binary=false
        log_message "Filename does not suggest a binary mask: $filename"
    fi
    
    # Explicitly check for known intensity images by name
    if [[ "$filename" =~ (T1|MPRAGE|FLAIR|T2|DWI|SWI|EPI|_brain) ]] && ! [[ "$filename" =~ (mask) ]]; then
        # Override the binary detection for actual image data types
        if [ "$is_binary" = "true" ]; then
            log_message "Overriding binary detection: file name suggests this is an actual image volume"
            is_binary=false
        fi
    fi
    
    # Special handling for BrainExtraction files that are NOT binary masks
    if [[ "$filename" =~ BrainExtraction ]] && ! [[ "$filename" =~ (Mask|Template|Prior|BrainFace|CSF) ]]; then
        is_binary=false
        log_message "BrainExtraction file that's not a mask, treating as intensity image"
    fi
    
    # Choose appropriate datatype based on content
    local target_datatype
    if [ "$is_binary" = "true" ]; then
        # Binary masks should be UINT8 for efficiency
        target_datatype="UINT8"
        log_message "Image is a binary or segmentation mask, using UINT8 datatype"
    else
        # For intensity data (like FLAIR and T1), preserve the original datatype or use FLOAT32
        local orig_datatype=$(fslinfo "$image" | grep "^data_type" | awk '{print $2}')
        
        if [ "$orig_datatype" = "FLOAT32" ] || [ "$orig_datatype" = "FLOAT64" ]; then
            # Preserve floating point for intensity data
            target_datatype="$orig_datatype"
            log_message "Preserving original float datatype: $orig_datatype"
        elif [[ "$filename" =~ (T1|MPRAGE|FLAIR|T2|DWI|SWI|EPI) ]]; then
            # Use FLOAT32 for actual image data that wasn't already float
            target_datatype="FLOAT32"
            log_message "Image appears to be an intensity image, converting to FLOAT32"
        else
            # Default to INT16 for other data
            target_datatype="INT16"
            log_message "Using INT16 for unclassified non-binary image"
        fi
    fi
    
    # Get current datatype of the image
    local img_datatype=$(fslinfo "$image" | grep "^data_type" | awk '{print $2}')
    
    # Convert datatype if needed
    if [ "$img_datatype" != "$target_datatype" ]; then
        log_message "Converting datatype from $img_datatype to $target_datatype"
        
        # Map datatype string to FSL datatype number
        local datatype_num
        case "$target_datatype" in
            "UINT8")   datatype_num=2  ;;
            "INT8")    datatype_num=2  ;;
            "INT16")   datatype_num=4  ;;
            "INT32")   datatype_num=8  ;;
            "FLOAT32") datatype_num=16 ;;
            "FLOAT64") datatype_num=64 ;;
            *)         datatype_num=4  ;; # Default to INT16
        esac
        
        # Convert datatype with detailed logging
        log_message "Running: fslmaths $image -dt $datatype_num $output"
        fslmaths "$image" -dt "$datatype_num" "$output"
    else
        log_message "Datatype already matches target ($target_datatype), copying file"
        cp "$image" "$output"
    fi
    
    if [ -f "$output" ]; then
        # Verify the operation was successful
        local final_datatype=$(fslinfo "$output" | grep "^data_type" | awk '{print $2}')
        log_formatted "SUCCESS" "Image format standardized: $output (datatype: $final_datatype)"
        return 0
    else
        log_formatted "ERROR" "Failed to standardize image format"
        return 1
    fi
}

# Function to register to standard MNI space with proper datatype handling
register_to_standard_with_validation() {
    local image="$1"
    local reference="${2:-$MNI_TEMPLATE}"
    local output="${3:-$(dirname "$image")/$(basename "$image" .nii.gz)_to_std.nii.gz}"
    local transform="${4:-$(dirname "$output")/$(basename "$output" .nii.gz)_xfm.mat}"
    local purpose="${5:-analysis}"  # "analysis" or "visualization"
    
    if [ "$purpose" = "visualization" ]; then
        log_formatted "INFO" "===== REGISTERING TO MNI SPACE FOR VISUALIZATION ONLY ====="
        # For visualization, we can use lower quality/faster registration
        log_message "Image: $image (visualization only)"
    else
        log_formatted "INFO" "===== REGISTERING TO STANDARD MNI SPACE FOR ANALYSIS ====="
        log_message "Image: $image (for analysis)"
    fi
    
    log_message "Reference: $reference"
    log_message "Output: $output"
    log_message "Transform: $transform"
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output")"
    
    # First standardize the image format
    local std_image="${output}_fmt.nii.gz"
    standardize_image_format "$image" "$reference" "$std_image"
    
    # Check if standardization was successful
    if [ ! -f "$std_image" ]; then
        log_formatted "ERROR" "Image standardization failed"
        return 1
    fi
    
    # Check if image is already in MNI space
    local already_in_mni=false
    validate_coordinate_space "$std_image" "$reference" "$(dirname "$output")/validation"
    
    # Extract dimensions from the validation report
    local validation_report="$(dirname "$output")/validation/space_validation_report.txt"
    if [ -f "$validation_report" ]; then
        if grep -q "Dimensions: COMPATIBLE - Exact match" "$validation_report" && \
           grep -q "Voxel size: COMPATIBLE - Close match" "$validation_report"; then
            log_message "Image already appears to be in MNI space - skipping registration"
            already_in_mni=true
            cp "$std_image" "$output"
        fi
    fi
    
    # Run the registration if needed
    if [ "$already_in_mni" = "false" ]; then
        log_message "Running registration to MNI space with standardized image..."
        # Create output directory if needed
        mkdir -p "$(dirname "$output")"
        
        # Always use ANTs SyN with the execute_ants_command function for proper logging
        log_message "Using ANTs SyN with execute_ants_command for registration"
        
        # Execute ANTs registration with proper logging and error handling
        execute_ants_command "direct_syn" "Direct ANTs SyN registration without WM guidance" \
          antsRegistrationSyN.sh \
          -d 3 \
          -f "$reference" \
          -m "$std_image" \
          -o "$(dirname "$output")/direct_syn_" \
          -t s \
          -n 12 \
          -p f \
          -x MI
        
        # Check if ANTs registration produced output
        if [ -f "$(dirname "$output")/direct_syn_Warped.nii.gz" ]; then
            cp "$(dirname "$output")/direct_syn_Warped.nii.gz" "$output"
            cp "$(dirname "$output")/direct_syn_0GenericAffine.mat" "$transform"
            log_message "ANTs registration successful, using ANTs output"
        else
            # Fall back to FLIRT if ANTs fails (should rarely happen)
            log_formatted "WARNING" "ANTs registration failed, falling back to FLIRT"
            flirt -in "$std_image" -ref "$reference" -out "$output" -omat "$transform" -dof 12
        fi
    fi
    
    # Check if registration was successful
    if [ ! -f "$output" ]; then
        log_formatted "ERROR" "Registration failed"
        # Clean up
        rm -f "$std_image"
        return 1
    fi
    
    # Clean up intermediate files
    rm -f "$std_image"
    
    # Validate the registration
    log_message "Validating registration result..."
    local validation_dir="$(dirname "$output")/validation"
    verify_registration_quality "$reference" "$output" "$validation_dir"
    
    log_formatted "SUCCESS" "Registration with validation complete"
    return 0
}

# Function to verify registration quality with objective metrics
verify_registration_quality() {
    local t1_file="$1"
    local flair_file="$2"
    local output_dir="$3"
    
    log_formatted "INFO" "===== VERIFYING REGISTRATION QUALITY ====="
    log_message "T1: $t1_file"
    log_message "FLAIR: $flair_file"
    log_message "Output directory: $output_dir"
    
    mkdir -p "$output_dir"
    
    # Create normalized versions for more accurate comparison
    local t1_norm="${output_dir}/t1_norm.nii.gz"
    local flair_norm="${output_dir}/flair_norm.nii.gz"
    
    # Normalize images using robust methods
    log_message "Normalizing images for comparison..."
    fslmaths "$t1_file" -inm 1 "$t1_norm"
    fslmaths "$flair_file" -inm 1 "$flair_norm"
    
    # Calculate difference map
    local diff_map="${output_dir}/diff_map.nii.gz"
    log_message "Calculating difference map..."
    fslmaths "$t1_norm" -sub "$flair_norm" -abs "$diff_map"
    
    # Calculate quantitative metrics
    local mean_diff=$(fslstats "$diff_map" -M)
    local std_diff=$(fslstats "$diff_map" -S)
    local max_diff=$(fslstats "$diff_map" -R | awk '{print $2}')
    
    # Calculate mutual information (using FSL's implementation)
    local mutual_info=$(calculate_mutual_information "$t1_file" "$flair_file")
    
    # Calculate cross-correlation
    local cross_corr=$(calculate_cross_correlation "$t1_file" "$flair_file")
    
    # Create overlay for visual inspection
    log_message "Creating overlay visualization..."
    slices "$t1_file" "$flair_file" -o "${output_dir}/registration_check.png" || true
    
    # Create report
    {
        echo "Registration Quality Assessment"
        echo "=============================="
        echo "Date: $(date)"
        echo ""
        echo "Images:"
        echo "  T1: $t1_file"
        echo "  FLAIR: $flair_file"
        echo ""
        echo "Quantitative Metrics:"
        echo "  Mean Absolute Difference: $mean_diff"
        echo "  Standard Deviation of Difference: $std_diff"
        echo "  Maximum Absolute Difference: $max_diff"
        echo "  Mutual Information: $mutual_info"
        echo "  Cross-Correlation: $cross_corr"
        echo ""
        echo "Overall Quality:"
        if (( $(echo "$cross_corr > 0.7" | bc -l) )); then
            echo "  EXCELLENT"
        elif (( $(echo "$cross_corr > 0.5" | bc -l) )); then
            echo "  GOOD"
        elif (( $(echo "$cross_corr > 0.3" | bc -l) )); then
            echo "  ACCEPTABLE"
        else
            echo "  POOR - REGISTRATION MAY NEED IMPROVEMENT"
        fi
    } > "${output_dir}/registration_quality_report.txt"
    
    log_message "Registration quality assessment complete"
    cat "${output_dir}/registration_quality_report.txt"
    
    return 0
}

# Function to calculate mutual information between two images
calculate_mutual_information() {
    local img1="$1"
    local img2="$2"
    
    # Use a temporary directory for intermediate files
    local temp_dir=$(mktemp -d)
    local hist1="${temp_dir}/hist1.txt"
    local hist2="${temp_dir}/hist2.txt"
    local joint_hist="${temp_dir}/joint_hist.txt"
    
    # Get histograms (simplified approach)
    fslstats "$img1" -H 256 0 255 > "$hist1"
    fslstats "$img2" -H 256 0 255 > "$hist2"
    
    # Calculate mutual information using the correlation ratio as approximation
    # This is a simplification, but provides a reasonable metric
    local mi=$(fslcc -t 1 -p 100 "$img1" "$img2" | tail -n 1 | awk '{print $3}')
    
    # Clean up
    rm -rf "$temp_dir"
    
    echo "$mi"
}

# Function to calculate cross-correlation between two images
calculate_cross_correlation() {
    local img1="$1"
    local img2="$2"
    
    # Use FSL's correlation coefficient
    local cc=$(fslcc -t 0 "$img1" "$img2" | tail -n 1 | awk '{print $3}')
    
    echo "$cc"
}

# Function to analyze hyperintensities across all segmentation masks
analyze_hyperintensities_in_all_masks() {
    local flair_file="$1"        # FLAIR image in standard space
    local t1_file="$2"           # T1 image in standard space 
    local segmentation_dir="$3"  # Directory containing segmentation masks
    local output_dir="$4"        # Output directory
    local threshold="${5:-2.0}"  # Default threshold is 2.0 SD above mean
    
    log_formatted "INFO" "===== ANALYZING HYPERINTENSITIES IN ALL SEGMENTATION MASKS ====="
    log_message "FLAIR: $flair_file"
    log_message "T1: $t1_file"
    log_message "Segmentation dir: $segmentation_dir"
    log_message "Using intensity threshold: $threshold SD"
    
    mkdir -p "$output_dir"
    
    # Find all segmentation masks
    local mask_files=()
    local mask_names=()
    
    # Harvard-Oxford brainstem
    local brainstem_mask=$(find "$segmentation_dir" -name "*brainstem*.nii.gz" | grep -v "orig" | head -1)
    if [ -f "$brainstem_mask" ]; then
        log_message "Found Harvard-Oxford brainstem mask: $brainstem_mask"
        mask_files+=("$brainstem_mask")
        mask_names+=("harvard_brainstem")
    fi
    
    # Pons mask
    local pons_mask=$(find "$segmentation_dir" -name "*pons.nii.gz" | grep -v "dorsal" | grep -v "ventral" | grep -v "orig" | head -1)
    if [ -f "$pons_mask" ]; then
        log_message "Found pons mask: $pons_mask"
        mask_files+=("$pons_mask")
        mask_names+=("pons")
    fi
    
    # Dorsal pons mask
    local dorsal_pons=$(find "$segmentation_dir" -name "*dorsal_pons.nii.gz" | grep -v "orig" | head -1)
    if [ -f "$dorsal_pons" ]; then
        log_message "Found dorsal pons mask: $dorsal_pons"
        mask_files+=("$dorsal_pons")
        mask_names+=("dorsal_pons")
    fi
    
    # Ventral pons mask
    local ventral_pons=$(find "$segmentation_dir" -name "*ventral_pons.nii.gz" | grep -v "orig" | head -1)
    if [ -f "$ventral_pons" ]; then
        log_message "Found ventral pons mask: $ventral_pons"
        mask_files+=("$ventral_pons")
        mask_names+=("ventral_pons")
    fi
    
    # Talairack atlas (if available)
    local talairack_mask=$(find "$segmentation_dir" -name "*talairack*.nii.gz" -o -name "*tailrack*.nii.gz" | head -1)
    if [ -f "$talairack_mask" ]; then
        log_message "Found Talairack atlas mask: $talairack_mask"
        mask_files+=("$talairack_mask")
        mask_names+=("talairack")
    fi
    
    # Gold standard (if available)
    local gold_mask=$(find "$segmentation_dir" -name "*gold*.nii.gz" -o -name "*manual*.nii.gz" -o -name "*expert*.nii.gz" | head -1)
    if [ -f "$gold_mask" ]; then
        log_message "Found gold standard mask: $gold_mask"
        mask_files+=("$gold_mask")
        mask_names+=("gold_standard")
    fi
    
    # Check if any masks were found
    if [ ${#mask_files[@]} -eq 0 ]; then
        log_formatted "ERROR" "No segmentation masks found in $segmentation_dir"
        return 1
    fi
    
    log_message "Found ${#mask_files[@]} segmentation masks for analysis"
    
    # Process each mask
    for i in "${!mask_files[@]}"; do
        local mask="${mask_files[$i]}"
        local mask_name="${mask_names[$i]}"
        local mask_output_dir="${output_dir}/${mask_name}"
        
        mkdir -p "$mask_output_dir"
        log_message "Processing $mask_name mask: $mask"
        
        # Create brain mask from FLAIR for reference tissue
        local brain_mask="${mask_output_dir}/brain_mask.nii.gz"
        log_message "Creating brain mask from FLAIR..."
        fslmaths "$flair_file" -bin "$brain_mask"
        
        # Create NAWM mask (normal-appearing white matter) by excluding the region of interest
        # This gives us a reference for normal tissue intensity
        local nawm_mask="${mask_output_dir}/nawm_mask.nii.gz"
        log_message "Creating NAWM mask for reference..."
        fslmaths "$brain_mask" -sub "$mask" -thr 0 -bin "$nawm_mask"
        
        # Calculate mean and standard deviation of NAWM
        local nawm_mean=$(fslstats "$flair_file" -k "$nawm_mask" -M)
        local nawm_std=$(fslstats "$flair_file" -k "$nawm_mask" -S)
        
        # Calculate threshold for hyperintensities
        local intensity_threshold=$(echo "$nawm_mean + $threshold * $nawm_std" | bc -l)
        log_message "NAWM mean: $nawm_mean, std: $nawm_std, threshold: $intensity_threshold"
        
        # Create hyperintensity mask within region of interest
        local hyperintensity_mask="${mask_output_dir}/hyperintensities.nii.gz"
        local hyperintensity_bin="${mask_output_dir}/hyperintensities_bin.nii.gz"
        
        log_message "Thresholding FLAIR at $intensity_threshold within $mask_name..."
        fslmaths "$flair_file" -thr "$intensity_threshold" -mas "$mask" "$hyperintensity_mask"
        fslmaths "$hyperintensity_mask" -bin "$hyperintensity_bin"
        
        # Calculate hyperintensity volume
        local volume_voxels=$(fslstats "$hyperintensity_bin" -V | awk '{print $1}')
        local volume_mm3=$(fslstats "$hyperintensity_bin" -V | awk '{print $2}')
        
        # Calculate percentage of region affected
        local roi_volume=$(fslstats "$mask" -V | awk '{print $1}')
        local percentage=$(echo "scale=2; 100 * $volume_voxels / $roi_volume" | bc -l)
        
        # Create cluster analysis
        local clusters="${mask_output_dir}/clusters.nii.gz"
        log_message "Performing cluster analysis..."
        cluster -i "$hyperintensity_bin" -t 0.5 -o "$clusters" > "${mask_output_dir}/cluster_report.txt"
        
        # Create RGB overlay for visualization
        local overlay="${mask_output_dir}/overlay.nii.gz"
        log_message "Creating RGB overlay..."
        overlay 1 0 "$flair_file" 1000 2000 "$hyperintensity_bin" 1 1 0 "$overlay"
        
        # Create visual slices
        slicer "$overlay" -a "${mask_output_dir}/hyperintensities_${mask_name}.png" || true
        
        # Create report
        {
            echo "Hyperintensity Analysis for $mask_name"
            echo "===================================="
            echo "Date: $(date)"
            echo ""
            echo "Parameters:"
            echo "  FLAIR image: $flair_file"
            echo "  Segmentation mask: $mask"
            echo "  Threshold: $threshold SD above NAWM mean"
            echo "  Absolute intensity threshold: $intensity_threshold"
            echo ""
            echo "Results:"
            echo "  Hyperintensity volume: $volume_mm3 mm³ ($volume_voxels voxels)"
            echo "  Region of interest volume: $(fslstats "$mask" -V | awk '{print $2}') mm³ ($roi_volume voxels)"
            echo "  Percentage of region affected: $percentage%"
            echo ""
            echo "Cluster Analysis:"
            echo "  See cluster_report.txt for detailed cluster information"
            echo "  Cluster map: $(basename "$clusters")"
            echo ""
            echo "Visualization:"
            echo "  RGB overlay: $(basename "$overlay")"
            echo "  PNG slices: hyperintensities_${mask_name}.png"
        } > "${mask_output_dir}/hyperintensity_report.txt"
        
        log_message "Completed analysis for $mask_name"
        cat "${mask_output_dir}/hyperintensity_report.txt"
    done
    
    # Create comparison report across all masks
    local comparison_file="${output_dir}/mask_comparison.txt"
    {
        echo "Hyperintensity Analysis Comparison Across Masks"
        echo "==============================================="
        echo "Date: $(date)"
        echo ""
        echo "Mask | Volume (mm³) | % of Region Affected"
        echo "------------------------------------------"
        for i in "${!mask_names[@]}"; do
            local report_file="${output_dir}/${mask_names[$i]}/hyperintensity_report.txt"
            if [ -f "$report_file" ]; then
                local volume=$(grep "Hyperintensity volume:" "$report_file" | awk '{print $3}')
                local percentage=$(grep "Percentage of region affected:" "$report_file" | awk '{print $5}')
                echo "${mask_names[$i]} | $volume | $percentage"
            fi
        done
    } > "$comparison_file"
    
    log_message "Created comparison report: $comparison_file"
    cat "$comparison_file"
    
    # Create visualization for all masks combined
    local all_masks="${output_dir}/all_masks_combined.nii.gz"
    log_message "Creating combined visualization of all masks..."
    
    # Start with an empty volume
    fslmaths "$mask_files[0]" -mul 0 "$all_masks"
    
    # Add each hyperintensity map with a different value
    for i in "${!mask_names[@]}"; do
        local hyper_bin="${output_dir}/${mask_names[$i]}/hyperintensities_bin.nii.gz"
        if [ -f "$hyper_bin" ]; then
            # Add with different intensity for each mask
            local intensity=$((i+1))
            fslmaths "$hyper_bin" -mul $intensity -add "$all_masks" "$all_masks"
        fi
    done
    
    # Create multi-color overlay
    overlay 1 0 "$flair_file" 1000 2000 "$all_masks" 1 5 "$all_masks" > "${output_dir}/all_masks_overlay.nii.gz"
    
    # Create visual slices
    slicer "${output_dir}/all_masks_overlay.nii.gz" -a "${output_dir}/all_masks_overlay.png" || true
    
    log_formatted "SUCCESS" "Hyperintensity analysis completed for all segmentation masks"
    return 0
}

# Function to transform segmentations between spaces
transform_segmentation_to_original() {
    local segmentation="$1"    # Segmentation in standard space
    local reference="$2"       # Reference image in original space
    local output="$3"          # Output path
    local transform="${4:-}"   # Optional transform to use
    
    log_formatted "INFO" "===== TRANSFORMING SEGMENTATION TO ORIGINAL SPACE ====="
    log_message "Segmentation: $segmentation"
    log_message "Reference: $reference"
    log_message "Output: $output"
    
    mkdir -p "$(dirname "$output")"
    
    # Check if we need to find a transform
    if [ -z "$transform" ]; then
        # Look for standard transform files in common locations
        log_message "No transform specified, searching for standard transforms..."
        
        # Check in registered directory
        local reg_dir="$(dirname "$reference")/../registered"
        if [ -d "$reg_dir" ]; then
            # Check common transform file patterns
            for pattern in "*0GenericAffine.mat" "*InverseWarped.nii.gz" "*1InverseWarp.nii.gz"; do
                local found_transform=$(find "$reg_dir" -name "$pattern" | head -1)
                if [ -n "$found_transform" ]; then
                    transform="$found_transform"
                    log_message "Found transform: $transform"
                    break
                fi
            done
        fi
        
        # If still not found, search in transforms directory
        if [ -z "$transform" ]; then
            local transforms_dir="$(dirname "$reference")/../transforms"
            if [ -d "$transforms_dir" ]; then
                # Check common transform file patterns
                for pattern in "*0GenericAffine.mat" "*InverseWarped.nii.gz" "*1InverseWarp.nii.gz"; do
                    local found_transform=$(find "$transforms_dir" -name "$pattern" | head -1)
                    if [ -n "$found_transform" ]; then
                        transform="$found_transform"
                        log_message "Found transform: $transform"
                        break
                    fi
                done
            fi
        fi
    fi
    
    # Check if we found a transform
    if [ -z "$transform" ]; then
        log_formatted "WARNING" "No transform found, trying direct resampling"
        
        # Fallback to direct resampling
        log_message "Using flirt for direct resampling..."
        flirt -in "$segmentation" -ref "$reference" -out "$output" -applyxfm -init $FSLDIR/etc/flirtsch/ident.mat -interp nearestneighbour
    else
        # Determine if it's an ANTs or FSL transform
        if [[ "$transform" == *"GenericAffine"* || "$transform" == *"Warp"* ]]; then
            # ANTs transform
            log_message "Using ANTs to apply transform..."
            antsApplyTransforms -d 3 -i "$segmentation" -r "$reference" -o "$output" -t "$transform" -n NearestNeighbor
        else
            # FSL transform
            log_message "Using flirt to apply transform..."
            flirt -in "$segmentation" -ref "$reference" -out "$output" -applyxfm -init "$transform" -interp nearestneighbour
        fi
    fi
    
    # Verify the output was created
    if [ -f "$output" ]; then
        log_formatted "SUCCESS" "Segmentation transformed to original space: $output"
        return 0
    else
        log_formatted "ERROR" "Failed to transform segmentation"
        return 1
    fi
}

# Function to verify dimensions consistency
verify_dimensions_consistency() {
    local img1="$1"  # Original T1
    local img2="$2"  # Standard space T1 
    local img3="$3"  # Segmentation in original space
    local output_file="${4:-/dev/stdout}"
    
    log_formatted "INFO" "===== VERIFYING DIMENSIONS CONSISTENCY ====="
    log_message "Image 1 (Original): $img1"
    log_message "Image 2 (Standard): $img2"
    log_message "Image 3 (Segmentation): $img3"
    
    # Create output directory if needed
    if [ "$output_file" != "/dev/stdout" ]; then
        mkdir -p "$(dirname "$output_file")"
    fi
    
    # Get dimensions and voxel sizes
    local img1_dims=($(fslinfo "$img1" | grep -E "^dim[1-3]" | awk '{print $2}'))
    local img2_dims=($(fslinfo "$img2" | grep -E "^dim[1-3]" | awk '{print $2}'))
    local img3_dims=($(fslinfo "$img3" | grep -E "^dim[1-3]" | awk '{print $2}'))
    
    local img1_voxels=($(fslinfo "$img1" | grep -E "^pixdim[1-3]" | awk '{print $2}'))
    local img2_voxels=($(fslinfo "$img2" | grep -E "^pixdim[1-3]" | awk '{print $2}'))
    local img3_voxels=($(fslinfo "$img3" | grep -E "^pixdim[1-3]" | awk '{print $2}'))
    
    # Check dimensions consistency
    local orig_std_consistent=true
    local orig_seg_consistent=true
    
    # Create report
    {
        echo "Dimensions Consistency Report"
        echo "============================"
        echo "Date: $(date)"
        echo ""
        echo "Image 1 (Original): $img1"
        echo "  Dimensions: ${img1_dims[0]} x ${img1_dims[1]} x ${img1_dims[2]}"
        echo "  Voxel size: ${img1_voxels[0]} x ${img1_voxels[1]} x ${img1_voxels[2]} mm"
        echo ""
        echo "Image 2 (Standard): $img2"
        echo "  Dimensions: ${img2_dims[0]} x ${img2_dims[1]} x ${img2_dims[2]}"
        echo "  Voxel size: ${img2_voxels[0]} x ${img2_voxels[1]} x ${img2_voxels[2]} mm"
        echo ""
        echo "Image 3 (Segmentation): $img3"
        echo "  Dimensions: ${img3_dims[0]} x ${img3_dims[1]} x ${img3_dims[2]}"
        echo "  Voxel size: ${img3_voxels[0]} x ${img3_voxels[1]} x ${img3_voxels[2]} mm"
        echo ""
        echo "Consistency Check:"
        
        # Check orig vs std dimensions (they should be different due to standardization)
        echo "  Original vs Standard: Expected Different Dimensions"
        if [ "${img1_dims[0]}" -eq "${img2_dims[0]}" ] && \
           [ "${img1_dims[1]}" -eq "${img2_dims[1]}" ] && \
           [ "${img1_dims[2]}" -eq "${img2_dims[2]}" ]; then
            echo "    WARNING: Dimensions are identical, but should be different after standardization"
            orig_std_consistent=false
        else
            echo "    PASSED: Dimensions properly differ after standardization"
        fi
        
        # Check orig vs segmentation (they should match for analysis)
        echo "  Original vs Segmentation: Require Matching Dimensions"
        if [ "${img1_dims[0]}" -eq "${img3_dims[0]}" ] && \
           [ "${img1_dims[1]}" -eq "${img3_dims[1]}" ] && \
           [ "${img1_dims[2]}" -eq "${img3_dims[2]}" ]; then
            echo "    PASSED: Dimensions match for proper analysis"
        else
            echo "    FAILED: Dimensions mismatch will cause analysis errors"
            echo "      Original: ${img1_dims[0]} x ${img1_dims[1]} x ${img1_dims[2]}"
            echo "      Segmentation: ${img3_dims[0]} x ${img3_dims[1]} x ${img3_dims[2]}"
            orig_seg_consistent=false
        fi
        
        echo ""
        echo "Overall Consistency:"
        if [ "$orig_seg_consistent" = "true" ]; then
            echo "  PASSED: Images have consistent dimensions for analysis"
        else
            echo "  FAILED: Images have inconsistent dimensions, analysis may be incorrect"
        fi
    } > "$output_file"
    
    if [ "$output_file" != "/dev/stdout" ]; then
        log_message "Dimensions consistency report saved to: $output_file"
        
        # If dimensions are inconsistent, log an error
        if [ "$orig_seg_consistent" = "false" ]; then
            log_formatted "ERROR" "Dimensions mismatch between original and segmentation images"
            return 1
        fi
    fi
    
    return 0
}

# Function to verify segmentation anatomical location
verify_segmentation_location() {
    local segmentation="$1"
    local reference="$2"
    local region_name="$3"
    local output_dir="${4:-./validation}"
    
    log_formatted "INFO" "===== VERIFYING SEGMENTATION LOCATION: $region_name ====="
    log_message "Segmentation: $segmentation"
    log_message "Reference: $reference"
    
    mkdir -p "$output_dir"
    
    # Create overlay for visual inspection
    local overlay="${output_dir}/${region_name}_location_check.nii.gz"
    log_message "Creating overlay for visual inspection..."
    overlay 1 0 "$reference" 1000 2000 "$segmentation" 1 1 0 "$overlay"
    
    # Create visual slices
    slicer "$overlay" -a "${output_dir}/${region_name}_location.png" || true
    
    # Calculate centroid
    local com=$(fslstats "$segmentation" -C)
    
    # Create report
    {
        echo "Segmentation Location Verification: $region_name"
        echo "==========================================="
        echo "Date: $(date)"
        echo ""
        echo "Segmentation: $segmentation"
        echo "Reference: $reference"
        echo ""
        echo "Location Statistics:"
        echo "  Center of Mass: $com"
        echo "  Volume: $(fslstats "$segmentation" -V | awk '{print $2}') mm³"
        echo ""
        echo "Expected Anatomical Location:"
        
        if [[ "$region_name" == *"brainstem"* ]]; then
            echo "  The brainstem should be located at the base of the brain,"
            echo "  connecting the cerebrum with the spinal cord."
        elif [[ "$region_name" == *"pons"* ]]; then
            echo "  The pons should be located in the middle of the brainstem,"
            echo "  between the midbrain and the medulla oblongata."
        elif [[ "$region_name" == *"dorsal_pons"* ]]; then
            echo "  The dorsal pons should be located in the posterior (dorsal)"
            echo "  portion of the pons, adjacent to the fourth ventricle."
        elif [[ "$region_name" == *"ventral_pons"* ]]; then
            echo "  The ventral pons should be located in the anterior (ventral)"
            echo "  portion of the pons, adjacent to the basilar artery."
        else
            echo "  Unknown region. Please verify location manually."
        fi
        
        echo ""
        echo "Visual Verification:"
        echo "  Overlay: $(basename "$overlay")"
        echo "  PNG slices: ${region_name}_location.png"
        echo ""
        echo "NOTE: Visual inspection is required to confirm proper anatomical location."
    } > "${output_dir}/${region_name}_location_report.txt"
    
    log_message "Segmentation location verification complete for $region_name"
    cat "${output_dir}/${region_name}_location_report.txt"
    
    return 0
}

# Function to create intensity mask from binary mask
create_intensity_mask() {
    local binary_mask="$1"
    local intensity_image="$2"
    local output="$3"
    
    log_message "Creating intensity mask from binary mask..."
    log_message "Binary mask: $binary_mask"
    log_message "Intensity image: $intensity_image"
    log_message "Output: $output"
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output")"
    
    # Calculate statistics for normalization
    local mask_mean=$(fslstats "$intensity_image" -k "$binary_mask" -M)
    local mask_std=$(fslstats "$intensity_image" -k "$binary_mask" -S)
    local mask_min=$(fslstats "$intensity_image" -k "$binary_mask" -R | awk '{print $1}')
    local mask_max=$(fslstats "$intensity_image" -k "$binary_mask" -R | awk '{print $2}')
    
    # Create intensity mask (preserving intensity values from original image)
    fslmaths "$intensity_image" -mas "$binary_mask" "$output"
    
    # Log statistics
    log_message "Intensity mask created with statistics:"
    log_message "  Mean: $mask_mean"
    log_message "  Standard deviation: $mask_std"
    log_message "  Range: $mask_min - $mask_max"
    
    # Verify output was created
    if [ -f "$output" ]; then
        log_formatted "SUCCESS" "Intensity mask created: $output"
        return 0
    else
        log_formatted "ERROR" "Failed to create intensity mask"
        return 1
    fi
}

# Function to run comprehensive validation and analysis
run_comprehensive_analysis() {
    local t1_file="$1"              # Original T1
    local flair_file="$2"           # Original FLAIR
    local t1_std="$3"               # Standardized T1
    local flair_std="$4"            # Standardized FLAIR
    local segmentation_dir="$5"     # Directory with segmentation masks
    local output_dir="$6"           # Output directory
    
    log_formatted "INFO" "===== RUNNING COMPREHENSIVE VALIDATION AND ANALYSIS ====="
    log_message "T1 (Original): $t1_file"
    log_message "FLAIR (Original): $flair_file"
    log_message "T1 (Standard): $t1_std"
    log_message "FLAIR (Standard): $flair_std"
    log_message "Segmentation directory: $segmentation_dir"
    log_message "Output directory: $output_dir"
    
    mkdir -p "$output_dir"
    
    # 1. Verify registration quality
    local reg_dir="${output_dir}/registration_validation"
    log_message "Step 1: Verifying registration quality..."
    verify_registration_quality "$t1_std" "$flair_std" "$reg_dir"
    
    # 2. Find all segmentation masks in standard space
    log_message "Step 2: Finding segmentation masks..."
    local masks=($(find "$segmentation_dir" -name "*.nii.gz" -type f))
    log_message "Found ${#masks[@]} segmentation masks"
    
    # 3. Transform segmentations to original space
    local orig_space_dir="${output_dir}/original_space"
    mkdir -p "$orig_space_dir"
    
    log_message "Step 3: Transforming segmentations to original space..."
    for mask in "${masks[@]}"; do
        local mask_name=$(basename "$mask" .nii.gz)
        local orig_mask="${orig_space_dir}/${mask_name}_orig.nii.gz"
        
        log_message "Transforming $mask_name to original space..."
        transform_segmentation_to_original "$mask" "$t1_file" "$orig_mask"
        
        # Create intensity mask
        local intensity_mask="${orig_space_dir}/${mask_name}_intensity.nii.gz"
        create_intensity_mask "$orig_mask" "$t1_file" "$intensity_mask"
        
        # Verify segmentation location
        verify_segmentation_location "$orig_mask" "$t1_file" "$mask_name" "${output_dir}/location_validation"
    done
    
    # 4. Verify dimensions consistency for key files
    log_message "Step 4: Verifying dimensions consistency..."
    
    # Find a representative segmentation in original space
    local orig_seg=$(find "$orig_space_dir" -name "*_orig.nii.gz" | head -1)
    
    if [ -n "$orig_seg" ]; then
        verify_dimensions_consistency "$t1_file" "$t1_std" "$orig_seg" "${output_dir}/dimensions_report.txt"
    else
        log_formatted "WARNING" "No segmentation in original space found for dimension verification"
    fi
    
    # 5. Analyze hyperintensities in all masks (in original space)
    log_message "Step 5: Analyzing hyperintensities in all masks..."
    analyze_hyperintensities_in_all_masks "$flair_file" "$t1_file" "$orig_space_dir" "${output_dir}/hyperintensities"
    
    # 6. Create combined visualization
    log_message "Step 6: Creating combined visualization..."
    # This is done inside analyze_hyperintensities_in_all_masks
    
    log_formatted "SUCCESS" "Comprehensive validation and analysis complete"
    log_message "Results available in: $output_dir"
    
    return 0
}

# Export functions
export -f verify_registration_quality
export -f calculate_mutual_information
export -f calculate_cross_correlation
export -f analyze_hyperintensities_in_all_masks
export -f transform_segmentation_to_original
export -f verify_dimensions_consistency
export -f verify_segmentation_location
export -f create_intensity_mask
export -f run_comprehensive_analysis
export -f validate_coordinate_space
export -f standardize_image_format
export -f register_to_standard_with_validation

# Function to verify expected outputs from a pipeline step
verify_pipeline_step_outputs() {
    local step_name="$1"       # Name of the pipeline step (e.g., "registration", "segmentation")
    local output_dir="$2"      # Directory containing the outputs
    local modality="$3"        # Modality being processed (e.g., "T1", "FLAIR")
    local min_expected="${4:-1}"  # Minimum number of expected .nii.gz files
    
    log_formatted "INFO" "===== VERIFYING OUTPUTS FOR $step_name ($modality) ====="
    log_message "Output directory: $output_dir"
    log_message "Minimum expected files: $min_expected"
    
    # Check if directory exists
    if [ ! -d "$output_dir" ]; then
        log_formatted "ERROR" "Output directory does not exist: $output_dir"
        return 1
    fi
    
    # Count .nii.gz files
    local file_count=$(find "$output_dir" -name "*.nii.gz" -type f | wc -l)
    log_message "Found $file_count .nii.gz files in $output_dir"
    
    # Check if we have enough files
    if [ "$file_count" -lt "$min_expected" ]; then
        log_formatted "ERROR" "Insufficient output files: found $file_count, expected at least $min_expected"
        return 1
    fi
    
    # Check file datatypes
    log_message "Checking file datatypes..."
    local error_count=0
    
    for file in $(find "$output_dir" -name "*.nii.gz" -type f); do
        local filename=$(basename "$file")
        local datatype=$(fslinfo "$file" | grep "^data_type" | awk '{print $2}')
        
        # Verify datatype is appropriate
        if [[ "$filename" =~ (mask|bin|binary|Brain_Extraction_Mask) ]]; then
            # Binary masks should be UINT8
            if [ "$datatype" != "UINT8" ]; then
                log_formatted "WARNING" "Binary mask $filename has incorrect datatype: $datatype (expected UINT8)"
                error_count=$((error_count + 1))
            fi
        elif [[ "$filename" =~ (T1|MPRAGE|FLAIR|T2|DWI|SWI|EPI|brain) ]] && ! [[ "$filename" =~ (mask) ]]; then
            # Intensity images should not be UINT8
            if [ "$datatype" = "UINT8" ]; then
                log_formatted "ERROR" "Intensity image $filename has incorrect datatype: UINT8"
                error_count=$((error_count + 1))
            fi
        fi
        
        log_message "File: $filename, Datatype: $datatype"
    done
    
    if [ "$error_count" -gt 0 ]; then
        log_formatted "WARNING" "Found $error_count datatype issues in output files"
    else
        log_formatted "SUCCESS" "All output files have appropriate datatypes"
    fi
    
    # Generate additional step-specific checks based on the step name
    case "$step_name" in
        "brain_extraction")
            # Check for brain mask
            if ! find "$output_dir" -name "*brain_mask.nii.gz" -type f | grep -q .; then
                log_formatted "WARNING" "No brain mask file found in brain extraction outputs"
                error_count=$((error_count + 1))
            fi
            
            # Check for extracted brain
            if ! find "$output_dir" -name "*brain.nii.gz" -type f | grep -q .; then
                log_formatted "WARNING" "No extracted brain file found in brain extraction outputs"
                error_count=$((error_count + 1))
            fi
            ;;
            
        "registration")
            # Check for warped file
            if ! find "$output_dir" -name "*Warped.nii.gz" -type f | grep -q .; then
                log_formatted "WARNING" "No warped file found in registration outputs"
                error_count=$((error_count + 1))
            fi
            
            # Check for transform file
            if ! find "$output_dir" -name "*GenericAffine.mat" -type f | grep -q .; then
                log_formatted "WARNING" "No transform file found in registration outputs"
                error_count=$((error_count + 1))
            fi
            ;;
            
        "segmentation")
            # Check for segmentation outputs
            if ! find "$output_dir" -name "*seg*.nii.gz" -type f | grep -q .; then
                log_formatted "WARNING" "No segmentation file found in segmentation outputs"
                error_count=$((error_count + 1))
            fi
            ;;
            
        "bias_corrected")
            # Check for bias corrected image
            if ! find "$output_dir" -name "*n4*.nii.gz" -type f | grep -q .; then
                log_formatted "WARNING" "No bias-corrected file found in outputs"
                error_count=$((error_count + 1))
            fi
            ;;
    esac
    
    # Return success if no errors, otherwise return error count
    if [ "$error_count" -eq 0 ]; then
        log_formatted "SUCCESS" "All expected outputs for $step_name ($modality) are present and valid"
        return 0
    else
        log_formatted "WARNING" "Found $error_count issues with $step_name ($modality) outputs"
        return "$error_count"
    fi
}

# Export verification function
export -f verify_pipeline_step_outputs

log_message "Enhanced registration validation module loaded with coordinate space validation"