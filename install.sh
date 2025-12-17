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

# Configure shell rc files with Nix environment variables
configure_shell_rc() {
  local nix_dir="$1"
  local local_bin_dir="$2"
  
  # Create shared configuration directory
  local config_dir="${HOME}/.config/rootless-devbox"
  local shared_config_bash="${config_dir}/env.sh"
  local shared_config_fish="${config_dir}/env.fish"
  
  mkdir -p "$config_dir"
  
  echo ""
  echo_color "$CYAN" "Creating shared configuration files..."
  
  # Determine where to store Nix-specific cache/data
  local nix_parent_dir=$(dirname "${nix_dir}")
  local nix_cache_target
  local nix_data_target
  
  # If using custom location, store Nix cache/data there; otherwise use defaults
  if [[ "${nix_dir}" != "${HOME}/.nix" ]]; then
    nix_cache_target="${nix_parent_dir}/cache/nix"
    nix_data_target="${nix_parent_dir}/data/nix"
  else
    # Using default location, no symlinks needed
    nix_cache_target="${HOME}/.cache/nix"
    nix_data_target="${HOME}/.local/share/nix"
  fi
  
  # Create shared config for bash/zsh
  cat > "$shared_config_bash" <<'BASHEOF'
# Rootless-DevBox Environment Configuration
# This file is sourced by your shell configuration

# Add ~/.local/bin to PATH if not already present
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# Nix environment variables
BASHEOF
  echo "export NIX_BASE_DIR=\"${nix_dir}\"" >> "$shared_config_bash"
  cat >> "$shared_config_bash" <<'BASHEOF'

# Add Nix profile to PATH (allows running Nix-installed programs globally)
if [ -d "\$HOME/.nix-profile/bin" ]; then
  export PATH="\$HOME/.nix-profile/bin:\$PATH"
fi

# Source Nix environment if available
if [ -f "\$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  source "\$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Nix-chroot environment indicator for bash
if [ "\$NIX_CHROOT" = "1" ] && [ -n "\$BASH_VERSION" ]; then
  PS1="(nix-chroot) \\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ "
fi

# Nix-chroot environment indicator for zsh
if [ "\$NIX_CHROOT" = "1" ] && [ -n "\$ZSH_VERSION" ]; then
  PS1="(nix-chroot) %F{green}%n@%m%f:%F{blue}%~%f%# "
fi
BASHEOF
  
  print_success "Created shared configuration: $shared_config_bash"
  
  # Create symlinks for Nix subdirectories if using custom location
  # This ensures both global Nix and nix-chroot use the same cache/data location
  if [[ "${nix_dir}" != "${HOME}/.nix" ]]; then
    echo ""
    echo_color "$CYAN" "Setting up Nix cache/data directories on external storage..."
    
    # Create target directories on external storage
    mkdir -p "${nix_cache_target}"
    mkdir -p "${nix_data_target}"
    
    # Ensure XDG parent directories exist
    mkdir -p "${HOME}/.cache"
    mkdir -p "${HOME}/.local/share"
    
    # Create symlinks (backup existing directories if needed)
    if [ -e "${HOME}/.cache/nix" ] && [ ! -L "${HOME}/.cache/nix" ]; then
      echo_color "$YELLOW" "Backing up existing ${HOME}/.cache/nix to ${HOME}/.cache/nix.backup"
      mv "${HOME}/.cache/nix" "${HOME}/.cache/nix.backup"
    fi
    ln -sfn "${nix_cache_target}" "${HOME}/.cache/nix"
    print_success "Symlinked ~/.cache/nix → ${nix_cache_target}"
    
    if [ -e "${HOME}/.local/share/nix" ] && [ ! -L "${HOME}/.local/share/nix" ]; then
      echo_color "$YELLOW" "Backing up existing ${HOME}/.local/share/nix to ${HOME}/.local/share/nix.backup"
      mv "${HOME}/.local/share/nix" "${HOME}/.local/share/nix.backup"
    fi
    ln -sfn "${nix_data_target}" "${HOME}/.local/share/nix"
    print_success "Symlinked ~/.local/share/nix → ${nix_data_target}"
    
    echo_color "$GREEN" "✓ Nix will use external storage for cache/data (both global and nix-chroot)"
    echo_color "$GREY" "  Other applications remain unaffected and use standard XDG locations"
  fi
  
  # Create shared config for fish
  cat > "$shared_config_fish" <<'FISHEOF'
# Rootless-DevBox Environment Configuration for Fish
# This file is sourced by Fish shell configuration

# Add ~/.local/bin to PATH if not already present
if not contains $HOME/.local/bin $PATH
    set -gx PATH $HOME/.local/bin $PATH
end

# Nix environment variables
FISHEOF
  echo "set -gx NIX_BASE_DIR \"${nix_dir}\"" >> "$shared_config_fish"
  cat >> "$shared_config_fish" <<'FISHEOF'

# Add Nix profile to PATH (allows running Nix-installed programs globally)
if test -d \$HOME/.nix-profile/bin
    set -gx PATH \$HOME/.nix-profile/bin \$PATH
end

# Source Nix environment if available
if test -f \$HOME/.nix-profile/etc/profile.d/nix.fish
    source \$HOME/.nix-profile/etc/profile.d/nix.fish
end

# Nix-chroot environment indicator for fish
if test "\$NIX_CHROOT" = "1"
    function fish_prompt
        echo -n "(nix-chroot) "
        set_color green
        echo -n (whoami)@(hostname)
        set_color normal
        echo -n ":"
        set_color blue
        echo -n (prompt_pwd)
        set_color normal
        echo -n "> "
    end
end
FISHEOF
  
  print_success "Created shared configuration: $shared_config_fish"
  
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
      # Fish uses 'source' command
      if ! grep -qF "source ${shared_config_fish}" "$shell_file_expanded"; then
        echo '' >> "$shell_file_expanded"
        echo '# Rootless-DevBox configuration' >> "$shell_file_expanded"
        echo "source ${shared_config_fish}" >> "$shell_file_expanded"
        print_success "Added Rootless-DevBox configuration source to $shell_file"
      else
        echo "  - Rootless-DevBox configuration already sourced"
      fi
    else
      # Bash/Zsh use '.' or 'source'
      if ! grep -qF "source ${shared_config_bash}" "$shell_file_expanded" && ! grep -qF ". ${shared_config_bash}" "$shell_file_expanded"; then
        echo '' >> "$shell_file_expanded"
        echo '# Rootless-DevBox configuration' >> "$shell_file_expanded"
        echo "source ${shared_config_bash}" >> "$shell_file_expanded"
        print_success "Added Rootless-DevBox configuration source to $shell_file"
      else
        echo "  - Rootless-DevBox configuration already sourced"
      fi
    fi
  done
  
  echo ""
  echo_color "$YELLOW" "Please restart your shell or run 'source <config-file>' for changes to take effect."
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
      echo_color "$GREY" "Example: ${HOME}/network_drive/users/$(whoami)/nix"
      echo_color "$GREY" "The installer will automatically append '/.nix' to your path"
      read -r custom_path
      
      # Expand tilde if present
      custom_path="${custom_path/#\~/$HOME}"
      
      if [ -z "$custom_path" ]; then
        echo_color "$YELLOW" "No path provided. Using default location."
        export NIX_BASE_DIR="${HOME}/.nix"
        break
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
            print_success "Created directory: $parent_dir"
            export NIX_BASE_DIR="${custom_path}/.nix"
            echo_color "$GREEN" "Nix will be installed at: ${NIX_BASE_DIR}"
            break
          else
            echo_color "$RED" "Failed to create directory. You may need appropriate permissions."
            echo_color "$YELLOW" "Please try a different location or use sudo to create the directory manually."
            continue
          fi
        elif [[ "$validation_choice" == "3" ]]; then
          echo_color "$GREEN" "Using default location: ${HOME}/.nix"
          export NIX_BASE_DIR="${HOME}/.nix"
          break
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
          echo_color "$GREEN" "Using default location: ${HOME}/.nix"
          export NIX_BASE_DIR="${HOME}/.nix"
          break
        else
          # Continue loop to try again
          continue
        fi
      else
        # Valid path
        export NIX_BASE_DIR="${custom_path}/.nix"
        echo_color "$GREEN" "Nix will be installed at: ${NIX_BASE_DIR}"
        break
      fi
    done
  else
    echo_color "$GREEN" "Using default location: ${HOME}/.nix"
    export NIX_BASE_DIR="${HOME}/.nix"
  fi
}

# Main installation process
main() {
  local local_bin_dir="${HOME}/.local/bin"
  local devbox_path="${local_bin_dir}/devbox"
  local nix_chroot_path="${local_bin_dir}/nix-chroot"
  local nix_user_chroot_path="${local_bin_dir}/nix-user-chroot"
  # NIX_BASE_DIR is set by ask_nix_directory() or can be pre-set by user
  local nix_symlinked_path="${NIX_BASE_DIR:-${HOME}/.nix}"
  local nix_dir=$(readlink -f "${nix_symlinked_path}")

  # Check if readlink succeeded (optional, but good)
  if [ -z "$nix_dir" ]; then
    echo "ERROR: Could not resolve symlink for ${nix_symlinked_path}. Aborting."
    exit 1
  fi

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
  ask_nix_directory

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

  # Step 4: Install Nix in rootless mode using nix-user-chroot
  print_step "Installing Nix in rootless mode"
  if [ ! -d "${HOME}/.nix-profile" ]; then
    "$nix_user_chroot_path" "$nix_dir" bash -c "curl -L ${NIX_INSTALL_URL} | bash"
    print_success "Nix installed in rootless mode"
  else
    echo "Nix already installed in ~/.nix-profile, skipping Nix installation."
  fi

  # Step 5: Create nix-chroot script
  print_step "Installing nix-chroot script"
  local nix_chroot_path_in_bin="${local_bin_dir}/nix-chroot"
  cat > "$nix_chroot_path_in_bin" <<EOF
#!/bin/bash
exec \${HOME}/.local/bin/nix-user-chroot ${nix_dir} env NIX_CHROOT=1 bash -l
EOF
  chmod +x "$nix_chroot_path_in_bin"
  print_success "Created nix-chroot script at ${nix_chroot_path_in_bin}"

  # Step 6: Continue with DevBox installation process
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
    
    configure_shell_rc "${nix_dir}" "${local_bin_dir}"
    
    echo_color "$YELLOW" "Environment variables configured. Now installing DevBox automatically in nix-chroot environment..."
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
    echo "After you have successfully completed BOTH steps above, would you like this script"
    echo "to configure your shell configuration files? (Adds ${local_bin_dir} to PATH and environment variables) [y/N]"
    read -r configure_shell
    if [[ "$configure_shell" =~ ^[Yy] ]]; then
      print_step "Configuring shell environment"
      
      configure_shell_rc "${nix_dir}" "${local_bin_dir}"
      echo ""
      echo_color "$GREEN" "DevBox setup process is complete!"
      echo "To use DevBox: "
      echo "1. Start the environment: '${local_bin_dir}/nix-chroot' (or 'nix-chroot' if PATH is set from new shell)"
      echo "2. Then use 'devbox' commands."
    else
      echo_color "$YELLOW" "Configuration of shell rc files skipped as per your choice."
      echo "Please ensure '${local_bin_dir}' is in your PATH for 'nix-chroot' and 'devbox' to work easily."
      echo "You might want to manually add to your shell configuration file:"
      echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
      echo "  export NIX_BASE_DIR=\"${nix_dir}\""
      echo "  export XDG_CACHE_HOME=\"\$NIX_BASE_DIR/cache\""
      echo "  export XDG_DATA_HOME=\"\$NIX_BASE_DIR/state\""
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
