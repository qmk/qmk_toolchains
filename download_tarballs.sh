#!/usr/bin/env bash

base_url="https://linux.qmk.fm/toolchain_tarballs"

cat tarball-mirrors.txt | while read -r line; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^# ]]; then
        continue
    fi

    # Extract the filename from the line
    filename=$(basename $(echo "$line" | awk '{print $2}'))
    checksum=$(echo "$line" | awk '{print $1}')
    url="$base_url/$filename"

    # Create the tarballs directory if it doesn't exist
    mkdir -p tarballs

    # Check if the tarball already exists in the tarballs directory
    if [[ -f "tarballs/$filename" ]]; then
        echo "Tarball $filename already exists, skipping download."
        continue
    fi

    # Download the tarball into the tarballs directory
    echo "Downloading $filename..."
    curl -fsSL -o "tarballs/$filename" "$url"
done

# Verify the checksum for each downloaded tarball, deleting it if the checksum does not match
sha512sum -c tarball-mirrors.txt 2>&1 | while read -r line; do
    if [[ -n "$(echo "$line" | grep "FAILED")" ]]; then
        filename=$(basename $(echo "$line" | cut -d: -f1))
        echo "Checksum verification failed for $filename, deleting file."
        rm -f "tarballs/$filename"
    fi
done
