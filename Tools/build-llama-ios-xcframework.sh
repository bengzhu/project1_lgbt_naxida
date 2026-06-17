#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_DIR="${ROOT_DIR}/third_party/llama.cpp"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-17.0}"
BUILD_APPLE_DIR="${ROOT_DIR}/build-apple"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -d "${LLAMA_DIR}" ]]; then
    echo "Missing ${LLAMA_DIR}. Clone llama.cpp first:" >&2
    echo "git clone --depth 1 https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp" >&2
    exit 1
fi

COMMON_CMAKE_ARGS=(
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf
    -DBUILD_SHARED_LIBS=OFF
    -DLLAMA_BUILD_APP=OFF
    -DLLAMA_BUILD_COMMON=OFF
    -DLLAMA_BUILD_EXAMPLES=OFF
    -DLLAMA_BUILD_TOOLS=OFF
    -DLLAMA_BUILD_TESTS=OFF
    -DLLAMA_BUILD_SERVER=OFF
    -DGGML_METAL=ON
    -DGGML_METAL_EMBED_LIBRARY=ON
    -DGGML_BLAS_DEFAULT=ON
    -DGGML_METAL_USE_BF16=ON
    -DGGML_NATIVE=OFF
    -DGGML_OPENMP=OFF
    -DLLAMA_OPENSSL=OFF
)

make_framework_shell() {
    local build_dir="$1"
    local platform="$2"
    local release_dir="$3"
    local sdk="$4"
    local min_flag="$5"
    local arch_flags="$6"
    local src_dir="${LLAMA_DIR}"
    local framework_dir="${src_dir}/${build_dir}/framework/llama.framework"

    mkdir -p "${framework_dir}/Headers" "${framework_dir}/Modules"

    cp "${src_dir}/include/llama.h" "${framework_dir}/Headers/"
    cp "${src_dir}/ggml/include/ggml.h" "${framework_dir}/Headers/"
    cp "${src_dir}/ggml/include/ggml-opt.h" "${framework_dir}/Headers/"
    cp "${src_dir}/ggml/include/ggml-alloc.h" "${framework_dir}/Headers/"
    cp "${src_dir}/ggml/include/ggml-backend.h" "${framework_dir}/Headers/"
    cp "${src_dir}/ggml/include/ggml-metal.h" "${framework_dir}/Headers/"
    cp "${src_dir}/ggml/include/ggml-cpu.h" "${framework_dir}/Headers/"
    cp "${src_dir}/ggml/include/ggml-blas.h" "${framework_dir}/Headers/"
    cp "${src_dir}/ggml/include/gguf.h" "${framework_dir}/Headers/"

    cat > "${framework_dir}/Modules/module.modulemap" <<'EOF'
framework module llama {
    umbrella "Headers"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"

    export *
}
EOF

    cat > "${framework_dir}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>llama</string>
    <key>CFBundleIdentifier</key>
    <string>org.ggml.llama</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>llama</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${MIN_IOS_VERSION}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>${platform}</string>
    </array>
    <key>DTPlatformName</key>
    <string>${sdk}</string>
</dict>
</plist>
EOF

    local temp_dir="${src_dir}/${build_dir}/temp"
    mkdir -p "${temp_dir}"

    local libs=(
        "${src_dir}/${build_dir}/src/${release_dir}/libllama.a"
        "${src_dir}/${build_dir}/ggml/src/${release_dir}/libggml.a"
        "${src_dir}/${build_dir}/ggml/src/${release_dir}/libggml-base.a"
        "${src_dir}/${build_dir}/ggml/src/${release_dir}/libggml-cpu.a"
        "${src_dir}/${build_dir}/ggml/src/ggml-metal/${release_dir}/libggml-metal.a"
        "${src_dir}/${build_dir}/ggml/src/ggml-blas/${release_dir}/libggml-blas.a"
    )

    xcrun libtool -static -o "${temp_dir}/combined.a" "${libs[@]}" 2>/dev/null
    xcrun -sdk "${sdk}" clang++ -dynamiclib \
        -isysroot "$(xcrun --sdk "${sdk}" --show-sdk-path)" \
        ${arch_flags} \
        "${min_flag}" \
        -Wl,-force_load,"${temp_dir}/combined.a" \
        -framework Foundation -framework Metal -framework Accelerate \
        -install_name "@rpath/llama.framework/llama" \
        -o "${framework_dir}/llama"
}

cd "${LLAMA_DIR}"

rm -rf build-ios-sim build-ios-device "${BUILD_APPLE_DIR}"

cmake -B build-ios-sim -G Xcode \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_IOS_VERSION}" \
    -DIOS=ON \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphonesimulator \
    -S .
cmake --build build-ios-sim --config Release -j "$(sysctl -n hw.logicalcpu)" -- -quiet

cmake -B build-ios-device -G Xcode \
    "${COMMON_CMAKE_ARGS[@]}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_IOS_VERSION}" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphoneos \
    -S .
cmake --build build-ios-device --config Release -j "$(sysctl -n hw.logicalcpu)" -- -quiet

make_framework_shell "build-ios-sim" "iPhoneSimulator" "Release-iphonesimulator" "iphonesimulator" "-mios-simulator-version-min=${MIN_IOS_VERSION}" "-arch arm64"
make_framework_shell "build-ios-device" "iPhoneOS" "Release-iphoneos" "iphoneos" "-mios-version-min=${MIN_IOS_VERSION}" "-arch arm64"

mkdir -p "${BUILD_APPLE_DIR}"
xcrun xcodebuild -create-xcframework \
    -framework "${LLAMA_DIR}/build-ios-sim/framework/llama.framework" \
    -framework "${LLAMA_DIR}/build-ios-device/framework/llama.framework" \
    -output "${BUILD_APPLE_DIR}/llama.xcframework"

echo "Built ${BUILD_APPLE_DIR}/llama.xcframework"
