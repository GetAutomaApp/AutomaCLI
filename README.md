# AutomaCLI Local Setup

This repository contains the source code for AutomaCLI. To set up AutomaCLI by building it from source and configuring it locally, you can use the `setup.sh` script.

## Prerequisites

Before running the setup script, ensure you have the following installed:

*   **Git**: For cloning the repository.
*   **Swift Toolchain**: For building the AutomaCLI binary. You can download it from [swift.org](https://swift.org/download/).

This script is designed to work on both macOS and Linux.

## Setup Instructions

The `setup.sh` script will perform the following actions:
1. Clone the AutomaCLI repository to a local directory (default: `~/.automacli_repo`).
2. Build the AutomaCLI binary from the cloned source code.
3. Create a configuration directory at `~/.config/automacli/`.
4. Create a `config.json` file within the configuration directory, storing the `repoPath` to the cloned repository.

If a `config.json` file already exists, the script will exit with an error unless the `AUTOMA_FORCE_OVERWRITE` environment variable is set to `true`.

To run the setup script, execute the following command in your terminal:

```bash
curl -sSL https://raw.githubusercontent.com/GetAutomaApp/AutomaCLI/main/setup.sh | bash
```

To force overwrite an existing configuration:

```bash
export AUTOMA_FORCE_OVERWRITE=true && curl -sSL https://raw.githubusercontent.com/GetAutomaApp/AutomaCLI/main/setup.sh | bash
```

After successful execution, the AutomaCLI binary will be symlinked to `/usr/local/bin/automa`, allowing you to run it using the `automa` command.
