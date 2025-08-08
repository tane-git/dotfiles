#!/bin/bash

DOTFILES_DIR="$HOME/dotfiles"

# Backup existing files
backup_if_exists() {
    if [ -f "$1" ] || [ -L "$1" ]; then
        mv "$1" "$1.backup.$(date +%Y%m%d_%H%M%S)"
        echo "Backed up $1"
    fi
}

# Create symlinks
link_file() {
    backup_if_exists "$HOME/$2"
    ln -s "$DOTFILES_DIR/$1" "$HOME/$2"
    echo "Linked $1 -> ~/$2"
}

# Link files
link_file ".tmux.conf" ".tmux.conf"

echo "Dotfiles setup complete!"
