#!/bin/bash

if [ -z "$LIBSSH2" ]
then
  LIBSSH2=1.11.1
fi

if [ -z "$IOS" ]
then
  IOS=`xcrun -sdk iphoneos --show-sdk-version`
fi

if [ -z "$MIN_IOS_VERSION" ]
then
  MIN_IOS_VERSION=13.0
fi

if [ -z "$MIN_CATALYST_VERSION" ]
then
  MIN_CATALYST_VERSION=13.1
fi

if [ -z "$MACOSX" ]
then
  MACOSX=`xcrun --sdk macosx --show-sdk-version|cut -d '.' -f 1-2`
fi

IFS=':' read -r -a build_targets <<< "$BUILD_TARGETS"
IFS=':' read -r -a link_targets <<< "$LINK_TARGETS"

declare -a all_targets=("ios-arm64" "ios-arm64e" "simulator_x86_64" "simulator_x86_64h" "simulator_arm64e" "simulator_arm64" "catalyst_x86_64" "catalyst_arm64" "macos_x86_64" "macos_x86_64h" "macos_arm64")
declare -a old_targets=("simulator_x86_64" "catalyst_x86_64" "macos_x86_64" "ios-arm64e")
declare -a appleSiliconTargets=("simulator_arm64" "simulator_x86_64" "catalyst_x86_64" "catalyst_arm64" "macos_arm64" "macos_x86_64" "ios-arm64e")


if [ -z "$build_targets" ]
then
  declare -a build_targets=("macos_x86_64" "macos_arm64" "catalyst_x86_64" "catalyst_arm64" "simulator_arm64" "ios-arm64")
fi

if [ -z "$link_targets" ]
then
  declare -a link_targets=("macos_x86_64" "macos_arm64" "catalyst_x86_64" "catalyst_arm64" "simulator_arm64" "ios-arm64")
fi

XCODE=`/usr/bin/xcode-select -p`

# Build LibreSSL from the requested branch. Consumer pull requests use master;
# LIBRESSL_REF can point at an update branch while validating it.
if [ -z "$LIBRESSL_OUTPUT_DIR" ]
then
  LIBRESSL_REF=${LIBRESSL_REF:-master}
  git clone --depth 1 --branch "$LIBRESSL_REF" https://github.com/build-xcframeworks/libressl.git libressl-source
  (
    cd libressl-source
    bash libressl.sh
  )
  LIBRESSL_OUTPUT_DIR=$(pwd)/libressl-source/output
fi

echo "Let's output all variables for the sake of the CI"
echo "---"
( set -o posix ; set )
echo "---"

set -e

if [ -e "libressl" ]
then
  rm -R libressl
fi

mkdir -p libressl/ios/lib
cp -R "$LIBRESSL_OUTPUT_DIR/libssl.xcframework/ios-arm64/Headers" libressl/ios/include
cp -R "$LIBRESSL_OUTPUT_DIR/libssl.xcframework/ios-arm64/libssl.a" libressl/ios/lib
cp -R "$LIBRESSL_OUTPUT_DIR/libcrypto.xcframework/ios-arm64/libcrypto.a" libressl/ios/lib

mkdir -p libressl/simulator/lib
cp -R "$LIBRESSL_OUTPUT_DIR/libssl.xcframework/ios-arm64-simulator/Headers" libressl/simulator/include
cp -R "$LIBRESSL_OUTPUT_DIR/libssl.xcframework/ios-arm64-simulator/libssl.a" libressl/simulator/lib
cp -R "$LIBRESSL_OUTPUT_DIR/libcrypto.xcframework/ios-arm64-simulator/libcrypto.a" libressl/simulator/lib

mkdir -p libressl/macos/lib
cp -R "$LIBRESSL_OUTPUT_DIR/libssl.xcframework/macos-arm64_x86_64/Headers" libressl/macos/include
cp -R "$LIBRESSL_OUTPUT_DIR/libssl.xcframework/macos-arm64_x86_64/libssl.a" libressl/macos/lib
cp -R "$LIBRESSL_OUTPUT_DIR/libcrypto.xcframework/macos-arm64_x86_64/libcrypto.a" libressl/macos/lib

