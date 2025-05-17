# General
This repository installs the latest [Azure pipelines agent](https://github.com/microsoft/azure-pipelines-agent) release.

# Prerequirements
- curl installed
- python3 installed

# Installation
## Linux
```
curl -fsSL https://raw.githubusercontent.com/Birchi/azure.pipelines.agent.installer/refs/heads/development/install.sh | /bin/bash -s -- --repository URL --token TOKEN --name NAME
```
