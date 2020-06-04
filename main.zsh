#!/bin/zsh


_CUR_DIR=$(dirname "$0")


function -dot-main() {
  # Load the framework. Sources files in order of:
  #  - file.zsh
  #  - */file.zsh
  #  - post-file.zsh
  #
  # Args:
  #  $1 - Directory location of the Dotfiles.
  #       Defaults to `$DOTFILES_DIR, if set, or `$HOME`.

  local src_dir="${1}"

  if test -z $src_dir; then
    src_dir="${DOTFILES_DIR:=${HOME}}";
  fi

  # Load Framework functions
  # --------------------------------------
  -dot-add-fpath "${_CUR_DIR}" "functions"
  -dot-add-fpath "${src_dir}" "functions"
  -dot-add-fpath "${_CUR_DIR}" "completions"
  -dot-add-fpath "${src_dir}" "completions"
  # Reload
  -dot-reload-autoload

  # Secrets
  # --------------------------------------
  -dot-source-dirglob "secrets.zsh"
  -dot-source-dotfile "post-secrets.zsh"

  # Config
  # --------------------------------------
  -dot-source-dirglob "config.zsh"
  -dot-source-dotfile "post-config.zsh"

  # Init
  # --------------------------------------
  -dot-source-dirglob "init.zsh"
  -dot-source-dotfile "post-init.zsh"

  # Finish Autocomplete Setup
  # --------------------------------------
  -dot-reload-compinit
}


function -dot-cache-get-file() {
  # Create or get the name of a file in the cache directory.
  # Usage :
  #  $1 = Name of the file to read from the cache. Will create the file if it
  #       doesn't exist.

  local fh="${ZSH_CACHE_DIR}/$1"

  if ! test -e "${fh}"; then
    mkdir -p "$(dirname ${fh})"
    touch "${fh}"
  fi

  echo "${fh}"
}


function -dot-cache-source-file() {
  # Source a file from the cache.
  # Usage :
  #   $1 = File name from cache directory.

  local fh=$(-dot-cache-get-file $1)

  test -e "${fh}" && source "${fh}"
}


function -dot-cache-update-file() {
  # Update a file in the cache directory by overwriting the contents with the
  # output of the passed command.
  # Usage :
  #   $1 = The name of the file to be updated.
  #   $2 = The command to be run to update the file.

  local fh=$(-dot-cache-get-file $1) cmmd="$2"

  echo "Updating cached file ${fh}"

  (eval "${cmmd}") &>"${fh}"
}


function -dot-source-dotfile() {
  # Source a file in the dotfile dir.
  # If it doesn't find the matching file in the dotfile directory, it will
  # source it from the current working directory.
  # Usage :
  #   $1 = The name of the file to find in the dotfiles directory.

  local fh="${1}" base_dir="${2:=${DOTFILES_DIR}}"

  if test -r "${base_dir}/${fh}"; then
    source "${base_dir}/${fh}";
  elif test -r "${fh}"; then
    source "${fh}";
  fi
}


function -dot-source-dirglob() {
  # Sources all files matching argument, beginning with the root file and then
  # source all in 1st level subdirectory.
  # Usage :
  #   $1 = The name of the file to find across directories.

  local _target_file=$1 base_dir=${2:=$DOTFILES_DIR}

  -dot-source-dotfile "${_target_file}"

  for the_file in $($SHELL +o nomatch -c "ls ${base_dir}/*/${_target_file} 2>/dev/null"); do
    -dot-source-dotfile $the_file;
  done
}


function -dot-add-symlink-to-home() {
  # Creates symlink in the $HOME directory
  # Usage :
  #   $1 = Source file to use as link.
  #   $2 = Destination for symlink.

  local _src="$DOTFILES_DIR/${1#"$DOTFILES_DIR/"}" _dest="$HOME/${2#"$HOME/"}"

  if ! test -L $_dest; then
    if ! test -e $_dest; then
      printf "Creating link for file %s at %s\n" "$_src" "$_dest"

      if test -e "$_src"; then
        printf "Creating target directory %s\n" $_dest

        mkdir -p $(dirname "$_dest")
        ln -sf "$_src" "$_dest"
        return 0
      else
        printf \
          "Unable to create symlink for %s; src file %s does not exist.\n" \
          $_dest \
          $_src
      fi
    else
      printf \
        "Unable to create symlink for %s; dest file %s already exists.\n" \
        $_src \
        $_dest
    fi
  fi
}


