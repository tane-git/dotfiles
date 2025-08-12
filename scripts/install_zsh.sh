#!/bin/bash
sudo apt install -y zsh
chsh -s $(which zsh)
exec zsh
