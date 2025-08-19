#!/bin/bash

#
# Lilith: Devil's Package Manager
# A self-contained package manager for regular users without root privileges
#

# Script configuration
LILITH_DIR="$HOME/.lilith"
INSTALLED_PACKAGES_FILE="$LILITH_DIR/installed_packages.txt"
MANIFESTS_DIR="$LILITH_DIR/manifests"
CACHE_DIR="$LILITH_DIR/cache"
TEMP_DIR="$LILITH_DIR/tmp"
PACKAGESITE_FILE="$CACHE_DIR/packagesite.yaml"
PACKAGESITE_TZST="$CACHE_DIR/packagesite.tzst"

# Global variables
REPO_URL=""
ABI=""
ABI_PRINTED=0
METADATA_UPDATED=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#
# Print colored output
#
print_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

print_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

#
# Check if required tools are available
#
check_dependencies() {
    local missing_tools=""

    for tool in fetch tar grep awk sed cut jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools="$missing_tools $tool"
        fi
    done

    # Check for zstd decompression tool
    if ! command -v "zstd" >/dev/null 2>&1; then
        missing_tools="$missing_tools zstd"
    fi

    if [ -n "$missing_tools" ]; then
        print_error "Missing required tools:$missing_tools"
        return 1
    fi

    return 0
}

#
# Initialize the Lilith directory structure
#
init_lilith_dir() {
    if [ ! -d "$LILITH_DIR" ]; then
        print_info "Creating Lilith directory: $LILITH_DIR"
        mkdir -p "$LILITH_DIR" || {
            print_error "Failed to create directory: $LILITH_DIR"
            return 1
        }
    fi

    for dir in "$CACHE_DIR" "$TEMP_DIR" "$MANIFESTS_DIR" "$LILITH_DIR/bin" "$LILITH_DIR/sbin" "$LILITH_DIR/lib" "$LILITH_DIR/libdata" "$LILITH_DIR/include" "$LILITH_DIR/share"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || {
                print_error "Failed to create directory: $dir"
                return 1
            }
        fi
    done

    if [ ! -f "$INSTALLED_PACKAGES_FILE" ]; then
        touch "$INSTALLED_PACKAGES_FILE" || {
            print_error "Failed to create installed packages file"
            return 1
        }
    fi

    return 0
}

#
# Determine the FreeBSD ABI and construct repository URL
#
get_abi_and_repo_url() {
    local ostype osrel arch

    ostype=$(uname -s) || {
        print_error "Failed to get OS type"
        return 1
    }

    osrel=$(uname -r | sed 's/\([0-9]*\).*/\1/') || {
        print_error "Failed to get OS release"
        return 1
    }

    arch=$(uname -m) || {
        print_error "Failed to get architecture"
        return 1
    }

    ABI="${ostype}:${osrel}:${arch}"
    REPO_URL="https://pkg.freebsd.org/${ABI}/quarterly/All"

    # Only print ABI info once per script execution
    if [ $ABI_PRINTED -eq 0 ]; then
        print_info "Detected ABI: $ABI"
        print_info "Repository URL: $REPO_URL"
        ABI_PRINTED=1
    fi

    return 0
}

#
# Download and extract packagesite metadata
#
update_packagesite() {
    local packagesite_url="${REPO_URL}/../packagesite.tzst"

    # Only print download messages once per session
    if [ $METADATA_UPDATED -eq 0 ]; then
        print_info "Downloading package metadata from: $packagesite_url"
    fi

    if ! fetch -o "$PACKAGESITE_TZST" "$packagesite_url" 2>/dev/null; then
        print_error "Failed to download packagesite.tzst"
        return 1
    fi

    # Only print extraction message once per session
    if [ $METADATA_UPDATED -eq 0 ]; then
        print_info "Extracting package metadata..."
    fi

    # Extract the tar archive compressed with zstd
    # First decompress with zstd, then extract with tar
    local temp_tar="$CACHE_DIR/packagesite.tar"

    if command -v "zstd" >/dev/null 2>&1; then
        # Decompress zstd to tar
        if ! zstd -d "$PACKAGESITE_TZST" -o "$temp_tar" 2>/dev/null; then
            print_error "Failed to decompress packagesite.tzst with zstd"
            return 1
        fi

        # Extract tar archive
        if ! tar -xf "$temp_tar" -C "$CACHE_DIR" 2>/dev/null; then
            print_error "Failed to extract tar archive"
            rm -f "$temp_tar"
            return 1
        fi

        # Clean up temporary tar file
        rm -f "$temp_tar"
    else
        print_error "zstd decompression tool not available"
        return 1
    fi

    if [ ! -f "$PACKAGESITE_FILE" ]; then
        print_error "packagesite.yaml not found after extraction"
        return 1
    fi

    # Only print success message once per session
    if [ $METADATA_UPDATED -eq 0 ]; then
        print_success "Package metadata updated successfully"
        METADATA_UPDATED=1
    fi

    return 0
}

