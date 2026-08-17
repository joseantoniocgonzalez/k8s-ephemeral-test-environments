#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${APP_DIR:-$(dirname "$PROJECT_ROOT")/ioc-reputation-checker}"
CLUSTER_NAME="${CLUSTER_NAME:-ioc-test}"
NAMESPACE="${NAMESPACE:-ioc-test}"
RELEASE_NAME="${RELEASE_NAME:-ioc-test}"
IMAGE="${IMAGE:-ioc-reputation-checker:local}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"

cluster_created=false

collect_diagnostics() {
    local diagnostics_dir="${PROJECT_ROOT}/artifacts/diagnostics"

    echo "Recopilando información del fallo..."
    mkdir -p "$diagnostics_dir"

    kubectl get all,pvc \
        --namespace "$NAMESPACE" \
        --context "$KUBECTL_CONTEXT" \
        > "${diagnostics_dir}/resources.txt" 2>&1 || true

    kubectl describe pods \
        --namespace "$NAMESPACE" \
        --context "$KUBECTL_CONTEXT" \
        > "${diagnostics_dir}/pods-description.txt" 2>&1 || true

    kubectl get events \
        --namespace "$NAMESPACE" \
        --context "$KUBECTL_CONTEXT" \
        --sort-by='.lastTimestamp' \
        > "${diagnostics_dir}/events.txt" 2>&1 || true

    kubectl logs deployment/"${RELEASE_NAME}-api" \
        --namespace "$NAMESPACE" \
        --context "$KUBECTL_CONTEXT" \
        --all-containers=true \
        > "${diagnostics_dir}/api.log" 2>&1 || true

    kubectl logs deployment/"${RELEASE_NAME}-postgresql" \
        --namespace "$NAMESPACE" \
        --context "$KUBECTL_CONTEXT" \
        --all-containers=true \
        > "${diagnostics_dir}/postgresql.log" 2>&1 || true

    echo "Diagnósticos guardados en: ${diagnostics_dir}"
}

cleanup() {
    local exit_code=$?

    trap - EXIT

    if [[ "$cluster_created" == true ]]; then
        if (( exit_code != 0 )); then
            collect_diagnostics
        fi

        echo "Eliminando únicamente el clúster temporal ${CLUSTER_NAME}..."
        kind delete cluster --name "$CLUSTER_NAME" || true
    fi

    exit "$exit_code"
}

trap cleanup EXIT

echo "Comprobando herramientas necesarias..."

for required_command in docker kind kubectl helm; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "Error: no se encuentra la herramienta ${required_command}."
        exit 1
    fi
done

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker Engine no está activo."
    exit 1
fi

if [[ ! -f "${APP_DIR}/Dockerfile" ]]; then
    echo "Error: no se encuentra ${APP_DIR}/Dockerfile."
    exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/kind/cluster.yaml" ]]; then
    echo "Error: no se encuentra kind/cluster.yaml."
    exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/charts/ioc-reputation-checker/Chart.yaml" ]]; then
    echo "Error: no se encuentra el chart de Helm."
    exit 1
fi

if kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
    echo "Error: el clúster ${CLUSTER_NAME} ya existe."
    echo "No se eliminará porque este script no lo ha creado."
    exit 1
fi

echo "Construyendo la imagen ${IMAGE}..."
docker build --tag "$IMAGE" "$APP_DIR"

echo "Creando el clúster temporal ${CLUSTER_NAME}..."
kind create cluster \
    --name "$CLUSTER_NAME" \
    --config "${PROJECT_ROOT}/kind/cluster.yaml" \
    --wait 120s

cluster_created=true

echo "Cargando la imagen en el clúster..."
kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"

echo "Desplegando la aplicación con Helm..."
helm upgrade --install "$RELEASE_NAME" \
    "${PROJECT_ROOT}/charts/ioc-reputation-checker" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --kube-context "$KUBECTL_CONTEXT" \
    --wait \
    --timeout 5m

echo "Ejecutando el smoke test..."
NAMESPACE="$NAMESPACE" \
RELEASE_NAME="$RELEASE_NAME" \
"${PROJECT_ROOT}/tests/smoke/test_api.sh"

echo "Entorno efímero validado correctamente."
