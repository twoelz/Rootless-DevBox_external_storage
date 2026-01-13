# Rootless-DevBox (with specific/external nix cache folder)

A simple, automated solution for installing Devbox in a rootless environment without requiring sudo or root privileges. Original version from: https://github.com/nebstudio/Rootless-DevBox.

**Fork info:**
This fork by https://github.com/twoelz adds several enhancements to support external storage installations and improve the overall installation experience. Key additions include:

**Main Features:**
1. **Custom Nix Store Location**: Interactive prompt to install Nix store on external storage (e.g., `/sgoinfre` at 42 school) instead of hardcoded `~/.nix`
2. **Smart Cache Symlinking**: Only symlinks cache to external storage, keeps critical database local
3. **Multi-Shell Support**: Configures bash, zsh, and fish shells (original only supported bash)
4. **China Network Mirrors**: Optional SJTU/Tsinghua mirrors for users in mainland China
5. **Auto-chroot Feature**: Optional automatic entry to nix-chroot on shell startup
6. **Enhanced Uninstaller**: Detects custom installation locations and safely removes all components

Below is a detailed description of the symlink approach:

When installing Nix to a custom location (e.g., external storage), the installer creates a symlink for the Nix cache directory:

~/.cache/nix → <custom-location>/cache/nix
Why only cache (not data/database):

Cache directory: Large (GBs), regenerable, safe to clear → goes to external storage
Data directory: Small (~MBs), contains critical SQLite database → stays local for reliability and performance
Benefits:

Space savings: Nix's download cache (largest non-store consumer) lives on external storage
Consistency: Both global Nix commands and nix-chroot use the same cache, preventing duplication
Isolation: Only Nix cache is redirected; other applications continue using ~/.cache normally
Reliability: Critical database remains on fast, reliable local storage (~/.local/share/nix)
Nix-compliant: The Nix store itself (~/.nix or custom location) remains a real directory (not a symlink)
Behavior:

Default installation (~/.nix): No symlinks created, uses standard XDG locations
Custom installation: Creates cache symlink, backs up any existing ~/.cache/nix directory
Database/state remains in ~/.local/share/nix for safety
This approach avoids setting global XDG_CACHE_HOME and XDG_DATA_HOME variables which would affect all applications system-wide.

**Shell Configuration:**
The installer adds configuration to your shell dotfiles (bash/zsh/fish). This configuration:
- Adds `~/.local/bin` and `~/.nix-profile/bin` to PATH (for running devbox/nix commands)
- Sources Nix's own environment setup
- Does NOT set XDG variables globally (cache redirection uses symlinks instead)