#
# Parse JSON data from packagesite.yaml
# This function extracts package information from the JSON file
#
parse_package_info() {
    local package_name="$1"
    local field="$2"

    if [ ! -f "$PACKAGESITE_FILE" ]; then
        print_error "Package metadata not found. Run 'lilith update-metadata' first."
        return 1
    fi

    # Find the package and extract the requested field from JSON using jq
    # First try exact match, then try prefix match for packages with versions
    local result
    result=$(jq -r --arg pkg "$package_name" --arg field "$field" \
        'select(.name == $pkg) | .[$field] // empty' "$PACKAGESITE_FILE")

    if [ -z "$result" ]; then
        # Try prefix match (package name followed by dash and version)
        result=$(jq -r --arg pkg "$package_name" --arg field "$field" \
            'select(.name | startswith($pkg + "-")) | .[$field] // empty' "$PACKAGESITE_FILE")
    fi

    echo "$result"
}

#
# Get package dependencies
#
get_package_deps() {
    local package_name="$1"

    if [ ! -f "$PACKAGESITE_FILE" ]; then
        print_error "Package metadata not found. Run 'lilith update-metadata' first."
        return 1
    fi

    # Extract dependencies from JSON using jq - deps is an object with package names as keys
    # First try exact match, then try prefix match for packages with versions
    local result
    result=$(jq -r --arg pkg "$package_name" \
        'select(.name == $pkg) | .deps // {} | keys[]' "$PACKAGESITE_FILE" 2>/dev/null)

    if [ -z "$result" ]; then
        # Try prefix match (package name followed by dash and version)
        result=$(jq -r --arg pkg "$package_name" \
            'select(.name | startswith($pkg + "-")) | .deps // {} | keys[]' "$PACKAGESITE_FILE" 2>/dev/null)
    fi

    echo "$result"
}

#
# Find package full name with version
#
find_package_fullname() {
    local package_name="$1"

    if [ ! -f "$PACKAGESITE_FILE" ]; then
        print_error "Package metadata not found. Run 'lilith update-metadata' first."
        return 1
    fi

    # Extract the full package name (name + version) from JSON using jq
    # First try exact match, then try prefix match for packages with versions
    local result
    result=$(jq -r --arg pkg "$package_name" \
        'select(.name == $pkg) | .name // empty' "$PACKAGESITE_FILE")

    if [ -z "$result" ]; then
        # Try prefix match (package name followed by dash and version)
        result=$(jq -r --arg pkg "$package_name" \
            'select(.name | startswith($pkg + "-")) | .name // empty' "$PACKAGESITE_FILE")
    fi

    echo "$result"
}

#
# Check if package is installed
#
is_package_installed() {
    local package_name="$1"

    if [ ! -f "$INSTALLED_PACKAGES_FILE" ]; then
        return 1
    fi

    grep -q "^${package_name}:" "$INSTALLED_PACKAGES_FILE"
}

