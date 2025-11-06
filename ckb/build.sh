#!/usr/bin/env bash
set -ex

CLANG="${CLANG:-clang-21}"
CLANG_VERSION=$($CLANG --version | head -n1 | sed -n 's/.*version \([0-9]\+\).*/\1/p')
BASE_CFLAGS="--target=riscv64-unknown-elf -DPAGE_SIZE=4096 -O3"
if [ -n "$CFI" ]; then
  if [ "$CFI" != "func-sig" ] && [ "$CFI" != "unlabeled" ]; then
    echo "Error: CFI must be either 'func-sig' or 'unlabeled'"
    exit 1
  fi
  if [ -z "$CLANG_VERSION" ] || [ "$CLANG_VERSION" -lt 21 ]; then
    echo "Error: CFI requires clang version >= 21, but got version $CLANG_VERSION"
    exit 1
  fi
  BASE_CFLAGS="${BASE_CFLAGS} -march=rv64imc_zba_zbb_zbc_zbs_zicfiss1p0_zicfilp1p0 -menable-experimental-extensions -fcf-protection=full -mcf-branch-label-scheme=${CFI}"
else
  BASE_CFLAGS="${BASE_CFLAGS} -march=rv64imc_zba_zbb_zbc_zbs"
fi

N_PROC="${N_PROC:-$(nproc)}"

mkdir -p release
CC="${CLANG}" CFLAGS="${BASE_CFLAGS}" \
  ./configure \
    --target=riscv64-linux-musl \
    --disable-shared \
    --with-malloc=oldmalloc \
    --prefix=`pwd`/release
make AR="${CLANG/clang/llvm-ar}" RANLIB="${CLANG/clang/llvm-ranlib}" -j ${N_PROC}
make AR="${CLANG/clang/llvm-ar}" RANLIB="${CLANG/clang/llvm-ranlib}" install
rm -rf release/bin

rm -rf release/lib/libgcc.a

CKB_FILES=("crt1" "hijack_syscall")
for f in ${CKB_FILES[@]}; do
  $CLANG $BASE_CFLAGS \
    -nostdinc \
    -I./arch/riscv64 -I./arch/generic -Iobj/src/internal -I./src/include -I./src/internal -Iobj/include -I./include \
    -Wall -Werror \
    -c ckb/$f.c -o release/$f.o

  "${CLANG/clang/llvm-ar}" rc release/lib/libgcc.a release/$f.o

  rm -rf release/$f.o
done

CKB_HEADERS=("musl_options")
rm -rf release/include/ckb
mkdir -p release/include/ckb
for f in ${CKB_HEADERS[@]}; do
  cp ckb/$f.h release/include/ckb/$f.h
done
