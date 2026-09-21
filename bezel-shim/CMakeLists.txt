cmake_minimum_required(VERSION 3.21)

project(bezel-shim
        VERSION 0.2.0
        DESCRIPTION "Bezel — Qt 6 shim exposing a stable C ABI for Racket FFI"
        LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

set(CMAKE_AUTOMOC ON)

file(GLOB BEZEL_GENERATED ${CMAKE_CURRENT_SOURCE_DIR}/src/generated/*.cpp)

set(BEZEL_SOURCES
    src/core.cpp
    src/widgets.cpp
    src/layouts.cpp
    src/signals.cpp
    src/signalsink.h
    ${BEZEL_GENERATED}
)

add_library(bezel SHARED ${BEZEL_SOURCES})
target_compile_definitions(bezel PRIVATE QT_NO_CAST_FROM_ASCII)
target_include_directories(bezel PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(bezel PRIVATE Qt6::Widgets)

set_target_properties(bezel PROPERTIES
    VERSION   ${PROJECT_VERSION}
    SOVERSION ${PROJECT_VERSION_MAJOR}
    PUBLIC_HEADER include/bezel/bezel.h
    MACOSX_RPATH ON)

# Keep development builds convenient while making installed/repackaged
# binaries relocatable. Release packaging places Qt beside libbezel on
# Linux and under the app Frameworks directory on macOS.
if(APPLE AND Qt6_DIR)
    set(BEZEL_QT_LIB_DIR "${Qt6_DIR}/../..")
    get_filename_component(BEZEL_QT_LIB_DIR "${BEZEL_QT_LIB_DIR}" ABSOLUTE)
    set_target_properties(bezel PROPERTIES
        BUILD_RPATH   "${BEZEL_QT_LIB_DIR}"
        INSTALL_RPATH "@loader_path")
elseif(UNIX)
    set_target_properties(bezel PROPERTIES
        INSTALL_RPATH "$ORIGIN")
endif()

# Windows development builds keep the core Qt DLLs next to bezel.dll so
# ordinary checkout runs work without editing PATH. The release packager
# expands this with the required platform plugins through windeployqt.
if(WIN32)
    add_custom_command(TARGET bezel POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_FILE:Qt6::Core>
                $<TARGET_FILE:Qt6::Gui>
                $<TARGET_FILE:Qt6::Widgets>
                $<TARGET_FILE_DIR:bezel>)
endif()

# A tiny executable gives Qt's deployment tools a normal executable to
# inspect. It is never shipped as part of the public API; packaging jobs
# use it to discover the transitive runtime dependency set.
add_executable(bezel-deploy-probe tools/deploy_probe.cpp)
target_include_directories(bezel-deploy-probe PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(bezel-deploy-probe PRIVATE bezel)
if(APPLE)
    set_target_properties(bezel-deploy-probe PROPERTIES MACOSX_BUNDLE TRUE)
endif()

install(TARGETS bezel
        LIBRARY DESTINATION lib
        RUNTIME DESTINATION bin
        PUBLIC_HEADER DESTINATION include/bezel)
