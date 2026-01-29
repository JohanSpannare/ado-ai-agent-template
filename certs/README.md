# CA Certificates

Place your organization's root CA certificates here to enable HTTPS access to internal endpoints (e.g., Confluence, internal APIs).

## Usage

1. Add `.crt` files to this directory in your organization repo:
   ```
   certs/
   ├── internal-ca.crt
   ├── proxy-ca.crt
   └── another-ca.crt
   ```

2. The pipeline will automatically:
   - Mount the `certs/` directory into the container
   - Run `update-ca-certificates` to install them system-wide
   - Set `NODE_EXTRA_CA_CERTS` so Node.js applications trust the certificates
   - All CLI tools (curl, wget, git, etc.) and Node.js will trust these certificates

## Notes

- Files must have `.crt` extension
- PEM format is required (Base64 encoded, starts with `-----BEGIN CERTIFICATE-----`)
- Multiple certificates are supported
- This directory in the template repo should remain empty (org-specific certs only)

## Technical Details

The pipeline configures certificates in three steps:
1. **Mount**: Certs are mounted to `/tmp/org-certs/` in the container
2. **Copy**: Certs are copied to `/usr/local/share/ca-certificates/` (required by `update-ca-certificates`)
3. **Install**: `update-ca-certificates` adds certs to `/etc/ssl/certs/ca-certificates.crt`
4. **Node.js**: `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt` makes Node.js use the system store

This ensures both native tools (curl, wget, git) and Node.js-based applications (like OpenCode) can access internal HTTPS endpoints.
