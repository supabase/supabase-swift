#!/bin/bash

SWIFT_VERSION="latest"

docker run -it --rm -v $(pwd):/app -w /app "swift:$SWIFT_VERSION" bash