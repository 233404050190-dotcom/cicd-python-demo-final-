# Verification status of this source package

This document separates checks performed on the source package from steps that require the team's GitHub account or a real Windows/Docker host.

## Checks performed while preparing this ZIP

- YAML parsing completed for `ci.yml`, `cd.yml`, `ruff.yml` and all four Compose files.
- Python source files passed Python AST syntax parsing.
- Bash syntax validation passed for `scripts/healthcheck_rollback.sh` and the Bash `run` blocks embedded in the GitHub Actions workflows.
- Compose `env_file` references were checked against files included in the project.
- The Bash rollback helper was exercised with mock `docker` and `curl` commands: a first healthy deployment saved its image SHA; a simulated unhealthy next deployment restored the prior image, preserved the prior state file, and returned exit code 1 so the release is still marked failed.

## Not verified in this environment

- `pytest` was not run against Flask because Flask dependencies could not be installed in this offline environment.
- Ruff was not run because Ruff was not installed and package installation was unavailable.
- Docker image build, Docker Compose runtime health, and GHCR push/pull were not run because Docker Engine and registry credentials were unavailable.
- PowerShell parsing and execution of `scripts/bootstrap_server.ps1` and `scripts/deploy.ps1` were not run because this environment does not contain PowerShell or Windows 11.
- GitHub Actions, GitHub Environment secrets, SSH connectivity, Telegram/Discord delivery, and end-to-end CD were not run against the team's actual repository or server.

## Required evidence before claiming completion

1. Ruff and Pytest jobs pass in GitHub Actions.
2. Build/Push job publishes the SHA image to GHCR.
3. The GHCR package visibility/authentication allows the Windows server to pull that image.
4. SSH from the GitHub runner to Windows succeeds with key authentication and verified `known_hosts`.
5. Development, Staging and Production each pass `/health` on their configured port.
6. A controlled failure in Development or Staging proves rollback restores the previously healthy image.
7. Telegram/Discord receives CI success and failure notifications.

Do not claim full end-to-end completion until these runtime checks have been captured.
