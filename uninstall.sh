#!/usr/bin/env bash
set -uo pipefail # -e is removed to allow checking command results without exiting immediately

# Rootless-DevBox Uninstaller
#
# This script removes DevBox and related configurations installed by Rootless-DevBox install.sh.
# Repository: https://github.com/nebstudio/Rootless-DevBox

# Color definitions
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"
GREY="\033[90m"
CYAN="\033[0;36m"

# Echo with color
echo_color() {
  local color="$1"
  local text="$2"
  echo -e "${color}${text}${RESET}"
}

# Print a step header
print_step() {
  echo_color "$BLUE" "\n=> $1"
}

# Print success message
print_success() {
  echo_color "$GREEN" "✓ $1"
}

# Print warning message
print_warning() {
  echo_color "$YELLOW" "⚠ $1"
}

# Print error message (does not exit by default, caller decides)
print_error_msg() {
  echo_color "$RED" "✗ $1"
}

# Confirm action
confirm_action() {
  local prompt_message="$1"
  local response
  # Correctly use echo -n with color codes directly
  echo -e -n "${YELLOW}${prompt_message} [y/N]: ${RESET}"
  read -r response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    return 0 # Yes
  else
    return 1 # No or anything else
  fi
}

remove_file_if_exists() {
  local file_path="$1"
  local file_description="$2"
  if [ -f "$file_path" ]; then
    if rm -f "$file_path"; then
      print_success "Removed $file_description: $file_path"
    else
      print_error_msg "Failed to remove $file_description: $file_path"
    fi
  else
    echo "$file_description not found at $file_path. Skipping."
  fi
}

# Remove Rootless-DevBox configuration from shell rc files
clean_shell_rc() {
  local rc_file="$1"
  local rc_file_expanded="${rc_file/#\~/$HOME}"
  
  if [ ! -f "$rc_file_expanded" ]; then
    echo "  $rc_file not found. Skipping."
    return
  fi
  
  # Check if file contains ANY Rootless-DevBox markers
  if ! grep -qE "(# Rootless-DevBox|# Added by Rootless-DevBox)" "$rc_file_expanded"; then
    echo "  No Rootless-DevBox configurations found in $rc_file"
    return
  fi
  
  local rc_backup="${rc_file_expanded}.devbox_uninstall_$(date +%Y%m%d%H%M%S).bak"
  echo "  Modifying $rc_file to remove Rootless-DevBox configuration"
  echo "  Creating backup: $rc_backup"
  
  if cp "$rc_file_expanded" "$rc_backup"; then
    # Create a temporary file for processing
    local temp_file="${rc_file_expanded}.tmp"
    
    # Process the file to remove Rootless-DevBox configurations
    # Note: We keep the PATH addition to ~/.local/bin as it's generally useful
    awk '
      /^# Rootless-DevBox: Auto-start nix-chroot/ {
        # Skip this line and the auto-chroot block
        while (getline > 0 && $0 !~ /^$/ && $0 !~ /^# [^R]/) {
          if ($0 ~ /^fi$/ || $0 ~ /^end$/) { getline; break; }
        }
        next
      }
      /^# Rootless-DevBox configuration$/ { next }
      /^# Added by Rootless-DevBox installer/ {
        while (getline > 0 && $0 !~ /^$/) { }
        next
      }
      /^# Rootless-DevBox Nix environment variables/ {
        while (getline > 0 && $0 !~ /^$/) { }
        next
      }
      /^# Rootless-DevBox nix-chroot environment indicator/ {
        while (getline > 0) { if ($0 ~ /^fi$/) break; }
        next
      }
      { print }
    ' "$rc_file_expanded" > "$temp_file"
    
    # Replace original with cleaned version
    mv "$temp_file" "$rc_file_expanded"
    
    print_success "  Processed $rc_file"
    echo "  Backup available at: $rc_backup"
  else
    print_error_msg "  Failed to create backup of $rc_file. Skipping modifications."
  fi
}

# Detect Nix installation directory from shell rc files
detect_nix_directory() {
  # Check for nix-chroot script which contains the actual nix directory path
  local nix_chroot_script="${HOME}/.local/bin/nix-chroot"
  
  if [ -f "$nix_chroot_script" ]; then
    # Extract the directory path from the nix-user-chroot command line
    local detected_dir=$(grep -oP 'nix-user-chroot \K[^ ]+' "$nix_chroot_script" 2>/dev/null | head -1)
    if [ -n "$detected_dir" ]; then
      # Expand any shell variables like ${HOME}
      # Basic validation: path should start with / or ~ or $
      if [[ "$detected_dir" =~ ^[/~$] ]]; then
        detected_dir=$(eval echo "$detected_dir")
        echo "$detected_dir"
        return 0
      fi
    fi
  fi
  
  # Fallback to default if not found
  echo "${HOME}/.nix"
  return 1
}

