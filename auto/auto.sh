#!/bin/bash
set -euo pipefail

#luu y file config.txt o cung cap thu muc voi file.sh
CRED_FILE="config.txt"

# check file config.txt
if [ ! -r "$CRED_FILE" ]; then
  echo "Khong tim thay hoac khong the doc duoc file: $CRED_FILE" >&2
  exit 1
fi

#doc file, loai bo comment va dong trong thua
lines=()
while IFS= read -r rawline; do
  #Lam sach khoang trang 2 dau
  line="$(printf '%s' "$rawline" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  #Loai bo dong trong va comment
  if [ -z "$line" ] || [[ "$line" == \#* ]]; then
    continue
  fi
  lines+=("$line")
done < "$CRED_FILE"

HOST_USER="${lines[0]:-}"
HOST_PASS="${lines[1]:-}"
RASPI_USER="${lines[2]:-}"
RASPI_PASS="${lines[3]:-}"
RASPI_IP="${lines[4]:-}"

#Dinh nghia ten cac folder neu muon thay doi
#trong file nay dong 187, trong file cau hinh toolchain.cmake, co hardcode duong link, neu thay doi xin hay thay doi ca ben trong toolchain.cmake
FOLDER_WORK="Qt6Cross" #Folder cha, chua tat ca cac file ben trong


printf '%s\n' "$HOST_PASS" | sudo -S -p '' apt update 
printf '%s\n' "$HOST_PASS" | sudo -S -p '' apt full-upgrade -y
printf '%s\n' "$HOST_PASS" | sudo -S -p '' apt install -y $(cat dep_list_host.txt)

#=============================================SCRIPT SETUP BEN RASPI=============================================
sshpass -p "$RASPI_PASS" ssh -o StrictHostKeyChecking=no "${RASPI_USER}@${RASPI_IP}" \
    "printf '%s\n' '$RASPI_PASS' | sudo -S -p '' apt update && printf '%s\n' '$RASPI_PASS' | sudo -S -p '' apt full-upgrade -y" 
    
PKGS="$(tr '\n' ' ' < dep_list_raspi.txt)"
sshpass -p "$RASPI_PASS" ssh -t -o StrictHostKeyChecking=no "${RASPI_USER}@${RASPI_IP}" \
  "printf '%s\n' \"$RASPI_PASS\" | sudo -S -p '' apt install -y $PKGS"
  
sshpass -p "$RASPI_PASS" ssh -o StrictHostKeyChecking=no "${RASPI_USER}@${RASPI_IP}" \
  "printf '%s\n' '$RASPI_PASS' | sudo -S mkdir -p /usr/local/qt6 && \
  printf '%s\n' '$RASPI_PASS' | sudo -S chmod 777 /usr/local/bin"

  
sshpass -p "$RASPI_PASS" ssh -o StrictHostKeyChecking=no "${RASPI_USER}@${RASPI_IP}" \
  "echo 'export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/usr/local/qt6/lib/' >> ~/.bashrc && source ~/.bashrc"

#================================================================================================================




#=============================================SCRIPT SETUP BEN HOST==============================================

# kiem tra nguoi chay script hien tai co cung sudo user trong config.txt khong
CUR_USER="$(id -un)"
if [ "$CUR_USER" != "$HOST_USER" ]; then
  echo "Script chi nen chay voi user duoc khai bao trong config.txt, nhung hien tai user dang chay script la '$CUR_USER'" >&2
  exit 1
fi

#tao folder lam viec rieng (folder chua tat ca)
cd ~
mkdir $FOLDER_WORK && cd $FOLDER_WORK

#tai va bien dich ma nguon cua cmake moi nhat
git clone https://github.com/Kitware/CMake.git
#cd CMake && ./bootstrap && make -j4 && \
#printf '%s\n' "$HOST_PASS" | sudo -S -p '' make install


#tai gcc lam cross compiler 
cd ~/$FOLDER_WORK
mkdir gcc_all && cd gcc_all
wget https://ftpmirror.gnu.org/binutils/binutils-2.35.2.tar.bz2
wget https://ftpmirror.gnu.org/glibc/glibc-2.31.tar.bz2
wget https://ftpmirror.gnu.org/gcc/gcc-10.3.0/gcc-10.3.0.tar.gz
git clone --depth=1 https://github.com/raspberrypi/linux
tar xf binutils-2.35.2.tar.bz2
tar xf glibc-2.31.tar.bz2
tar xf gcc-10.3.0.tar.gz
rm *.tar.*
cd gcc-10.3.0
contrib/download_prerequisites

#folder chua binaries cross compiler
printf '%s\n' "$HOST_PASS" | sudo -S -p '' mkdir -p /opt/cross-pi-gcc
printf '%s\n' "$HOST_PASS" | sudo -S -p '' chown $USER /opt/cross-pi-gcc
export PATH=/opt/cross-pi-gcc/bin:$PATH

#Cai dat kernel header cua raspi
cd ~/$FOLDER_WORK/gcc_all
cd linux
KERNEL=kernel7
make ARCH=arm64 INSTALL_HDR_PATH=/opt/cross-pi-gcc/aarch64-linux-gnu headers_install

#build và cài đặt binutils cho cross-compiler
cd ~/$FOLDER_WORK/gcc_all
mkdir build-binutils && cd build-binutils
../binutils-2.35.2/configure --prefix=/opt/cross-pi-gcc --target=aarch64-linux-gnu --with-arch=armv8 --disable-multilib
make -j 8
make install

sed -i '1i#ifndef PATH_MAX\n#define PATH_MAX 4096\n#endif' ~/$FOLDER_WORK/gcc_all/gcc-10.3.0/libsanitizer/asan/asan_linux.cpp


#build GCC cross-compiler chính
cd ~/$FOLDER_WORK/gcc_all
mkdir build-gcc && cd build-gcc
../gcc-10.3.0/configure --prefix=/opt/cross-pi-gcc --target=aarch64-linux-gnu --enable-languages=c,c++ --disable-multilib
make -j8 all-gcc
make install-gcc

#build và cài đặt glibc cho cross-compiler
cd ~/$FOLDER_WORK/gcc_all
mkdir build-glibc && cd build-glibc
../glibc-2.31/configure --prefix=/opt/cross-pi-gcc/aarch64-linux-gnu --build=$MACHTYPE --host=aarch64-linux-gnu --target=aarch64-linux-gnu --with-headers=/opt/cross-pi-gcc/aarch64-linux-gnu/include --disable-multilib libc_cv_forced_unwind=yes
make install-bootstrap-headers=yes install-headers
make -j8 csu/subdir_lib
install csu/crt1.o csu/crti.o csu/crtn.o /opt/cross-pi-gcc/aarch64-linux-gnu/lib
aarch64-linux-gnu-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o /opt/cross-pi-gcc/aarch64-linux-gnu/lib/libc.so
touch /opt/cross-pi-gcc/aarch64-linux-gnu/include/gnu/stubs.h

#build thư viện runtime libgcc cho cross-compiler
cd ~/$FOLDER_WORK/gcc_all/build-gcc
make -j8 all-target-libgcc
make install-target-libgcc

#build glibc đầy đủ cho cross-compiler.
cd ~/$FOLDER_WORK/gcc_all/build-glibc
make -j8
make install

#build và cài đặt GCC hoàn chỉnh sau khi đã chuẩn bị glibc và libgcc
cd ~/$FOLDER_WORK/gcc_all/build-gcc
make -j8
make install
#====================================================================================================================



#=============================================SCRIPT BUILD=======================================================

#buld Qt6 cho host
cd ~/$FOLDER_WORK
mkdir qt6 qt6/host qt6/pi qt6/host-build qt6/pi-build qt6/src

cd ~/$FOLDER_WORK/qt6/src
wget https://download.qt.io/official_releases/qt/6.5/6.5.1/submodules/qtbase-everywhere-src-6.5.1.tar.xz
tar xf qtbase-everywhere-src-6.5.1.tar.xz

cd $HOME/$FOLDER_WORK/qt6/host-build/
cmake ../src/qtbase-everywhere-src-6.5.1/ -GNinja -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX=$HOME/$FOLDER_WORK/qt6/host
cmake --build . --parallel 8
cmake --install .



#Tao folder chua sysroot cua raspi
cd ~/$FOLDER_WORK
mkdir rpi-sysroot rpi-sysroot/usr 


#Copy sysroot cua pi sang may host
cd ~/$FOLDER_WORK
sshpass -p "$RASPI_PASS" rsync -avz --rsync-path="sudo rsync" ${RASPI_USER}@${RASPI_IP}:/usr/include rpi-sysroot/usr
sshpass -p "$RASPI_PASS" rsync -avz --rsync-path="sudo rsync" ${RASPI_USER}@${RASPI_IP}:/lib rpi-sysroot
sshpass -p "$RASPI_PASS" rsync -avz --rsync-path="sudo rsync" ${RASPI_USER}@${RASPI_IP}:/usr/lib rpi-sysroot/usr

#Sua chua symbol link, tranh bi loi link lien ket khi copy sysroot tu pi sang host
wget https://raw.githubusercontent.com/riscv/riscv-poky/master/scripts/sysroot-relativelinks.py
chmod +x sysroot-relativelinks.py
python3 sysroot-relativelinks.py rpi-sysroot

#Tao folder chua bien dich cheo cua qt
cd $HOME/$FOLDER_WORK/qt6/pi-build



cat << 'EOF' > toolchain.cmake
cmake_minimum_required(VERSION 3.18)
include_guard(GLOBAL)

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

# You should change location of sysroot to your needs.
set(TARGET_SYSROOT $ENV{HOME}/Qt6Cross/rpi-sysroot)
set(TARGET_ARCHITECTURE aarch64-linux-gnu)
set(CMAKE_SYSROOT ${TARGET_SYSROOT})

set(ENV{PKG_CONFIG_PATH} $PKG_CONFIG_PATH:${CMAKE_SYSROOT}/usr/lib/${TARGET_ARCHITECTURE}/pkgconfig)
set(ENV{PKG_CONFIG_LIBDIR} /usr/lib/pkgconfig:/usr/share/pkgconfig/:${TARGET_SYSROOT}/usr/lib/${TARGET_ARCHITECTURE}/pkgconfig:${TARGET_SYSROOT}/usr/lib/pkgconfig)
set(ENV{PKG_CONFIG_SYSROOT_DIR} ${CMAKE_SYSROOT})

set(CMAKE_C_COMPILER /opt/cross-pi-gcc/bin/${TARGET_ARCHITECTURE}-gcc)
set(CMAKE_CXX_COMPILER /opt/cross-pi-gcc/bin/${TARGET_ARCHITECTURE}-g++)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -isystem=/usr/include -isystem=/usr/local/include -isystem=/usr/include/${TARGET_ARCHITECTURE}")
set(CMAKE_CXX_FLAGS "${CMAKE_C_FLAGS}")

set(QT_COMPILER_FLAGS "-march=armv8-a")
set(QT_COMPILER_FLAGS_RELEASE "-O2 -pipe")
set(QT_LINKER_FLAGS "-Wl,-O1 -Wl,--hash-style=gnu -Wl,--as-needed -Wl,-rpath-link=${TARGET_SYSROOT}/usr/lib/${TARGET_ARCHITECTURE} -Wl,-rpath-link=$HOME/qt6/pi/lib")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(CMAKE_BUILD_RPATH ${TARGET_SYSROOT})

include(CMakeInitializeConfigs)

function(cmake_initialize_per_config_variable _PREFIX _DOCSTRING)
  if (_PREFIX MATCHES "CMAKE_(C|CXX|ASM)_FLAGS")
    set(CMAKE_${CMAKE_MATCH_1}_FLAGS_INIT "${QT_COMPILER_FLAGS}")
        
    foreach (config DEBUG RELEASE MINSIZEREL RELWITHDEBINFO)
      if (DEFINED QT_COMPILER_FLAGS_${config})
        set(CMAKE_${CMAKE_MATCH_1}_FLAGS_${config}_INIT "${QT_COMPILER_FLAGS_${config}}")
      endif()
    endforeach()
  endif()


  if (_PREFIX MATCHES "CMAKE_(SHARED|MODULE|EXE)_LINKER_FLAGS")
    foreach (config SHARED MODULE EXE)
      set(CMAKE_${config}_LINKER_FLAGS_INIT "${QT_LINKER_FLAGS}")
    endforeach()
  endif()

  _cmake_initialize_per_config_variable(${ARGV})
endfunction()

set(XCB_PATH_VARIABLE ${TARGET_SYSROOT})

set(GL_INC_DIR ${TARGET_SYSROOT}/usr/include)
set(GL_LIB_DIR ${TARGET_SYSROOT}:${TARGET_SYSROOT}/usr/lib/${TARGET_ARCHITECTURE}/:${TARGET_SYSROOT}/usr:${TARGET_SYSROOT}/usr/lib)

set(EGL_INCLUDE_DIR ${GL_INC_DIR})
set(EGL_LIBRARY ${XCB_PATH_VARIABLE}/usr/lib/${TARGET_ARCHITECTURE}/libEGL.so)

set(OPENGL_INCLUDE_DIR ${GL_INC_DIR})
set(OPENGL_opengl_LIBRARY ${XCB_PATH_VARIABLE}/usr/lib/${TARGET_ARCHITECTURE}/libOpenGL.so)

set(GLESv2_INCLUDE_DIR ${GL_INC_DIR})
set(GLIB_LIBRARY ${XCB_PATH_VARIABLE}/usr/lib/${TARGET_ARCHITECTURE}/libGLESv2.so)

set(GLESv2_INCLUDE_DIR ${GL_INC_DIR})
set(GLESv2_LIBRARY ${XCB_PATH_VARIABLE}/usr/lib/${TARGET_ARCHITECTURE}/libGLESv2.so)

set(gbm_INCLUDE_DIR ${GL_INC_DIR})
set(gbm_LIBRARY ${XCB_PATH_VARIABLE}/usr/lib/${TARGET_ARCHITECTURE}/libgbm.so)

set(Libdrm_INCLUDE_DIR ${GL_INC_DIR})
set(Libdrm_LIBRARY ${XCB_PATH_VARIABLE}/usr/lib/${TARGET_ARCHITECTURE}/libdrm.so)

set(XCB_XCB_INCLUDE_DIR ${GL_INC_DIR})
set(XCB_XCB_LIBRARY ${XCB_PATH_VARIABLE}/usr/lib/${TARGET_ARCHITECTURE}/libxcb.so)

list(APPEND CMAKE_LIBRARY_PATH ${CMAKE_SYSROOT}/usr/lib/${TARGET_ARCHITECTURE})
list(APPEND CMAKE_PREFIX_PATH "/usr/lib/${TARGET_ARCHITECTURE}/cmake")
EOF


cd $HOME/$FOLDER_WORK/qt6/pi-build

cmake ../src/qtbase-everywhere-src-6.5.1/ -GNinja -DCMAKE_BUILD_TYPE=Release -DINPUT_opengl=es2 -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DQT_HOST_PATH=$HOME/$FOLDER_WORK/qt6/host -DCMAKE_STAGING_PREFIX=$HOME/$FOLDER_WORK/qt6/pi -DCMAKE_INSTALL_PREFIX=/usr/local/qt6 -DCMAKE_TOOLCHAIN_FILE=$HOME/$FOLDER_WORK/qt6/pi-build/toolchain.cmake -DQT_QMAKE_TARGET_MKSPEC=devices/linux-rasp-pi4-aarch64 -DQT_FEATURE_xcb=ON -DFEATURE_xcb_xlib=ON -DQT_FEATURE_xlib=ON

cmake --build . --parallel 8

cmake --install .

sshpass -p "$RASPI_PASS" rsync -avz --rsync-path="sudo rsync" "$HOME/$FOLDER_WORK/qt6/pi/*" ${RASPI_USER}@${RASPI_IP}:/usr/local/qt6
#================================================================================================================

