##########################################
#
# c.f. https://stackoverflow.com/questions/3520977/build-fat-static-library-device-simulator-using-xcode-and-sdk-4
#
# Version 3.0
#
# Latest Changes:
# - Added support for latest iOS and Xcode as of 10/22/21.  - Kevin
# - Added support for . and XCFramework as well.  - Kevin
# - Added copying of all headers.  - Kevin
# - MORE tweaks to get the iOS 10+ and 9- working
# - Support iOS 10+
# - Corrected typo for iOS 1-10+ (thanks @stuikomma)
#
# Purpose:
#   Automatically create a universal static library or framework for iPhone + iPad + iPhone Simulator from within Xcode
#
# Author: Adam Martin - http://twitter.com/redglassesapps
# Based on: original script from Eonil (main changes: Eonil's script WILL NOT WORK in Xcode GUI - it WILL CRASH YOUR COMPUTER)
# Additions and cleanup by Kevin Teman of Artificially Intelligent Matchmaker. http://www.aimm.online
#
##########################################

set -e
set -o pipefail

#################[ Tests: helps workaround any future bugs in Xcode ]########
#
DEBUG_THIS_SCRIPT="false"

if [ $DEBUG_THIS_SCRIPT = "true" ]
then
    echo "########### TESTS #############"
    echo "Use the following variables when debugging this script; note that they may change on recursions"
    echo "BUILD_DIR = $BUILD_DIR"
    echo "BUILD_ROOT = $BUILD_ROOT"
    echo "CONFIGURATION_BUILD_DIR = $CONFIGURATION_BUILD_DIR"
    echo "BUILT_PRODUCTS_DIR = $BUILT_PRODUCTS_DIR"
    echo "CONFIGURATION_TEMP_DIR = $CONFIGURATION_TEMP_DIR"
    echo "TARGET_BUILD_DIR = $TARGET_BUILD_DIR"
fi

#####################[ part 1 ]##################
# First, work out the BASESDK version number (NB: Apple ought to report this, but they hide it)
#    (incidental: searching for substrings in sh is a nightmare! Sob)

SDK_VERSION=$(echo ${SDK_NAME} | grep -o '\d\{1,2\}\.\d\{1,2\}$')

# Next, work out if we're in SIM or DEVICE

if [ ${PLATFORM_NAME} = "iphonesimulator" ]
then
    OTHER_SDK_TO_BUILD=iphoneos${SDK_VERSION}
    OTHER_ARCH="amrv7,arm64"
else
    OTHER_SDK_TO_BUILD=iphonesimulator${SDK_VERSION}
    OTHER_ARCH="x86_64"
fi

echo "XCode has selected SDK: ${PLATFORM_NAME} with version: ${SDK_VERSION} (although back-targetting: ${IPHONEOS_DEPLOYMENT_TARGET})"
echo "...therefore, OTHER_SDK_TO_BUILD = ${OTHER_SDK_TO_BUILD}"
#
#####################[ end of part 1 ]##################

#####################[ part 2 ]##################
#
# IF this is the original invocation, invoke WHATEVER other builds are required
#
# Xcode is already building ONE target...
#
# ...but this is a LIBRARY, so Apple is wrong to set it to build just one.
# ...we need to build ALL targets
# ...we MUST NOT re-build the target that is ALREADY being built: Xcode WILL CRASH YOUR COMPUTER if you try this (infinite recursion!)
#
#
# So: build ONLY the missing platforms/configurations.

if [ "true" == ${ALREADYINVOKED:-false} ]
then
    echo "RECURSION: I am NOT the root invocation, so I'm NOT going to recurse"
