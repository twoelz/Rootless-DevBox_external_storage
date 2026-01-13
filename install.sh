#!/usr/bin/env bash
set -euo pipefail

# Rootless-DevBox Installer
# 
# This script automates the installation of DevBox in a rootless environment
# using nix-user-chroot without requiring root privileges.
#
# Repository: https://github.com/nebstudio/Rootless-DevBox

# Color definitions
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"
GREY="\033[90m" # Added GREY color
CYAN="\033[0;36m" # Added CYAN color

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

# Print error message
print_error() {
  echo_color "$RED" "✗ $1"
  exit 1
}

# Check if the system supports user namespaces (required for nix-user-chroot)
check_user_namespace_support() {
  print_step "Checking system compatibility"
  echo "Verifying if your system supports unprivileged user namespaces (required for nix-user-chroot)..."
  
  if ! unshare --user --pid echo "YES" &>/dev/null; then
    print_error "Your system does not support unprivileged user namespaces, which is required for nix-user-chroot to work.

This can happen in:
- Older Linux kernels
- Systems with user namespaces disabled
- Containerized environments like Docker or GitHub Codespaces

Please run this script on a compatible Linux system, or use an alternative installation method.
For more information, see: https://github.com/nix-community/nix-user-chroot"
  fi
  print_success "System supports unprivileged user namespaces"
}

# Detect system architecture
get_architecture() {
  local arch=$(uname -m)
  
  case "$arch" in
    x86_64)
      echo "x86_64-unknown-linux-musl"
      ;;
    aarch64|arm64)
      echo "aarch64-unknown-linux-musl"
      ;;
    armv7*)
      echo "armv7-unknown-linux-musleabihf"
      ;;
    i686|i386)
      echo "i686-unknown-linux-musl"
      ;;
    *)
      print_error "Unsupported architecture: $arch"
      ;;
  esac
}

# Download a file with progress
download_file() {
  local url="$1"
  local output_file="$2"
  
  if command -v curl &>/dev/null; then
    curl -fsSL "$url" -o "$output_file" || return 1
  elif command -v wget &>/dev/null; then
    wget -q "$url" -O "$output_file" || return 1
  else
    print_error "Neither curl nor wget found. Please install one of them and try again."
  fi
}

# Create temporary directory for installation files
create_temp_dir() {
  mktemp -d 2>/dev/null || print_error "Failed to create temporary directory"
}

# Set Nix mirror if needed
set_nix_mirror_if_needed() {
  echo ""
  echo_color "$YELLOW" "Are you located in mainland China and want to use the SJTU Nix mirror for faster downloads? [y/N]"
  read -r use_mirror
  use_mirror=${use_mirror:-n}
  if [[ "$use_mirror" =~ ^[Yy]$ ]]; then
    export NIX_USER_CHROOT_MIRROR="gitee"
    export NIX_INSTALL_URL="https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install"
    local nix_conf_dir="${HOME}/.config/nix"
    local nix_conf_file="${nix_conf_dir}/nix.conf"
    mkdir -p "$nix_conf_dir"
    if grep -q '^substituters =' "$nix_conf_file" 2>/dev/null; then
      sed -i 's|^substituters =.*|substituters = https://mirror.sjtu.edu.cn/nix-channels/store https://cache.nixos.org/|' "$nix_conf_file"
    else
      echo "substituters = https://mirror.sjtu.edu.cn/nix-channels/store https://cache.nixos.org/" >> "$nix_conf_file"
    fi
    echo_color "$GREEN" "Configured Nix to use SJTU mirror."
    echo "You can edit ${nix_conf_file} to adjust this setting."
  else
    export NIX_USER_CHROOT_MIRROR="github"
    export NIX_INSTALL_URL="https://nixos.org/nix/install"
  fi
}

