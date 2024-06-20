# k8scertgen

`k8scertgen` is a Bash script to generate and manage Kubernetes certificates using `cert-manager`. It allows you to create certificates and retrieve the generated secrets for use in your applications.

## Usage

```bash
./k8scertgen [FLAGS] [ARGS...]
```

### Flags

- `--name <cert_name>`: Set the certificate name (mandatory).
- `-n, --namespace <namespace>`: Set the namespace (default: default).
- `-s, --secret <secret_name>`: Define the secretName (default: <cert_name>-tls).
- `-d, --duration <duration>`: Set certificate duration (default: 2160h).
- `-r, --renew <renew_before>`: Set certificate renewBefore (default: 360h).
- `-c, --cname <common_name>`: Set the commonName (default: <cert_name>).
- `--dns <dns_names>`: Set dnsNames array (comma-separated).
- `--ips <ip_addresses>`: Set ipAddresses array (comma-separated).
- `-i, --issuer <issuer_ref>`: Set issuerRef.name value (mandatory).
- `-f, --file <yaml_file>`: Receive a Kubernetes YAML file (ignores other flags).
- `-o, --output <output_dir>`: Directory to save `tls.crt`, `tls.key`, and `ca.crt` (default: ./).
- `--dry-run`: Output the generated YAML without applying it.

## Examples

### Example 1: Generate a certificate with mandatory arguments

```bash
./k8scertgen --name my-cert --issuer my-issuer
```

### Example 2: Generate a certificate with optional arguments

```bash
./k8scertgen --name my-cert --namespace my-namespace --secret my-secret \
             --duration 4320h --renew 720h --cname my-common-name \
             --dns "example.com,www.example.com" --ips "192.168.1.1,10.0.0.1" \
             --issuer my-issuer --output /path/to/output
```

### Example 3: Apply a Kubernetes YAML file

```bash
./k8scertgen --file /path/to/certificate.yaml
```

### Example 4: Specify output directory for generated secrets

```bash
./k8scertgen --name my-cert --issuer my-issuer --output /path/to/output
```

## Notes

- The `--name` and `--issuer` arguments are mandatory.
- If the `--secret` argument is not provided, it defaults to `<cert_name>-tls`.
- If the `--cname` argument is not provided, it defaults to the value of `--name`.
- The script includes a retry mechanism with exponential backoff to wait for the secret to be created by Kubernetes before attempting to retrieve it.
