# fedora-workstation

Configuration and post-install scripts for [Fedora Workstation](https://fedoraproject.org/workstation/) (GNOME Desktop Environment). Initial version: 43.

## Aliases

Public aliases reside in [aliases/.aliases](aliases/.aliases) and are meant to be sourced from shell configs.

| Alias          | Command                                                    | Description                                                          |
| -------------- | ---------------------------------------------------------- | -------------------------------------------------------------------- |
| `cb`           | `wl-copy`                                                  | Copy text to the clipboard from the terminal.                        |
| `cursor`       | `/usr/bin/cursor --no-sandbox`                             | Allows launching Cursor to edit a file by running `cursor filename`. |
| `docker-start` | `sudo systemctl start docker`                              | Start the Docker service.                                            |
| `docker-stop`  | `sudo systemctl stop docker`                               | Stop the Docker service.                                             |
| `update`       | `sudo dnf up -y && flatpak update -y && sudo snap refresh` | Update system packages, Flatpaks, and Snap packages.                 |

## Packages

Package lists contain system packages (DNF), Flatpaks and Snaps.

| Package List                           | Description                                                    |
| -------------------------------------- | -------------------------------------------------------------- |
| [packages/general/](packages/general/) | General packages to install on any Fedora Workstation machine. |
| [packages/work/](packages/work/)       | Packages that are only necessary for work.                     |
| [packages/remove/](packages/remove/)   | Bloat to remove from a standard installation.                  |

## Scripts

| Script                                        | Description                                                                                    |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| [install](scripts/install.sh)                 | General installation script. Supports step parameter to run specific steps in isolation.       |
| [install-work](scripts/install-work.sh)       | Work-specific installation script. Supports step parameter to run specific steps in isolation. |
| [nvidia-drivers](scripts/nvidia-drivers.sh)   | Helps set up NVIDIA GPU drivers.                                                               |
| [secure-boot-key](scripts/secure-boot-key.sh) | Helps with Secure Boot key setup.                                                              |
| [utils](scripts/utils.sh)                     | Contains utility functions used by other scripts.                                              |