# Configure shell rc files to add ~/.local/bin to PATH
configure_shell_rc() {
  local local_bin_dir="$1"
  
  # Detect available shells
  local shells=()
  local current_shell=$(basename "$SHELL")
  
  echo ""
  echo_color "$CYAN" "Detecting shell configuration files..."
  
  # Check for common shell rc files
  [[ -f ~/.bashrc ]] && shells+=("bash:~/.bashrc")
  [[ -f ~/.zshrc ]] && shells+=("zsh:~/.zshrc")
  [[ -f ~/.config/fish/config.fish ]] && shells+=("fish:~/.config/fish/config.fish")
  
  if [ ${#shells[@]} -eq 0 ]; then
    echo_color "$YELLOW" "No shell configuration files found. Creating ~/.bashrc"
    touch ~/.bashrc
    shells+=("bash:~/.bashrc")
  fi
  
  echo "Found the following shell configuration files:"
  for i in "${!shells[@]}"; do
    local shell_info="${shells[$i]}"
    local shell_name="${shell_info%%:*}"
    local shell_file="${shell_info#*:}"
    if [ "$shell_name" = "$current_shell" ]; then
      echo "  $((i+1)). $shell_file ($shell_name) [current shell]"
    else
      echo "  $((i+1)). $shell_file ($shell_name)"
    fi
  done
  
  echo ""
  echo "Which shell configuration files would you like to update?"
  echo "Enter numbers separated by spaces (e.g., '1 2'), or 'all' for all shells, or 'current' for current shell only:"
  read -r shell_choice
  
  local files_to_update=()
  
  if [[ "$shell_choice" == "all" ]]; then
    files_to_update=("${shells[@]}")
  elif [[ "$shell_choice" == "current" ]]; then
    for shell_info in "${shells[@]}"; do
      local shell_name="${shell_info%%:*}"
      if [ "$shell_name" = "$current_shell" ]; then
        files_to_update+=("$shell_info")
        break
      fi
    done
  else
    for num in $shell_choice; do
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#shells[@]}" ]; then
        files_to_update+=("${shells[$((num-1))]}")
      fi
    done
  fi
  
  if [ ${#files_to_update[@]} -eq 0 ]; then
    echo_color "$YELLOW" "No shells selected. Skipping shell configuration."
    return
  fi
  
  # Update selected shell files with a single source line
  for shell_info in "${files_to_update[@]}"; do
    local shell_name="${shell_info%%:*}"
    local shell_file="${shell_info#*:}"
    local shell_file_expanded="${shell_file/#\~/$HOME}"
    
    echo ""
    echo_color "$BLUE" "Configuring $shell_file..."
    
    if [ "$shell_name" = "fish" ]; then
      # Fish shell - add PATH check
      if ! grep -q "# Rootless-DevBox: Add ~/.local/bin to PATH" "$shell_file_expanded"; then
        echo '' >> "$shell_file_expanded"
        echo '# Rootless-DevBox: Add ~/.local/bin to PATH' >> "$shell_file_expanded"
        echo 'if not contains $HOME/.local/bin $PATH' >> "$shell_file_expanded"
        echo '    set -gx PATH $HOME/.local/bin $PATH' >> "$shell_file_expanded"
        echo 'end' >> "$shell_file_expanded"
        print_success "Added ~/.local/bin to PATH in $shell_file"
      else
        echo "  - ~/.local/bin PATH configuration already present"
      fi
    else
      # Bash/Zsh - add PATH check
      if ! grep -q "# Rootless-DevBox: Add ~/.local/bin to PATH" "$shell_file_expanded"; then
        echo '' >> "$shell_file_expanded"
        echo '# Rootless-DevBox: Add ~/.local/bin to PATH' >> "$shell_file_expanded"
        echo 'if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then' >> "$shell_file_expanded"
        echo '  export PATH="$HOME/.local/bin:$PATH"' >> "$shell_file_expanded"
        echo 'fi' >> "$shell_file_expanded"
        print_success "Added ~/.local/bin to PATH in $shell_file"
      else
        echo "  - ~/.local/bin PATH configuration already present"
      fi
    fi
  done
  
  echo ""
  echo_color "$YELLOW" "Please restart your shell or run 'source <config-file>' for changes to take effect."
}

# =============================================================================
# OPTIONAL FEATURE: Auto-start nix-chroot on shell initialization
# =============================================================================
# This function adds auto-chroot configuration to shell RC files.
# When enabled, every new interactive shell will automatically enter nix-chroot,
# making global Nix packages available without manually running 'nix-chroot'.
#
# Useful for: Anyone who wants global packages (from 'devbox global add' or
#             'nix-env -i') to work automatically in every new shell
# Trade-off: Adds startup delay per shell (~100ms local, 2-10s network storage)
# Bypass: Set SKIP_NIX_CHROOT=1 before opening shell (e.g., SKIP_NIX_CHROOT=1 bash)
#
# To remove this feature:
# 1. Delete this entire function
# 2. Remove the call to setup_auto_chroot_if_requested in main()
# 3. Shell RC files remain unmodified (clean install)
# =============================================================================
setup_auto_chroot_if_requested() {
  local nix_dir="$1"
  local files_to_update=("$@")
  # Remove first argument (nix_dir) to get list of shell files
  shift
  files_to_update=("$@")
  
  if [ ${#files_to_update[@]} -eq 0 ]; then
    return
  fi
  
  echo ""
  echo_color "$CYAN" "═══════════════════════════════════════════════════════════"
  echo_color "$CYAN" "Optional: Auto-start nix-chroot for global packages"
  echo_color "$CYAN" "═══════════════════════════════════════════════════════════"
  echo ""
  echo "This feature automatically enters nix-chroot when you open a new shell,"
  echo "making global Nix packages (from 'devbox global add' or 'nix-env -i')"
  echo "available immediately without typing 'nix-chroot' manually."
  echo ""
  echo_color "$YELLOW" "Trade-offs:"
  echo "  ${GREEN}+${RESET} Convenience: Global packages work in every new shell"
  echo "  ${RED}-${RESET} Performance: Adds 2-10s startup delay (especially with network storage)"
  echo ""
  echo_color "$GREY" "Bypass anytime: SKIP_NIX_CHROOT=1 bash (or fish/zsh)"
  echo ""
  echo_color "$YELLOW" "Enable auto-chroot? [y/N]"
  read -r enable_auto
  enable_auto=${enable_auto:-n}
  
  if [[ ! "$enable_auto" =~ ^[Yy]$ ]]; then
    echo_color "$GREEN" "Auto-chroot disabled. Use 'nix-chroot' manually when needed."
    return
  fi
  
  # Add auto-chroot to each selected shell file
  for shell_info in "${files_to_update[@]}"; do
    local shell_name="${shell_info%%:*}"
    local shell_file="${shell_info#*:}"
    local shell_file_expanded="${shell_file/#\~/$HOME}"
    
    if [ "$shell_name" = "fish" ]; then
      if ! grep -q "# Rootless-DevBox: Auto-start nix-chroot" "$shell_file_expanded"; then
        echo '' >> "$shell_file_expanded"
        echo '# Rootless-DevBox: Auto-start nix-chroot for global packages' >> "$shell_file_expanded"
        echo '# Set SKIP_NIX_CHROOT=1 to bypass (e.g., SKIP_NIX_CHROOT=1 fish)' >> "$shell_file_expanded"
        echo 'if status is-interactive; and not set -q NIX_CHROOT; and not set -q SKIP_NIX_CHROOT' >> "$shell_file_expanded"
        echo "    if test -x \$HOME/.local/bin/nix-user-chroot" >> "$shell_file_expanded"
        echo "        exec \$HOME/.local/bin/nix-user-chroot ${nix_dir} env NIX_CHROOT=1 fish" >> "$shell_file_expanded"
        echo '    end' >> "$shell_file_expanded"
        echo 'end' >> "$shell_file_expanded"
        print_success "Added auto-chroot to $shell_file"
      fi
    else
      if ! grep -q "# Rootless-DevBox: Auto-start nix-chroot" "$shell_file_expanded"; then
        # Determine the correct shell to exec (bash or zsh)
        local exec_shell="bash"
        if [ "$shell_name" = "zsh" ]; then
          exec_shell="zsh"
        fi
        
        echo '' >> "$shell_file_expanded"
        echo '# Rootless-DevBox: Auto-start nix-chroot for global packages' >> "$shell_file_expanded"
        echo "# Set SKIP_NIX_CHROOT=1 to bypass (e.g., SKIP_NIX_CHROOT=1 ${exec_shell})" >> "$shell_file_expanded"
        echo 'if [[ $- == *i* ]] && [ -z "$NIX_CHROOT" ] && [ -z "$SKIP_NIX_CHROOT" ]; then' >> "$shell_file_expanded"
        echo '  if [ -x "$HOME/.local/bin/nix-user-chroot" ]; then' >> "$shell_file_expanded"
        echo "    exec \$HOME/.local/bin/nix-user-chroot ${nix_dir} env NIX_CHROOT=1 ${exec_shell} -l" >> "$shell_file_expanded"
        echo '  fi' >> "$shell_file_expanded"
        echo 'fi' >> "$shell_file_expanded"
        print_success "Added auto-chroot to $shell_file"
      fi
    fi
  done
  
  echo ""
  echo_color "$GREEN" "✓ Auto-chroot enabled! Global packages will be available in new shells."
  echo_color "$GREY" "  Note: Shell startup will be 2-10s slower due to nix-chroot initialization."
  echo_color "$GREY" "  Bypass anytime with: SKIP_NIX_CHROOT=1 bash (or fish/zsh)"
}

# Setup Nix cache symlink if using custom location
# Data/database stays local for reliability (small size, critical for Nix operation)
setup_nix_cache_symlinks() {
  local nix_dir="$1"
  
  # Only set up symlinks if using custom location
  if [[ "${nix_dir}" == "${HOME}/.nix" ]]; then
    return 0
  fi
  
  echo ""
  echo_color "$CYAN" "Setting up Nix cache directory on external storage..."
  
  local nix_parent_dir=$(dirname "${nix_dir}")
  local nix_cache_target="${nix_parent_dir}/cache/nix"
  
  # Create target directory on external storage
  mkdir -p "${nix_cache_target}"
  
  # Ensure XDG parent directory exists
  mkdir -p "${HOME}/.cache"
  
  # Create symlink (backup existing directory if needed)
  if [ -L "${HOME}/.cache/nix" ]; then
    # Already a symlink - check if it points to the same location
    local existing_target=$(readlink -f "${HOME}/.cache/nix" 2>/dev/null || readlink "${HOME}/.cache/nix")
    if [ "$existing_target" != "${nix_cache_target}" ] && [ -n "$existing_target" ]; then
      echo_color "$YELLOW" "Warning: ~/.cache/nix already symlinks to: $existing_target"
      echo_color "$YELLOW" "This will be changed to: ${nix_cache_target}"
    fi
  elif [ -e "${HOME}/.cache/nix" ]; then
    # Exists as a real directory
    echo_color "$YELLOW" "Backing up existing ${HOME}/.cache/nix to ${HOME}/.cache/nix.backup"
    mv "${HOME}/.cache/nix" "${HOME}/.cache/nix.backup"
  fi
  ln -sfn "${nix_cache_target}" "${HOME}/.cache/nix"
  print_success "Symlinked ~/.cache/nix → ${nix_cache_target}"
  
  echo_color "$GREEN" "✓ Nix cache on external storage (saves space, safe to clear)"
  echo_color "$GREY" "  Database remains in ~/.local/share/nix (local, small, critical)"
}

# Ask user for Nix installation directory
ask_nix_directory() {
  echo ""
  echo_color "$CYAN" "Where would you like to install Nix?"
  echo "The Nix store requires significant disk space and will be located at this path."
  echo ""
  echo "Options:"
  echo "  1. Default location (${HOME}/.nix)"
  echo "  2. Custom location (e.g., external storage like 'network_drive')"
  echo ""
  echo_color "$YELLOW" "Enter '1' for default, or '2' to specify a custom path:"
  read -r nix_dir_choice
  
  if [[ "$nix_dir_choice" == "2" ]]; then
    while true; do
      echo ""
      echo "Enter the custom directory path (without the trailing '/.nix'):"
      echo_color "$GREY" "Example: /mnt/external/nix or ${HOME}/custom_storage/nix"
      echo_color "$GREY" "The installer will automatically append '/.nix' to your path"
      read -r custom_path
      
      # Expand tilde if present
      custom_path="${custom_path/#\~/$HOME}"
      
      if [ -z "$custom_path" ]; then
        echo_color "$YELLOW" "No path provided. Using default location." >&2
        echo "${HOME}/.nix"
        return 0
      fi
      
      # Validate the path
      local parent_dir=$(dirname "$custom_path")
      
      # Check if parent directory exists or can be accessed
      if [ ! -d "$parent_dir" ]; then
        echo_color "$RED" "Error: Parent directory '$parent_dir' does not exist."
        echo ""
        echo "Options:"
        echo "  1. Create the parent directory now"
        echo "  2. Try a different path"
        echo "  3. Use default location (${HOME}/.nix)"
        echo ""
        echo_color "$YELLOW" "Enter your choice (1/2/3):"
        read -r validation_choice
        
        if [[ "$validation_choice" == "1" ]]; then
          if mkdir -p "$parent_dir" 2>/dev/null; then
            print_success "Created directory: $parent_dir" >&2
            local result_path="${custom_path}/.nix"
            echo_color "$GREEN" "Nix will be installed at: ${result_path}" >&2
            echo "$result_path"
            return 0
          else
            echo_color "$RED" "Failed to create directory. You may need appropriate permissions."
            echo_color "$YELLOW" "Please try a different location or use sudo to create the directory manually."
            continue
          fi
        elif [[ "$validation_choice" == "3" ]]; then
          echo_color "$GREEN" "Using default location: ${HOME}/.nix" >&2
          echo "${HOME}/.nix"
          return 0
        else
          # Continue loop to try again (choice 2 or invalid input)
          continue
        fi
      elif [ ! -w "$parent_dir" ]; then
        echo_color "$RED" "Error: No write permission for '$parent_dir'."
        echo ""
        echo "Options:"
        echo "  1. Try a different path"
        echo "  2. Use default location (${HOME}/.nix)"
        echo ""
        echo_color "$YELLOW" "Enter your choice (1/2):"
        read -r permission_choice
        
        if [[ "$permission_choice" == "2" ]]; then
          echo_color "$GREEN" "Using default location: ${HOME}/.nix" >&2
          echo "${HOME}/.nix"
          return 0
        else
          # Continue loop to try again
          continue
        fi
      else
        # Valid path
        local result_path="${custom_path}/.nix"
        echo_color "$GREEN" "Nix will be installed at: ${result_path}" >&2
        echo "$result_path"
        return 0
      fi
    done
  else
    echo_color "$GREEN" "Using default location: ${HOME}/.nix" >&2
    echo "${HOME}/.nix"
    return 0
  fi
}

# Main installation process
main() {
  local local_bin_dir="${HOME}/.local/bin"
  local devbox_path="${local_bin_dir}/devbox"
  local nix_chroot_path="${local_bin_dir}/nix-chroot"
  local nix_user_chroot_path="${local_bin_dir}/nix-user-chroot"
  local nix_dir=""
  local nix_user_chroot_version="1.2.2"
  local arch=$(get_architecture)
  local temp_dir=$(create_temp_dir)

  if [ -x "$devbox_path" ] && [ -x "$nix_chroot_path" ] && [ -x "$nix_user_chroot_path" ]; then
    echo_color "$GREEN" "All components are already installed!"
    echo "You can use 'nix-chroot' to enter the environment and 'devbox' directly."
    exit 0
  fi

  echo_color "$BOLD" "Rootless-DevBox Installer"
  echo "This script will install DevBox in a rootless environment."
  echo "It will make changes only to your user environment and will not require root permissions."
  echo ""

  # Check if the system supports user namespaces (required for nix-user-chroot)
  check_user_namespace_support
  
  # Ask user where to install Nix
  nix_dir=$(ask_nix_directory)
  
  if [ -z "$nix_dir" ]; then
    print_error "Failed to determine Nix installation directory."
    exit 1
  fi
  
  # Strip trailing slash if present to avoid path issues
  nix_dir="${nix_dir%/}"

  # Step 1: Create ~/.local/bin directory
  print_step "Creating local bin directory"
  if [ -d "$local_bin_dir" ]; then
    echo "Directory $local_bin_dir already exists."
  else
    mkdir -p "$local_bin_dir"
    print_success "Created directory $local_bin_dir"
  fi

  set_nix_mirror_if_needed

  # Step 2: Download nix-user-chroot
  print_step "Downloading nix-user-chroot"
  local nix_user_chroot_filename="nix-user-chroot-bin-${nix_user_chroot_version}-${arch}"
  local nix_user_chroot_path="${local_bin_dir}/nix-user-chroot"
  local nix_user_chroot_url

  if [ "${NIX_USER_CHROOT_MIRROR:-github}" = "gitee" ]; then
    nix_user_chroot_url="https://gitee.com/wangshuyu1999/nix-user-chroot/releases/download/${nix_user_chroot_version}/${nix_user_chroot_filename}"
  else
    nix_user_chroot_url="https://github.com/nix-community/nix-user-chroot/releases/download/${nix_user_chroot_version}/${nix_user_chroot_filename}"
  fi

  echo "Architecture detected: ${arch}"
  echo "Downloading from: ${nix_user_chroot_url}"

  if ! download_file "$nix_user_chroot_url" "$nix_user_chroot_path"; then
    print_error "Failed to download nix-user-chroot. Please check your internet connection and try again."
  fi

  chmod +x "$nix_user_chroot_path"
  print_success "nix-user-chroot downloaded and made executable"

  # Step 3: Create ~/.nix directory (or other if using other folder) (with permissions)
  print_step "Creating Nix data directory (~/.nix or other folder for store)"
  if [ -d "$nix_dir" ]; then
    chmod 0755 "$nix_dir"
    echo "Directory $nix_dir already exists. Set permissions to 0755."
  else
    mkdir -m 0755 "$nix_dir"
    print_success "Created directory $nix_dir with permissions 0755"
  fi

  # Step 4: Set up Nix cache/data symlinks if using custom location
  setup_nix_cache_symlinks "${nix_dir}"

  # Step 5: Install Nix in rootless mode using nix-user-chroot
  print_step "Installing Nix in rootless mode"
  if [ ! -d "${HOME}/.nix-profile" ]; then
    "$nix_user_chroot_path" "$nix_dir" bash -c "curl -L ${NIX_INSTALL_URL} | bash"
    print_success "Nix installed in rootless mode"
  else
    echo "Nix already installed in ~/.nix-profile, skipping Nix installation."
  fi

  # Step 6: Create nix-chroot script
  print_step "Installing nix-chroot script"
  local nix_chroot_path_in_bin="${local_bin_dir}/nix-chroot"
  cat > "$nix_chroot_path_in_bin" <<EOF
#!/bin/bash
exec \${HOME}/.local/bin/nix-user-chroot ${nix_dir} env NIX_CHROOT=1 bash -l
EOF
  chmod +x "$nix_chroot_path_in_bin"
  print_success "Created nix-chroot script at ${nix_chroot_path_in_bin}"

  # Step 7: Continue with DevBox installation process
  print_step "Preparing DevBox installation"
  
  local devbox_install_script="${temp_dir}/devbox_install_user.sh"
  local permanent_devbox_install_script="${HOME}/devbox_install_user.sh" 
  
  cat > "$devbox_install_script" <<'EOF'
#!/bin/bash
#
# Install script
#
# Downloads and installs a binary from the given url.

set -euo pipefail

# ========================
# Customize install script
# ========================

readonly INSTALL_DIR="${HOME}/.local/bin"
readonly BIN="devbox"
readonly DOWNLOAD_URL="https://releases.jetify.com/devbox"

readonly TITLE="Devbox 📦 by Jetify (User Install)"
readonly DESCRIPTION=$(
    cat <<EOD
  Instant, easy and predictable development environments.

  This script downloads and installs the latest devbox binary to your user directory.
EOD
)
readonly DOCS_URL="https://github.com/jetify-com/devbox"
readonly COMMUNITY_URL="https://discord.gg/jetify"

FORCE="${FORCE:-0}"

parse_flags() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -f | --force)
            FORCE=1
            shift 1
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
        esac
    done
}

readonly BOLD="$(tput bold 2>/dev/null || echo '')"
readonly GREY="$(tput setaf 8 2>/dev/null || echo '')"
readonly UNDERLINE="$(tput smul 2>/dev/null || echo '')"
readonly RED="$(tput setaf 1 2>/dev/null || echo '')"
readonly GREEN="$(tput setaf 2 2>/dev/null || echo '')"
readonly YELLOW="$(tput setaf 3 2>/dev/null || echo '')"
readonly BLUE="$(tput setaf 4 2>/dev/null || echo '')"
readonly MAGENTA="$(tput setaf 5 2>/dev/null || echo '')"
readonly CYAN="$(tput setaf 6 2>/dev/null || echo '')"
readonly NO_COLOR="$(tput sgr0 2>/dev/null || echo '')"
readonly CLEAR_LAST_MSG="\033[1F\033[0K"

title() {
    local -r text="$*"
    printf "%s\n" "${BOLD}${MAGENTA}${text}${NO_COLOR}"
}

header() {
    local -r text="$*"
    printf "%s\n" "${BOLD}${text}${NO_COLOR}"
}

plain() {
    local -r text="$*"
    printf "%s\n" "${text}"
}

info() {
    local -r text="$*"
    printf "%s\n" "${BOLD}${GREY}→${NO_COLOR} ${text}"
}

warn() {
    local -r text="$*"
    printf "%s\n" "${YELLOW}! $*${NO_COLOR}"
}

error() {
    local -r text="$*"
    printf "%s\n" "${RED}✘ ${text}${NO_COLOR}" >&2
}

success() {
    local -r text="$*"
    printf "%s\n" "${GREEN}✓${NO_COLOR} ${text}"
}

start_task() {
    local -r text="$*"
    printf "%s\n" "${BOLD}${GREY}→${NO_COLOR} ${text}..."
}

end_task() {
    local -r text="$*"
    printf "${CLEAR_LAST_MSG}%s\n" "${GREEN}✓${NO_COLOR} ${text}... [DONE]"
}

fail_task() {
    local -r text="$*"
    printf "${CLEAR_LAST_MSG}%s\n" "${RED}✘ ${text}... [FAILED]${NO_COLOR}" >&2
}

confirm() {
    if [ ${FORCE-} -ne 1 ]; then
        printf "%s " "${MAGENTA}?${NO_COLOR} $* ${BOLD}[Y/n]${NO_COLOR}"
        set +e
        read -r yn </dev/tty
        rc=$?
        set -e
        if [ $rc -ne 0 ]; then
            error "Error reading from prompt (re-run with '-f' flag to auto select Yes if running in a script)"
            exit 1
        fi
        if [ "$yn" != "y" ] && [ "$yn" != "Y" ] && [ "$yn" != "yes" ] && [ "$yn" != "" ]; then
            error 'Aborting (please answer "yes" to continue)'
            exit 1
        fi
    fi
}

delay() {
    sleep 0.3
}

has() {
    command -v "$1" 1>/dev/null 2>&1
}

download() {
    local -r url="$1"
    local -r file="$2"
    local cmd=""

    if has curl; then
        cmd="curl --fail --silent --location --output $file $url"
    elif has wget; then
        cmd="wget --quiet --output-document=$file $url"
    elif has fetch; then
        cmd="fetch --quiet --output=$file $url"
    else
        error "No program to download files found. Please install one of: curl, wget, fetch"
        error "Exiting..."
        return 1
    fi

    if [[ ${3:-} == "--fail" ]]; then
        $cmd && return 0 || rc=$?
        error "Command failed (exit code $rc): ${BLUE}${cmd}${NO_COLOR}"
        exit $rc
    fi

    $cmd && return 0 || rc=$?
    return $rc
}

intro_msg() {
    title "${TITLE}"
    plain "${DESCRIPTION}"
    printf "\n"
    header "Confirm Installation Details"
    plain "  Location:     ${GREEN}${INSTALL_DIR}/${BIN}${NO_COLOR}"
    plain "  Download URL: ${UNDERLINE}${BLUE}${DOWNLOAD_URL}${NO_COLOR}"
    printf "\n"
}

install_flow() {
    confirm "Install ${GREEN}${BIN}${NO_COLOR} to ${GREEN}${INSTALL_DIR}${NO_COLOR}?"
    printf "\n"
    header "Downloading and Installing"

    start_task "Downloading ${BIN} binary"
    local -r tmp_file=$(mktemp)
    download "${DOWNLOAD_URL}" "${tmp_file}" --fail
    delay
    end_task "Downloading ${BIN} binary"

    start_task "Installing in ${INSTALL_DIR}/${BIN}"
    chmod +x "${tmp_file}"
    mkdir -p "${INSTALL_DIR}"
    mv "${tmp_file}" "${INSTALL_DIR}/${BIN}"
    delay
    end_task "Installing in ${INSTALL_DIR}/${BIN}"
    delay

    success "${BOLD}Successfully installed ${GREEN}${BIN}${NO_COLOR}${BOLD}${NO_COLOR} 🚀"
    delay
    printf "\n"
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        warn "NOTE: You may need to add ${INSTALL_DIR} to your PATH."
        plain "  You can do this by adding the following line to your shell configuration file (e.g., ~/.bashrc, ~/.zshrc):"
        plain "  export PATH=\"${INSTALL_DIR}:\$PATH\""
        plain "  Then, source the file (e.g., source ~/.bashrc) or open a new terminal."
        printf "\n"
    fi
}

next_steps_msg() {
    header "Next Steps"
    plain "  1. ${BOLD}Learn how to use ${BIN}${NO_COLOR}"
    plain "     ${GREY}Run ${CYAN}${BIN} help${GREY} or read the docs at ${UNDERLINE}${BLUE}${DOCS_URL}${NO_COLOR}"
    plain "  2. ${BOLD}Get help and give feedback${NO_COLOR}"
    plain "     ${GREY}Join our community at ${UNDERLINE}${BLUE}${COMMUNITY_URL}${NO_COLOR}"
}

main() {
    parse_flags "$@"
    intro_msg
    install_flow
    next_steps_msg
}

main "$@"
EOF
  
  chmod +x "$devbox_install_script"
  cp "$devbox_install_script" "$permanent_devbox_install_script"
  chmod +x "$permanent_devbox_install_script"
  print_success "Created DevBox installation script: ${devbox_install_script}"
  print_success "Created permanent backup at: ${permanent_devbox_install_script}"
  
  
  echo ""
  echo_color "$BOLD" "Next: Activate Nix Environment and Install DevBox"
  echo_color "$BOLD" "⚠️  IMPORTANT: Installation requires TWO steps! ⚠️"
  echo "You now need to enter the nix-chroot environment and then run the DevBox installer script."
  echo "The commands are:"
  echo_color "$YELLOW" "    1. ${local_bin_dir}/nix-chroot"
  echo_color "$YELLOW" "    2. (Inside nix-chroot) ${permanent_devbox_install_script}"
  echo ""
  echo "Would you like this script to attempt to run '${local_bin_dir}/nix-chroot' for you now? [Y/n]"
  echo_color "$GREY" "(If you choose yes, after nix-chroot starts, you MUST MANUALLY run the second command shown above)"
  
  if [ -t 0 ]; then
    read -r response
  else
    response="y"
    echo "Non-interactive mode detected. Defaulting to 'y'."
  fi
  
  response=${response:-y}
  
  if [[ "$response" =~ ^[Yy] ]]; then
    echo ""
    echo_color "$CYAN" "Attempting to start ${local_bin_dir}/nix-chroot..."
    echo_color "$BOLD$RED" "⚠️  CRITICAL STEP: After nix-chroot starts, you MUST run: ⚠️"
    echo_color "$YELLOW$BOLD" "    ${permanent_devbox_install_script}"
    echo ""
    echo "Without this step, devbox will NOT be installed!"
    echo "Press Enter to continue and execute ${local_bin_dir}/nix-chroot..."
    read -r
    if [ ! -x "${local_bin_dir}/nix-chroot" ]; then
        print_error "${local_bin_dir}/nix-chroot not found or not executable. Please check previous steps."
    fi
    
    # Check if ~/.local/bin is already in PATH
    if [[ ":$PATH:" == *":${local_bin_dir}:"* ]]; then
      echo ""
      echo_color "$GREEN" "✓ ${local_bin_dir} is already in your PATH"
      echo_color "$GREY" "  Skipping PATH configuration"
    else
      echo ""
      echo_color "$YELLOW" "${local_bin_dir} is not in your current PATH"
      echo "Would you like to add it to your shell configuration? [Y/n]"
      read -r add_to_path
      add_to_path=${add_to_path:-y}
      if [[ "$add_to_path" =~ ^[Yy]$ ]]; then
        # Detect shells for auto-chroot feature
        local shells_for_auto=()
        [[ -f ~/.bashrc ]] && shells_for_auto+=("bash:~/.bashrc")
        [[ -f ~/.zshrc ]] && shells_for_auto+=("zsh:~/.zshrc")
        [[ -f ~/.config/fish/config.fish ]] && shells_for_auto+=("fish:~/.config/fish/config.fish")
        
        configure_shell_rc "${local_bin_dir}"
        
        # Offer auto-chroot setup (optional feature)
        if [ ${#shells_for_auto[@]} -gt 0 ]; then
          setup_auto_chroot_if_requested "${nix_dir}" "${shells_for_auto[@]}"
        fi
      else
        echo_color "$YELLOW" "Skipped. You'll need to use full path: ${local_bin_dir}/nix-chroot"
      fi
    fi
    
    echo ""
    echo_color "$YELLOW" "Now installing DevBox automatically in nix-chroot environment..."
    "${local_bin_dir}/nix-user-chroot" "${nix_dir}" env NIX_CHROOT=1 bash "${permanent_devbox_install_script}"
    if [ -x "${local_bin_dir}/devbox" ]; then
      print_success "DevBox installed successfully! You can now use 'nix-chroot' and 'devbox'."
    else
      print_error "DevBox installation failed. Please check the output above or try manual installation."
    fi
    exit 0
  else
    echo ""
    echo_color "$YELLOW" "Okay, proceeding with manual installation guidance."
    echo "Please perform the following steps in your terminal:"
    echo "1. Run the nix-chroot environment. If '${local_bin_dir}' is not yet in your active PATH,"
    echo "   you can add it for your current session with 'export PATH=\"${local_bin_dir}:\$PATH\"' or use the full path:"
    echo_color "$CYAN" "     ${local_bin_dir}/nix-chroot"
    echo "2. Once inside the nix-chroot environment (e.g., you see '(nix-chroot)' in your prompt),"
    echo "   run the DevBox installer script:"
    echo_color "$CYAN" "     ${permanent_devbox_install_script}"
    echo ""
    # Check if ~/.local/bin is already in PATH
    if [[ ":$PATH:" == *":${local_bin_dir}:"* ]]; then
      echo ""
      echo_color "$GREEN" "✓ ${local_bin_dir} is already in your PATH"
      echo_color "$GREY" "  No shell configuration needed"
      echo ""
      echo_color "$GREEN" "DevBox setup process is complete!"
      echo "To use DevBox: "
      echo "1. Start the environment: 'nix-chroot'"
      echo "2. Then use 'devbox' commands."
    else
      echo "After you have successfully completed BOTH steps above, would you like to add"
      echo "${local_bin_dir} to your PATH via shell configuration? [y/N]"
      read -r configure_shell
      if [[ "$configure_shell" =~ ^[Yy]$ ]]; then
        print_step "Configuring shell environment"
        
        # Detect shells for auto-chroot feature
        local shells_for_auto=()
        [[ -f ~/.bashrc ]] && shells_for_auto+=("bash:~/.bashrc")
        [[ -f ~/.zshrc ]] && shells_for_auto+=("zsh:~/.zshrc")
        [[ -f ~/.config/fish/config.fish ]] && shells_for_auto+=("fish:~/.config/fish/config.fish")
        
        configure_shell_rc "${local_bin_dir}"
        
        # Offer auto-chroot setup (optional feature)
        local enable_auto_result="no"
        if [ ${#shells_for_auto[@]} -gt 0 ]; then
          setup_auto_chroot_if_requested "${nix_dir}" "${shells_for_auto[@]}"
          # Check if user enabled it by looking for the marker in any shell config
          if grep -q "# Rootless-DevBox: Auto-start nix-chroot" ~/.bashrc 2>/dev/null || \
             grep -q "# Rootless-DevBox: Auto-start nix-chroot" ~/.zshrc 2>/dev/null || \
             grep -q "# Rootless-DevBox: Auto-start nix-chroot" ~/.config/fish/config.fish 2>/dev/null; then
            enable_auto_result="yes"
          fi
        fi
        
        echo ""
        echo_color "$GREEN" "DevBox setup process is complete!"
        echo "To use DevBox: "
        if [ "$enable_auto_result" = "yes" ]; then
          echo "1. Open a new shell (auto-starts nix-chroot)"
          echo "2. Use 'devbox' commands directly"
        else
          echo "1. Start the environment: '${local_bin_dir}/nix-chroot' (or 'nix-chroot' in a new shell)"
          echo "2. Then use 'devbox' commands."
        fi
      else
        echo_color "$YELLOW" "Configuration skipped. You'll need to use the full path: ${local_bin_dir}/nix-chroot"
        echo "Or manually add to your shell configuration file:"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
      fi
    fi
  fi
  
  echo ""
  echo_color "$YELLOW" "⚠️  Verify Installation ⚠️"
  echo "After installation, please confirm the following files exist:"
  echo "1. ${local_bin_dir}/nix-user-chroot - Nix user chroot binary"
  echo "2. ${local_bin_dir}/nix-chroot - Script to enter Nix environment"
  echo "3. ${local_bin_dir}/devbox - DevBox binary (after completing step 2)"
  echo ""
  echo "If devbox doesn't exist, please enter the nix-chroot environment and run:"
  echo_color "$CYAN" "${permanent_devbox_install_script}"
  
  echo ""
  echo "If you encounter any issues, please report them at: https://github.com/nebstudio/Rootless-DevBox/issues"
  echo "If this script was helpful, please consider giving a Star on GitHub! ⭐"
}

main "$@"