function -dot-install-github-repo() {
  # Idempotently clone repo from GitHub into directory.
  # Usage:
  # $1 (required) = Namespace/ProjectName
  # $2 (required) = Filesystem Location
  # $3            = Protocol (SSH|HTTPS)

  local __test __url __dir=$2 __protocol="${GIT_PROTOCOL:=ssh}"

  if ! test -d $__dir; then mkdir -p $__dir; fi

  __test=$(git -C $__dir remote -v &>/dev/null)

  if test $? -ne 0 -o ! -d "${__dir}/.git"; then
    if test "$3"; then __protocol="$3"; fi;

    case $__protocol in
      https|HTTPS) # Use HTTPS
        __url="https://github.com/$1.git"
        ;;
      ssh|SSH|*)   # Default
        __url="git@github.com:$1.git"
        ;;
    esac;

    rm -r ${__dir} || true;

    git clone --depth 10 $__url $__dir;
  fi
}


function -dot-install-github-plugin() {
  # Install Github Plugin
  # Usage:
  # $1 = Group + Plugin Name
  # $2 = Install Directory

  local name=$1 plugin_name=${1#*/} __dir="${2:=${ZSH_CUSTOM}/plugins}"

  -dot-install-github-repo \
    "$name" \
    "${__dir}/${plugin_name}" \
    "HTTPS";

  plugins=($plugins $plugin_name)
}


function -dot-install-omz() {
  # Installs OMZ into the ZSH directory
  # Usage:
  #

  -dot-install-github-repo \
    "robbyrussell/oh-my-zsh" \
    "${ZSH:=${ZSH_CACHE_DIR}/oh-my-zsh}"
}


function -dot-install-brew-bundle() {
  # Installs all of the packages in a Homebrew Brewfile.
  # Usage:
  #   $1 = Brewfile to use. Defaults to env `BREW_FILE`
  #

  local _brewfile=${1:=${BREW_FILE}} _brew=$(command -v brew)

  test -n ${_brew} ||
    { echo 'HomeBrew not found; "brew" command not available' && return 1 }
  test -r ${_brewfile} ||
    { echo 'Unable to find or read Brewfile.' && return 1 }

  printf 'Installing brew packages from %s\n' "${_brewfile}"
  printf 'Executing: %s bundle install --file "%s" --verbose\n' ${_brew} ${_brewfile}

  ${_brew} bundle install --file "${_brewfile}" --verbose
}


function -dot-dump-brew-bundle() {
  # Dump brew packages to file.
  # Usage:
  #   $1 = Brewfile to write. Defaults to env `BREW_FILE`
  #

  local _brewfile=${1:=${BREW_FILE}} _brew=$(command -v brew)

  test -n ${_brew} || {echo 'HomeBrew not found; "brew" command not available' && return 1}

  printf 'Installing brew packages from %s\n' "${_brewfile}"
  printf 'Executing: %s bundle dump --file "%s" --force --all\n' ${_brew} ${_brewfile}

  ${_brew} bundle dump --file "${_brewfile}" --force --all
}


function -dot-upgrade-dir-repos() {
  # Update plugins from Github
  # Usage:
  # $1 = Directory to check for repos.
  # $2 = Array of directory names to ignore

  local _remote_url _found
  local _target_dir=$1 _ignore_dirs=(${2})

  if test ${#__ignore_dirs[@]} -eq 0; then
    _found=($(find "${_target_dir}" -maxdepth 1 -type d \
      -not -path "${_target_dir}" \
      -not \( \
        -name "${_ignore_dirs[1]}" \
        $(printf -- '-o -name "%s" ' "${_ignore_dirs[2,-1]}") \
      \)))
  else
    _found=($(find "${_target_dir}" -maxdepth 1 -type d \
      -not -path "${_target_dir}" \
      ));
  fi

  for i in $_found; do
    (
      printf "=> Upgrading directory %s from origin %s.\n=> git -C %s pull origin master\n" \
        $i \
        "$(git -C $i config remote.origin.url)" \
        $i

      git -C $i pull origin master
    ) &
  done

  wait
}


function -dot-upgrade-dotfiles-dir() {
  # Update the dotfiles directory, caching the contents while updating.
  # Usage :
  #  $1 = Dotfiles Repo Directory

  local repo_dir=${1:=${DOTFILES_DIR}}

  (
    set -v
    git -C "${repo_dir}" stash
    git -C "${repo_dir}" pull --ff-only origin master || true
  )

  (git -C "${repo_dir}" stash pop || true) &>/dev/null

  -dot-main
}


function -dot-upgrade-brew() {
  # Upgrade Homebrew
  # Usage :

  local _update_args _upgrade_args _dump_args _cmd

  { # Update brew
    _update_args="--force"
    if [[ -n "$ZSH_DEBUG" ]]; then _update_args="--verbose ${_update_args}"; fi
    _cmd="brew update $_update_args"
    echo "${_cmd}"
    eval "${_cmd}"
  }

  { # Upgrade brews
    _upgrade_args="--display-times"
    if [[ -n "$ZSH_DEBUG" ]]; then _upgrade_args="--verbose ${_upgrade_args}"; fi
    _cmd="brew upgrade $_upgrade_args"
    echo "${_cmd}"
    eval "${_cmd}"
  }

  { # Dump installed brews to file.
    if [ -n "$BREW_FILE" ]; then
      -dot-dump-brew-bundle
    fi
  }

  { # Cleanup cached brews
    _cmd="brew cleanup --verbose --prune=${BREW_CLEANUP_PRUNE_DAYS}"
    echo "${_cmd}"
    eval "${_cmd}"
  }
}


function -dot-upgrade-cache-repos() {
  # Update cache directory repositories
  # Usage :

  local __cachedir="${ZSH_CACHE_DIR:=${DOTFILES_DIR}/.cache}"
  local _ignored_plugins=(${DOT_UPGRADE_IGNORE})

  -dot-upgrade-dir-repos "${__cachedir}" ${_ignored_plugins}
}


function -dot-upgrade-zsh-plugins() {
  # Update plugins for ZSH
  # Usage :

  -dot-upgrade-dir-repos "${ZSH_CUSTOM}/plugins"
}


function -dot-upgrade-dotfiles-projects() {
  # Run upgrade.zsh across project
  # Usage :

  for i in $(ls -d ${DOTFILES_DIR}/*/upgrade.zsh); do
    (
      set -v
      source "${i}"
    ) &
  done

  wait
}


function -dot-upgrade-shell-env() {
  # Upgrade the Dotfiles environment
  # Runs all the upgrade functions against the environment.
  # Usage :

  # Upgrade the dotfiles repo.
  -dot-upgrade-dotfiles-dir ${DOTFILES_DIR}

  # We have to run the brew upgrade first since everything is installed by it.
  -dot-upgrade-brew

  # The Rest
  -dot-upgrade-cache-repos
  -dot-upgrade-zsh-plugins
  -dot-upgrade-dotfiles-projects

  # Lastly, reload the shell
  exec "${SHELL}"
}


function -dot-upgrade-completion() {
  # Upgrade a completion file.
  # Usage :
  #   1 = Name of the command
  #   2 = Path of completions directory
  #

  local \
    commd="${1}" \
    dir="${2}"

  command -v ${commd} || return 1

  {
    mkdir -p "${dir}" || true

    ${commd} completion zsh &> "${dir}/_${commd}"
  }
}


function -dot-profile-zsh() {
  # Run a cprof-like load of the ZSH Environment
  # Usage :

  # exposes zprofexport
  if [[ -z "$ZSH_DEBUG" ]]; then
    echo 'Set $ZSH_DEBUG=1 to enable profiling.'
  else
    zmodload zsh/zprof
    time (zsh -i -c exit)
    zprof
  fi
}


function -dot-reload-compinit() {
  # Reload/Setup Autoload functions and compinit
  # Usage :

  autoload -Uz +X compinit
  autoload -Uz +X bashcompinit

  # Autoload fpath and bash completes compat, as well
  -dot-reload-autoload

  compinit -C -i -d "${ZSH_COMPDUMP}" && bashcompinit
}


function -dot-reload-autoload() {
  # Reload the functions added to autoload.

  for func in $^fpath/*(N-.x:t); do
    autoload -Uz $func
  done
}


function -dot-add-path() {
  # A stupid function that adds a new Path to the beginning of the PATH.
  # Usage:
  # $1 = Path string.

  export PATH="${1}:${PATH}"
}


function -dot-add-fpath() {
  # Add the directory, and any 1st level directories, to the fpath.
  #
  # Usage:
  #   1 - Directory to begin search.
  #   2 - Name of directory to load within the base directory

  local _src_dir="$1" _fn="${2}"

  if test -d "${_src_dir}/${_fn}"; then
    fpath=(${_src_dir}/${_fn} $fpath)
  fi

  for fdir in $(find "$_src_dir" -type d -maxdepth 1 -not -name "*.*" -print); do
    if test -d "${fdir}/${_fn}"; then
      fpath=($fdir/${_fn} $fpath)
    fi
  done
}
