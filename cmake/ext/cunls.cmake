# Copyright (c) 2026, NVIDIA CORPORATION. All rights reserved.
#
# NVIDIA software released under the NVIDIA Community License is intended to be used to enable
# the further development of AI and robotics technologies. Such software has been designed, tested,
# and optimized for use with NVIDIA hardware, and this License grants permission to use the software
# solely with such hardware.
# Subject to the terms of this License, NVIDIA confirms that you are free to commercially use,
# modify, and distribute the software with NVIDIA hardware. NVIDIA does not claim ownership of any
# outputs generated using the software or derivative works thereof. Any code contributions that you
# share with NVIDIA are licensed to NVIDIA as feedback under this License and may be incorporated
# in future releases without notice or attribution.
# By using, reproducing, modifying, distributing, performing, or displaying any portion or element
# of the software or derivative works thereof, you agree to be bound by this License.

# Static libcunls.a with CMake package config (cunls::cunls). spdlog and cuDSS are linked into the
# archive; consumers only need CUDA toolkit math libraries at link time.

if(NOT USE_CUDA)
    message(FATAL_ERROR "USE_CUNLS requires USE_CUDA")
endif()

if(CUVSLAM_CUNLS_ROOT STREQUAL "")
    message(FATAL_ERROR "USE_CUNLS is ON but CUVSLAM_CUNLS_ROOT is empty. Set CUVSLAM_CUNLS_ROOT to the cuNLS install prefix (directory containing include/ and lib/).")
endif()

get_filename_component(_cunls_root "${CUVSLAM_CUNLS_ROOT}" ABSOLUTE)

if(MSVC)
    set(_cunls_archive "${_cunls_root}/lib/cunls.lib")
else()
    set(_cunls_archive "${_cunls_root}/lib/libcunls.a")
endif()

if(NOT EXISTS "${_cunls_archive}")
    message(FATAL_ERROR "cuNLS static library not found at ${_cunls_archive}. Check CUVSLAM_CUNLS_ROOT (${_cunls_root}).")
endif()

find_package(cunls CONFIG REQUIRED PATHS "${_cunls_root}" NO_DEFAULT_PATH)

if(NOT TARGET cunls::cunls)
    message(FATAL_ERROR "find_package(cunls) did not define target cunls::cunls")
endif()

get_target_property(_cunls_type cunls::cunls TYPE)
if(NOT _cunls_type STREQUAL "STATIC_LIBRARY")
    message(WARNING "cunls::cunls is not STATIC_LIBRARY (got ${_cunls_type}); cuVSLAM expects a static libcunls.")
endif()

# Package config lists spdlog and cudss as link dependencies; this build links them inside libcunls.a.
set_target_properties(cunls::cunls PROPERTIES
    INTERFACE_LINK_LIBRARIES
        "CUDA::cudart;\$<LINK_ONLY:CUDA::cusparse>;\$<LINK_ONLY:CUDA::cublas>;\$<LINK_ONLY:CUDA::cusolver>"
)

# Install tree may only export Release; reuse the same archive for other single-config build types.
if(CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    string(TOUPPER "${CMAKE_BUILD_TYPE}" _cunls_cfg)
    if(NOT _cunls_cfg STREQUAL "RELEASE")
        set_target_properties(cunls::cunls PROPERTIES
            "IMPORTED_LOCATION_${_cunls_cfg}" "${_cunls_archive}"
        )
    endif()
endif()

# Multi-config generators (e.g. MSVC): map other configurations to Release import data.
set_target_properties(cunls::cunls PROPERTIES
    MAP_IMPORTED_CONFIG_MINSIZEREL Release
    MAP_IMPORTED_CONFIG_RELWITHDEBINFO Release
    MAP_IMPORTED_CONFIG_DEBUG Release
)

message(STATUS "cuNLS: ${_cunls_root} (static ${_cunls_archive})")
