# Use an official Swift runtime as a base image
FROM swift:latest

# Set the working directory to /app
WORKDIR /app

# Copy the entire content of the local directory to the container
COPY . .

# Build the Swift package
RUN swift build

# Run tests
CMD ["swift", "test"]

