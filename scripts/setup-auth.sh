#!/bin/bash
set -e
SSH_KEY="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY" ]; then
  echo "Generating SSH key..."
  ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N ""
  echo "Public key (add to GitHub/GitLab):"
  cat "$SSH_KEY.pub"
else
  echo "SSH key already exists at $SSH_KEY"
fi
echo "Test your SSH connection with: ssh -T git@github.com" 