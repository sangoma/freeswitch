#!/bin/bash
##### -*- mode:shell-script; indent-tabs-mode:nil; sh-basic-offset:2 -*-
##### Author: Travis Cross <tc@traviscross.com>

set -e

ddir="."
[ -n "${0%/*}" ] && ddir="${0%/*}"

err () {
  echo "$0 error: $1" >&2
  exit 1
}

xread () {
  local xIFS="$IFS"
  IFS=''
  read $@
  local ret=$?
  IFS="$xIFS"
  return $ret
}

create_dbg_pkgs () {
  for x in $ddir/*; do
    test ! -d $x && continue
    test "$x" = "tmp" -o "$x" = "source" && continue
    test ! "$x" = "${x%-dbg}" && continue
    test ! -d $x/usr/lib/debug && continue
    mkdir -p $x-dbg/usr/lib
    mv $x/usr/lib/debug $x-dbg/usr/lib/
  done
}

list_build_depends () {
  test -f $ddir/.stamp-bootstrap || (cd $ddir && ./bootstrap.sh)
  local deps="" found=false
  while xread l; do
    if [ "${l%%:*}" = "Build-Depends" ]; then
      deps="${l#*:}"
      found=true
      continue
    elif $found; then
      if [ -z "$l" ]; then
        # is newline
        break
      elif [ -z "${l##\#*}" ]; then
        # is comment
        continue
      elif [ -z "${l## *}" ]; then
        # is continuation line
        deps="$deps $(echo "$l" | sed -e 's/^ *//' -e 's/ *([^)]*)//g' -e 's/,//g')"
      else
        # is a new header
        break
      fi
    fi
  done < $ddir/control
  echo "${deps# }"
}

install_build_depends () {
  local apt=""
  if [ -n "$(which aptitude)" ]; then
    apt=$(which aptitude)
  elif [ -n "$(which apt-get)" ]; then
    apt=$(which apt-get)
  else
    err "Can't find apt-get or aptitude; are you running on debian?"
  fi
  $apt install -y $(list_build_depends)
  touch $ddir/.stamp-build-depends
}

cwget () {
  local url="$1" f="${1##*/}"
  echo "fetching: $url to $f" >&2
  if [ -n "$FS_FILES_DIR" ]; then
    if ! [ -s "$FS_FILES_DIR/$f" ]; then
      (cd $FS_FILES_DIR && wget -N "$url")
    fi
    cp -a $FS_FILES_DIR/$f .
  else
    wget -N "$url"
  fi
}

getlib () {
  local sd="$1" url="$2" f="${2##*/}"
  (cd $sd/libs \
    && cwget "$url" \
    && tar -xv --no-same-owner --no-same-permissions -f "$f" \
    && rm -f "$f" \
    && mkdir -p $f)
}

getsound () {
  local sd="$1" url="$2" f="${2##*/}"
  (cd $sd \
    && cwget "$url")
}

getlibs () {
  local sd="$1"
  # get pinned libraries
  getlib $sd http://downloads.mongodb.org/cxx-driver/mongodb-linux-x86_64-v1.8-latest.tgz
  getlib $sd http://files.freeswitch.org/downloads/libs/json-c-0.9.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/libmemcached-0.32.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/soundtouch-1.6.0.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/flite-1.5.4-current.tar.bz2
  getlib $sd http://files.freeswitch.org/downloads/libs/sphinxbase-0.7.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/pocketsphinx-0.7.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/communicator_semi_6000_20080321.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/celt-0.10.0.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/opus-0.9.0.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/openldap-2.4.19.tar.gz
  getlib $sd http://download.zeromq.org/zeromq-2.1.9.tar.gz \
    || getlib $sd http://download.zeromq.org/historic/zeromq-2.1.9.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/freeradius-client-1.1.6.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/lame-3.98.4.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/libshout-2.2.2.tar.gz
  getlib $sd http://files.freeswitch.org/downloads/libs/mpg123-1.13.2.tar.gz
  # get sounds and music
  for x in 8000 16000 32000 48000; do
    getsound $sd http://files.freeswitch.org/freeswitch-sounds-en-us-callie-$x-1.0.18.tar.gz
    getsound $sd http://files.freeswitch.org/freeswitch-sounds-music-$x-1.0.8.tar.gz
  done
  # cleanup mongo
  (
    cd $sd/libs/mongo-cxx-driver-v1.8
    rm -rf config.log .sconf_temp *Test *Example
    find . -name "*.o" -exec rm -f {} \;
  )
}

get_current_version () {
  cat $ddir/changelog \
    | grep -e '^freeswitch ' \
    | awk '{print $2}' \
    | sed -e 's/[()]//g' -e 's/-.*//'
}

_create_orig () {
  . $ddir/../scripts/ci/common.sh
  eval $(parse_version "$(get_current_version)")
  local destdir="$1" xz_level="$2" n=freeswitch
  local d=${n}-${dver} f=${n}_${dver}
  local sd=${ddir}/sdeb/$d
  [ -n "$destdir" ] || destdir=$ddir/../../
  mkdir -p $sd
  tar -c -C $ddir/../ \
    --exclude=.git \
    --exclude=debian \
    --exclude=freeswitch.xcodeproj \
    --exclude=fscomm \
    --exclude=htdocs \
    --exclude=w32 \
    --exclude=web \
    -vf - . | tar -x -C $sd -vf -
  (cd $sd && set_fs_ver "$gver" "$gmajor" "$gminor" "$gmicro" "$grev")
  getlibs $sd
  tar -c -C $ddir/sdeb -vf $ddir/sdeb/$f.orig.tar $d
  xz -${xz_level}v $ddir/sdeb/$f.orig.tar
  mv $ddir/sdeb/$f.orig.tar.xz $destdir
  rm -rf $ddir/sdeb
}

create_orig () {
  local xz_level="6"
  while getopts 'dz:' o; do
    case "$o" in
      d) set -vx;;
      z) xz_level="$OPTARG";;
    esac
  done
  shift $(($OPTIND-1))
  _create_orig "$1" "$xz_level"
}

create_dsc () {
  . $ddir/../scripts/ci/common.sh
  local xz_level="6"
  while getopts 'dz:' o; do
    case "$o" in
      d) set -vx;;
      z) xz_level="$OPTARG";;
    esac
  done
  shift $(($OPTIND-1))
  eval $(parse_version "$(get_current_version)")
  local destdir="$1" n=freeswitch
  local d=${n}-${dver} f=${n}_${dver}
  [ -n "$destdir" ] || destdir=$ddir/../../
  [ -f $destdir/$f.orig.tar.xz ] \
    || _create_orig "$1" "${xz_level}"
  (
    ddir=$(pwd)/$ddir
    cd $destdir
    mkdir -p $f
    cp -a $ddir $f
    dpkg-source -b -i.* -Zxz -z9 $f
  )
}

cmd="$1"
shift
case "$cmd" in
  create-dbg-pkgs) create_dbg_pkgs ;;
  create-dsc) create_dsc "$@" ;;
  create-orig) create_orig "$@" ;;
  list-build-depends) list_build_depends ;;
  install-build-depends) install_build_depends ;;
esac

