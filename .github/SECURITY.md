# Security Policy

PDF Seal Master handles local documents, stamps, and signatures. These files may contain private or legally sensitive information, so security and privacy reports should avoid public disclosure of sample data.

## Supported Versions

The project is in early development. Security fixes target the latest `main` branch unless a tagged release states otherwise.

## Reporting a Vulnerability

If you find a security or privacy issue:

1. Do not attach private documents, real stamps, real signatures, certificates, or secrets to a public issue.
2. Open a minimal public issue that describes the affected area without sensitive data, or contact the maintainer through GitHub profile contact options if private details are required.
3. Provide a safe synthetic sample when possible.

Useful report details:

- Operating system and Python version.
- Reproduction steps.
- Expected and actual behavior.
- Whether the issue affects import, preview, export, local storage, or iOS code.

## Scope

In scope:

- Unsafe handling of local files or temporary files.
- Accidental inclusion of private assets in repository workflows.
- Export behavior that leaks data beyond the intended output.
- Dependency or packaging risks.

Out of scope:

- Issues requiring real private documents without a synthetic reproduction.
- Social engineering or account compromise unrelated to this repository.