else
    
    
    # CRITICAL:
    # Prevent infinite recursion (Xcode sucks)
    export ALREADYINVOKED="true"
    
    echo "RECURSION: I am the root ... recursing all missing build targets NOW..."
    echo "RECURSION: ...about to invoke: xcodebuild -configuration \"${CONFIGURATION}\" -project \"${PROJECT_NAME}.xcodeproj\" -target \"${TARGET_NAME}\" -sdk \"${OTHER_SDK_TO_BUILD}\" ${ACTION} RUN_CLANG_STATIC_ANALYZER=NO" BUILD_DIR=\"${BUILD_DIR}\" BUILD_ROOT=\"${BUILD_ROOT}\" SYMROOT=\"${SYMROOT}\"
    
    xcodebuild -configuration "${CONFIGURATION}" -project "${PROJECT_NAME}.xcodeproj" -target "${TARGET_NAME}" -sdk "${OTHER_SDK_TO_BUILD}" -arch ${OTHER_ARCH} ${ACTION} RUN_CLANG_STATIC_ANALYZER=NO BUILD_DIR="${BUILD_DIR}" BUILD_ROOT="${BUILD_ROOT}" SYMROOT="${SYMROOT}" SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
    
    ACTION="build"
    
    #Merge all platform binaries as a fat binary for each configurations.
    
    # Calculate where the (multiple) built files are coming from:
    CURRENTCONFIG_DEVICE_DIR=${SYMROOT}/${CONFIGURATION}-iphoneos
    CURRENTCONFIG_SIMULATOR_DIR=${SYMROOT}/${CONFIGURATION}-iphonesimulator
    
    echo "Taking device build from: ${CURRENTCONFIG_DEVICE_DIR}"
    echo "Taking simulator build from: ${CURRENTCONFIG_SIMULATOR_DIR}"
    
    CREATING_UNIVERSAL_DIR=${SYMROOT}/${CONFIGURATION}-universal
    echo "...I will output a universal build to: ${CREATING_UNIVERSAL_DIR}"
    
    # ... remove the products of previous runs of this script
    #      NB: this directory is ONLY created by this script - it should be safe to delete!
    
    rm -rf "${CREATING_UNIVERSAL_DIR}/${FULL_PRODUCT_NAME}"
    mkdir -p "${CREATING_UNIVERSAL_DIR}"
    
    



    # Build either an XCFramework or a fat library.

    if [[ "${FULL_PRODUCT_NAME}" == *".framework"* ]];
    then
        #Generate xcframework for both arches
        echo "lipo: for current framework configuration (${CONFIGURATION}) creating output file: ${CREATING_UNIVERSAL_DIR}/${FULL_PRODUCT_NAME}"
        xcodebuild -create-xcframework -framework "${CURRENTCONFIG_DEVICE_DIR}/${FULL_PRODUCT_NAME}" -framework "${CURRENTCONFIG_SIMULATOR_DIR}/${FULL_PRODUCT_NAME}" -output "${CREATING_UNIVERSAL_DIR}/${EXECUTABLE_NAME}.xcframework"

    else
        #Generate library for both arches
        echo "lipo: for current library configuration (${CONFIGURATION}) creating output file: ${CREATING_UNIVERSAL_DIR}/${FULL_PRODUCT_NAME}"
        xcrun -sdk iphoneos lipo -create -output "${CREATING_UNIVERSAL_DIR}/${FULL_PRODUCT_NAME}" "${CURRENTCONFIG_DEVICE_DIR}/${FULL_PRODUCT_NAME}" "${CURRENTCONFIG_SIMULATOR_DIR}/${FULL_PRODUCT_NAME}"

    fi




    #########
    #
    # Added: StackOverflow suggestion to also copy "include" files
    #    (untested, but should work OK)
    #
    echo "Fetching headers from ${PUBLIC_HEADERS_FOLDER_PATH}"
    echo "  (if you embed your library project in another project, you will need to add"
    echo "   a "User Search Headers" build setting of: (NB INCLUDE THE DOUBLE QUOTES BELOW!)"
    echo '        "$(TARGET_BUILD_DIR)/usr/local/include/"'

    echo "Check to see if Objective-C headers should be copied."
    CURRENT_OBJECTIVE_C_HEADERS="${CURRENTCONFIG_DEVICE_DIR}${PUBLIC_HEADERS_FOLDER_PATH}"
    if [ -d "${CURRENT_OBJECTIVE_C_HEADERS}" ]
    then
        
        # Copy headers
        NEW_LOCATION="${CREATING_UNIVERSAL_DIR}${PUBLIC_HEADERS_FOLDER_PATH}"

        echo "Proceeding to copy Objective-C headers from: ${CURRENT_OBJECTIVE_C_HEADERS}\nCopying to: ${NEW_LOCATION}"

        mkdir -p "${NEW_LOCATION}"
        cp -rf "${CURRENT_OBJECTIVE_C_HEADERS}/." "${CREATING_UNIVERSAL_DIR}${PUBLIC_HEADERS_FOLDER_PATH}"
    fi


    echo "Check to see if Objective-C includes should be copied."
    CURRENT_OBJECTIVE_C_INCLUDES="${CURRENTCONFIG_DEVICE_DIR}/include/${PRODUCT_MODULE_NAME}"
    if [ -d "${CURRENT_OBJECTIVE_C_INCLUDES}" ]
    then
        
        # Copy includes
        NEW_LOCATION="${CREATING_UNIVERSAL_DIR}/include/${PRODUCT_MODULE_NAME}"

        echo "Proceeding to copy Objective-C includes from: ${CURRENT_OBJECTIVE_C_INCLUDES}\nCopying to: ${NEW_LOCATION}"

        mkdir -p "${NEW_LOCATION}"
        cp -rf "${CURRENT_OBJECTIVE_C_INCLUDES}/." "${NEW_LOCATION}"
    fi


    
    
    
    # Copy swiftmodules to new universal directory
    SWIFT_MODULE_FILENAME="${PRODUCT_MODULE_NAME}.swiftmodule"
    OLD_SWIFT_MODULE_PATH="${CURRENTCONFIG_DEVICE_DIR}/${SWIFT_MODULE_FILENAME}"
    NEW_SWIFT_MODULE_PATH="${CREATING_UNIVERSAL_DIR}/${SWIFT_MODULE_FILENAME}"
    
    if [ -d "${OLD_SWIFT_MODULE_PATH}" ]
    then
        cp -rf "${OLD_SWIFT_MODULE_PATH}" "${NEW_SWIFT_MODULE_PATH}"
    fi
    
    
    
    # Copy to distribute folder if we are in an archive build.
    if [[ "${CREATING_UNIVERSAL_DIR}" == *"Archive"* ]];
    then
        DISTRIBUTED_LIBRARY_FOLDER="${PROJECT_DIR}/../Build/Distribute"
        
        echo "We are in an archive build. Copying universal library to distributed folder: ${DISTRIBUTED_LIBRARY_FOLDER}"
        
        # Copy library to distribute folder.
        cp -rf "${CREATING_UNIVERSAL_DIR}/${FULL_PRODUCT_NAME}" "${DISTRIBUTED_LIBRARY_FOLDER}/${FULL_PRODUCT_NAME}"
        
        DISTRIBUTED_SWIFT_HEADERS_PATH="${DISTRIBUTED_LIBRARY_FOLDER}/${SWIFT_MODULE_FILENAME}"
        
        # Copy swift module interfaces to distribute folder.
        if [ -d "${NEW_SWIFT_MODULE_PATH}" ]
        then
            rm -rf "${DISTRIBUTED_SWIFT_HEADERS_PATH}"
            cp -rf "${NEW_SWIFT_MODULE_PATH}" "${DISTRIBUTED_SWIFT_HEADERS_PATH}"
        fi
        
        # Copy Objective-C headers to distribute folder.
        if [ -d "${CURRENT_OBJECTIVE_C_HEADERS}" ]
        then
            DISTRIBUTED_LIBRARY_HEADERS_FOLDER="${DISTRIBUTED_LIBRARY_FOLDER}/${PUBLIC_HEADERS_FOLDER_PATH}"
            mkdir -p "${DISTRIBUTED_LIBRARY_HEADERS_FOLDER}"
            cp -rf "${CURRENT_OBJECTIVE_C_HEADERS}/." "${DISTRIBUTED_LIBRARY_HEADERS_FOLDER}"
        fi
    fi
    
fi