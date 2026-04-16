#!/bin/bash

# Set color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log functions - 所有日志输出到 stderr
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Display usage instructions
usage() {
    echo "Usage: $0 <srpm_file> <loongarch_files_or_directory>" >&2
    echo "" >&2
    echo "Parameters:" >&2
    echo "  srpm_file                  Path to the SRPM file to process" >&2
    echo "  loongarch_files_or_directory  A file, multiple files, or a directory containing files to add to loongarch64 directory" >&2
    echo "" >&2
    echo "This script will:" >&2
    echo "1. Clean entire ~/rpmbuild directory" >&2
    echo "2. Install the specified SRPM package" >&2
    echo "3. Modify the rpmbuild/SPEC file Release version number and changelog" >&2
    echo "4. Add a loongarch64 directory and specified files to tar packages in /rpmbuild/SOURCES" >&2
    echo "5. Execute rpmbuild -ba to build the modified package" >&2
}

# Clean entire rpmbuild directory
clean_rpmbuild() {
    local rpmbuild_dir="$HOME/rpmbuild"
    
    log_info "Cleaning entire rpmbuild directory: $rpmbuild_dir"
    
    # 删除整个rpmbuild目录（如果存在）
    if [ -d "$rpmbuild_dir" ]; then
        rm -rf "$rpmbuild_dir"
        log_success "Removed existing rpmbuild directory"
    fi
    
    # 重新创建必要的目录结构
    log_info "Creating fresh rpmbuild directory structure"
    mkdir -p "$rpmbuild_dir"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    
    log_success "Created fresh rpmbuild directory structure"
}

# Check if file exists
check_file() {
    local file=$1
    if [ ! -f "$file" ]; then
        log_error "File does not exist: $file"
        return 1
    fi
    return 0
}

# Expand files from directory or use provided files
expand_files() {
    local files_or_dir=("$@")
    local expanded_files=()
    
    for item in "${files_or_dir[@]}"; do
        if [ -d "$item" ]; then
            # 日志输出到 stderr
            log_info "Expanding directory: $item" >&2
            while IFS= read -r -d '' file; do
                expanded_files+=("$file")
            done < <(find "$item" -maxdepth 1 -type f -print0)
        elif [ -f "$item" ]; then
            # If it's a file, add it directly
            expanded_files+=("$item")
        else
            log_error "Item is neither a file nor a directory: $item" >&2
            return 1
        fi
    done
    
    # 只输出文件列表到 stdout
    printf '%s\n' "${expanded_files[@]}"
    return 0
}

# Step 1: Install SRPM package
install_srpm() {
    local srpm_file=$1
    
    log_info "Checking SRPM file..."
    if ! check_file "$srpm_file"; then
        return 1
    fi
    
    log_info "Installing SRPM package: $(basename "$srpm_file")"
    rpm -i "$srpm_file"
    if [ $? -ne 0 ]; then
        log_error "Installation failed: $(basename "$srpm_file")"
        return 1
    fi
    log_success "Successfully installed: $(basename "$srpm_file")"
    
    return 0
}

