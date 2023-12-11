# .zshrc, placed here temporarily for reference

export PATH="$HOME/go/bin:$PATH"

setopt GLOB_SUBST

# Allow binding a key to edit current command in $EDITOR
autoload -U edit-command-line

# Don't ask to confirm history substitution
# TODO: this doeesn't work
unsetopt histverify

# Path to your oh-my-zsh installation.
export ZSH="~/.oh-my-zsh"

# Set name of the theme to load
ZSH_THEME="powerlevel10k/powerlevel10k"

# Use hyphen-insensitive completion, _ and - will be interchangeable.
HYPHEN_INSENSITIVE="true"

# Don't automatically set title, we want to do it ourselves for arbtt
DISABLE_AUTO_TITLE="true"

plugins=(
  cabal
  cargo
  command-not-found
  docker
  docker-compose
  docker-machine
  git
  mercurial
  pip
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# Powerlevel10k setup

POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs virtualenv)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status background_jobs)
POWERLEVEL9K_PROMPT_ON_NEWLINE=false

# Status segment customization
POWERLEVEL9K_STATUS_OK=false
POWERLEVEL9K_STATUS_HIDE_SIGNAME=true

# Dir customization
POWERLEVEL9K_SHORTEN_DIR_LENGTH=1
POWERLEVEL9K_SHORTEN_STRATEGY="truncate_from_right"

alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
alias grep='grep --color=auto'                                 # Colorize grep output
alias ll='ls -lah'
alias mkdir='mkdir -p'                                         # mkdir won't fail if directory already exists
alias px='ps aux | grep -v grep --color=auto | grep -i'        # Search running processes
alias zshreload='source ~/.zshrc && echo zsh config reloaded'
