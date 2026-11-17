#!/usr/bin/env bash
# Linux/local deployment helper. Automated Windows 11 CD uses deploy.ps1 instead.
set -Eeuo pipefail

usage() {
    cat <<'USAGE'
Usage:
  scripts/healthcheck_rollback.sh <development|staging|production> <compose-file> <sha-commit> <health-url>

Example:
  scripts/healthcheck_rollback.sh staging docker-compose.staging.yml sha-0123456789abcdef0123456789abcdef01234567 http://127.0.0.1:8001/health

The Compose file must read DOCKER_IMAGE from the environment. The script stores
only the last successfully health-checked image in ./state/<environment>-image.txt.
USAGE
}

if [[ "$#" -ne 4 ]]; then
    usage >&2
    exit 2
fi

ENVIRONMENT="$1"
COMPOSE_FILE="$2"
IMAGE_TAG="$3"
HEALTH_URL="$4"
IMAGE_REPOSITORY="ghcr.io/233404050190-dotcom/cicd-python-demo"
IMAGE="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
STATE_DIRECTORY="${STATE_DIRECTORY:-state}"

case "$ENVIRONMENT" in
    development)
        PROJECT_NAME="cicd-development"
        ;;
    staging)
        PROJECT_NAME="cicd-staging"
        ;;
    production)
        PROJECT_NAME="cicd-production"
        ;;
    *)
        echo "Unsupported environment: $ENVIRONMENT" >&2
        usage >&2
        exit 2
        ;;
esac

if [[ ! "$IMAGE_TAG" =~ ^sha-[0-9a-f]{40}$ ]]; then
    echo "Image tag must be sha- followed by 40 lowercase hexadecimal characters." >&2
    exit 2
fi
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Compose file not found: $COMPOSE_FILE" >&2
    exit 2
fi

mkdir -p "$STATE_DIRECTORY"
STATE_FILE="${STATE_DIRECTORY}/${ENVIRONMENT}-image.txt"
PREVIOUS_IMAGE=""
if [[ -f "$STATE_FILE" ]]; then
    PREVIOUS_IMAGE="$(<"$STATE_FILE")"
    if [[ -n "$PREVIOUS_IMAGE" && ! "$PREVIOUS_IMAGE" =~ ^${IMAGE_REPOSITORY//./\\.}:sha-[0-9a-f]{40}$ ]]; then
        echo "Invalid previous image reference in $STATE_FILE" >&2
        exit 2
    fi
fi

compose_up() {
    local selected_image="$1"
    DOCKER_IMAGE="$selected_image" docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" up -d --force-recreate --remove-orphans
}

compose_down() {
    DOCKER_IMAGE="$IMAGE" docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" down --remove-orphans
}

health_check() {
    local max_retries="${MAX_RETRIES:-12}"
    local wait_seconds="${WAIT_TIME:-5}"
    local attempt
    local status

    for ((attempt = 1; attempt <= max_retries; attempt++)); do
        status="$(curl --silent --show-error --max-time 5 --output /dev/null --write-out '%{http_code}' "$HEALTH_URL" 2>/dev/null || true)"
        printf 'Health Check %s/%s: HTTP %s\n' "$attempt" "$max_retries" "${status:-no response}"
        if [[ "$status" == "200" ]]; then
            return 0
        fi
        if (( attempt < max_retries )); then
            sleep "$wait_seconds"
        fi
    done

    return 1
}

rollback() {
    if [[ -z "$PREVIOUS_IMAGE" ]]; then
        echo 'No previous successful deployment is recorded; stopping the failed first deployment.'
        compose_down || true
        return 0
    fi

    echo "Restoring previous image: $PREVIOUS_IMAGE"
    if ! docker image inspect "$PREVIOUS_IMAGE" >/dev/null 2>&1; then
        docker pull "$PREVIOUS_IMAGE" || return 1
    fi
    compose_up "$PREVIOUS_IMAGE" || return 1
    if health_check; then
        echo "ROLLBACK SUCCESS: $PREVIOUS_IMAGE"
        return 0
    fi

    echo "ROLLBACK FAILED: previous image is not healthy: $PREVIOUS_IMAGE" >&2
    return 1
}

printf 'Environment: %s\nNew image: %s\nPrevious image: %s\n' \
    "$ENVIRONMENT" "$IMAGE" "${PREVIOUS_IMAGE:-none}"

if docker pull "$IMAGE" && compose_up "$IMAGE" && health_check; then
    temporary_state="${STATE_FILE}.tmp"
    printf '%s\n' "$IMAGE" > "$temporary_state"
    mv -f "$temporary_state" "$STATE_FILE"
    echo "DEPLOYMENT SUCCESS: $IMAGE"
    exit 0
fi

echo 'DEPLOYMENT FAILED: starting rollback.' >&2
if rollback; then
    # Keep a non-zero exit so CI/CD records that the new release failed.
    exit 1
fi
exit 2