#
# Check if package exists in system (fast check)
#
is_package_in_system() {
    local package_name="$1"

    # Check if executable exists in PATH
    if command -v "$package_name" >/dev/null 2>&1; then
        return 0
    fi

    # Check for library files
    if [ -e "/usr/lib/lib${package_name}.so" ] || [ -e "/usr/local/lib/lib${package_name}.so" ]; then
        return 0
    fi

    if [ -e "/usr/lib/${package_name}.so" ] || [ -e "/usr/local/lib/${package_name}.so" ]; then
        return 0
    fi

    # Check with pkg-config if available
    if command -v pkg-config >/dev/null 2>&1; then
        if pkg-config --exists "$package_name" 2>/dev/null; then
            return 0
        fi
        # Try with lib prefix
        if pkg-config --exists "lib${package_name}" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

#
# Add package to installed list
#
add_to_installed() {
    local package_fullname="$1"
    local package_name="$2"

    # Get additional info from manifest if available
    local manifest_file="$MANIFESTS_DIR/${package_name}.manifest"
    local version="N/A"
    local comment="No description"
    local origin="N/A"

    if [ -f "$manifest_file" ]; then
        version=$(jq -r '.version // "N/A"' "$manifest_file" 2>/dev/null)
        comment=$(jq -r '.comment // "No description"' "$manifest_file" 2>/dev/null)
        origin=$(jq -r '.origin // "N/A"' "$manifest_file" 2>/dev/null)
    fi

    if ! grep -q "^${package_name}:" "$INSTALLED_PACKAGES_FILE" 2>/dev/null; then
        echo "${package_name}:${version}:${comment}:${origin}" >>"$INSTALLED_PACKAGES_FILE"
    fi
}

#
# Remove package from installed list
#
remove_from_installed() {
    local package_name="$1"
    local temp_file="${INSTALLED_PACKAGES_FILE}.tmp"

    if [ -f "$INSTALLED_PACKAGES_FILE" ]; then
        grep -v "^${package_name}:" "$INSTALLED_PACKAGES_FILE" >"$temp_file" || true
        mv "$temp_file" "$INSTALLED_PACKAGES_FILE"
    fi
}

#
# Create symlinks for shared libraries in subdirectories to main lib directory
#
create_library_symlinks() {
    if [ ! -d "$LILITH_DIR/lib" ]; then
        return 0
    fi

    # Find all .so files in subdirectories of lib (but not in lib itself)
    find "$LILITH_DIR/lib" -mindepth 2 -type f \( -name "*.so" -o -name "*.so.*" \) 2>/dev/null | while read -r lib_file; do
        local lib_name
        lib_name=$(basename "$lib_file")
        local symlink_target="$LILITH_DIR/lib/$lib_name"

        # Only create symlink if it doesn't already exist
        if [ ! -e "$symlink_target" ]; then
            # Calculate relative path manually
            local relative_path
            relative_path=$(echo "$lib_file" | sed "s|^$LILITH_DIR/lib/||")

            if ln -sf "$relative_path" "$symlink_target" 2>/dev/null; then
                : # Symlink created
            else
                print_warning "Failed to create symlink for: $lib_name"
            fi
        fi

        # For versioned libraries like libperl.so.5.40.2, also create symlinks for shorter versions
        if echo "$lib_name" | grep -q '\.so\.[0-9]'; then
            # Create symlink for major.minor version (e.g., libperl.so.5.40)
            local base_version
            base_version=$(echo "$lib_name" | sed 's/\(\.so\.[0-9]*\.[0-9]*\)\.[0-9]*/\1/')
            if [ "$base_version" != "$lib_name" ] && [ ! -e "$LILITH_DIR/lib/$base_version" ]; then
                local relative_path
                relative_path=$(echo "$lib_file" | sed "s|^$LILITH_DIR/lib/||")
                if ln -sf "$relative_path" "$LILITH_DIR/lib/$base_version" 2>/dev/null; then
                    : # Symlink created
                else
                    print_warning "Failed to create symlink for: $lib_name"
                fi
            fi

            # Create symlink for major version only (e.g., libperl.so.5)
            local major_version
            major_version=$(echo "$lib_name" | sed 's/\(\.so\.[0-9]*\)\.[0-9]*.*/\1/')
            if [ "$major_version" != "$lib_name" ] && [ "$major_version" != "$base_version" ] && [ ! -e "$LILITH_DIR/lib/$major_version" ]; then
                local relative_path
                relative_path=$(echo "$lib_file" | sed "s|^$LILITH_DIR/lib/||")
                if ln -sf "$relative_path" "$LILITH_DIR/lib/$major_version" 2>/dev/null; then
                    : # Symlink created
                else
                    print_warning "Failed to create symlink for: $lib_name"
                fi
            fi
        fi
    done
}

#
# Download and extract a package
#
install_package_file() {
    local package_name="$1"

    # Get the actual package file path from the JSON
    local package_path
    package_path=$(parse_package_info "$package_name" "path")

    if [ -z "$package_path" ]; then
        print_error "Could not find package path for: $package_name"
        return 1
    fi

    # Extract filename from path
    local package_filename
    package_filename=$(basename "$package_path")

    local package_url="${REPO_URL}/${package_filename}"
    local temp_package="$TEMP_DIR/${package_filename}"

    print_info "Downloading: $package_name ($package_filename)"

    if ! fetch -o "$temp_package" "$package_url" 2>/dev/null; then
        print_error "Failed to download: $package_filename"
        return 1
    fi

    print_info "Extracting: $package_name"

    # Create a temporary extraction directory
    local temp_extract="$TEMP_DIR/extract_$$"
    mkdir -p "$temp_extract"

    # Extract the package to temporary directory
    if ! tar -xf "$temp_package" -C "$temp_extract" 2>/dev/null; then
        print_error "Failed to extract: $package_filename"
        rm -rf "$temp_extract"
        rm -f "$temp_package"
        return 1
    fi

    # Save the manifest file for future removal
    if [ -f "$temp_extract/+MANIFEST" ]; then
        cp "$temp_extract/+MANIFEST" "$MANIFESTS_DIR/${package_name}.manifest"
    fi

    # Move files from usr/local/* to ~/.lilith/*
    if [ -d "$temp_extract/usr/local" ]; then
        # Copy files, preserving directory structure
        (cd "$temp_extract/usr/local" && tar -cf - .) | (cd "$LILITH_DIR" && tar -xf -)

        # Create symlinks for shared libraries in subdirectories
        create_library_symlinks
    fi

    # Clean up
    rm -rf "$temp_extract"

    rm -f "$temp_package"
    return 0
}

#
# Install a package and its dependencies
#
cmd_install() {
    local skip_system=1 # Default to skipping system packages
    local no_deps=0
    local package_name=""

    # Initialize INSTALL_STACK if not set (for loop prevention)
    if [ -z "${INSTALL_STACK+x}" ]; then
        INSTALL_STACK=""
    fi

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
        --full-deps)
            skip_system=0
            ;;
        --no-deps)
            no_deps=1
            ;;
        -h | --help)
            print_info "Usage: lilith install [options] <package_name>"
            print_info "Options:"
            print_info "  --full-deps      Install all dependencies, even if they exist in system"
            print_info "  --no-deps        Install only the requested package, skip dependencies"
            print_info "  -h, --help       Show this help message"
            print_info "By default, skips packages that already exist in the system."
            return 0
            ;;
        -*)
            print_error "Unknown option: $1"
            return 1
            ;;
        *)
            package_name="$1"
            ;;
        esac
        shift
    done

    if [ -z "$package_name" ]; then
        print_error "Package name required"
        print_info "Usage: lilith install [options] <package_name>"
        print_info "Use 'lilith install --help' for more information"
        return 1
    fi

    # Check for circular dependencies
    case " $INSTALL_STACK " in
    *" $package_name "*)
        print_warning "Circular dependency detected for: $package_name (skipping)"
        return 0
        ;;
    esac

    # Add to install stack
    INSTALL_STACK="$INSTALL_STACK $package_name"

    if ! init_lilith_dir; then
        return 1
    fi

    if ! get_abi_and_repo_url; then
        return 1
    fi

    # For install command, download metadata if missing
    if [ ! -f "$PACKAGESITE_FILE" ]; then
        print_info "Package metadata not found, downloading..."
        if ! update_packagesite; then
            return 1
        fi
    fi

    local package_fullname
    package_fullname=$(find_package_fullname "$package_name")

    if [ -z "$package_fullname" ]; then
        print_error "Package not found: $package_name"
        return 1
    fi

    if is_package_installed "$package_name"; then
        print_warning "Package already installed: $package_name"
        return 0
    fi

    print_info "Installing package: $package_name ($package_fullname)"

    # Get and install dependencies first (unless --no-deps is specified)
    if [ $no_deps -eq 0 ]; then
        local deps
        deps=$(get_package_deps "$package_name")

        if [ -n "$deps" ]; then
            print_info "Installing dependencies..."
            for dep in $deps; do
                # Extract just the package name without version for dependency checking
                local dep_base_name
                dep_base_name=$(echo "$dep" | sed 's/-[0-9].*//')

                # Check if already installed in lilith
                if is_package_installed "$dep_base_name"; then
                    continue
                fi

                # Check if exists in system (if --skip-system is enabled)
                if [ $skip_system -eq 1 ] && is_package_in_system "$dep_base_name"; then
                    print_success "System package found for dependency: $dep_base_name (skipping)"
                    continue
                fi

                print_info "Installing dependency: $dep"
                # Pass flags to recursive call
                local install_args=""
                if [ $skip_system -eq 0 ]; then
                    install_args="$install_args --full-deps"
                fi
                # Dependencies always install their own dependencies
                INSTALL_STACK="$INSTALL_STACK" cmd_install "$install_args" "$dep"
                if [ $? -ne 0 ]; then
                    print_error "Failed to install dependency: $dep"
                    return 1
                fi
            done
        fi
    else
        print_info "Skipping dependencies (--no-deps specified)"
    fi

    # Install the main package
    if ! install_package_file "$package_name"; then
        return 1
    fi

    add_to_installed "$package_fullname" "$package_name"

    print_success "Successfully installed: $package_name"

    return 0
}

