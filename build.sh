#!/bin/bash

# -----------------------------------------------------------------------------
# | SYSTEM DISCOVERY AND CONFIGURATION                                        |
# -----------------------------------------------------------------------------

# Git refresh
git submodule update --init

# Environment Variables
[ -z "$ANDROID_HOME" ] && [ -d ~/Android/Sdk ] && export ANDROID_HOME=~/Android/Sdk && echo 'export ANDROID_HOME=~/Android/Sdk' >> ~/.profile && echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin' >> ~/.profile
[ -z "$ANDROID_SDK_ROOT" ] && [ -d ~/Android/Sdk ] && export ANDROID_SDK_ROOT=~/Android/Sdk && echo 'export ANDROID_SDK_ROOT=~/Android/Sdk' >> ~/.profile
[ -z "$ANDROID_AVD_HOME" ] && [ -d ~/.android/avd ] && export ANDROID_AVD_HOME=~/.android/avd && echo 'export ANDROID_AVD_HOME=~/.android/avd' >> ~/.profile

# Find and set cmake
CMAKE=cmake3
if [[ $(which $CMAKE) = "" ]];
then
	CMAKE=cmake # try this next
fi
if [[ $(which $CMAKE) = "" ]];
then
	echo "CMake (cmake) not found. Please install before continuing."
	exit
fi

#
if [[ ! $(which tree) = "" ]];
then
	TREE=tree
else
	TREE="du -a "
fi

# Determine operating system
OSNAME=$(uname | tr '[A-Z]' '[a-z]')
if [[ $OSNAME = *"darwin"* ]]; then
	SHARED_LIB_NAME="libzt.dylib"
	STATIC_LIB_NAME="libzt.a"
	HOST_PLATFORM="macos"
fi
if [[ $OSNAME = *"linux"* ]]; then
	SHARED_LIB_NAME="libzt.so"
	STATIC_LIB_NAME="libzt.a"
	HOST_PLATFORM="linux"
fi

# Determine and normalize machine type
HOST_MACHINE_TYPE=$(uname -m)
if [[ $HOST_MACHINE_TYPE = *"x86_64"* ]]; then
	HOST_MACHINE_TYPE="x64"
fi

# Determine number of cores. We'll tell CMake to use them all
if [[ $OSNAME = *"darwin"* ]]; then
	N_PROCESSORS=$(sysctl -n hw.ncpu)
fi
if [[ $OSNAME = *"linux"* ]]; then
	N_PROCESSORS=$(nproc --all)
fi

# How many processor cores CMake should use during builds,
# comment out the below line out if you don't want parallelism:
BUILD_CONCURRENCY="-j $N_PROCESSORS"

# -----------------------------------------------------------------------------
# | PATHS                                                                     |
# -----------------------------------------------------------------------------

# Where we place all finished artifacts
BUILD_OUTPUT_DIR=$(pwd)/dist
# Where we tell CMake to place its build systems and their caches
BUILD_CACHE_DIR=$(pwd)/cache
# Where package projects, scripts, spec files, etc live
PKG_DIR=$(pwd)/pkg
# Default location for (host) libraries
DEFAULT_HOST_LIB_OUTPUT_DIR=$BUILD_OUTPUT_DIR/$HOST_PLATFORM-$HOST_MACHINE_TYPE
# Default location for (host) binaries
DEFAULT_HOST_BIN_OUTPUT_DIR=$BUILD_OUTPUT_DIR/$HOST_PLATFORM-$HOST_MACHINE_TYPE
# Default location for (host) packages
DEFAULT_HOST_PKG_OUTPUT_DIR=$BUILD_OUTPUT_DIR/$HOST_PLATFORM-$HOST_MACHINE_TYPE
# Defaultlocation for CMake's caches (when building for host)
DEFAULT_HOST_BUILD_CACHE_DIR=$BUILD_CACHE_DIR/$HOST_PLATFORM-$HOST_MACHINE_TYPE
# Headers
[ ! -f /usr/lib/jvm/java-8-openjdk-amd64/include/jni_md.h ] && [ -f /usr/lib/jvm/java-8-openjdk-amd64/include/linux/jni_md.h ] && sudo ln -s /usr/lib/jvm/java-8-openjdk-amd64/include/linux/jni_md.h /usr/lib/jvm/java-8-openjdk-amd64/include/jni_md.h
[ ! -f /usr/lib/jvm/java-11-openjdk-amd64/include/jni_md.h ] && [ -f /usr/lib/jvm/java-11-openjdk-amd64/include/linux/jni_md.h ] && sudo ln -s /usr/lib/jvm/java-11-openjdk-amd64/include/linux/jni_md.h /usr/lib/jvm/java-11-openjdk-amd64/include/jni_md.h

