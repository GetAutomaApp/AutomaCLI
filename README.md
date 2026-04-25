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
curl -sSL "https://x-access-token:$(gh auth token)@raw.githubusercontent.com/GetAutomaApp/AutomaCLI/main/setup.sh" | bash
```

To force overwrite an existing configuration:

```bash
export AUTOMA_FORCE_OVERWRITE=true && curl -sSL "https://x-access-token:$(gh auth token)@raw.githubusercontent.com/GetAutomaApp/AutomaCLI/main/setup.sh" | bash
```

After successful execution, the AutomaCLI binary will be symlinked to `/usr/local/bin/automa`, allowing you to run it using the `automa` command.

## Grafana Jsonnet Workflow

AutomaCLI supports a Jsonnet-first Grafana flow that keeps templates and ID/UID state in git.

### Commands

- `automa grafana init [--environment <env>]` scaffolds folders and starter templates.
- `automa grafana render [--environment <env>]` renders `*.jsonnet` templates to `grafana/rendered/<env>`.
- `automa grafana apply [--environment <env>]` applies rendered JSON files to Grafana and updates local state IDs/UIDs.
- `automa grafana sync-ids [--environment <env>]` refreshes dashboard IDs/UIDs from Grafana into local state.

Grafana credentials are read from `Secrets/Grafana/<environment>/creds.md` using `.env`-style keys:
- `GRAFANA_URL=...`
- `GRAFANA_AUTH_TOKEN=...`

### Repository Layout

```text
grafana/
  templates/
    dashboards/
      *.dashboard.jsonnet
    alerts/
      *.alert.jsonnet
  rendered/
    <environment>/
      ...rendered json files...
      manifest.json
  state/
    <environment>/
      dashboards/
        <templateKey>.json
      alerts/
        <templateKey>.json
```

### State File Schema

`grafana/state/<environment>/dashboards/<templateKey>.json`

```json
{
  "uid": "string",
  "id": 1,
  "title": "string"
}
```

`grafana/state/<environment>/alerts/<templateKey>.json`

```json
{
  "uid": "string",
  "title": "string"
}
```

`templateKey` is derived from the rendered template file name (without extension), so state stays stable, reviewable, and less conflict-prone in git.