#
# Update a package
#
cmd_update() {
    local package_name="$1"

    if [ -z "$package_name" ]; then
        print_error "Package name required"
        print_info "Usage: lilith update <package_name>"
        return 1
    fi

    if ! is_package_installed "$package_name"; then
        print_error "Package not installed: $package_name"
        return 1
    fi

    if ! get_abi_and_repo_url; then
        return 1
    fi

    if ! update_packagesite; then
        return 1
    fi

    local current_version new_version
    current_version=$(grep "^${package_name}:" "$INSTALLED_PACKAGES_FILE" | cut -d: -f2)
    new_version=$(find_package_fullname "$package_name")

    if [ "$current_version" = "$new_version" ]; then
        print_info "Package is already up to date: $package_name"
        return 0
    fi

    print_info "Updating $package_name: $current_version -> $new_version"

    # Remove old version and install new one
    if ! cmd_remove "$package_name"; then
        print_error "Failed to remove old version"
        return 1
    fi

    if ! cmd_install "$package_name"; then
        print_error "Failed to install new version"
        return 1
    fi

    print_success "Successfully updated: $package_name"
    return 0
}

#
# Check if a package is required by other installed packages
#
is_package_required() {
    local package_name="$1"

    # Check all manifest files for dependencies
    for manifest in "$MANIFESTS_DIR"/*.manifest; do
        if [ -f "$manifest" ]; then
            local manifest_pkg
            manifest_pkg=$(basename "$manifest" .manifest)
            if [ "$manifest_pkg" != "$package_name" ]; then
                # Check if this package is in the dependencies
                # Dependencies can have version numbers, so we need to check both exact match and base name match
                if jq -e --arg dep "$package_name" '.deps | has($dep)' "$manifest" >/dev/null 2>&1; then
                    echo "$manifest_pkg"
                    return 0
                fi

                # Also check for dependencies that start with package_name followed by a dash (version)
                local versioned_dep
                versioned_dep=$(jq -r --arg dep "$package_name" '.deps | keys[] | select(startswith($dep + "-"))' "$manifest" 2>/dev/null)
                if [ -n "$versioned_dep" ]; then
                    echo "$manifest_pkg"
                    return 0
                fi
            fi
        fi
    done
    return 1
}

#
# Remove package files using manifest
#
remove_package_files() {
    local package_name="$1"
    local manifest_file="$MANIFESTS_DIR/${package_name}.manifest"

    if [ ! -f "$manifest_file" ]; then
        print_warning "No manifest found for $package_name, cannot remove files"
        return 1
    fi

    print_info "Removing files for package: $package_name"

    # Get list of files from manifest and remove them
    jq -r '.files | keys[]' "$manifest_file" 2>/dev/null | while read -r file_path; do
        # Convert /usr/local path to ~/.lilith path
        local lilith_path
        lilith_path=$(echo "$file_path" | sed 's|^/usr/local|'"$LILITH_DIR"'|')

        if [ -f "$lilith_path" ]; then
            rm -f "$lilith_path" 2>/dev/null
        elif [ -d "$lilith_path" ]; then
            # Only remove directory if it's empty
            rmdir "$lilith_path" 2>/dev/null || true
        fi
    done

    # Remove empty directories (bottom-up)
    find "$LILITH_DIR" -type d -empty -delete 2>/dev/null || true

    return 0
}

#
# Remove a package
#
cmd_remove() {
    local package_name="$1"
    local force=0
    local auto_remove=1      # Default to auto-removing orphaned dependencies
    local cleanup_symlinks=1 # Default to cleaning up symlinks

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
        --force)
            force=1
            ;;
        --no-auto-remove)
            auto_remove=0
            ;;
        --no-cleanup)
            cleanup_symlinks=0
            ;;
        -h | --help)
            print_info "Usage: lilith remove [options] <package_name>"
            print_info "Options:"
            print_info "  --force           Remove package even if required by other packages"
            print_info "  --no-auto-remove  Don't automatically remove orphaned dependencies"
            print_info "  -h, --help        Show this help message"
            print_info "By default, orphaned dependencies are automatically removed."
            return 0
            ;;
        -*)
            print_error "Unknown option: $1"
            return 1
            ;;
        *)
            package_name="$1"
            ;;
        esac
        shift
    done

    if [ -z "$package_name" ]; then
        print_error "Package name required"
        print_info "Usage: lilith remove [options] <package_name>"
        print_info "Use 'lilith remove --help' for more information"
        return 1
    fi

    if ! is_package_installed "$package_name"; then
        print_error "Package not installed: $package_name"
        return 1
    fi

    # Check if package is required by others
    if [ $force -eq 0 ]; then
        local required_by
        required_by=$(is_package_required "$package_name")
        if [ $? -eq 0 ]; then
            print_error "Package $package_name is required by: $required_by"
            print_info "Use --force to remove anyway, or remove the dependent package first"
            return 1
        fi
    fi

    print_info "Removing package: $package_name"

    # Save dependencies before removing manifest
    local deps_to_check=""
    local manifest_file="$MANIFESTS_DIR/${package_name}.manifest"
    if [ -f "$manifest_file" ]; then
        deps_to_check=$(jq -r '.deps // {} | keys[]' "$manifest_file" 2>/dev/null | tr '\n' ' ')
    fi

    # Remove package files
    if ! remove_package_files "$package_name"; then
        print_warning "Failed to remove some files for: $package_name"
    fi

    # Remove from installed list
    remove_from_installed "$package_name"

    # Remove manifest file
    rm -f "$MANIFESTS_DIR/${package_name}.manifest"

    print_success "Successfully removed package: $package_name"

    # Check for orphaned dependencies and remove them if auto_remove is enabled
    print_info "Checking for orphaned dependencies..."

    # Now check each dependency
    for dep in $deps_to_check; do
        # Extract base package name (remove version suffix)
        local dep_base_name
        dep_base_name=$(echo "$dep" | sed 's/-[0-9].*//')

        if is_package_installed "$dep_base_name"; then
            local required_by
            required_by=$(is_package_required "$dep_base_name" 2>/dev/null)
            if [ $? -ne 0 ]; then
                # Package is not required by others, safe to remove
                if [ $auto_remove -eq 1 ]; then
                    print_info "Auto-removing orphaned dependency: $dep_base_name"
                    # Pass --no-cleanup to prevent recursive symlink cleanup
                    cmd_remove --no-cleanup "$dep_base_name"
                else
                    print_info "Orphaned dependency found: $dep_base_name (use 'lilith remove $dep_base_name' to remove)"
                fi
            fi
        fi
    done

    # Clean up any dead symlinks that may have been left behind (only for top-level calls)
    if [ $cleanup_symlinks -eq 1 ]; then
        print_info "Cleaning up dead symlinks..."
        remove_dead_symlinks
    fi

    return 0
}

