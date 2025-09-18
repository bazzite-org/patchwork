#!/usr/bin/env bats
# Purpose: Test that all CONFIG_* files end with newlines

load test-lib.bash

_validate_config_newlines() {
	local config_dir="$1"
	local config_files
	local file
	local errors=0

	config_files=$(find "$config_dir" -name "CONFIG_*" ! -name "*~" 2>/dev/null || true)

	if [ -z "$config_files" ]; then
		return 0
	fi

	for file in $config_files; do
		if [ -s "$file" ] && [ "$(tail -c1 "$file" | wc -l)" -eq 0 ]; then
			echo "ERROR: CONFIG file '$file' does not end with a newline" >&2
			errors=$((errors + 1))
		fi
	done

	return $errors
}

@test "CONFIG files end with newlines" {
	run _validate_config_newlines "$BATS_TEST_DIRNAME/../configs"
	check_status
}