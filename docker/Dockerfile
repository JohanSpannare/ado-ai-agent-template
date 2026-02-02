# OpenCode with Node.js for MCP support
FROM ghcr.io/anomalyco/opencode:latest

# Install Node.js and npm for MCP servers
# Install bash, curl, jq for scripts (update-workitem.sh etc.)
# Install pandoc for document conversion
RUN apk add --no-cache nodejs npm bash curl jq pandoc

# Verify installation
RUN node --version && npm --version && npx --version && bash --version && jq --version