[![GitHub License](https://img.shields.io/github/license/nebstudio/Rootless-DevBox)](https://github.com/nebstudio/Rootless-DevBox/blob/main/LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/nebstudio/Rootless-DevBox?style=social)](https://github.com/nebstudio/Rootless-DevBox/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/nebstudio/Rootless-DevBox)](https://github.com/nebstudio/Rootless-DevBox/issues)

## What is Rootless-DevBox (with specific nix folders)?

Rootless-DevBox is a project that enables users to install and use [Devbox](https://github.com/jetify-com/devbox) in environments where they don't have root access, such as shared hosting, university systems, or corporate environments with restricted permissions. It leverages [nix-user-chroot](https://github.com/nix-community/nix-user-chroot) to create a containerized environment where Nix and Devbox can run without requiring elevated privileges.

## Features

- 🛡️ **No Root Required**: Install and use Devbox without sudo or root privileges
- 🔄 **Isolated Environment**: Run packages in a contained environment without affecting the system
- 🚀 **Easy Setup**: One script to set up everything automatically
- 💻 **Cross-Platform**: Works on various Linux distributions and architectures
- 🔒 **Safe**: Only modifies your user environment, not system files
- 🌏 **China Network Friendly**: The script can automatically configure Nix to use Tsinghua University mirrors for users in mainland China or other network-restricted environments

> **Note:**  
> While the script tries to minimize network issues by adding the Tsinghua Nix mirror for users in mainland China or restricted networks, you may **still need to temporarily use a proxy** to access resources on GitHub or other sites that are blocked or throttled in your region.

## Quick Start

> **Note:**  
> The installation script is intentionally interactive and will prompt you for input at several steps.  
> This is by design: it allows you to make choices during installation, ensures you understand each step, and gives you flexibility to adapt the process to your environment.  
> Please do not be discouraged by the extra prompts—this approach is meant to maximize compatibility and user control, especially in diverse or restricted Linux environments.

Simply run this command in your terminal:

```bash
# Download the installer
curl -o rootless-devbox-installer.sh https://raw.githubusercontent.com/nebstudio/Rootless-DevBox/main/install.sh

# Make it executable
chmod +x rootless-devbox-installer.sh

# Run the installer
./rootless-devbox-installer.sh
```

## How it Works

Rootless-DevBox (with set folders) sets up your environment in 4 main steps:

0. Runs a script to setup nix folders/directories in a separate address.
1. **Install nix-user-chroot**: Downloads and configures a tool that creates a userspace chroot environment
2. **Create nix environment**: Sets up a containerized Nix environment in your user directory
3. **Install Devbox**: Installs Devbox within this environment so you can use it without root

After installation, you'll access your development environment using the `nix-chroot` command, which activates the isolated environment where Devbox is available.

## Usage

### Entering the Nix Environment

After installation, enter the Nix environment by running:

```bash
nix-chroot
```

You'll see your prompt change to indicate you're in the nix-chroot environment:

```
(nix-chroot) user@hostname:~$
```

### Using Devbox

Once inside the nix-chroot environment, you can use Devbox normally:

```bash
# Show help
devbox help

# Initialize a new project
devbox init

# Add packages
devbox add nodejs python

# Start a shell with your development environment
devbox shell
```

### Exiting the Environment

To exit the nix-chroot environment:

```bash
exit
```

## Requirements

- Linux-based operating system
- Bash shell
- Internet connection
- No root access needed!

## Supported Architectures

- x86_64
- aarch64/arm64
- armv7
- i686/i386

## Troubleshooting

### Common Issues

**Q: I get "command not found" when trying to use nix-chroot.**  
A: Make sure `~/.local/bin` is in your PATH. Try running `source ~/.bashrc` or restarting your terminal.

**Q: Installation fails when downloading nix-user-chroot.**  
A: Check your internet connection. If the issue persists, try manually downloading the appropriate binary from [the releases page](https://github.com/nix-community/nix-user-chroot/releases).

**Q: I can't install packages in the nix environment.**  
A: Some systems have quotas or disk space limitations. Check your available space with `df -h ~`.

For more troubleshooting help, please [open an issue](https://github.com/nebstudio/Rootless-DevBox/issues).

## Uninstalling

If you need to remove Rootless-DevBox from your system, you have two options:

### Option 1: Using the Uninstall Script

We provide an uninstall script that can remove most components:

```bash
# Download the uninstaller
curl -o rootless-devbox-uninstaller.sh https://raw.githubusercontent.com/nebstudio/Rootless-DevBox/main/uninstall.sh

# Make it executable
chmod +x rootless-devbox-uninstaller.sh

# Run the uninstaller
./rootless-devbox-uninstaller.sh
```

### Option 2: Manual Uninstallation (Recommended)

For more control over the uninstallation process, you can manually remove components:

1. **Remove the installed binaries**:
   ```bash
   rm -f ~/.local/bin/devbox
   rm -f ~/.local/bin/nix-chroot
   rm -f ~/.local/bin/nix-user-chroot
   ```

2. **Clean up the Nix directory** (optional, removes all Nix packages):
   ```bash
   rm -rf ~/.nix
   ```

3. **⚠️ IMPORTANT: Edit your shell configuration file** (`~/.bashrc`, `~/.zshrc`, etc.):
   
   **Strongly recommended**: Manually inspect and remove the following additions rather than relying on automated cleanup:
   
   - Remove the PATH modification line:
     ```bash
     export PATH="$HOME/.local/bin:$PATH" # Added by Rootless-DevBox
     ```
   
   - Remove the PS1 prompt modification block:
     ```bash
     # Rootless-DevBox nix-chroot environment indicator
     if [ "$NIX_CHROOT" = "1" ]; then
       PS1="(nix-chroot) \[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "
     fi
     ```

   After editing, apply the changes:
   ```bash
   source ~/.bashrc  # or your specific shell config file
   ```

> **Note**: While the uninstall script attempts to safely edit your shell configuration file, **manually inspecting and removing the specific lines** is safest to prevent unintended modifications to your environment variables.

After uninstallation, you may need to open a new terminal session for all changes to take effect.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add some amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## Acknowledgements

This project wouldn't be possible without these amazing projects:

- [nix-user-chroot](https://github.com/nix-community/nix-user-chroot) - For providing the ability to run Nix as a non-root user
- [Devbox](https://github.com/jetify-com/devbox) - For creating an excellent development environment tool
- [Nix](https://nixos.org/) - For the powerful package management system underlying it all

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Security Considerations

Rootless-DevBox only modifies files within your user's home directory and doesn't require or use root privileges. It's designed to be safe to use even in restricted environments.

---

⭐ If this project helped you, please consider giving it a star on GitHub! ⭐

Created with ❤️ by [nebstudio](https://github.com/nebstudio)
