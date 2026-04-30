#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"

REPORT_DIR="${1:-$REPO_ROOT/reports}"
OUT_FILE="${2:-$REPORT_DIR/security-summary.md}"
PIP_AUDIT_APP_FILE="$REPORT_DIR/pip-audit-app.json"
PIP_AUDIT_DEV_FILE="$REPORT_DIR/pip-audit-dev.json"

command -v jq >/dev/null 2>&1 || die "jq not found"

mkdir -p "$(dirname "$OUT_FILE")"

is_number() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

get_json_value() {
  local file="$1"
  local expr="$2"
  if [[ -s "$file" ]]; then
    jq -r "$expr" "$file"
  else
    echo "N/A"
  fi
}

calc_unfixed() {
  local total="$1"
  local fixable="$2"

  if is_number "$total" && is_number "$fixable"; then
    echo $((total - fixable))
  else
    echo "N/A"
  fi
}

#
# Trivy image helpers
#
trivy_total_by_severity() {
  local severity="$1"
  if [[ -s "$REPORT_DIR/trivy-image.json" ]]; then
    jq -r --arg sev "$severity" '
      [.Results[]? | (.Vulnerabilities // [])[] | select(.Severity == $sev)] | length
    ' "$REPORT_DIR/trivy-image.json"
  else
    echo "N/A"
  fi
}

trivy_fixable_by_severity() {
  local severity="$1"
  if [[ -s "$REPORT_DIR/trivy-image.json" ]]; then
    jq -r --arg sev "$severity" '
      [.Results[]?
       | (.Vulnerabilities // [])[]
       | select(.Severity == $sev and (.FixedVersion // "") != "")
      ] | length
    ' "$REPORT_DIR/trivy-image.json"
  else
    echo "N/A"
  fi
}

#
# pip-audit helpers
#
pip_audit_vulnerable_dependencies() {
  local file="$1"
  if [[ -s "$file" ]]; then
    jq -r '
      [.dependencies[]? | select((.vulns // []) | length > 0)] | length
    ' "$file"
  else
    echo "N/A"
  fi
}

pip_audit_total_vulns() {
  local file="$1"
  if [[ -s "$file" ]]; then
    jq -r '
      [.dependencies[]? | (.vulns // [])[]] | length
    ' "$file"
  else
    echo "N/A"
  fi
}

pip_audit_fixable_vulns() {
  local file="$1"
  if [[ -s "$file" ]]; then
    jq -r '
      [.dependencies[]?
       | (.vulns // [])[]
       | select((.fix_versions // []) | length > 0)
      ] | length
    ' "$file"
  else
    echo "N/A"
  fi
}

pip_audit_actionable_rows() {
  local file="$1"
  if [[ -s "$file" ]]; then
    jq -r '
      [
        .dependencies[]?
        | . as $dep
        | ($dep.vulns // [])[]
        | select((.fix_versions // []) | length > 0)
        | {
            package: ($dep.name // "-"),
            installed: ($dep.version // "-"),
            vuln: (.id // "-"),
            fixed: ((.fix_versions // []) | join(", "))
          }
      ]
      | .[:10]
      | .[]
      | "| `\(.package)` | `\(.installed)` | \(.vuln) | `\(.fixed)` |"
    ' "$file"
  else
    echo ""
  fi
}

#
# ZAP helpers
#
zap_count_by_risk() {
  local risk="$1"
  if [[ -s "$REPORT_DIR/zap-api.json" ]]; then
    jq -r --arg risk "$risk" '
      ([.site[]?.alerts[]?
        | select((.riskdesc // "") | startswith($risk))
        | (.count | tonumber?)] | add) // 0
    ' "$REPORT_DIR/zap-api.json"
  else
    echo "N/A"
  fi
}

bandit_count="$(get_json_value "$REPORT_DIR/bandit.json" '.results | length')"
sbom_components="$(get_json_value "$REPORT_DIR/sbom.cdx.json" '.components | length')"
sbom_spec_version="$(get_json_value "$REPORT_DIR/sbom.cdx.json" '.specVersion')"

pip_audit_app_dep_count="$(pip_audit_vulnerable_dependencies "$PIP_AUDIT_APP_FILE")"
pip_audit_app_vuln_total="$(pip_audit_total_vulns "$PIP_AUDIT_APP_FILE")"
pip_audit_app_fixable_total="$(pip_audit_fixable_vulns "$PIP_AUDIT_APP_FILE")"
pip_audit_app_unfixed_total="$(calc_unfixed "$pip_audit_app_vuln_total" "$pip_audit_app_fixable_total")"

pip_audit_dev_dep_count="$(pip_audit_vulnerable_dependencies "$PIP_AUDIT_DEV_FILE")"
pip_audit_dev_vuln_total="$(pip_audit_total_vulns "$PIP_AUDIT_DEV_FILE")"
pip_audit_dev_fixable_total="$(pip_audit_fixable_vulns "$PIP_AUDIT_DEV_FILE")"
pip_audit_dev_unfixed_total="$(calc_unfixed "$pip_audit_dev_vuln_total" "$pip_audit_dev_fixable_total")"

trivy_critical_total="$(trivy_total_by_severity CRITICAL)"
trivy_high_total="$(trivy_total_by_severity HIGH)"
trivy_medium_total="$(trivy_total_by_severity MEDIUM)"
trivy_low_total="$(trivy_total_by_severity LOW)"
trivy_unknown_total="$(trivy_total_by_severity UNKNOWN)"

trivy_critical_fixable="$(trivy_fixable_by_severity CRITICAL)"
trivy_high_fixable="$(trivy_fixable_by_severity HIGH)"
trivy_medium_fixable="$(trivy_fixable_by_severity MEDIUM)"
trivy_low_fixable="$(trivy_fixable_by_severity LOW)"
trivy_unknown_fixable="$(trivy_fixable_by_severity UNKNOWN)"

trivy_critical_unfixed="$(calc_unfixed "$trivy_critical_total" "$trivy_critical_fixable")"
trivy_high_unfixed="$(calc_unfixed "$trivy_high_total" "$trivy_high_fixable")"
trivy_medium_unfixed="$(calc_unfixed "$trivy_medium_total" "$trivy_medium_fixable")"
trivy_low_unfixed="$(calc_unfixed "$trivy_low_total" "$trivy_low_fixable")"
trivy_unknown_unfixed="$(calc_unfixed "$trivy_unknown_total" "$trivy_unknown_fixable")"

zap_high_count="$(zap_count_by_risk High)"
zap_medium_count="$(zap_count_by_risk Medium)"
zap_low_count="$(zap_count_by_risk Low)"
zap_info_count="$(zap_count_by_risk Informational)"

pip_audit_app_actionable_rows="$(pip_audit_actionable_rows "$PIP_AUDIT_APP_FILE")"
pip_audit_dev_actionable_rows="$(pip_audit_actionable_rows "$PIP_AUDIT_DEV_FILE")"

if [[ -s "$REPORT_DIR/trivy-image.json" ]]; then
  trivy_actionable_rows="$(jq -r '
    [
      .Results[]?
      | (.Vulnerabilities // [])[]
      | select((.Severity == "CRITICAL" or .Severity == "HIGH") and (.FixedVersion // "") != "")
      | {
          severity: .Severity,
          pkg: .PkgName,
          installed: (.InstalledVersion // "-"),
          fixed: (.FixedVersion // "-"),
          vuln: .VulnerabilityID
        }
    ]
    | .[:10]
    | .[]
    | "| \(.severity) | `\(.pkg)` | `\(.installed)` | `\(.fixed)` | \(.vuln) |"
  ' "$REPORT_DIR/trivy-image.json")"
else
  trivy_actionable_rows=""
fi

if [[ -s "$REPORT_DIR/zap-api.json" ]]; then
  zap_blocking_rows="$(jq -r '
    [
      .site[]?.alerts[]?
      | select((.riskdesc // "") | startswith("High"))
      | {
          pluginid: (.pluginid // "-"),
          count: (.count // "-"),
          name: (.name // "-")
        }
    ]
    | .[:10]
    | .[]
    | "| \(.pluginid) | \(.count) | \(.name) |"
  ' "$REPORT_DIR/zap-api.json")"

  zap_alert_rows="$(jq -r '
    .site[]?.alerts[]?
    | "| \(.pluginid) | \(.riskdesc) | \(.count) | \(.name) |"
  ' "$REPORT_DIR/zap-api.json")"
else
  zap_blocking_rows=""
  zap_alert_rows=""
fi

info "Generating security summary..."

{
  echo "# Security Summary"
  echo

  echo "## Static"
  echo
  echo "| Check | Result |"
  echo "|---|---:|"
  echo "| Bandit findings (blocking) | $bandit_count |"
  echo "| SBOM components | $sbom_components |"
  echo "| SBOM spec version | $sbom_spec_version |"
  echo

   echo "### Python dependencies / pip-audit (app)"
  echo
  echo "_Current mode: signal-first on findings; hard fail only on tool/runtime failure_"
  echo
  echo "| Metric | Result |"
  echo "|---|---:|"
  echo "| Vulnerable dependencies | $pip_audit_app_dep_count |"
  echo "| Total advisories | $pip_audit_app_vuln_total |"
  echo "| Fixable advisories | $pip_audit_app_fixable_total |"
  echo "| Unfixed advisories | $pip_audit_app_unfixed_total |"
  echo

  echo "#### pip-audit actionable advisories (app)"
  echo
  echo "| Package | Installed | Vulnerability | Suggested fix versions |"
  echo "|---|---|---|---|"
  if [[ -n "$pip_audit_app_actionable_rows" ]]; then
    echo "$pip_audit_app_actionable_rows"
  else
    echo "| - | - | - | No fixable advisories |"
  fi
  echo

  echo "### Python dependencies / pip-audit (dev)"
  echo
  echo "_Current mode: signal-first on findings; hard fail only on tool/runtime failure_"
  echo
  echo "| Metric | Result |"
  echo "|---|---:|"
  echo "| Vulnerable dependencies | $pip_audit_dev_dep_count |"
  echo "| Total advisories | $pip_audit_dev_vuln_total |"
  echo "| Fixable advisories | $pip_audit_dev_fixable_total |"
  echo "| Unfixed advisories | $pip_audit_dev_unfixed_total |"
  echo

  echo "#### pip-audit actionable advisories (dev)"
  echo
  echo "| Package | Installed | Vulnerability | Suggested fix versions |"
  echo "|---|---|---|---|"
  if [[ -n "$pip_audit_dev_actionable_rows" ]]; then
    echo "$pip_audit_dev_actionable_rows"
  else
    echo "| - | - | - | No fixable advisories |"
  fi
  echo

  echo "## Image artifact"
  echo
  echo "_Trivy image scope: OS/base-image layer_"
  echo
  echo "| Severity | Total | Fixable | Unfixed |"
  echo "|---|---:|---:|---:|"
  echo "| CRITICAL | $trivy_critical_total | $trivy_critical_fixable | $trivy_critical_unfixed |"
  echo "| HIGH | $trivy_high_total | $trivy_high_fixable | $trivy_high_unfixed |"
  echo "| MEDIUM | $trivy_medium_total | $trivy_medium_fixable | $trivy_medium_unfixed |"
  echo "| LOW | $trivy_low_total | $trivy_low_fixable | $trivy_low_unfixed |"
  echo "| UNKNOWN | $trivy_unknown_total | $trivy_unknown_fixable | $trivy_unknown_unfixed |"
  echo

  echo "### Trivy actionable findings"
  echo
  echo "| Severity | Package | Installed | Fixed | Vulnerability |"
  echo "|---|---|---|---|---|"
  if [[ -n "$trivy_actionable_rows" ]]; then
    echo "$trivy_actionable_rows"
  else
    echo "| - | - | - | - | No fixable CRITICAL/HIGH findings |"
  fi
  echo

  echo "## Runtime / ZAP"
  echo
  echo "_Current blocking threshold in plan: High_"
  echo
  echo "| Risk level | Count |"
  echo "|---|---:|"
  echo "| High | $zap_high_count |"
  echo "| Medium | $zap_medium_count |"
  echo "| Low | $zap_low_count |"
  echo "| Informational | $zap_info_count |"
  echo

  echo "### ZAP blocking findings"
  echo
  echo "| Plugin ID | Count | Name |"
  echo "|---|---:|---|"
  if [[ -n "$zap_blocking_rows" ]]; then
    echo "$zap_blocking_rows"
  else
    echo "| - | - | No High findings |"
  fi
  echo

  echo "### ZAP all findings"
  echo
  echo "| Plugin ID | Risk | Count | Name |"
  echo "|---|---|---:|---|"
  if [[ -n "$zap_alert_rows" ]]; then
    echo "$zap_alert_rows"
  else
    echo "| - | - | - | No ZAP findings or report missing |"
  fi
} > "$OUT_FILE"

info "Security summary written: $OUT_FILE"
info "Summary size: $(wc -c < "$OUT_FILE") bytes"