gethosttype()
{
	echo $HOST_PLATFORM-$HOST_MACHINE_TYPE
}

# -----------------------------------------------------------------------------
# | TARGETS                                                                   |
# -----------------------------------------------------------------------------

# Build xcframework
#
# ./build.sh xcframework "debug"
#
# Example output:
#
#	 - Cache        : /Volumes/$USER/zt/libzt/libzt-dev/cache/apple-xcframework-debug
#	 - Build output : /Volumes/$USER/zt/libzt/libzt-dev/dist
#
# apple-xcframework-debug
# └── pkg
#     └── zt.xcframework
#         ├── Info.plist
#         ├── ios-arm64
#         │   └── zt.framework
#         │       └── ...
#         ├── ios-arm64_x86_64-simulator
#         │   └── zt.framework
#         │       └── ...
#         └── macos-arm64_x86_64
#             └── zt.framework
#                 └── ...
#
xcframework()
{
	if [[ ! $OSNAME = *"darwin"* ]]; then
		echo "Can only build this on a Mac"
		exit 0
	fi
	BUILD_TYPE=${1:-release}
	UPPERCASE_BUILD_TYPE="$(tr '[:lower:]' '[:upper:]' <<< ${BUILD_TYPE:0:1})${BUILD_TYPE:1}"

	# Build all frameworks
	macos-framework $BUILD_TYPE
	iphoneos-framework $BUILD_TYPE
	iphonesimulator-framework $BUILD_TYPE

	ARTIFACT="xcframework"
	TARGET_PLATFORM="apple"
	TARGET_BUILD_DIR=$BUILD_OUTPUT_DIR/$TARGET_PLATFORM-$ARTIFACT-$BUILD_TYPE
	rm -rf $TARGET_BUILD_DIR
	PKG_OUTPUT_DIR=$TARGET_BUILD_DIR/pkg
	mkdir -p $PKG_OUTPUT_DIR

	MACOS_FRAMEWORK_DIR=macos-x64-framework-$BUILD_TYPE
	IOS_FRAMEWORK_DIR=iphoneos-arm64-framework-$BUILD_TYPE
	IOS_SIM_FRAMEWORK_DIR=iphonesimulator-x64-framework-$BUILD_TYPE

	# Pack everything
	rm -rf $PKG_OUTPUT_DIR/zt.xcframework # Remove prior to move to prevent error
	xcodebuild -create-xcframework \
		-framework $BUILD_CACHE_DIR/$MACOS_FRAMEWORK_DIR/lib/$UPPERCASE_BUILD_TYPE/zt.framework \
		-framework $BUILD_CACHE_DIR/$IOS_FRAMEWORK_DIR/lib/$UPPERCASE_BUILD_TYPE/zt.framework \
		-framework $BUILD_CACHE_DIR/$IOS_SIM_FRAMEWORK_DIR/lib/$UPPERCASE_BUILD_TYPE/zt.framework \
		-output $PKG_OUTPUT_DIR/zt.xcframework
}

