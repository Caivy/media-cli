# media-cli

media-cli is a command-line tool that allows you to watch anime and drama directly from your terminal. It provides a convenient and streamlined way to search and stream your favorite anime and drama series without leaving the command line.

## Features

- Search and stream anime series
- Search and stream drama series
- Easy-to-use command-line interface
- Cross-platform support (Linux, macOS, Windows, Android, iOS)
- Supports popular media players like MPV, VLC

## Installation

To install media-cli, follow the instructions for your respective operating system:

- **Linux/MacOS**: Open the terminal and run the following command:
```sh
git clone https://github.com/Caivy/media-cli.git
```
- **Windows**:

*media-cli needs a posix shell and the current way is git bash. Unfortunately fzf can't run in git bash's default terminal. The solution is to use git bash in windows terminal*

First, you'll need windows terminal preview. [(Install)](https://apps.microsoft.com/store/detail/windows-terminal-preview/9N8G5RFZ9XK3?hl=de-at&gl=at&rtc=1)

Then make sure git bash is installed. [(Install)](https://git-scm.com/download/win) It needs to be added to windows terminal [(Instructions)](https://stackoverflow.com/questions/56839307/adding-git-bash-to-the-new-windows-terminal) or Alternatively you could also just use the git bash from the official git pages 

#### From installer
```sh
git clone https://github.com/Caivy/media-cli.git
```
- **Android (Termux)**: Open Termux and run the following command:
```bash
git clone https://github.com/Caivy/media-cli.git
```
- **iOS (iSH)**: Open iSH and run the following command:
```bash
git clone https://github.com/Caivy/media-cli.git
```
***Make sure you have the media player of your choice installed, such as MPV or VLC.***

## Usage

After installing media-cli, you can start using it by running the `media-cli` command in your terminal. The tool provides a set of interactive menus to search for and stream anime and drama series.

To get started, simply launch the tool and follow the on-screen prompts to search for your desired series, select an episode, and start streaming.

## Updating media-cli

To update media-cli to the latest version, you can use the built-in update command. Run the following command in your terminal:

```bash
media-cli -u
```

This command will automatically check for updates and apply them if available.

