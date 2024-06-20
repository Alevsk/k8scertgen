#!/bin/bash

# Global variables for script arguments
NAME=""
NAMESPACE="default"
SECRET=""
DURATION="2160h"
RENEW="360h"
CNAME=""
DNS=()
IPS=()
ISSUER=""
FILE=""
OUTPUT="./"
DRY_RUN=false

# Function to show usage
usage() {
    printf "Usage: %s [FLAGS] [ARGS...]\n" "$(basename "$0")"
    printf "Flags:\n"
    printf "  --name <cert_name>                Set the certificate name (mandatory)\n"
    printf "  -n, --namespace <namespace>       Set the namespace (default: default)\n"
    printf "  -s, --secret <secret_name>        Define the secretName (default: <cert_name>-tls)\n"
    printf "  -d, --duration <duration>         Set certificate duration (default: 2160h)\n"
    printf "  -r, --renew <renew_before>        Set certificate renewBefore (default: 360h)\n"
    printf "  -c, --cname <common_name>         Set the commonName (default: <cert_name>)\n"
    printf "  --dns <dns_names>                 Set dnsNames array (comma separated)\n"
    printf "  --ips <ip_addresses>              Set ipAddresses array (comma separated)\n"
    printf "  -i, --issuer <issuer_ref>         Set issuerRef.name value (mandatory)\n"
    printf "  -f, --file <yaml_file>            Receive a kubernetes YAML file (ignores other flags)\n"
    printf "  -o, --output <output_dir>         Directory to save tls.crt, tls.key, and ca.crt (default: ./)\n"
    printf "  --dry-run                         Output the generated YAML without applying it\n"
    exit 1
}

# Function to parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                NAME="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -s|--secret)
                SECRET="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -r|--renew)
                RENEW="$2"
                shift 2
                ;;
            -c|--cname)
                CNAME="$2"
                shift 2
                ;;
            --dns)
                IFS=',' read -r -a DNS <<< "$2"
                DNS=("${DNS[@]// /}")  # Trim whitespace
                shift 2
                ;;
            --ips)
                IFS=',' read -r -a IPS <<< "$2"
                IPS=("${IPS[@]// /}")  # Trim whitespace
                shift 2
                ;;
            -i|--issuer)
                ISSUER="$2"
                shift 2
                ;;
            -f|--file)
                FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                usage
                ;;
        esac
    done
}

# Function to validate arguments
validate_args() {
    if [[ -z "$NAME" ]]; then
        printf "Error: --name is mandatory\n" >&2
        usage
    fi

    if [[ -z "$ISSUER" ]]; then
        printf "Error: --issuer is mandatory\n" >&2
        usage
    fi

    if [[ -z "$SECRET" ]]; then
        SECRET="${NAME}-tls"
    fi

    if [[ -z "$CNAME" ]]; then
        CNAME="$NAME"
    fi
}

# Function to generate YAML for the certificate
generate_certificate_yaml() {
    printf "apiVersion: cert-manager.io/v1\n"
    printf "kind: Certificate\n"
    printf "metadata:\n"
    printf "  name: %s\n" "$NAME"
    printf "  namespace: %s\n" "$NAMESPACE"
    printf "spec:\n"
    printf "  secretName: %s\n" "$SECRET"
    printf "  duration: %s\n" "$DURATION"
    printf "  renewBefore: %s\n" "$RENEW"
    printf "  commonName: \"%s\"\n" "$CNAME"

    if [[ ${#DNS[@]} -gt 0 ]]; then
        printf "  dnsNames:\n"
        for dns in "${DNS[@]}"; do
            printf "    - \"%s\"\n" "$dns"
        done
    fi

    if [[ ${#IPS[@]} -gt 0 ]]; then
        printf "  ipAddresses:\n"
        for ip in "${IPS[@]}"; do
            printf "    - \"%s\"\n" "$ip"
        done
    fi

    printf "  issuerRef:\n"
    printf "    name: %s\n" "$ISSUER"
    printf "    kind: ClusterIssuer\n"
}

# Function to apply the certificate YAML
apply_certificate() {
    if [[ -n "$FILE" ]]; then
        kubectl apply -f "$FILE"
    else
        generate_certificate_yaml | kubectl apply -f -
    fi
}

# Function to check the existence of the secret with exponential backoff
check_secret_existence() {
    local secret_namespace="$1"
    local secret_name="$2"
    local max_retries=5
    local delay=1

    for ((i=1; i<=max_retries; i++)); do
        if kubectl get secrets "$secret_name" -n "$secret_namespace" >/dev/null 2>&1; then
            return 0
        fi
        printf "Secret not found, retrying in %d seconds...\n" "$delay"
        sleep "$delay"
        delay=$((delay * 2))
    done

    printf "Error: Secret %s not found in namespace %s after %d attempts\n" "$secret_name" "$secret_namespace" "$max_retries" >&2
    return 1
}

# Function to retrieve secrets and save to files
retrieve_secrets() {
    local secret_namespace="$1"
    local secret_name="$2"
    local output_dir="$3"

    mkdir -p "$output_dir"

    if ! check_secret_existence "$secret_namespace" "$secret_name"; then
        return
    fi

    local tls_key tls_crt ca_crt
    if ! tls_key=$(kubectl get secrets "$secret_name" -n "$secret_namespace" -o json | jq '.data."tls.key"' -j | base64 -d); then
        printf "Error retrieving tls.key\n" >&2
        return
    fi
    if ! tls_crt=$(kubectl get secrets "$secret_name" -n "$secret_namespace" -o json | jq '.data."tls.crt"' -j | base64 -d); then
        printf "Error retrieving tls.crt\n" >&2
        return
    fi
    if ! ca_crt=$(kubectl get secrets "$secret_name" -n "$secret_namespace" -o json | jq '.data."ca.crt"' -j | base64 -d); then
        printf "Error retrieving ca.crt\n" >&2
        return
    fi

    printf "%s" "$tls_key" > "${output_dir}/tls.key"
    printf "%s" "$tls_crt" > "${output_dir}/tls.crt"
    printf "%s" "$ca_crt" > "${output_dir}/ca.crt"
}

# Main function
main() {
    parse_args "$@"
    validate_args

    if [[ "$DRY_RUN" == true ]]; then
        generate_certificate_yaml
        exit 0
    fi

    apply_certificate

    if [[ -n "$OUTPUT" ]]; then
        retrieve_secrets "$NAMESPACE" "$SECRET" "$OUTPUT"
    fi
}

main "$@"
