#!/bin/bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
source ~/.zshrc
nvm install --lts
nvm use --lts
nvm install --latest-npm
echo "nvm and latest LTS node installed"