#
# Show detailed information about a package
#
cmd_info() {
    local package_name="$1"

    if [ -z "$package_name" ]; then
        print_error "Package name required"
        print_info "Usage: lilith info <package_name>"
        return 1
    fi

    if ! init_lilith_dir; then
        return 1
    fi

    if ! get_abi_and_repo_url; then
        return 1
    fi

    # Check if metadata exists, if not suggest updating
    if [ ! -f "$PACKAGESITE_FILE" ]; then
        print_error "Package metadata not found. Please run: lilith update-metadata"
        return 1
    fi

    # Find package info using jq - exact match only
    local package_info
    package_info=$(jq -r --arg pkg "$package_name" '
        select(.name == $pkg) | 
        "Name: \(.name)
Version: \(.version // "N/A")
Comment: \(.comment // "No description")
Maintainer: \(.maintainer // "N/A")
WWW: \(.www // "N/A")
Arch: \(.arch // "N/A")
Origin: \(.origin // "N/A")
Categories: \(.categories // [] | join(", "))
License: \(.licenselogic // "N/A") \(.licenses // [] | join(", "))
Package Size: \(.pkgsize // "N/A") bytes
Installed Size: \(.flatsize // "N/A") bytes
Dependencies: \(.deps // {} | keys | join(", "))
---"' "$PACKAGESITE_FILE")

    if [ -z "$package_info" ]; then
        print_error "Package not found: $package_name"
        print_info "Try searching with: lilith search $package_name"
        return 1
    fi

    print_info "Package Information:"
    print_info ""
    echo "$package_info"

    return 0
}

#
# Search for packages
#
cmd_search() {
    local search_all=0
    local query=""

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
        -a | --all)
            search_all=1
            ;;
        -h | --help)
            print_info "Usage: lilith search [options] <query>"
            print_info "Options:"
            print_info "  -a, --all    Search in package names and descriptions"
            print_info "  -h, --help   Show this help message"
            print_info "By default, searches only in package names."
            return 0
            ;;
        -*)
            print_error "Unknown option: $1"
            return 1
            ;;
        *)
            query="$1"
            ;;
        esac
        shift
    done

    if [ -z "$query" ]; then
        print_error "Search query required"
        print_info "Usage: lilith search [options] <query>"
        print_info "Use 'lilith search --help' for more information"
        return 1
    fi

    if ! init_lilith_dir; then
        return 1
    fi

    if ! get_abi_and_repo_url; then
        return 1
    fi

    # Check if metadata exists, if not suggest updating
    if [ ! -f "$PACKAGESITE_FILE" ]; then
        print_error "Package metadata not found. Please run: lilith update-metadata"
        return 1
    fi

    if [ $search_all -eq 1 ]; then
        print_info "Searching for '$query' in package names and descriptions..."
    else
        print_info "Searching for '$query' in package names only..."
    fi
    print_info ""

    # Search in JSON format using jq
    local results
    if [ $search_all -eq 1 ]; then
        # Search in both name and comment fields
        results=$(jq -r --arg query "$query" \
            'select((.name | test($query; "i")) or (.comment | test($query; "i"))) | 
             "\(.name)|\(.version // "N/A")|\(.comment // "No description")"' "$PACKAGESITE_FILE" 2>/dev/null)
    else
        # Search only in name field
        results=$(jq -r --arg query "$query" \
            'select(.name | test($query; "i")) | 
             "\(.name)|\(.version // "N/A")|\(.comment // "No description")"' "$PACKAGESITE_FILE" 2>/dev/null)
    fi

    if [ -n "$results" ]; then
        printf "%-30s %-15s %s\n" "Package" "Version" "Description"
        printf "%-30s %-15s %s\n" "-------" "-------" "-----------"
        echo "$results" | while IFS='|' read -r name version comment; do
            printf "%-30s %-15s %s\n" "$name" "$version" "$comment"
        done
    else
        print_info "No packages found matching: $query"
    fi

    return 0
}

#
# List installed packages
#
cmd_list() {
    if [ ! -f "$INSTALLED_PACKAGES_FILE" ]; then
        print_info "No packages installed"
        return 0
    fi

    if [ ! -s "$INSTALLED_PACKAGES_FILE" ]; then
        print_info "No packages installed"
        return 0
    fi

    print_info "Installed packages:"
    print_info ""

    # New format with version, description, and origin
    printf "%-25s %-15s %-40s %s\n" "Package" "Version" "Description" "Origin"
    printf "%-25s %-15s %-40s %s\n" "-------" "-------" "-----------" "------"
    awk -F: '{ 
        desc = $3; if (length(desc) > 38) desc = substr(desc, 1, 35) "..."
        printf "%-25s %-15s %-40s %s\n", $1, $2, desc, $4 
    }' "$INSTALLED_PACKAGES_FILE"

    return 0
}

#
# Update package metadata
#
cmd_update_metadata() {
    if ! init_lilith_dir; then
        return 1
    fi

    if ! get_abi_and_repo_url; then
        return 1
    fi

    if ! update_packagesite; then
        return 1
    fi

    return 0
}

#
# Show help
#
cmd_help() {
    cat <<'EOF'
Lilith: Devil's Package Manager
A self-contained package manager for regular users without root privileges

USAGE:
    lilith <command> [arguments]

COMMANDS:
    install [options] <package>   Install a package and its dependencies
                                  Options: --full-deps (install all dependencies)
                                           --no-deps (skip dependencies)
    update <package>              Update a package to the latest version
    remove [options] <package>    Remove a package from the system
                                  Options: --force (remove even if required by others)
                                           --no-auto-remove (keep orphaned dependencies)
    search [options] <query>      Search for packages matching the query
                                  Options: -a/--all (search names and descriptions)
    info <package>                Show detailed information about a package
    list                          List all installed packages
    update-metadata               Update package repository metadata
    fix-symlinks                  Create symlinks for libraries in subdirectories
    help                          Show this help message

ENVIRONMENT:
    After installing packages, you may need to update your environment:

    For devil users, add to ~/.bash_profile:
        export PATH="$HOME/.lilith/bin:$HOME/.lilith/sbin:$PATH"
        export LD_LIBRARY_PATH="$HOME/.lilith/lib:$LD_LIBRARY_PATH"
        export MANPATH="$HOME/.lilith/share/man:$MANPATH"
        export C_INCLUDE_PATH="$HOME/.lilith/include:$C_INCLUDE_PATH"
        export CPLUS_INCLUDE_PATH="$HOME/.lilith/include:$CPLUS_INCLUDE_PATH"
        export PKG_CONFIG_PATH="$HOME/.lilith/lib/pkgconfig:$HOME/.lilith/libdata/pkgconfig:$PKG_CONFIG_PATH"
EOF
}

#
# Remove dead symlinks from lib directory
#
remove_dead_symlinks() {
    if [ ! -d "$LILITH_DIR/lib" ]; then
        return 0
    fi

    # Find all symlinks in lib directory and check if they're broken
    find "$LILITH_DIR/lib" -maxdepth 1 -type l 2>/dev/null | while read -r symlink; do
        if [ ! -e "$symlink" ]; then
            local symlink_name
            symlink_name=$(basename "$symlink")
            if rm -f "$symlink" 2>/dev/null; then
                : # Removed dead symlink
            else
                print_warning "Failed to remove dead symlink: $symlink_name"
            fi
        fi
    done
}

#
# Fix symlinks for all installed packages
#
cmd_fix_symlinks() {
    if ! init_lilith_dir; then
        return 1
    fi

    print_info "Cleaning up dead symlinks..."
    remove_dead_symlinks

    print_info "Creating symlinks for all installed packages..."
    create_library_symlinks
    print_success "Symlink creation completed"
    return 0
}

#
# Show environment setup
#
show_environment_setup() {
    print_info "For devil users, add to ~/.bash_profile:"
    print_info '  export PATH="$HOME/.lilith/bin:$HOME/.lilith/sbin:$PATH"'
    print_info '  export LD_LIBRARY_PATH="$HOME/.lilith/lib:$LD_LIBRARY_PATH"'
    print_info '  export MANPATH="$HOME/.lilith/share/man:$MANPATH"'
    print_info '  export C_INCLUDE_PATH="$HOME/.lilith/include:$C_INCLUDE_PATH"'
    print_info '  export CPLUS_INCLUDE_PATH="$HOME/.lilith/include:$CPLUS_INCLUDE_PATH"'
    print_info '  export PKG_CONFIG_PATH="$HOME/.lilith/lib/pkgconfig:$HOME/.lilith/libdata/pkgconfig:$PKG_CONFIG_PATH"'
}

#
# Main function
#
main() {
    if ! check_dependencies; then
        exit 1
    fi

    case "${1:-help}" in
    install)
        shift
        if cmd_install "$@"; then
            # Show environment setup instructions only after successful installation
            print_info ""
            show_environment_setup
        fi
        ;;
    update)
        cmd_update "$2"
        ;;
    remove)
        shift
        cmd_remove "$@"
        ;;
    search)
        shift
        cmd_search "$@"
        ;;
    info)
        cmd_info "$2"
        ;;
    list)
        cmd_list
        ;;
    update-metadata)
        cmd_update_metadata
        ;;
    fix-symlinks)
        cmd_fix_symlinks
        ;;
    help | --help | -h)
        cmd_help
        ;;
    *)
        print_error "Unknown command: ${1:-help}"
        print_info "Run 'lilith help' for usage information"
        exit 1
        ;;
    esac
}

# Run main function with all arguments
main "$@"
