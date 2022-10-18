#!/bin/bash

imageRef=$1
TRIVY_VERSION=0.32.1

wget https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.deb
sudo dpkg -i trivy_${TRIVY_VERSION}_Linux-64bit.deb

trivy image "$imageRef" --format json \
  | jq -r -c '.Results[].Vulnerabilities[] | {
    VulnerabilityID: .VulnerabilityID,
    PkgName: .PkgName,
    InstalledVersion: .InstalledVersion,
    FixedVersion: .FixedVersion,
    Title: .Title,
    Severity: .Severity
  }' > /tmp/formatted_trivy_report.json

rows=""
while read line; do
  library=$(echo "$line" | jq '.PkgName')
  vulnerability=$(echo "$line" | jq '.VulnerabilityID')
  severity=$(echo "$line" | jq '.Severity')
  installedVersion=$(echo "$line" | jq '.InstalledVersion')
  fixedVersion=$(echo "$line" | jq '.FixedVersion')
  title=$(echo "$line" | jq '.Title' | sed 's/null//g')
  row=$(echo "| $library | $vulnerability | $severity | $installedVersion | $fixedVersion | $title |" | sed 's/\"//g')

  rows="$rows$row\n"
done < /tmp/formatted_trivy_report.json

tableMD="""
### Relatório do Trivy de vulnerabilidade da imagem

| Library | Vulnerability | Severity | Installed Version | Fixed Version | Title |
| ------- | ------------- | -------- | ----------------- | ------------- | ----- |
$rows
"""

printf "$tableMD" >> "$GITHUB_STEP_SUMMARY"
