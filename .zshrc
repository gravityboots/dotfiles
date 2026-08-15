# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

source /usr/share/cachyos-zsh-config/cachyos-config.zsh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# For starship, currently disabled
# eval "$(starship init zsh)"


# Main Config Stuff


#if [[ -o interactive ]]; then
#    fastfetch
#fi

unsetopt correct
unsetopt correct_all

# For Bash/Zsh
export APPIMAGE="1"
export ELECTRON_OZONE_PLATFORM_HINT=wayland
export HYPRSHOT_DIR="$HOME/Pictures/Screenshots"
export VSCODE_GALLERY_SERVICE_URL="https://marketplace.visualstudio.com/_apis/public/gallery"
export VSCODE_GALLERY_ITEM_URL="https://marketplace.visualstudio.com/items"
export VSCODE_GALLERY_CACHE_URL="https://vscode.blob.core.windows.net/gallery/index"
export VSCODE_GALLERY_CONTROL_URL=""

export PATH=$PATH:/home/gravityboots/.spicetify
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.platformio/penv/bin:$PATH"

export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx

# for ssh agent auth for GUI & sandboxed apps; run along with systemctl --user enable --now ssh-agent
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

alias pipi='pip install --user --break-system-packages'
alias pipu='pip uninstall --user --break-system-packages'
alias snvim='sudo HOME=$HOME nvim'
alias ..='cd ..'
alias ...='cd ../..'