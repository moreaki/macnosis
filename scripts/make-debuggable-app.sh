#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<EOF
Usage:
  $(basename "$0") [--force] /path/to/App.app [output.app]
  $(basename "$0") --repair-damaged /path/to/App.app

Copies an app bundle, adds com.apple.security.get-task-allow, and re-signs
the copy ad-hoc. If output.app is omitted, the copy is created next to the
source as App-debug.app.

Repair mode:
  --repair-damaged re-signs the given app in place ad-hoc, clears quarantine
  and other removable extended attributes, then verifies the bundle. Use this
  for macOS dialogs such as:

    "App.app" is damaged and can't be opened. You should move it to the Trash.

  That message is often caused by quarantine plus a stale or invalid bundle
  signature, especially when nested Unity plugins/frameworks no longer match
  the app's CodeResources seal. Repair mode does not add get-task-allow and
  does not create a copy.

Why this helps:
  Debuggers and memory tools such as Bit Slicer usually need permission to
  attach to the target process. The entitlement that normally signals this is:

    com.apple.security.get-task-allow = true

What changes:
  The original app may be signed with a Developer ID certificate, for example:

    Developer ID Application -> Apple Developer ID CA -> Apple Root CA

  That Apple-backed trust chain proves who signed the app. It also gives the
  app a TeamIdentifier and may preserve notarization for that exact build.
  Once a bundle is copied, modified, or re-signed, the original signature and
  notarization no longer apply to the copy.

  This tool signs the copy ad-hoc:

    codesign --sign -

  Ad-hoc signing creates a valid local code signature, but no Apple trust
  chain, no TeamIdentifier, and no notarization identity. This is usually the
  practical local choice when adding get-task-allow for debugging.

Hardened Runtime:
  Hardened Runtime is a signing option shown by codesign as:

    flags=0x10000(runtime)

  It restricts debugger attachment, library injection, executable memory, and
  similar behavior unless matching entitlements allow exceptions. This script
  does not re-enable Hardened Runtime on the debug copy.

Why not just remove the signature:
  codesign --remove-signature leaves the app unsigned and removes all
  entitlements. This script instead leaves the copy signed and explicitly adds
  get-task-allow.

What repair mode changes:
  Repair mode replaces the app's current signature with an ad-hoc signature,
  so any original Developer ID trust chain, TeamIdentifier, notarization
  identity, and Hardened Runtime signing option are no longer present on that
  local app bundle. It is meant as a local launch repair, not a distribution
  signing workflow.

Checking for a real local signing identity:
  security find-identity -v -p codesigning

  If that prints "0 valid identities found", ad-hoc signing is the only local
  signing option available. Even with a Developer ID certificate, some
  entitlements may be unsuitable or restricted for distributed Developer ID
  signing, so ad-hoc signing is still often simpler for local debugging.
EOF
}

cleanup() {
	rm -rf "$tmpdir"
}

make_empty_entitlements_plist() {
	local output="$1"

	cat >"$output" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
PLIST
}

extract_entitlements_plist() {
	local code="$1"
	local output="$2"

	rm -f "$output"
	if ! codesign -d --xml --entitlements "$output" "$code" >/dev/null 2>&1; then
		rm -f "$output"
		return 1
	fi

	if [[ ! -s "$output" ]] || ! plutil -lint "$output" >/dev/null 2>&1; then
		rm -f "$output"
		return 1
	fi
}

add_debug_entitlement() {
	local entitlements="$1"

	/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$entitlements" >/dev/null 2>&1 || true
	/usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool true' "$entitlements"
}

sign_code() {
	local code="$1"
	local add_debug="${2:-0}"
	local entitlements
	local has_entitlements=0

	entitlements_counter=$((entitlements_counter + 1))
	entitlements="$tmpdir/entitlements-$entitlements_counter.plist"

	if extract_entitlements_plist "$code" "$entitlements"; then
		has_entitlements=1
	elif [[ "$add_debug" -eq 1 ]]; then
		make_empty_entitlements_plist "$entitlements"
		has_entitlements=1
	fi

	if [[ "$add_debug" -eq 1 ]]; then
		add_debug_entitlement "$entitlements"
	fi

	if [[ "$has_entitlements" -eq 1 ]]; then
		codesign --force --sign - --entitlements "$entitlements" "$code"
	else
		codesign --force --sign - "$code"
	fi
}

is_signable_bundle() {
	local candidate="$1"

	[[ -d "$candidate" ]] || return 1
	case "$candidate" in
		*.app|*.appex|*.bundle|*.framework|*.mdimporter|*.plugin|*.qlgenerator|*.saver|*.service|*.xpc)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

is_macho_file() {
	local candidate="$1"

	[[ -f "$candidate" && ! -L "$candidate" ]] || return 1
	/usr/bin/file -b "$candidate" 2>/dev/null | grep -q 'Mach-O'
}

