#!/bin/bash

# Install media-cli on Linux/MacOS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  sudo apt-get update
  sudo apt-get install -y mpv
  sudo rm -rf "/usr/local/share/media-cli" "/usr/local/bin/media-cli" "/usr/local/bin/UI" /usr/local/bin/player_*
  git clone "https://github.com/Caivy/media-cli.git"
  sudo cp media-cli/media-cli /usr/local/bin
  rm -rf media-cli
  git clone --depth 1 "https://github.com/junegunn/fzf.git" "$HOME/.fzf"
  "$HOME/.fzf/install"
  echo "media-cli installed successfully on Linux/MacOS!"

# Install media-cli on Windows using scoop
elif [[ "$OSTYPE" == "msys" ]]; then
  scoop bucket add extras
  scoop install mpv
  scoop install media-cli
  git clone --depth 1 "https://github.com/junegunn/fzf.git" "$HOME/.fzf"
  "$HOME/.fzf/install"
  echo "media-cli installed successfully on Windows!"

# Install media-cli on Android using termux
elif [[ "$OSTYPE" == "linux-android" ]]; then
  rm -rf "$PREFIX/share/media-cli" "$PREFIX/bin/media-cli" "$PREFIX/bin/UI" "$PREFIX"/local/bin/player_*
  git clone "https://github.com/Caivy/media-cli.git"
  cp media-cli/media-cli "$PREFIX"/bin
  rm -rf media-cli
  git clone --depth 1 "https://github.com/junegunn/fzf.git" "$HOME/.fzf"
  "$HOME/.fzf/install"
  echo "media-cli installed successfully on Android!"

# Install media-cli on iOS using iSH
elif [[ "$OSTYPE" == "darwin"* && $(uname -p) == "arm" ]]; then
  apk add grep sed curl fzf git aria2 alpine-sdk ncurses
  git clone https://github.com/Lockl00p/ffmpeglibs-iSH.git ~/ffmpeg
  cd ~/ffmpeg
  cat fmp.?? > ffmpeg.tar.gz
  tar -xvf ffmpeg.tar.gz
  cd FFmpeg
  make install
  cd
  rm -rf ffmpeg
  apk add ffmpeg
  
  git clone --depth 1 "https://github.com/junegunn/fzf.git" "$HOME/.fzf"
  "$HOME/.fzf/install"
  
  sudo rm -rf "/usr/local/share/media-cli" "/usr/local/bin/media-cli" "/usr/local/bin/UI" /usr/local/bin/player_*
  git clone "https://github.com/Caivy/media-cli.git"
  sudo cp media-cli/media-cli /usr/local/bin
  rm -rf media-cli
  echo "media-cli installed successfully on iOS!"

else
  echo "Unsupported OS! media-cli installation failed."
fi
