#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# For Bash/Zsh
export APPIMAGE="1"
export ELECTRON_OZONE_PLATFORM_HINT=wayland
