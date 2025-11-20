#!/bin/bash

SWIFT_VERSION="latest"

# Spin Swift Docker container
docker run -it --rm -v $(pwd):/app -w /app "swift:$SWIFT_VERSION" bash