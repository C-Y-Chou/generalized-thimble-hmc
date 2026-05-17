#!/usr/bin/env bash
# Validate and export the Python embedding environment used by official DFO-LS.

tltm_configure_python_embed() {
  : "${TLTM_WORKTREE:=$(pwd)}"
  : "${TLTM_PYTHON_VERSION:=3.11}"
  : "${TLTM_PYTHON_DEVEL_ROOT:=${TLTM_WORKTREE}/.deps/python-devel-${TLTM_PYTHON_VERSION}}"

  local py_include="${TLTM_PYTHON_DEVEL_ROOT}/usr/include/python${TLTM_PYTHON_VERSION}"
  local py_libdir="${TLTM_PYTHON_DEVEL_ROOT}/usr/lib64"
  local py_lib="${py_libdir}/libpython${TLTM_PYTHON_VERSION}.so"
  local py_cflags="-I${py_include}"

  if [ ! -f "${py_include}/Python.h" ]; then
    echo "[ERROR] missing Python.h for embedded official DFO-LS: ${py_include}/Python.h" >&2
    echo "[ERROR] set TLTM_PYTHON_DEVEL_ROOT to a complete python-devel bundle." >&2
    return 66
  fi

  if [ -f "${py_include}/pyconfig.h" ] && grep -q 'pyconfig-' "${py_include}/pyconfig.h"; then
    if ! ls "${py_include}"/pyconfig-*.h >/dev/null 2>&1; then
      local fallback_include
      local fragment_found=0
      for fallback_include in \
        "/usr/include/python${TLTM_PYTHON_VERSION}" \
        "/usr/local/include/python${TLTM_PYTHON_VERSION}"
      do
        if ls "${fallback_include}"/pyconfig-*.h >/dev/null 2>&1; then
          py_cflags="${py_cflags} -I${fallback_include}"
          fragment_found=1
          break
        fi
      done
      if [ "${fragment_found}" != "1" ]; then
        echo "[ERROR] ${py_include}/pyconfig.h requires a pyconfig-* platform fragment." >&2
        echo "[ERROR] add pyconfig-*.h to TLTM_PYTHON_DEVEL_ROOT or set PYTHON_EMBED_CFLAGS explicitly." >&2
        return 66
      fi
    fi
  fi

  if [ ! -e "${py_lib}" ]; then
    if [ -e "${py_lib}.1.0" ]; then
      py_lib="${py_lib}.1.0"
    elif [ -e "/usr/lib64/libpython${TLTM_PYTHON_VERSION}.so.1.0" ]; then
      py_lib="/usr/lib64/libpython${TLTM_PYTHON_VERSION}.so.1.0"
    else
      echo "[ERROR] missing libpython for embedded official DFO-LS: ${py_lib}" >&2
      echo "[ERROR] provide libpython${TLTM_PYTHON_VERSION}.so or libpython${TLTM_PYTHON_VERSION}.so.1.0." >&2
      return 66
    fi
  fi

  : "${PYTHON:=python${TLTM_PYTHON_VERSION}}"
  : "${PYTHON_EMBED_CFLAGS:=${py_cflags}}"
  : "${PYTHON_EMBED_LDFLAGS:=${py_lib} -lpthread -ldl -lutil -lm}"

  export PYTHON PYTHON_EMBED_CFLAGS PYTHON_EMBED_LDFLAGS
  export TLTM_PYTHON_DEVEL_ROOT
  export LD_LIBRARY_PATH="${py_libdir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
}

tltm_configure_python_embed