# Build iOS framework
#
# ./build.sh iphonesimulator-framework "debug"
#
# Example output:
#
#	 - Cache        : /Volumes/$USER/zt/libzt/libzt-dev/cache/iphonesimulator-x64-framework-debug
#	 - Build output : /Volumes/$USER/zt/libzt/libzt-dev/dist
#
# /Volumes/$USER/zt/libzt/libzt-dev/dist/iphonesimulator-x64-framework-debug
# └── pkg
#     └── zt.framework
#         ├── Headers
#         │   └── ZeroTierSockets.h
#         ├── Info.plist
#         ├── Modules
#         │   └── module.modulemap
#         └── zt
#
iphonesimulator-framework()
{
	if [[ ! $OSNAME = *"darwin"* ]]; then
		echo "Can only build this on a Mac"
		exit 0
	fi
	ARTIFACT="framework"
	BUILD_TYPE=${1:-Release}
	UPPERCASE_BUILD_TYPE="$(tr '[:lower:]' '[:upper:]' <<< ${BUILD_TYPE:0:1})${BUILD_TYPE:1}"
	VARIANT="-DBUILD_IOS_FRAMEWORK=True"
	TARGET_PLATFORM="iphonesimulator"
	TARGET_MACHINE_TYPE="x64" # presumably
	CACHE_DIR=$BUILD_CACHE_DIR/$TARGET_PLATFORM-$TARGET_MACHINE_TYPE-$ARTIFACT-$BUILD_TYPE
	TARGET_BUILD_DIR=$BUILD_OUTPUT_DIR/$TARGET_PLATFORM-$TARGET_MACHINE_TYPE-$ARTIFACT-$BUILD_TYPE
	rm -rf $TARGET_BUILD_DIR
	PKG_OUTPUT_DIR=$TARGET_BUILD_DIR/pkg
	mkdir -p $PKG_OUTPUT_DIR
	# Generate project
	mkdir -p $CACHE_DIR
	cd $CACHE_DIR
	# iOS (SDK 11+, 64-bit only, arm64)
	$CMAKE -G Xcode ../../ $VARIANT
	# Build framework
	xcodebuild -target zt -configuration "$UPPERCASE_BUILD_TYPE" -sdk "iphonesimulator"
	cd -
	cp -rf $CACHE_DIR/lib/$UPPERCASE_BUILD_TYPE/*.framework $PKG_OUTPUT_DIR
	echo -e "\n - Build cache  : $CACHE_DIR\n - Build output : $BUILD_OUTPUT_DIR\n"
	$TREE $TARGET_BUILD_DIR
}

# Build macOS framework
#
# ./build.sh macos-framework "debug"
#
# Example output:
#
#	 - Cache        : /Volumes/$USER/zt/libzt/libzt-dev/cache/macos-x64-framework-debug
#	 - Build output : /Volumes/$USER/zt/libzt/libzt-dev/dist
#
# /Volumes/$USER/zt/libzt/libzt-dev/dist/macos-x64-framework-debug
# └── pkg
#     └── zt.framework
#         ├── Headers
#         │   └── ZeroTierSockets.h
#         ├── Info.plist
#         ├── Modules
#         │   └── module.modulemap
#         └── zt
#
macos-framework()
{
	if [[ ! $OSNAME = *"darwin"* ]]; then
		echo "Can only build this on a Mac"
		exit 0
	fi
	ARTIFACT="framework"
	BUILD_TYPE=${1:-Release}
	UPPERCASE_BUILD_TYPE="$(tr '[:lower:]' '[:upper:]' <<< ${BUILD_TYPE:0:1})${BUILD_TYPE:1}"
	VARIANT="-DBUILD_MACOS_FRAMEWORK=True"
	CACHE_DIR=$DEFAULT_HOST_BUILD_CACHE_DIR-$ARTIFACT-$BUILD_TYPE
	TARGET_BUILD_DIR=$DEFAULT_HOST_BIN_OUTPUT_DIR-$ARTIFACT-$BUILD_TYPE
	rm -rf $TARGET_BUILD_DIR
	PKG_OUTPUT_DIR=$TARGET_BUILD_DIR/pkg
	mkdir -p $PKG_OUTPUT_DIR
	# Generate project
	mkdir -p $CACHE_DIR
	cd $CACHE_DIR
	$CMAKE -G Xcode ../../ $VARIANT
	# Build framework
	xcodebuild -target zt -configuration $UPPERCASE_BUILD_TYPE -sdk "macosx"
	cd -
	cp -rf $CACHE_DIR/lib/$UPPERCASE_BUILD_TYPE/*.framework $PKG_OUTPUT_DIR
	echo -e "\n - Build cache  : $CACHE_DIR\n - Build output : $BUILD_OUTPUT_DIR\n"
	$TREE $TARGET_BUILD_DIR
}

# Build iOS framework
#
# ./build.sh iphoneos-framework "debug"
#
# Example output:
#
#	 - Cache        : /Volumes/$USER/zt/libzt/libzt-dev/cache/iphoneos-arm64-framework-debug
#	 - Build output : /Volumes/$USER/zt/libzt/libzt-dev/dist
#
# /Volumes/$USER/zt/libzt/libzt-dev/dist/iphoneos-arm64-framework-debug
# └── pkg
#     └── zt.framework
#         ├── Headers
#         │   └── ZeroTierSockets.h
#         ├── Info.plist
#         ├── Modules
#         │   └── module.modulemap
#         └── zt
#
iphoneos-framework()
{
	if [[ ! $OSNAME = *"darwin"* ]]; then
		echo "Can only build this on a Mac"
		exit 0
	fi
	ARTIFACT="framework"
	BUILD_TYPE=${1:-Release}
	UPPERCASE_BUILD_TYPE="$(tr '[:lower:]' '[:upper:]' <<< ${BUILD_TYPE:0:1})${BUILD_TYPE:1}"
	VARIANT="-DBUILD_IOS_FRAMEWORK=True -DIOS_ARM64=True"
	TARGET_PLATFORM="iphoneos"
	TARGET_MACHINE_TYPE=arm64
	CACHE_DIR=$BUILD_CACHE_DIR/$TARGET_PLATFORM-$TARGET_MACHINE_TYPE-$ARTIFACT-$BUILD_TYPE
	TARGET_BUILD_DIR=$BUILD_OUTPUT_DIR/$TARGET_PLATFORM-$TARGET_MACHINE_TYPE-$ARTIFACT-$BUILD_TYPE
	rm -rf $TARGET_BUILD_DIR
	PKG_OUTPUT_DIR=$TARGET_BUILD_DIR/pkg
	mkdir -p $PKG_OUTPUT_DIR
	# Generate project
	mkdir -p $CACHE_DIR
	cd $CACHE_DIR
	# iOS (SDK 11+, 64-bit only, arm64)
	$CMAKE -G Xcode ../../ $VARIANT
	sed -i '' 's/x86_64/$(CURRENT_ARCH)/g' zt.xcodeproj/project.pbxproj
	# Build framework
	xcodebuild -arch $TARGET_MACHINE_TYPE -target zt -configuration "$UPPERCASE_BUILD_TYPE" -sdk "iphoneos"
	cd -
	cp -rvf $CACHE_DIR/lib/$UPPERCASE_BUILD_TYPE/*.framework $PKG_OUTPUT_DIR
	echo -e "\n - Build cache  : $CACHE_DIR\n - Build output : $BUILD_OUTPUT_DIR\n"
	$TREE $TARGET_BUILD_DIR
}

# Build standard libraries, examples, and selftest
#
# ./build.sh host "release"
#
# Example output:
#
#	 - Cache        : /Volumes/$USER/zt/libzt/libzt-dev/cache/linux-x64-host-release
#	 - Build output : /Volumes/$USER/zt/libzt/libzt-dev/dist
#
# linux-x64-host-release
# ├── bin
# │   ├── client
# │   └── server
# └── lib
#     ├── libzt.a
#     └── libzt.so # .dylib, .dll
#
host()
{
	ARTIFACT="host"
	# Default to release
	BUILD_TYPE=${1:-release}
	# -DZTS_ENABLE_CENTRAL_API=0
	VARIANT="-DBUILD_HOST=True"
	CACHE_DIR=$DEFAULT_HOST_BUILD_CACHE_DIR-$ARTIFACT-$BUILD_TYPE
	TARGET_BUILD_DIR=$DEFAULT_HOST_BIN_OUTPUT_DIR-$ARTIFACT-$BUILD_TYPE
	rm -rf $TARGET_BUILD_DIR
	LIB_OUTPUT_DIR=$TARGET_BUILD_DIR/lib
	BIN_OUTPUT_DIR=$TARGET_BUILD_DIR/bin
	mkdir -p $LIB_OUTPUT_DIR
	mkdir -p $BIN_OUTPUT_DIR
	$CMAKE $VARIANT -H. -B$CACHE_DIR -DCMAKE_BUILD_TYPE=$BUILD_TYPE
	$CMAKE --build $CACHE_DIR $BUILD_CONCURRENCY
	cp -f $CACHE_DIR/lib/libzt.* $LIB_OUTPUT_DIR
	cp -f $CACHE_DIR/bin/* $BIN_OUTPUT_DIR
	echo -e "\n - Build cache  : $CACHE_DIR\n - Build output : $BUILD_OUTPUT_DIR\n"
	$TREE $TARGET_BUILD_DIR
}
host-install()
{
	cd cache/$HOST_PLATFORM-$HOST_MACHINE_TYPE-host-$1/
	make install
	cd -
}
host-uninstall()
{
	cd cache/$HOST_PLATFORM-$HOST_MACHINE_TYPE-host-$1/
	xargs rm < install_manifest.txt
	cd -
}

# Build shared library with python wrapper symbols exported
host-python()
{
	ARTIFACT="python"
	# Default to release
	BUILD_TYPE=${1:-release}
	VARIANT="-DZTS_ENABLE_PYTHON=True"
	CACHE_DIR=$DEFAULT_HOST_BUILD_CACHE_DIR-$ARTIFACT-$BUILD_TYPE
	TARGET_BUILD_DIR=$DEFAULT_HOST_BIN_OUTPUT_DIR-$ARTIFACT-$BUILD_TYPE
	rm -rf $TARGET_BUILD_DIR
	LIB_OUTPUT_DIR=$TARGET_BUILD_DIR/lib
	BIN_OUTPUT_DIR=$TARGET_BUILD_DIR/bin
	mkdir -p $LIB_OUTPUT_DIR
	# Optional step to generate new SWIG wrapper
	swig -c++ -python -o src/bindings/python/zt_wrap.cpp -Iinclude src/bindings/python/zt.i
	$CMAKE $VARIANT -H. -B$CACHE_DIR -DCMAKE_BUILD_TYPE=$BUILD_TYPE
	$CMAKE --build $CACHE_DIR $BUILD_CONCURRENCY
	cp -f $CACHE_DIR/lib/$SHARED_LIB_NAME $LIB_OUTPUT_DIR/_libzt.so
	echo -e "\n - Build cache  : $CACHE_DIR\n - Build output : $BUILD_OUTPUT_DIR\n"
	$TREE $TARGET_BUILD_DIR
}

# Build shared library with P/INVOKE wrapper symbols exported
host-pinvoke()
{
	ARTIFACT="pinvoke"
	# Default to release
	BUILD_TYPE=${1:-release}
	VARIANT="-DZTS_ENABLE_PINVOKE=True"
	CACHE_DIR=$DEFAULT_HOST_BUILD_CACHE_DIR-$ARTIFACT-$BUILD_TYPE
	TARGET_BUILD_DIR=$DEFAULT_HOST_BIN_OUTPUT_DIR-$ARTIFACT-$BUILD_TYPE
	rm -rf $TARGET_BUILD_DIR
	LIB_OUTPUT_DIR=$TARGET_BUILD_DIR/lib
	BIN_OUTPUT_DIR=$TARGET_BUILD_DIR/bin
	mkdir -p $LIB_OUTPUT_DIR
	$CMAKE $VARIANT -H. -B$CACHE_DIR -DCMAKE_BUILD_TYPE=$BUILD_TYPE
	$CMAKE --build $CACHE_DIR $BUILD_CONCURRENCY
	cp -f $CACHE_DIR/lib/libzt.* $LIB_OUTPUT_DIR
	echo -e "\n - Build cache  : $CACHE_DIR\n - Build output : $BUILD_OUTPUT_DIR\n"
	$TREE $TARGET_BUILD_DIR
}

# Build shared library with Java JNI wrapper symbols exported (.jar)
host-jar()
{
	ARTIFACT="jar"
	# Default to release
	BUILD_TYPE=${1:-release}
	VARIANT="-DZTS_ENABLE_JAVA=True"
	CACHE_DIR=$DEFAULT_HOST_BUILD_CACHE_DIR-$ARTIFACT-$BUILD_TYPE
	TARGET_BUILD_DIR=$DEFAULT_HOST_BIN_OUTPUT_DIR-$ARTIFACT-$BUILD_TYPE
	rm -rf $TARGET_BUILD_DIR
	PKG_OUTPUT_DIR=$TARGET_BUILD_DIR/pkg
	mkdir -p $PKG_OUTPUT_DIR
	# Share same cache dir with CMake
	JAVA_JAR_DIR=$CACHE_DIR/pkg/jar
	JAVA_JAR_SOURCE_TREE_DIR=$JAVA_JAR_DIR/com/zerotier/libzt/
	mkdir -p $JAVA_JAR_SOURCE_TREE_DIR
	cp -f ext/ZeroTierOne/java/src/com/zerotier/sdk/*.java $JAVA_JAR_SOURCE_TREE_DIR
	# Build
	$CMAKE $VARIANT -H. -B$CACHE_DIR -DCMAKE_BUILD_TYPE=$BUILD_TYPE
	$CMAKE --build $CACHE_DIR $BUILD_CONCURRENCY
	# Package everything
	cp -f $CACHE_DIR/lib/libzt.* $JAVA_JAR_DIR
	cd $JAVA_JAR_DIR
	export JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF8
	javac com/zerotier/libzt/*.java
	jar cf libzt-"$(git describe --abbrev=0)".jar $SHARED_LIB_NAME com/zerotier/libzt/*.class
	rm -rf com $SHARED_LIB_NAME
	cd -
	# Copy JAR to dist/
	echo -e "\nContents of JAR:\n"
	jar tf $JAVA_JAR_DIR/*.jar
	echo -e
	mv $JAVA_JAR_DIR/*.jar $PKG_OUTPUT_DIR
	echo -e "\n - Build cache  : $CACHE_DIR\n - Build output : $BUILD_OUTPUT_DIR\n"
	$TREE $TARGET_BUILD_DIR
}


# -----------------------------------------------------------------------------
# | ANDROID CONFIG                                                            |
# -----------------------------------------------------------------------------

ANDROID_PKG_PROJ_DIR=$(pwd)/pkg/android

# Set ANDROID_HOME because setting sdk.dir in local.properties isn't always reliable
#export PATH=/Library/Java/JavaVirtualMachines/$JDK/Contents/Home/bin/:${PATH}
#export PATH=/Users/$USER/Library/Android/sdk/platform-tools/:${PATH}
GRADLE_ARGS=--stacktrace
#ANDROID_APP_NAME=com.example.mynewestapplication
# for our purposes we limit this to execution on macOS
if [[ $OSNAME = *"linux"* ]]; then
	export ANDROID_HOME=/usr/lib/android-sdk/
fi
if [[ $OSNAME = *"darwin"* ]]; then
	export ANDROID_HOME=/Users/$USER/Library/Android/sdk
fi

# Build shared library with Java JNI wrapper symbols exported (.aar)
#
# ./build.sh android-aar "release"
#
# Example output:
#
#	 - Cache        : /Volumes/$USER/zt/libzt/libzt-dev/cache/android-any-android-release
#	 - Build output : /Volumes/$USER/zt/libzt/libzt-dev/dist
#
# android-any-android-release
# └── libzt-release.aar
#
# Dependency: sudo apt install ninja-build
#
android-aar()
{
	ARTIFACT="android"
	BUILD_TYPE=${1:-release} # Default to release
	CMAKE_SWITCH="ZTS_ENABLE_JAVA"
	TARGET_PLATFORM="android"
	TARGET_MACHINE_TYPE=any
	CACHE_DIR=$BUILD_CACHE_DIR/$TARGET_PLATFORM-$TARGET_MACHINE_TYPE-$ARTIFACT-$BUILD_TYPE
	PKG_OUTPUT_DIR=$BUILD_OUTPUT_DIR/$TARGET_PLATFORM-$TARGET_MACHINE_TYPE-$ARTIFACT-$BUILD_TYPE
	mkdir -p $CACHE_DIR
	mkdir -p $PKG_OUTPUT_DIR
	# Unsure why, but Gradle's build script chokes on this non-source file now
	rm -rf ext/ZeroTierOne/ext/miniupnpc/VERSION
	export PATH=$ANDROID_HOME/cmdline-tools/tools/bin:$PATH
	# Copy source files into project
	cp -f ext/ZeroTierOne/java/src/com/zerotier/sdk/*.java ${ANDROID_PKG_PROJ_DIR}/app/src/main/java/com/zerotier/libzt
	# Build
	UPPERCASE_BUILD_TYPE="$(tr '[:lower:]' '[:upper:]' <<< ${BUILD_TYPE:0:1})${BUILD_TYPE:1}"
	CMAKE_FLAGS="-D${CMAKE_SWITCH}=1 -D${CMAKE_SWITCH}=ON"
	cd $ANDROID_PKG_PROJ_DIR
	./gradlew $GRADLE_ARGS assemble$UPPERCASE_BUILD_TYPE # assembleRelease / assembleDebug
	mv $ANDROID_PKG_PROJ_DIR/app/build/outputs/aar/*.aar \
		$PKG_OUTPUT_DIR/libzt-$BUILD_TYPE.aar
	cd -
	echo -e "\n - Build cache  : $CACHE_DIR\n - Build output : $BUILD_OUTPUT_DIR\n"
	$TREE $PKG_OUTPUT_DIR
}

# Build static library and selftest. Currently this only tests
# the core C API, not any of the language bindings.
test()
{
	ARTIFACT="test"
	# Default to release
	BUILD_TYPE=${1:-release}
	VARIANT="-DBUILD_HOST_SELFTEST_ONLY=True"
	CACHE_DIR=$DEFAULT_HOST_BUILD_CACHE_DIR-$ARTIFACT-$BUILD_TYPE
	TARGET_BUILD_DIR=$DEFAULT_HOST_BIN_OUTPUT_DIR-$ARTIFACT-$BUILD_TYPE
	rm -rf $TARGET_BUILD_DIR
	LIB_OUTPUT_DIR=$TARGET_BUILD_DIR/lib
	BIN_OUTPUT_DIR=$TARGET_BUILD_DIR/bin
	mkdir -p $BIN_OUTPUT_DIR
	$CMAKE $VARIANT -H. -B$CACHE_DIR -DCMAKE_BUILD_TYPE=$BUILD_TYPE
	$CMAKE --build $CACHE_DIR $BUILD_CONCURRENCY
	cp -f $CACHE_DIR/bin/* $BIN_OUTPUT_DIR
	echo -e "\n - Build cache  : $CACHE_DIR\n - Build output : $BUILD_OUTPUT_DIR\n"
	$TREE $TARGET_BUILD_DIR
	# Test
	cd $CACHE_DIR
	ctest -C release
	cd -
}

# Recursive deep clean
clean()
{
	# Finished artifacts
	rm -rf $BUILD_OUTPUT_DIR
	# CMake's build system cache
	rm -rf $BUILD_CACHE_DIR
	# CMake test output
	rm -rf bin
	rm -rf Testing
	rm -rf CMakeFiles
	rm -rf *.cmake
	rm -rf CMakeCache.txt
	rm -rf Makefile
	# Android AAR project binaries and sources (copied from ext/ZeroTierOne/java)
	rm -rf $ANDROID_PKG_PROJ_DIR/app/build
	rm -rf $ANDROID_PKG_PROJ_DIR/app/src/main/java/com/zerotier/libzt/*.java
	rm -rf $ANDROID_PKG_PROJ_DIR/app/.externalNativeBuild
	# Remove whatever remains
	find . \
		\( -name '*.dylib' \
		-o -name '*.dll'   \
		-o -name '*.aar'   \
		-o -name '*.jar'   \
		-o -name '*.so'    \
		-o -name '*.a'     \
		-o -name '*.o'     \
		-o -name '*.exe'   \
		-o -name '*.o.d'   \
		-o -name '*.out'   \
		-o -name '*.log'   \
		-o -name '*.dSYM'  \
		-o -name '*.class' \
		\) -exec rm -rf {} +

	find . -type d -name "__pycache__" -exec rm -rf {} +
}

list()
{
	IFS=$'\n'
	for f in $(declare -F); do
		echo "${f:11}"
	done
}

"$@"
