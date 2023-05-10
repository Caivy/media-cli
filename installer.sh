#!/bin/bash

# Install media-cli on Linux/MacOS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then

  # Function to detect the Linux distribution
  get_linux_distribution() {
      if [ -f /etc/arch-release ]; then
          echo "arch"
      elif [ -f /etc/debian_version ]; then
          echo "debian"
      elif [ -f /etc/gentoo-release ]; then
          echo "gentoo"
      elif [ -f /etc/SuSE-release ]; then
          echo "opensuse"
      elif [ -f /etc/fedora-release ]; then
          echo "fedora"
      else
          echo "unknown"
      fi
  }

  # Install media-cli on Linux
  linux_distro=$(get_linux_distribution)

  case "$linux_distro" in
      arch)
          sudo pacman -Syu mpv
          ;;
      debian)
          sudo apt-get update
          sudo apt-get install -y mpv
          ;;
      gentoo)
          sudo emerge -av mpv
          ;;
      opensuse)
          sudo zypper install -y mpv
          ;;
      fedora)
          sudo dnf install -y mpv
          ;;
      *)
          echo "Unsupported Linux distribution! media-cli installation failed."
          exit 1
          ;;
  esac

  sudo rm -rf "/usr/local/share/media-cli" "/usr/local/bin/media-cli" "/usr/local/bin/UI" /usr/local/bin/player_*
  if [ -d "media-cli" ]; then
    echo "media-cli directory already exists. Skipping git clone."
  else
    git clone "https://github.com/Caivy/media-cli.git"
  fi
  sudo cp -i -rf media-cli/media-cli /bin/
  rm -rf media-cli

  # Install fzf
  # git clone --depth 1 "https://github.com/junegunn/fzf.git" "$HOME/.fzf"
  # "$HOME/.fzf/install"

  echo "media-cli installed successfully on $linux_distro!"


# Install media-cli on Windows using scoop
elif [[ "$OSTYPE" == "msys" ]]; then
#   scoop bucket add extras
#   scoop install mpv
  
  if [ -d "media-cli" ]; then
    echo "media-cli directory already exists. Skipping git clone."
  else
    git clone "https://github.com/Caivy/media-cli.git"
  fi
  
  sudo cp -i -rf media-cli/media-cli /usr/bin/
  rm -rf media-cli
  
  git clone --depth 1 "https://github.com/junegunn/fzf.git" "$HOME/.fzf"
  "$HOME/.fzf/install"
  
  echo "media-cli installed successfully on Windows!"

# Install media-cli on Android using termux
elif [[ "$OSTYPE" == "linux-android" ]]; then
  rm -rf "$PREFIX/share/media-cli" "$PREFIX/bin/media-cli" "$PREFIX/bin/UI" "$PREFIX"/local/bin/player_*
  
  if [ -d "media-cli" ]; then
    echo "media-cli directory already exists. Skipping git clone."
  else
    git clone "https://github.com/Caivy/media-cli.git"
  fi
  
  cp -i -rf media-cli/media-cli "$PREFIX"/bin
  rm -rf media-cli
    
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
  
  sudo rm -rf "/usr/local/share/media-cli" "/usr/local/bin/media-cli" "/usr/local/bin/UI" /usr/local/bin/player_*
  
  if [ -d "media-cli" ]; then
    echo "media-cli directory already exists. Skipping git clone."
  else
    git clone "https://github.com/Caivy/media-cli.git"
  fi
  
  sudo cp -i -rf media-cli/media-cli /usr/local/bin
  rm -rf media-cli
  
  echo "media-cli installed successfully on iOS!"

else
  echo "Unsupported OS! media-cli installation failed."
fi
