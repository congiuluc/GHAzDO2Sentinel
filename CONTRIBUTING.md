# Contributing

Discuss substantial changes in an issue before starting work. For a bug, include reproduction steps without posting credentials, secrets, or private alert data.

Create a branch for your changes and open a pull request describing the behavior changed and how you checked it. Keep changes focused and add tests for new or corrected behavior.

## Local checks

With the .NET 10 SDK and Azure CLI installed, run:

```powershell
dotnet build .\GhasSentinel.sln
dotnet test .\GhasSentinel.sln
az bicep build --file .\infra\main.bicep --stdout > $null
```

See the [README](README.md) for setup and operational details. Never commit tokens, connection strings, Azure environment files, or Function local settings. Report vulnerabilities privately as described in the [security policy](SECURITY.md).

The GitHub Pages guide and browser presentation live in `docs/`. Update them alongside relevant behavior changes, and preview them with the local server described in the README.
