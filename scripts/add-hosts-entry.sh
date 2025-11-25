#!/bin/bash

# Check if entry already exists
if grep -q "app.local" /etc/hosts; then
  echo "✓ Host entry for app.local already exists in /etc/hosts"
else
  echo "Adding app.local to /etc/hosts (requires sudo)..."
  echo "127.0.0.1 app.local" | sudo tee -a /etc/hosts
  echo "✓ Host entry added"
fi



