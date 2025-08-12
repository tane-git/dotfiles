#!/bin/bash
sudo apt update
sudo add-apt-repository universe -y
sudo apt install -y ninja-build gettext cmake unzip curl build-essential make
mkdir -p ~/github
git clone https://github.com/neovim/neovim ~/github/neovim
cd ~/github/neovim
git checkout stable
make CMAKE_BUILD_TYPE=Release
sudo make install
echo "nvim built and installed"
