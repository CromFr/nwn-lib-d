#!/bin/bash

FROM=${1:-}
TO=${2:-}

CURR_TAG=$(git tag --points-at HEAD)

if [ -n "$FROM" ] && [ -n "$FROM" ]; then
	CURR_TAG=$TO
	LAST_TAG=$FROM
elif [[ -z "$CURR_TAG" ]]; then
	# Untagged commit
	CURR_TAG=$(git rev-parse --short HEAD)
	LAST_TAG=$(git tag | grep -P '^v\d\.\d\.\d(-rc\d)?$' | tail -n1)
elif [[ "$CURR_TAG" == v*.*.*-rc* ]]; then
	# Prerelease, changelog since last prerelease or release
	LAST_TAG=$(git tag | grep -P '^v\d\.\d\.\d(-rc\d)?$' | tail -n2 | head -n1)
else
	# Release, changelog since last release
	LAST_TAG=$(git tag | grep -P '^v\d\.\d\.\d$' | tail -n2 | head -n1)
fi


HEADER=0
for TOOL in tools/nwn-*; do
	TOOL=$(basename "$TOOL")

	COMMITS=$(git log --format="%H" --grep="^$TOOL: " "$LAST_TAG..$CURR_TAG")

	if [ -n "$COMMITS" ]; then
		if (( !HEADER )); then
			echo "### Tool changes since \`$LAST_TAG\`:"
			HEADER=1
		fi
		echo
		echo "#### $TOOL"
		echo
		for COMMIT in $COMMITS; do
			LOG=$(git log --format="%s%n%b" "$COMMIT^-")

			FIRST=1
			while read -r LINE; do
				if (( FIRST )); then
					echo "- $(echo "$LINE" | cut -d ' ' -f 2-)"
					FIRST=0
				else
					echo "  $LINE"
				fi
			done < <(echo "$LOG")

		done
	fi
done