# Step 2: Modify SPEC file
modify_spec_file() {
    local spec_dir="$HOME/rpmbuild/SPECS"
    
    log_info "Checking SPEC directory..."
    if [ ! -d "$spec_dir" ]; then
        log_error "SPEC directory does not exist: $spec_dir"
        return 1
    fi
    
    # Find SPEC files
    local spec_files=($(find "$spec_dir" -name "*.spec"))
    if [ ${#spec_files[@]} -eq 0 ]; then
        log_error "No SPEC files found in $spec_dir"
        return 1
    fi
    
    for spec_file in "${spec_files[@]}"; do
        log_info "Modifying SPEC file: $(basename "$spec_file")"
        
        # Backup original file
        cp "$spec_file" "${spec_file}.backup"
        
        # 1. Modify Release version number to 1
        # Match "Release: any version number" and replace with "Release: 1"
        sed -i 's/^Release:[[:space:]]*[0-9.]*/Release: 1/g' "$spec_file"
        log_info "Changed Release version number to 1"
        
        # 2. Add specified content after %changelog
        # First extract version number
        local version=$(grep -E '^Version:' "$spec_file" | head -1 | awk '{print $2}')
        if [ -z "$version" ]; then
            log_error "Could not extract version number from SPEC file"
            return 1
        fi
        
        log_info "Extracted version: $version"
        
        if grep -q "%changelog" "$spec_file"; then
            # Use temporary file for insertion
            local temp_file=$(mktemp)
            awk -v version="$version" '
            /%changelog/ {
                print $0
                print "* Tue Dec 23 2025 Huang Yang <huangyang@loongson.cn> - "version"-1"
                print "- Add loong64"
                next
            }
            { print $0 }
            ' "$spec_file" > "$temp_file"
            
            mv "$temp_file" "$spec_file"
            log_info "Successfully added content after changelog with version: $version-1"
        else
            log_warn "No changelog section found in $(basename "$spec_file"), skipping modification"
        fi
        
        log_success "Successfully modified SPEC file: $(basename "$spec_file")"
    done
    
    return 0
}

# Step 3: Modify tar packages
modify_tar_ball() {
    local sources_dir="$HOME/rpmbuild/SOURCES"
    local loongarch_files=("$@")

    log_info "Checking SOURCES directory..."
    if [ ! -d "$sources_dir" ]; then
        log_error "SOURCES directory does not exist: $sources_dir"
        return 1
    fi

    # Expand files (handle directories)
    local expanded_files
    expanded_files=$(expand_files "${loongarch_files[@]}")
    if [ $? -ne 0 ]; then
        log_error "Failed to expand files"
        return 1
    fi

    # Convert to array
    local file_array=()
    while IFS= read -r line; do
        file_array+=("$line")
    done <<< "$expanded_files"

    if [ ${#file_array[@]} -eq 0 ]; then
        log_error "No valid files found after expansion"
        return 1
    fi

    log_info "Files to add to loongarch64 directory:"
    for file in "${file_array[@]}"; do
        log_info "  - $file"
    done

    # Find tar packages
    local tar_files=($(find "$sources_dir" -name "*.tar.gz" -o -name "*.tgz" -o -name "*.tar.bz2" -o -name "*.tar.xz"))
    if [ ${#tar_files[@]} -eq 0 ]; then
        log_warn "No tar packages found in $sources_dir"
        return 0
    fi

    for tar_file in "${tar_files[@]}"; do
        log_info "Processing tar package: $(basename "$tar_file")"

        local temp_dir=$(mktemp -d)
        local compress_type=""

        # Determine compression and extract
        case "$tar_file" in
            *.tar.gz|*.tgz)
                tar -xzf "$tar_file" -C "$temp_dir"
                compress_type="gz"
                ;;
            *.tar.bz2)
                tar -xjf "$tar_file" -C "$temp_dir"
                compress_type="bz2"
                ;;
            *.tar.xz)
                tar -xJf "$tar_file" -C "$temp_dir"
                compress_type="xz"
                ;;
            *)
                log_warn "Unsupported compression format: $(basename "$tar_file")"
                rm -rf "$temp_dir"
                continue
                ;;
        esac

        if [ $? -ne 0 ]; then
            log_error "Extraction failed: $(basename "$tar_file")"
            rm -rf "$temp_dir"
            continue
        fi

        # Create loongarch64 directory directly in the extracted root
        local loongarch64_dir="$temp_dir/loongarch64"
        mkdir -p "$loongarch64_dir"

        # Copy all specified files into loongarch64/
        for loongarch_file in "${file_array[@]}"; do
            if [ -x "$loongarch_file" ]; then
                install -m 755 "$loongarch_file" "$loongarch64_dir/"
            else
                cp "$loongarch_file" "$loongarch64_dir/"
            fi

            if [ $? -eq 0 ]; then
                log_info "Added file to loongarch64: $(basename "$loongarch_file")"
            else
                log_error "Failed to copy file: $(basename "$loongarch_file")"
            fi
        done

        # Repackage
        local output_tar="$tar_file"
        case "$compress_type" in
            gz)
                tar -czf "$output_tar" -C "$temp_dir" .
                ;;
            bz2)
                tar -cjf "$output_tar" -C "$temp_dir" .
                ;;
            xz)
                tar -cJf "$output_tar" -C "$temp_dir" .
                ;;
        esac

        if [ $? -eq 0 ]; then
            log_info "Successfully updated tar package: $(basename "$tar_file")"
        else
            log_error "Repackaging failed: $(basename "$tar_file")"
        fi

        rm -rf "$temp_dir"
    done

    return 0
}

# Step 4: Build RPM package
build_rpm() {
    local spec_dir="$HOME/rpmbuild/SPECS"
    
    log_info "Starting RPM build process..."
    
    # Find SPEC files
    local spec_files=($(find "$spec_dir" -name "*.spec"))
    if [ ${#spec_files[@]} -eq 0 ]; then
        log_error "No SPEC files found for building"
        return 1
    fi
    
    for spec_file in "${spec_files[@]}"; do
        log_info "Building RPM package from: $(basename "$spec_file")"
        rpmbuild -ba "$spec_file"
        
        if [ $? -eq 0 ]; then
            log_success "Successfully built RPM package from: $(basename "$spec_file")"
            log_info "Built RPMs can be found in: $HOME/rpmbuild/RPMS/"
            log_info "Built SRPMs can be found in: $HOME/rpmbuild/SRPMS/"
        else
            log_error "RPM build failed for: $(basename "$spec_file")"
            return 1
        fi
    done
    
    return 0
}

# Main function
main() {
    local srpm_file=$1
    shift
    local loongarch_items=("$@")
    
    if [ -z "$srpm_file" ] || [ ${#loongarch_items[@]} -eq 0 ]; then
        usage
        exit 1
    fi
    
    log_info "Starting SRPM package processing: $srpm_file"
    log_info "Items to add to loongarch64 directory: ${loongarch_items[*]}"

    # Step 0: Clean entire rpmbuild directory
    clean_rpmbuild

    # Step 1: Install SRPM package
    if ! install_srpm "$srpm_file"; then
        log_error "SRPM package installation failed"
        exit 1
    fi
    
    # Step 2: Modify SPEC file
    if ! modify_spec_file; then
        log_error "SPEC file modification failed"
        exit 1
    fi
    
    # Step 3: Modify tar packages
    if ! modify_tar_ball "${loongarch_items[@]}"; then
        log_error "Tar package modification failed"
        exit 1
    fi
    
    # Step 4: Build RPM package
    if ! build_rpm; then
        log_error "RPM build failed"
        exit 1
    fi
    
    log_success "All steps completed successfully!"
    log_info "Modified file locations:"
    log_info "  - SPEC files: $HOME/rpmbuild/SPECS/"
    log_info "  - SOURCES files: $HOME/rpmbuild/SOURCES/"
    log_info "  - Built RPMs: $HOME/rpmbuild/RPMS/"
    log_info "  - Built SRPMs: $HOME/rpmbuild/SRPMS/"
}

# Check if running as root user
if [ "$EUID" -eq 0 ]; then
    log_warn "Not recommended to run this script as root user"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Execute main function
main "$@"
