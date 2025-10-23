#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Enable nullglob to handle empty globs safely
shopt -s nullglob

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Error logging function
error() {
    log "ERROR: $*"
}

# Safe file copy helper function
# Usage: safe_copy_file <source> <destination>
# Returns: 0 on success, 1 on failure
safe_copy_file() {
    local src="$1"
    local dest="$2"
    
    if [[ $# -ne 2 ]]; then
        error "safe_copy_file requires exactly 2 arguments: source and destination"
        return 1
    fi
    
    # Check if source file exists
    if [[ ! -f "$src" ]]; then
        error "Source file does not exist: $src"
        return 1
    fi
    
    # Check if source file is non-empty
    if [[ ! -s "$src" ]]; then
        error "Source file is empty: $src"
        return 1
    fi
    
    # Create destination directory if it doesn't exist
    local dest_dir
    dest_dir="$(dirname "$dest")"
    if ! mkdir -p "$dest_dir"; then
        error "Failed to create destination directory: $dest_dir"
        return 1
    fi
    
    # Perform the copy operation
    if ! cp "$src" "$dest"; then
        error "Failed to copy $src to $dest"
        return 1
    fi
    
    log "Successfully copied $src to $dest"
    return 0
}

# Safe directory creation helper
safe_mkdir() {
    local dir="$1"
    if ! mkdir -p "$dir"; then
        error "Failed to create directory: $dir"
        return 1
    fi
    log "Created directory: $dir"
    return 0
}

# Main analysis function
run_coderabbit_analysis() {
    log "Starting CodeRabbit analysis..."

    # Create analysis directory (separate output to avoid self-copy)
    local analysis_dir="./coderabbit_analysis_output"
    if ! safe_mkdir "$analysis_dir"; then
        error "Failed to create analysis directory"
        return 1
    fi
    
    # Initialize success flag
    local success=true
    
    # Process Swift files with safe glob handling
    local swift_files=(./**/*.swift)
    if [[ ${#swift_files[@]} -eq 0 ]]; then
        log "No Swift files found for analysis"
    else
        log "Found ${#swift_files[@]} Swift files for analysis"
        for file in "${swift_files[@]}"; do
            if [[ -f "$file" && -s "$file" ]]; then
                # Preserve relative path to avoid filename collisions
                local relative_path="${file#./}"
                local dest_file="$analysis_dir/$relative_path"
                if ! safe_copy_file "$file" "$dest_file"; then
                    error "Failed to process Swift file: $file"
                    success=false
                fi
            fi
        done
    fi
    
    # Process configuration files
    local config_files=(./*.yml ./*.yaml ./*.json)
    if [[ ${#config_files[@]} -eq 0 ]]; then
        log "No configuration files found"
    else
        log "Processing ${#config_files[@]} configuration files"
        for file in "${config_files[@]}"; do
            if [[ -f "$file" && -s "$file" ]]; then
                local dest_file="$analysis_dir/$(basename "$file")"
                if ! safe_copy_file "$file" "$dest_file"; then
                    error "Failed to process config file: $file"
                    success=false
                fi
            fi
        done
    fi
    
    # Process project files
    local project_files=(./NFC\ DEMO/NFCDemo/*.xcodeproj/project.pbxproj)
    if [[ ${#project_files[@]} -eq 0 ]]; then
        log "No Xcode project files found"
    else
        log "Processing ${#project_files[@]} project files"
        for file in "${project_files[@]}"; do
            if [[ -f "$file" && -s "$file" ]]; then
                local dest_file="$analysis_dir/project.pbxproj"
                if ! safe_copy_file "$file" "$dest_file"; then
                    error "Failed to process project file: $file"
                    success=false
                fi
            fi
        done
    fi
    
    # Generate analysis summary
    local summary_file="$analysis_dir/analysis_summary.txt"
    {
        echo "CodeRabbit Analysis Summary"
        echo "=========================="
        echo "Generated: $(date)"
        echo "Files processed:"
        find "$analysis_dir" -type f -name "*.swift" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "project.pbxproj" | sort
    } > "$summary_file"
    
    if [[ "$success" == true ]]; then
        log "CodeRabbit analysis completed successfully"
        log "Analysis files saved to: $analysis_dir"
        return 0
    else
        error "CodeRabbit analysis completed with errors"
        return 1
    fi
}

# Main execution
main() {
    local exit_code=0
    
    log "Starting CodeRabbit analysis script"
    
    if ! run_coderabbit_analysis; then
        error "Analysis failed"
        exit_code=1
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log "Script completed successfully"
    else
        error "Script failed with exit code $exit_code"
    fi
    
    exit $exit_code
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
