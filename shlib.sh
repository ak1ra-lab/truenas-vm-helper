cat /dev/null <<EOF
------------------------------------------------------------------------
https://github.com/client9/shlib - portable posix shell functions
Public domain - http://unlicense.org
https://github.com/client9/shlib/blob/master/LICENSE.md
but credit (and pull requests) appreciated.
------------------------------------------------------------------------
EOF
date_iso8601() {
  date -u +%Y-%m-%dT%H:%M:%S+0000
}
echoerr() {
  echo "$@" 1>&2
}
git_clone_or_update() {
  giturl=$1
  if [ ! -d "$gitrepo" ]; then
    git clone "$giturl"
  else
    (cd "$gitrepo" && git pull >/dev/null)
  fi
}
github_api() {
  local_file=$1
  source_url=$2
  header=""
  case "$source_url" in
    https://api.github.com*)
      test -z "$GITHUB_TOKEN" || header="Authorization: token $GITHUB_TOKEN"
      ;;
  esac
  http_download "$local_file" "$source_url" "$header"
}
github_release() {
  owner_repo=$1
  version=$2
  test -z "$version" && version="latest"
  giturl="https://github.com/${owner_repo}/releases/${version}"
  json=$(http_copy "$giturl" "Accept:application/json")
  test -z "$json" && return 1
  version=$(echo "$json" | tr -s '\n' ' ' | sed 's/.*"tag_name":"//' | sed 's/".*//')
  test -z "$version" && return 1
  echo "$version"
}
hash_md5() {
  target=${1:-/dev/stdin}
  if is_command md5sum; then
    sum=$(md5sum "$target" 2>/dev/null) || return 1
    echo "$sum" | cut -d ' ' -f 1
  elif is_command md5; then
    md5 -q "$target" 2>/dev/null
  else
    log_crit "hash_md5 unable to find command to compute md5 hash"
    return 1
  fi
}
hash_sha256() {
  TARGET=${1:-/dev/stdin}
  if is_command gsha256sum; then
    hash=$(gsha256sum "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command sha256sum; then
    hash=$(sha256sum "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command shasum; then
    hash=$(shasum -a 256 "$TARGET" 2>/dev/null) || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command openssl; then
    hash=$(openssl dgst -sha256 "$TARGET") || return 1
    echo "$hash" | cut -d "=" -f 2 | sed -e 's/^[[:space:]]*//'
  else
    log_crit "hash_sha256 unable to find command to compute sha-256 hash"
    return 1
  fi
}
hash_sha256_verify() {
  TARGET=$1
  checksums=$2
  if [ -z "$checksums" ]; then
    log_err "hash_sha256_verify checksum file not specified in arg2"
    return 1
  fi
  BASENAME=${TARGET##*/}
  if grep -q '^SHA256 ('${BASENAME}') =' "${checksums}"; then
    want=$(grep '^SHA256 ('${BASENAME}') =' "${checksums}" | cut -d "=" -f 2 | sed -e 's/^[[:space:]]*//')
  elif grep -q '^SHA2-256\(('${BASENAME}')\)?=' "${checksums}"; then
    want=$(grep '^SHA2-256\(('${BASENAME}')\)?=' "${checksums}" | cut -d "=" -f 2 | sed -e 's/^[[:space:]]*//')
  else
    want=$(grep "${BASENAME}$" "${checksums}" 2>/dev/null | tr '\t' ' ' | cut -d ' ' -f 1)
  fi
  if [ -z "$want" ]; then
    log_err "hash_sha256_verify unable to find checksum for '${TARGET}' in '${checksums}'"
    return 1
  fi
  got=$(hash_sha256 "$TARGET")
  if [ "$want" != "$got" ]; then
    log_err "hash_sha256_verify checksum for '$TARGET' did not verify ${want} vs $got"
    return 1
  fi
}
hash_sha512() {
  TARGET=${1:-/dev/stdin}
  if is_command gsha512sum; then
    hash=$(gsha512sum "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command sha512sum; then
    hash=$(sha512sum "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command shasum; then
    hash=$(shasum -a 512 "$TARGET" 2>/dev/null) || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command openssl; then
    hash=$(openssl dgst -sha512 "$TARGET") || return 1
    echo "$hash" | cut -d "=" -f 2 | sed -e 's/^[[:space:]]*//'
  else
    log_crit "hash_sha512 unable to find command to compute sha-512 hash"
    return 1
  fi
}
hash_sha512_verify() {
  TARGET=$1
  checksums=$2
  if [ -z "$checksums" ]; then
    log_err "hash_sha512_verify checksum file not specified in arg2"
    return 1
  fi
  BASENAME=${TARGET##*/}
  if grep -q '^SHA512 ('${BASENAME}') =' "${checksums}"; then
    want=$(grep '^SHA512 ('${BASENAME}') =' "${checksums}" | cut -d "=" -f 2 | sed -e 's/^[[:space:]]*//')
  elif grep -q '^SHA2-512\(('${BASENAME}')\)?=' "${checksums}"; then
    want=$(grep '^SHA2-512\(('${BASENAME}')\)?=' "${checksums}" | cut -d "=" -f 2 | sed -e 's/^[[:space:]]*//')
  else
    want=$(grep "${BASENAME}$" "${checksums}" 2>/dev/null | tr '\t' ' ' | cut -d ' ' -f 1)
  fi
  if [ -z "$want" ]; then
    log_err "hash_sha512_verify unable to find checksum for '${TARGET}' in '${checksums}'"
    return 1
  fi
  got=$(hash_sha512 "$TARGET")
  if [ "$want" != "$got" ]; then
    log_err "hash_sha512_verify checksum for '$TARGET' did not verify ${want} vs $got"
    return 1
  fi
}
http_download_curl() {
  local_file=$1
  source_url=$2
  header=$3
  if [ -z "$header" ]; then
    code=$(curl -w '%{http_code}' -sL -o "$local_file" "$source_url")
  else
    code=$(curl -w '%{http_code}' -sL -H "$header" -o "$local_file" "$source_url")
  fi
  if [ "$code" != "200" ]; then
    log_debug "http_download_curl received HTTP status $code"
    return 1
  fi
  return 0
}
http_download_wget() {
  local_file=$1
  source_url=$2
  header=$3
  if [ -z "$header" ]; then
    wget -q -O "$local_file" "$source_url"
  else
    wget -q --header "$header" -O "$local_file" "$source_url"
  fi
}
http_download_aria2() {
  local_file=$1
  source_url=$2
  header=$3
  local_file_dir=${local_file%/*}
  if [ -z "$header" ]; then
    aria2c -q -d "$local_file_dir" "$source_url"
  else
    aria2c -q --header "$header" -d "$local_file_dir" "$source_url"
  fi
}
http_download() {
  log_debug "http_download $2"
  if is_command curl; then
    http_download_curl "$@"
    return
  elif is_command wget; then
    http_download_wget "$@"
    return
  elif is_command aria2c; then
    http_download_aria2 "$@"
    return
  fi
  log_crit "http_download unable to find wget or curl"
  return 1
}
http_copy() {
  tmp=$(mktemp)
  http_download "${tmp}" "$1" "$2" || return 1
  body=$(cat "$tmp")
  rm -f "${tmp}"
  echo "$body"
}
http_last_modified() {
  url=${1:-/dev/stdin}
  curl -L -s --fail --head "$url" | grep -i 'Last-Modified:' | tail -c 31 | head -c 29
}
is_command() {
  command -v "$1" >/dev/null
}
require_command() {
  for c in "$@"; do
    command -v "$c" >/dev/null || {
      echo >&2 "required command '$c' is not installed, aborting..."
      exit 1
    }
  done
}
log_prefix() {
  echo "[$(date_iso8601)][$0]"
}
_logp=6
log_set_priority() {
  _logp="$1"
}
log_priority() {
  if test -z "$1"; then
    echo "$_logp"
    return
  fi
  [ "$1" -le "$_logp" ]
}
log_tag() {
  case $1 in
    0) echo "emerg" ;;
    1) echo "alert" ;;
    2) echo "crit" ;;
    3) echo "err" ;;
    4) echo "warning" ;;
    5) echo "notice" ;;
    6) echo "info" ;;
    7) echo "debug" ;;
    *) echo "$1" ;;
  esac
}
log_debug() {
  log_priority 7 || return 0
  echoerr "$(log_prefix)[$(log_tag 7)]" "$@"
}
log_info() {
  log_priority 6 || return 0
  echoerr "$(log_prefix)[$(log_tag 6)]" "$@"
}
log_notice() {
  log_priority 5 || return 0
  echoerr "$(log_prefix)[$(log_tag 5)]" "$@"
}
log_warning() {
  log_priority 4 || return 0
  echoerr "$(log_prefix)[$(log_tag 4)]" "$@"
}
log_err() {
  log_priority 3 || return 0
  echoerr "$(log_prefix)[$(log_tag 3)]" "$@"
}
log_crit() {
  log_priority 2 || return 0
  echoerr "$(log_prefix)[$(log_tag 2)]" "$@"
}
log_alert() {
  log_priority 1 || return 0
  echoerr "$(log_prefix)[$(log_tag 1)]" "$@"
}
log_emerg() {
  log_priority 0 || return 0
  echoerr "$(log_prefix)[$(log_tag 0)]" "$@"
}
mktmpdir() {
  test -z "$TMPDIR" && TMPDIR="$(mktemp -d)"
  mkdir -p "${TMPDIR}"
  echo "${TMPDIR}"
}
uname_arch() {
  arch=$(uname -m)
  case $arch in
    x86_64) arch="amd64" ;;
    x86) arch="386" ;;
    i686) arch="386" ;;
    i386) arch="386" ;;
    aarch64) arch="arm64" ;;
    armv5*) arch="armv5" ;;
    armv6*) arch="armv6" ;;
    armv7*) arch="armv7" ;;
  esac
  echo ${arch}
}
uname_arch_check() {
  arch=$(uname_arch)
  case "$arch" in
    386) return 0 ;;
    amd64) return 0 ;;
    arm64) return 0 ;;
    armv5) return 0 ;;
    armv6) return 0 ;;
    armv7) return 0 ;;
    ppc64) return 0 ;;
    ppc64le) return 0 ;;
    mips) return 0 ;;
    mipsle) return 0 ;;
    mips64) return 0 ;;
    mips64le) return 0 ;;
    s390x) return 0 ;;
    amd64p32) return 0 ;;
  esac
  log_crit "uname_arch_check '$(uname -m)' got converted to '$arch' which is not a GOARCH value.  Please file bug report at https://github.com/client9/shlib"
  return 1
}
uname_os() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$os" in
    msys*) os="windows" ;;
    mingw*) os="windows" ;;
    cygwin*) os="windows" ;;
  esac
  echo "$os"
}
uname_os_check() {
  os=$(uname_os)
  case "$os" in
    darwin) return 0 ;;
    dragonfly) return 0 ;;
    freebsd) return 0 ;;
    linux) return 0 ;;
    android) return 0 ;;
    nacl) return 0 ;;
    netbsd) return 0 ;;
    openbsd) return 0 ;;
    plan9) return 0 ;;
    solaris) return 0 ;;
    windows) return 0 ;;
  esac
  log_crit "uname_os_check '$(uname -s)' got converted to '$os' which is not a GOOS value. Please file bug at https://github.com/client9/shlib"
  return 1
}
untar() {
  tarball=$1
  case "${tarball}" in
    *.tar.gz | *.tgz) tar -xzf "${tarball}" ;;
    *.tar) tar -xf "${tarball}" ;;
    *.zip) unzip "${tarball}" ;;
    *)
      log_err "untar unknown archive format for ${tarball}"
      return 1
      ;;
  esac
}
cat /dev/null <<EOF
------------------------------------------------------------------------
End of functions from https://github.com/client9/shlib
------------------------------------------------------------------------
EOF