mkdir -p libressl/catalyst/lib
cp -R "$LIBRESSL_OUTPUT_DIR/libssl.xcframework/ios-arm64_x86_64-maccatalyst/Headers" libressl/catalyst/include
cp -R "$LIBRESSL_OUTPUT_DIR/libssl.xcframework/ios-arm64_x86_64-maccatalyst/libssl.a" libressl/catalyst/lib
cp -R "$LIBRESSL_OUTPUT_DIR/libcrypto.xcframework/ios-arm64_x86_64-maccatalyst/libcrypto.a" libressl/catalyst/lib


PREFIX=$(pwd)/build
OUTPUT=$(pwd)/Fat
XCFRAMEWORKS=$(pwd)/output
ROOT=$(pwd)

mkdir -p $PREFIX
mkdir -p $OUTPUT
mkdir -p $XCFRAMEWORKS

for target in "${build_targets[@]}"
do
  mkdir -p $PREFIX/$target;
  mkdir -p $OUTPUT/$target/lib;
  mkdir -p $OUTPUT/$target/include;
done

# some bash'isms
. resolve_path.inc # https://github.com/keen99/shell-functions/tree/master/resolve_path

elementIn () { # source https://stackoverflow.com/questions/3685970/check-if-a-bash-array-contains-a-value
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

moveOutputInPlace() {
  local target=$1
  local output=$2
  cp crypto/.libs/libcrypto.a $output/$target/lib
  cp ssl/.libs/libssl.a $output/$target/lib
  # cp include .... $OUTPUT/$target/include # which one is this?
}

resetLibSSH() {
  cd $ROOT
  if [ ! -e "libssh2-$LIBSSH2.tar.gz" ]
  then
    curl -OL "https://www.libssh2.org/download/libssh2-${LIBSSH2}.tar.gz"
  fi
  if [ -e "libssh2-$LIBSSH2" ]
  then
    rm -R libssh2-${LIBSSH2}
  fi

  tar xvfz libssh2-${LIBSSH2}.tar.gz

  cd libssh2-${LIBSSH2}
}

#####################################
##  iOS simulator x86_64 Compilation
#####################################

target=simulator_x86_64
if elementIn "$target" "${build_targets[@]}"; then
  
  resetLibSSH  
  printf "\n\n--> iOS simulator x86_64 Compilation: $target"

  DEVROOT=$XCODE/Platforms/iPhoneSimulator.platform/Developer
  SDKROOT=$DEVROOT/SDKs/iPhoneSimulator${IOS}.sdk
  LIBRESSLROOT_RELATIVE=`pwd`/../libressl/simulator
  LIBRESSLROOT=$(resolve_path ${LIBRESSLROOT_RELATIVE})

  ./configure \
	--with-crypto=openssl \
	--with-libssl-prefix=${LIBRESSLROOT} \
	--host=x86_64-apple-darwin \
	--prefix="$PREFIX/$target" \
	--disable-debug \
	--disable-dependency-tracking \
	--disable-silent-rules \
	--disable-examples-build \
	--with-libz \
	--disable-shared \
	--enable-static \
    CC="/usr/bin/clang -target x86_64-apple-ios${MIN_IOS_VERSION}-simulator" \
    CPPFLAGS="-I$SDKROOT/usr/include/ -I${LIBRESSLROOT}/include" \
    CFLAGS="$CPPFLAGS -arch x86_64 -miphoneos-version-min=${MIN_IOS_VERSION} -pipe -no-cpp-precomp -isysroot $SDKROOT" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="$DEVROOT/usr/bin/ld -L${LIBRESSLROOT}"

  make clean
  make -j 4 install \
    CC="/usr/bin/clang -target x86_64-apple-ios${MIN_IOS_VERSION}-simulator" \
    CPPFLAGS="-I$SDKROOT/usr/include/ -I${LIBRESSLROOT}/include" \
    CFLAGS="$CPPFLAGS -arch x86_64 -miphoneos-version-min=${MIN_IOS_VERSION} -pipe -no-cpp-precomp -isysroot $SDKROOT" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="$DEVROOT/usr/bin/ld -L${LIBRESSLROOT}"
	  
  printf "\n\n--> XX iOS simulator x86_64 Compilation"
  mv $PREFIX/$target/include/*.h $OUTPUT/$target/include
  mv $PREFIX/$target/lib/libssh2.a $OUTPUT/$target/lib

fi;

####################################
##  iOS simulator arm64 Compilation
####################################

target=simulator_arm64
if elementIn "$target" "${build_targets[@]}"; then
  
  resetLibSSH  
  printf "\n\n--> iOS simulator arm64 Compilation: $target"

  DEVROOT=$XCODE/Platforms/iPhoneSimulator.platform/Developer
  SDKROOT=$DEVROOT/SDKs/iPhoneSimulator${IOS}.sdk
  LIBRESSLROOT_RELATIVE=`pwd`/../libressl/simulator
  LIBRESSLROOT=$(resolve_path ${LIBRESSLROOT_RELATIVE})

  ./configure --build=aarch64-apple-darwin --host=aarch64-apple-darwin22 --with-crypto=openssl --with-libssl-prefix=${LIBRESSLROOT} --prefix="$PREFIX/$target" --disable-debug --disable-dependency-tracking --disable-silent-rules --disable-examples-build --with-libz --disable-shared --enable-static \
    CC="/usr/bin/clang -target arm64-apple-ios${MIN_IOS_VERSION}-simulator" \
    CPPFLAGS="-I$SDKROOT/usr/include/ -I${LIBRESSLROOT}/include" \
    CFLAGS="$CPPFLAGS -arch arm64 -miphoneos-version-min=${MIN_IOS_VERSION} -pipe -no-cpp-precomp -isysroot $SDKROOT" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="$DEVROOT/usr/bin/ld -L${LIBRESSLROOT}"
  
  make clean
  make -j 4 install \
    CC="/usr/bin/clang -target arm64-apple-ios${MIN_IOS_VERSION}-simulator" \
    CPPFLAGS="-I$SDKROOT/usr/include/ -I${LIBRESSLROOT}/include" \
    CFLAGS="$CPPFLAGS -arch arm64 -miphoneos-version-min=${MIN_IOS_VERSION} -pipe -no-cpp-precomp -isysroot $SDKROOT" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="$DEVROOT/usr/bin/ld -L${LIBRESSLROOT}"
	  
  printf "\n\n--> XX iOS simulator arm64 Compilation"
  mv $PREFIX/$target/include/*.h $OUTPUT/$target/include
  mv $PREFIX/$target/lib/libssh2.a $OUTPUT/$target/lib

fi;


#############################
##  macOS x86_64 Compilation
#############################

target=macos_x86_64
if elementIn "$target" "${build_targets[@]}"; then
  
  resetLibSSH  
  printf "\n\n--> macOS x86_64 Compilation: $target"

  DEVROOT=$XCODE/Platforms/MacOSX.platform/Developer
  SDKROOT=$DEVROOT/SDKs/MacOSX${MACOSX}.sdk
  LIBRESSLROOT_RELATIVE=`pwd`/../libressl/macos
  LIBRESSLROOT=$(resolve_path ${LIBRESSLROOT_RELATIVE})

  ./configure --with-crypto=openssl --with-libssl-prefix=${LIBRESSLROOT} --host=x86_64-apple-darwin --prefix="$PREFIX/$target" --disable-debug --disable-dependency-tracking --disable-silent-rules --disable-examples-build --with-libz --disable-shared --enable-static \
    CC="/usr/bin/clang -isysroot $SDKROOT" \
    CPPFLAGS="-fembed-bitcode -I${LIBRESSLROOT}/include -I$SDKROOT/usr/include/" \
    CFLAGS="$CPPFLAGS -arch x86_64 -pipe -no-cpp-precomp" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="/usr/bin/ld -L${LIBRESSLROOT}"
  
  make clean
  make -j 4 install \
    CC="/usr/bin/clang -isysroot $SDKROOT" \
    CPPFLAGS="-fembed-bitcode -I${LIBRESSLROOT}/include -I$SDKROOT/usr/include/" \
    CFLAGS="$CPPFLAGS -arch x86_64 -pipe -no-cpp-precomp" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="/usr/bin/ld -L${LIBRESSLROOT}"
	  
  printf "\n\n--> XX macOS x86_64 Compilation"
  mv $PREFIX/$target/include/*.h $OUTPUT/$target/include
  mv $PREFIX/$target/lib/libssh2.a $OUTPUT/$target/lib

fi;

############################
##  macOS arm64 Compilation
############################

target=macos_arm64
if elementIn "$target" "${build_targets[@]}"; then
  
  resetLibSSH  
  printf "\n\n--> macOS arm64 Compilation: $target"

  DEVROOT=$XCODE/Platforms/MacOSX.platform/Developer
  SDKROOT=$DEVROOT/SDKs/MacOSX${MACOSX}.sdk
  LIBRESSLROOT_RELATIVE=`pwd`/../libressl/macos
  LIBRESSLROOT=$(resolve_path ${LIBRESSLROOT_RELATIVE})

  ./configure \
	--build=aarch64-apple-darwin \
	--with-crypto=openssl \
	--with-libssl-prefix=${LIBRESSLROOT} \
	--host=arm-apple-darwin \
	--prefix="$PREFIX/$target" \
	--disable-debug \
	--disable-dependency-tracking \
	--disable-silent-rules \
	--disable-examples-build \
	--with-libz \
	--disable-shared \
	--enable-static \
    CC="/usr/bin/clang -isysroot $SDKROOT" \
    CPPFLAGS="-fembed-bitcode -I${LIBRESSLROOT}/include -I$SDKROOT/usr/include/" \
    CFLAGS="$CPPFLAGS -arch arm64 -pipe -no-cpp-precomp" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="/usr/bin/ld -L${LIBRESSLROOT}"
  
  make clean
  make -j 4 install \
    CC="/usr/bin/clang -isysroot $SDKROOT" \
    CPPFLAGS="-fembed-bitcode -I${LIBRESSLROOT}/include -I$SDKROOT/usr/include/" \
    CFLAGS="$CPPFLAGS -arch arm64 -pipe -no-cpp-precomp" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="/usr/bin/ld -L${LIBRESSLROOT}"
	  
  printf "\n\n--> XX macOS arm64 Compilation"
  mv $PREFIX/$target/include/*.h $OUTPUT/$target/include
  mv $PREFIX/$target/lib/libssh2.a $OUTPUT/$target/lib

fi;

#######################################
##  macOS Catalyst x86_64 Compilation
#######################################

target=catalyst_x86_64
if elementIn "$target" "${build_targets[@]}"; then
  
  resetLibSSH  
  printf "\n\n--> macOS Catalyst x86_64 Compilation: $target"

  DEVROOT=$XCODE/Platforms/MacOSX.platform/Developer
  SDKROOT=$DEVROOT/SDKs/MacOSX${MACOSX}.sdk
  LIBRESSLROOT_RELATIVE=`pwd`/../libressl/catalyst
  LIBRESSLROOT=$(resolve_path ${LIBRESSLROOT_RELATIVE})

  ./configure --with-crypto=openssl --with-libssl-prefix=${LIBRESSLROOT} --host=x86_64-apple-darwin --prefix="$PREFIX/$target" --disable-debug --disable-dependency-tracking --disable-silent-rules --disable-examples-build --with-libz --disable-shared --enable-static \
    CC="/usr/bin/clang -target x86_64-apple-ios${MIN_CATALYST_VERSION}-macabi -isysroot $SDKROOT" \
    CPPFLAGS="-fembed-bitcode -I${LIBRESSLROOT}/include -I$SDKROOT/usr/include/" \
    CFLAGS="$CPPFLAGS -arch x86_64 -pipe -no-cpp-precomp" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="/usr/bin/ld -L${LIBRESSLROOT}"

  make clean
  make -j 4 install \
    CC="/usr/bin/clang -target x86_64-apple-ios${MIN_CATALYST_VERSION}-macabi -isysroot $SDKROOT" \
    CPPFLAGS="-fembed-bitcode -I${LIBRESSLROOT}/include -I$SDKROOT/usr/include/" \
    CFLAGS="$CPPFLAGS -arch x86_64 -pipe -no-cpp-precomp" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="/usr/bin/ld -L${LIBRESSLROOT}"
	  
  printf "\n\n--> XX macOS Catalyst x86_64 Compilation"
  mv $PREFIX/$target/include/*.h $OUTPUT/$target/include
  mv $PREFIX/$target/lib/libssh2.a $OUTPUT/$target/lib

fi;

#####################################
##  macOS Catalyst arm64 Compilation
#####################################

target=catalyst_arm64
if elementIn "$target" "${build_targets[@]}"; then
  
  resetLibSSH  
  printf "\n\n--> macOS Catalyst arm64 Compilation: $target"

  DEVROOT=$XCODE/Platforms/MacOSX.platform/Developer
  SDKROOT=$DEVROOT/SDKs/MacOSX${MACOSX}.sdk
  LIBRESSLROOT_RELATIVE=`pwd`/../libressl/catalyst
  LIBRESSLROOT=$(resolve_path ${LIBRESSLROOT_RELATIVE})

  ./configure --build=aarch64-apple-darwin --host=aarch64-apple-darwin22 --with-crypto=openssl --with-libssl-prefix=${LIBRESSLROOT} --prefix="$PREFIX/$target" --disable-debug --disable-dependency-tracking --disable-silent-rules --disable-examples-build --with-libz --disable-shared --enable-static \
    CC="/usr/bin/clang -target arm64-apple-ios${MIN_CATALYST_VERSION}-macabi -isysroot $SDKROOT" \
    CPPFLAGS="-fembed-bitcode -I${LIBRESSLROOT}/include -I$SDKROOT/usr/include/" \
    CFLAGS="$CPPFLAGS -arch arm64 -pipe -no-cpp-precomp" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="/usr/bin/ld -L${LIBRESSLROOT}"

  make clean
  make -j 4 install \
    CC="/usr/bin/clang -target arm64-apple-ios${MIN_CATALYST_VERSION}-macabi -isysroot $SDKROOT" \
    CPPFLAGS="-fembed-bitcode -I${LIBRESSLROOT}/include -I$SDKROOT/usr/include/" \
    CFLAGS="$CPPFLAGS -arch arm64 -pipe -no-cpp-precomp" \
    CPP="/usr/bin/cpp $CPPFLAGS" \
    LD="/usr/bin/ld -L${LIBRESSLROOT}"
	  
  printf "\n\n--> XX macOS Catalyst arm64 Compilation"
  mv $PREFIX/$target/include/*.h $OUTPUT/$target/include
  mv $PREFIX/$target/lib/libssh2.a $OUTPUT/$target/lib

fi;

##########################
##  iOS arm64 Compilation
##########################

target=ios-arm64
if elementIn "$target" "${build_targets[@]}"; then

  resetLibSSH  
  printf "\n\n--> iOS arm64 Compilation: $target"

  DEVROOT=$XCODE/Platforms/iPhoneOS.platform/Developer
  SDKROOT=$DEVROOT/SDKs/iPhoneOS${IOS}.sdk
  LIBRESSLROOT_RELATIVE=`pwd`/../libressl/ios
  LIBRESSLROOT=$(resolve_path ${LIBRESSLROOT_RELATIVE})

  ./configure --with-crypto=openssl --with-libssl-prefix=${LIBRESSLROOT} --host=aarch64-apple-darwin --prefix="$PREFIX/$target" --disable-debug --disable-dependency-tracking --disable-silent-rules --disable-examples-build --with-libz --disable-shared --enable-static \
    CC="/usr/bin/clang -isysroot $SDKROOT" \
    CPPFLAGS="-fembed-bitcode -I`pwd`/../libressl/ios/include -I$SDKROOT/usr/include/" \
    CFLAGS="$CPPFLAGS -arch arm64 -miphoneos-version-min=${MIN_IOS_VERSION} -pipe -no-cpp-precomp" \
    CPP="/usr/bin/cpp -D__arm__=1 $CPPFLAGS" \
    LD="$DEVROOT/usr/bin/ld -L${LIBRESSLROOT}"
  
  make clean
  make -j 4 install \
      CC="/usr/bin/clang -isysroot $SDKROOT" \
      CPPFLAGS="-fembed-bitcode -I`pwd`/../libressl/ios/include -I$SDKROOT/usr/include/" \
      CFLAGS="$CPPFLAGS -arch arm64 -miphoneos-version-min=${MIN_IOS_VERSION} -pipe -no-cpp-precomp" \
      CPP="/usr/bin/cpp -D__arm__=1 $CPPFLAGS" \
      LD="$DEVROOT/usr/bin/ld -L${LIBRESSLROOT}"
	  
  printf "\n\n--> XX iOS arm64 Compilation"
  mv $PREFIX/$target/include/*.h $OUTPUT/$target/include
  mv $PREFIX/$target/lib/libssh2.a $OUTPUT/$target/lib

fi;




## Lipo & XCFramework

cd $ROOT

XCFRAMEWORK_CMD="xcodebuild -create-xcframework"

macos=()
catalyst=()
simulator=()
ios=()

for target in "${link_targets[@]}"
do
  if [[ $target == "ios-"* ]]; then
    ios+=($target)
  fi
  if [[ $target == "simulator_"* ]]; then
    simulator+=($target)
  fi
  if [[ $target == "catalyst_"* ]]; then
    catalyst+=($target)
  fi
  if [[ $target == "macos_"* ]]; then
    macos+=($target)
  fi
done

if [ ${#ios[@]} -gt 0 ]; then
  lipo="lipo -create "

  mkdir -p $OUTPUT/ios/lib
  mkdir -p $OUTPUT/ios/include

  for target in "${ios[@]}"
  do
    lipo="$lipo $OUTPUT/$target/lib/libssh2.a"
    rsync -a $OUTPUT/$target/include/* $OUTPUT/ios/include
  done

  lipo="$lipo -output $OUTPUT/ios/lib/libssh2.a"
  echo $lipo
  eval $lipo

  XCFRAMEWORK_CMD="$XCFRAMEWORK_CMD -library $OUTPUT/ios/lib/libssh2.a"
  XCFRAMEWORK_CMD="$XCFRAMEWORK_CMD -headers $OUTPUT/ios/include"
fi

if [ ${#catalyst[@]} -gt 0 ]; then
  lipo="lipo -create "

  mkdir -p $OUTPUT/catalyst/lib
  mkdir -p $OUTPUT/catalyst/include

  for target in "${catalyst[@]}"
  do
    lipo="$lipo $OUTPUT/$target/lib/libssh2.a"
    rsync -a $OUTPUT/$target/include/* $OUTPUT/catalyst/include
  done

  lipo="$lipo -output $OUTPUT/catalyst/lib/libssh2.a"
  echo $lipo
  eval $lipo

  XCFRAMEWORK_CMD="$XCFRAMEWORK_CMD -library $OUTPUT/catalyst/lib/libssh2.a"
  XCFRAMEWORK_CMD="$XCFRAMEWORK_CMD -headers $OUTPUT/catalyst/include"
fi

if [ ${#macos[@]} -gt 0 ]; then
  lipo="lipo -create "

  mkdir -p $OUTPUT/macos/lib
  mkdir -p $OUTPUT/macos/include

  for target in "${macos[@]}"
  do
    lipo="$lipo $OUTPUT/$target/lib/libssh2.a"
    rsync -a $OUTPUT/$target/include/* $OUTPUT/macos/include
  done

  lipo="$lipo -output $OUTPUT/macos/lib/libssh2.a"
  echo $lipo
  eval $lipo

  XCFRAMEWORK_CMD="$XCFRAMEWORK_CMD -library $OUTPUT/macos/lib/libssh2.a"
  XCFRAMEWORK_CMD="$XCFRAMEWORK_CMD -headers $OUTPUT/macos/include"
fi

if [ ${#simulator[@]} -gt 0 ]; then
  lipo="lipo -create "

  mkdir -p $OUTPUT/simulator/lib
  mkdir -p $OUTPUT/simulator/include

  for target in "${simulator[@]}"
  do
    lipo="$lipo $OUTPUT/$target/lib/libssh2.a"
    rsync -a $OUTPUT/$target/include/* $OUTPUT/simulator/include
  done

  lipo="$lipo -output $OUTPUT/simulator/lib/libssh2.a"
  echo $lipo
  eval $lipo

  XCFRAMEWORK_CMD="$XCFRAMEWORK_CMD -library $OUTPUT/simulator/lib/libssh2.a"
  XCFRAMEWORK_CMD="$XCFRAMEWORK_CMD -headers $OUTPUT/simulator/include"
fi

#rm -R $OUTPUT
XCFRAMEWORK_CMD="$XCFRAMEWORK_CMD -output $XCFRAMEWORKS/libssh2.xcframework"

echo $XCFRAMEWORK_CMD
echo "----"
eval $XCFRAMEWORK_CMD