main() {
  local local_bin_dir="${HOME}/.local/bin"
  local devbox_path="${local_bin_dir}/devbox"
  local nix_chroot_path="${local_bin_dir}/nix-chroot"
  local nix_user_chroot_path="${local_bin_dir}/nix-user-chroot"
  
  # Detect Nix directory from shell configuration
  local nix_dir=$(detect_nix_directory)
  local nix_dir_detected=$?
  
  if [ $nix_dir_detected -eq 0 ]; then
    echo_color "$CYAN" "Detected Nix installation at: $nix_dir"
  else
    echo_color "$YELLOW" "Could not detect Nix installation location. Using default: $nix_dir"
  fi
  
  # Detect shell rc files
  local shell_rc_files=()
  [[ -f ~/.bashrc ]] && shell_rc_files+=("~/.bashrc")
  [[ -f ~/.zshrc ]] && shell_rc_files+=("~/.zshrc")
  [[ -f ~/.config/fish/config.fish ]] && shell_rc_files+=("~/.config/fish/config.fish")

  # Check if any component is installed
  local has_components=0
  [ -f "$devbox_path" ] || [ -f "$nix_chroot_path" ] || [ -f "$nix_user_chroot_path" ] || [ -d "$nix_dir" ] && has_components=1
  
  # Check shell rc files for configurations
  for rc_file in "${shell_rc_files[@]}"; do
    local rc_file_expanded="${rc_file/#\~/$HOME}"
    if [ -f "$rc_file_expanded" ] && grep -qE '(# Added by Rootless-DevBox installer|# Rootless-DevBox)' "$rc_file_expanded" 2>/dev/null; then
      has_components=1
      break
    fi
  done
  
  if [ $has_components -eq 0 ]; then
    echo_color "$YELLOW" "No Rootless-DevBox components found. Uninstallation is not required."
    exit 0
  fi

  echo_color "$BOLD" "Rootless-DevBox Uninstaller"
  echo "This script will attempt to remove DevBox and related components"
  echo "installed by the Rootless-DevBox installer."
  echo "It will target files in '${local_bin_dir}' and configurations in shell rc files."
  echo "The directory '${local_bin_dir}' itself will NOT be removed."
  echo ""

  if ! confirm_action "Are you sure you want to proceed with uninstallation?"; then
    echo_color "$YELLOW" "Uninstallation aborted by user."
    exit 0
  fi

  print_step "Removing installed files"
  remove_file_if_exists "${local_bin_dir}/devbox" "DevBox binary"
  remove_file_if_exists "${local_bin_dir}/nix-chroot" "nix-chroot script"
  remove_file_if_exists "${local_bin_dir}/nix-user-chroot" "nix-user-chroot binary"
  remove_file_if_exists "${HOME}/devbox_install_user.sh" "DevBox installer script"

  print_step "Processing shell configuration files"
  if [ ${#shell_rc_files[@]} -eq 0 ]; then
    print_warning "No shell configuration files found. Skipping shell rc modifications."
  else
    echo "Found ${#shell_rc_files[@]} shell configuration file(s) to check:"
    for rc_file in "${shell_rc_files[@]}"; do
      echo ""
      echo_color "$CYAN" "Processing $rc_file..."
      clean_shell_rc "$rc_file"
    done
    echo ""
    echo "Please review the modified files to ensure changes are correct."
    echo "Backups are available with the .devbox_uninstall_*.bak extension."
    echo "You may need to run 'source <rc-file>' or open a new terminal for changes to take effect."
  fi
  
  print_step "Removing shared configuration files"
  local config_dir="${HOME}/.config/rootless-devbox"
  if [ -d "$config_dir" ]; then
    if rm -rf "$config_dir"; then
      print_success "Removed Rootless-DevBox configuration directory: $config_dir"
    else
      print_error_msg "Failed to remove configuration directory: $config_dir"
    fi
  else
    echo "Configuration directory not found: $config_dir"
  fi

  print_step "Optionally removing Nix directory"
  if [ -d "$nix_dir" ]; then
    echo "The directory ${nix_dir} was used by Rootless-DevBox for Nix."
    echo "This directory may contain cached Nix derivations and other Nix-related data."
    print_warning "Nix often sets special permissions (immutable attributes) on its store files,"
    print_warning "which might prevent normal removal even with 'rm -rf'."
    if confirm_action "Do you want to attempt to remove the directory ${nix_dir}?"; then
      echo_color "$CYAN" "Attempting to reset permissions for ${nix_dir} (this may take a while)..."
      find "${nix_dir}" -print0 | xargs -0 -P"$(nproc)" -n100 chmod 777 2>/dev/null
      echo_color "$CYAN" "Attempting to remove ${nix_dir}..."
      # Attempt removal, suppressing stderr to avoid spamming permission errors on individual files
      if rm -rf "${nix_dir}" 2>/dev/null; then
        if [ ! -d "${nix_dir}" ]; then
            print_success "Successfully removed directory: ${nix_dir}"
        else
            print_warning "rm -rf command reported success, but the directory ${nix_dir} or some of its contents still exist."
            echo_color "$YELLOW" "This can happen if some files had immutable attributes that 'rm -rf' could not override without sudo."
            echo_color "$YELLOW" "Please check manually. You might need to use 'sudo' as described below if files remain."
        fi
      else
        print_error_msg "Failed to completely remove directory: ${nix_dir}."
        echo_color "$YELLOW" "This is common with Nix stores as files inside '${nix_dir}/store' often have immutable attributes."
        echo_color "$YELLOW" "To completely remove it, you might need to use 'sudo' or other manual steps:"
        echo_color "$YELLOW" "  Option 1 (if you have sudo access):"
        echo_color "$YELLOW" "    1. sudo chattr -R -i \"${nix_dir}\"  (Removes immutable attribute)"
        echo_color "$YELLOW" "    2. sudo rm -rf \"${nix_dir}\""
        echo_color "$YELLOW" "  Option 2 (if nix-chroot is still usable and was not removed):"
        echo_color "$YELLOW" "    1. Enter the environment (e.g., ~/.local/bin/nix-chroot)"
        echo_color "$YELLOW" "    2. Run Nix garbage collection: nix-store --gc"
        echo_color "$YELLOW" "    3. Exit nix-chroot, then try again: rm -rf \"${nix_dir}\""
        echo_color "$YELLOW" "If you lack sudo access and Option 2 doesn't work, some files or the directory may remain."
      fi
    else
      echo "Skipped removal of ${nix_dir}."
    fi
  else
    echo "Nix directory ${nix_dir} not found. Skipping."
  fi

  print_step "Removing Nix user profile files and symlinks"
  local items_removed=0
  
  # Remove .nix-profile symlink (or directory if it exists)
  if [ -L "${HOME}/.nix-profile" ] || [ -e "${HOME}/.nix-profile" ]; then
    if rm -rf "${HOME}/.nix-profile"; then
      print_success "Removed: ~/.nix-profile"
      items_removed=1
    else
      print_error_msg "Failed to remove: ~/.nix-profile"
    fi
  fi
  
  # Remove .nix-defexpr directory
  if [ -d "${HOME}/.nix-defexpr" ]; then
    if rm -rf "${HOME}/.nix-defexpr"; then
      print_success "Removed directory: ~/.nix-defexpr"
      items_removed=1
    else
      print_error_msg "Failed to remove directory: ~/.nix-defexpr"
    fi
  fi
  
  # Remove .nix-channels file
  if [ -f "${HOME}/.nix-channels" ]; then
    if rm "${HOME}/.nix-channels"; then
      print_success "Removed file: ~/.nix-channels"
      items_removed=1
    else
      print_error_msg "Failed to remove file: ~/.nix-channels"
    fi
  fi
  
  # Remove XDG symlinks
  if [ -L "${HOME}/.cache/nix" ]; then
    if rm "${HOME}/.cache/nix"; then
      print_success "Removed symlink: ~/.cache/nix"
      items_removed=1
    else
      print_error_msg "Failed to remove symlink: ~/.cache/nix"
    fi
  fi
  
  if [ -L "${HOME}/.local/share/nix" ]; then
    if rm "${HOME}/.local/share/nix"; then
      print_success "Removed symlink: ~/.local/share/nix"
      items_removed=1
    else
      print_error_msg "Failed to remove symlink: ~/.local/share/nix"
    fi
  fi
  
  if [ $items_removed -eq 0 ]; then
    echo "No Nix user profile files or symlinks found"
  fi

  echo ""
  print_success "Rootless-DevBox uninstallation process complete."
  echo "Please check any output above for details or manual steps required."
  echo "If you had sourced changes from shell rc files, you might need to open a new terminal"
  echo "or re-source your shell configuration for all changes to fully apply."
}

# Run the main function
main "$@"
exit 0