sign_nested_code() {
	local app="$1"
	local contents="$app/Contents"
	local candidate

	[[ -d "$contents" ]] || return

	while IFS= read -r -d '' candidate; do
		[[ -L "$candidate" ]] && continue
		if is_signable_bundle "$candidate" || is_macho_file "$candidate"; then
			printf '  Signing nested code: %s\n' "$candidate"
			sign_code "$candidate"
		fi
	done < <(/usr/bin/find "$contents" -depth \( -type f -o -type d \) -print0)
}

validate_source_app() {
	local app="$1"

	if [[ ! -d "$app" || "$app" != *.app ]]; then
		printf 'error: source must be an existing .app bundle: %s\n' "$app" >&2
		exit 1
	fi
}

default_output_app() {
	local app="$1"
	local source_dir
	local source_base

	source_dir="$(dirname "$app")"
	source_base="$(basename "$app" .app)"
	printf '%s/%s-debug.app\n' "$source_dir" "$source_base"
}

validate_output_app() {
	local app="$1"

	if [[ "$app" != *.app ]]; then
		printf 'error: output path must end in .app: %s\n' "$app" >&2
		exit 1
	fi
}

ensure_output_available() {
	local app="$1"

	if [[ ! -e "$app" ]]; then
		return
	fi

	if [[ "$force" -ne 1 ]]; then
		printf 'error: output already exists: %s\n' "$app" >&2
		printf '       rerun with --force to replace it\n' >&2
		exit 1
	fi

	rm -rf "$app"
}

clear_launch_blocking_attrs() {
	local app="$1"

	xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
	xattr -cr "$app" 2>/dev/null || true
}

verify_app_signature() {
	local app="$1"

	codesign --verify --deep --strict --verbose=2 "$app"
}

repair_damaged_app() {
	local app="$1"

	printf 'Repairing in place:\n  %s\n' "$app"
	printf 'Re-signing nested code inside-out with preserved entitlements...\n'
	sign_nested_code "$app"
	sign_code "$app"

	printf 'Clearing quarantine and removable extended attributes...\n'
	clear_launch_blocking_attrs "$app"

	printf 'Verifying signature...\n'
	verify_app_signature "$app"

	printf '\nDone. Repaired app:\n  %s\n' "$app"
}

make_debuggable_copy() {
	local app="$1"
	local output_app="$2"

	validate_output_app "$output_app"
	ensure_output_available "$output_app"

	printf 'Copying:\n  %s\n  -> %s\n' "$app" "$output_app"
	/usr/bin/ditto "$app" "$output_app"

	printf 'Re-signing nested code inside-out with preserved entitlements...\n'
	sign_nested_code "$output_app"
	printf 'Adding debugger entitlement to the main app only...\n'
	sign_code "$output_app" 1

	printf 'Verifying signature...\n'
	verify_app_signature "$output_app"

	printf '\nDone. Debuggable copy created at:\n  %s\n\n' "$output_app"
	printf 'Confirmed entitlement:\n'
	codesign -d --xml --entitlements - "$output_app" 2>/dev/null | grep -A1 'com.apple.security.get-task-allow' || {
		printf 'warning: get-task-allow was not found in the signed output\n' >&2
		exit 1
	}
}

parse_args() {
	force=0
	repair_damaged=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--force) force=1; shift ;;
			--repair-damaged|--fix-damaged) repair_damaged=1; shift ;;
			-h|--help) usage; exit 0 ;;
			--) shift; break ;;
			-*)
				printf 'error: unknown option: %s\n\n' "$1" >&2; usage; exit 2
				;;
			*) break ;;
		esac
	done

	positional_args=("$@")
}

main() {
	parse_args "$@"

	if [[ "$repair_damaged" -eq 1 && "${#positional_args[@]}" -ne 1 ]]; then
		printf 'error: --repair-damaged takes exactly one .app path and repairs it in place\n\n' >&2
		usage
		exit 2
	fi

	if [[ "$repair_damaged" -eq 0 && ( "${#positional_args[@]}" -lt 1 || "${#positional_args[@]}" -gt 2 ) ]]; then
		usage
		exit 2
	fi

	source_app="${positional_args[0]%/}"
	validate_source_app "$source_app"

	output_app=""
	if [[ "$repair_damaged" -eq 0 && "${#positional_args[@]}" -eq 2 ]]; then
		output_app="${positional_args[1]%/}"
	elif [[ "$repair_damaged" -eq 0 ]]; then
		output_app="$(default_output_app "$source_app")"
	fi

	tmpdir="$(mktemp -d)"
	entitlements_counter=0
	trap cleanup EXIT

	if [[ "$repair_damaged" -eq 1 ]]; then
		repair_damaged_app "$source_app"
		return
	fi

	make_debuggable_copy "$source_app" "$output_app"
}

main "$@"
