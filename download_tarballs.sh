#!/usr/bin/env bash

cat tarball-mirrors.txt | while read -r line; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^# ]]; then
        continue
    fi

    # Extract the URL and filename from the line
    url=$(echo "$line" | awk '{print $1}')
    filename=$(basename "$url")

    # Create the tarballs directory if it doesn't exist
    mkdir -p tarballs

    # Check if the tarball already exists in the tarballs directory
    if [[ -f "tarballs/$filename" ]]; then
        echo "Tarball $filename already exists, skipping download."
        continue
    fi

    # Download the tarball into the tarballs directory
    echo "Downloading $filename..."
    curl -L -o "tarballs/$filename" "$url"
done