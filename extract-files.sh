#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_FIRMWARE=
ONLY_TARGET=
KANG=
SECTION=
CARRIER_SKIP_FILES=()

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common)
            ONLY_COMMON=true
            ;;
        --only-firmware)
            ONLY_FIRMWARE=true
            ;;
        --only-target)
            ONLY_TARGET=true
            ;;
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"
            shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
    system_ext/etc/init/dpmd.rc|system_ext/etc/permissions/com.qti.dpmframework.xml)
        [ "$2" = "" ] && return 0
        sed -i "s/\/system\/product\/bin\//\/system\/system_ext\/bin\//g" "${2}"
        ;;
    system_ext/etc/permissions/dpmapi.xml|system_ext/etc/permissions/qcrilhook.xml)
        [ "$2" = "" ] && return 0
        sed -i "s/\/system\/product\/framework\//\/system\/system_ext\/framework\//g" "${2}"
        ;;
    system_ext/etc/permissions/telephonyservice.xml)
        [ "$2" = "" ] && return 0
        sed -i "s/\/system\/framework\//\/system\/system_ext\/framework\//g" "${2}"
        ;;
    vendor/bin/imsrcsd)
        [ "$2" = "" ] && return 0
        sed -i "s/libhidltransport.so/libbase_shim.so\x00\x00\x00\x00/" "${2}"
        ;;
    vendor/bin/pm-service)
        [ "$2" = "" ] && return 0
        grep -q libutils-v33.so "${2}" || "${PATCHELF}" --add-needed "libutils-v33.so" "${2}"
        ;;
    vendor/lib64/hw/android.hardware.bluetooth@1.0-impl-qti.so)
        [ "$2" = "" ] && return 0
        sed -i "s/libhidltransport.so/libbase_shim.so\x00\x00\x00\x00/" "${2}"
        ;;
    vendor/lib64/hw/vulkan.msm8996.so)
        [ "$2" = "" ] && return 0
        sed -i "s/vulkan.msm8953.so/vulkan.msm8996.so/g" "${2}"
        ;;
    vendor/lib64/lib-dplmedia.so)
        [ "$2" = "" ] && return 0
        "${PATCHELF}" --remove-needed "libmedia.so" "${2}"
        ;;
    vendor/lib64/lib-uceservice.so)
        [ "$2" = "" ] && return 0
        sed -i "s/libhidltransport.so/libbase_shim.so\x00\x00\x00\x00/" "${2}"
        ;;
    vendor/lib/hw/vulkan.msm8996.so)
        [ "$2" = "" ] && return 0
        sed -i "s/vulkan.msm8953.so/vulkan.msm8996.so/g" "${2}"
        ;;
    vendor/lib/libmmcamera2_isp_modules.so)
        [ "$2" = "" ] && return 0
        "${SIGSCAN}" -p "06 9B 03 F5 30 2C 0C F2 5C 40 FE F7 5C EC 06 9A 02 F5 30 21 01 F5 8B 60 FE F7 5A EC 0C B9" \
                     -P "7C B9 06 9B 03 F5 30 2C 0C F2 5C 40 FE F7 5A EC 06 9A 02 F5 30 21 01 F5 8B 60 FE F7 5A EC" \
                     -f "${2}"
        ;;
    vendor/lib/libmmcamera2_sensor_modules.so)
        [ "$2" = "" ] && return 0
        sed -i "s/\/system\/etc\/camera\//\/vendor\/etc\/camera\//g" "${2}"
        ;;
    vendor/lib/libmmcamera2_stats_modules.so)
        [ "$2" = "" ] && return 0
        "${PATCHELF}" --remove-needed "libandroid.so" "${2}"
        "${PATCHELF}" --replace-needed "libgui.so" "libgui_vendor.so" "${2}"
        ;;
    vendor/lib64/libril-qc-hal-qmi.so)
        [ "$2" = "" ] && return 0
        for v in 1.{0..2}; do
            sed -i "s|android.hardware.radio.config@${v}.so|android.hardware.radio.c_shim@${v}.so|g" "${2}"
        done
        ;;
    vendor/lib64/libwvhidl.so)
        [ "$2" = "" ] && return 0
        grep -q libcrypto_shim.so "${2}" || "${PATCHELF}" --add-needed "libcrypto_shim.so" "${2}"
        ;;
        *)
            return 1
            ;;
    esac

    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

if [ -z "${ONLY_FIRMWARE}" ] && [ -z "${ONLY_TARGET}" ]; then
    # Initialize the helper for common device
    setup_vendor "${DEVICE_COMMON}" "${VENDOR_COMMON:-$VENDOR}" "${ANDROID_ROOT}" true "${CLEAN_VENDOR}"

    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -s "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files.txt" ]; then
    # Reinitialize the helper for device
    source "${MY_DIR}/../../${VENDOR}/${DEVICE}/extract-files.sh"
    setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

    if [ -z "${ONLY_FIRMWARE}" ]; then
        extract "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

        if [ -f "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files-carriersettings.txt" ]; then
            generate_prop_list_from_image "product.img" "${MY_DIR}/../../proprietary-files-carriersettings.txt" CARRIER_SKIP_FILES carriersettings
            extract "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files-carriersettings.txt" "${SRC}" "${KANG}" --section "${SECTION}"

            extract_carriersettings
        fi
    fi

    if [ -z "${SECTION}" ] && [ -f "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-firmware.txt" ]; then
        extract_firmware "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-firmware.txt" "${SRC}"
    fi
fi

"${MY_DIR}/setup-makefiles.sh"
