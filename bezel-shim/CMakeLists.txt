cmake_minimum_required(VERSION 3.21)

project(bezel-shim
        VERSION 0.1.0
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

# macOS: brew Qt frameworks carry @rpath install names; give the
# build-tree library an rpath into the Qt lib directory so dlopen from
# the Racket FFI resolves them without install steps.
if(APPLE AND Qt6_DIR)
    set(BEZEL_QT_LIB_DIR "${Qt6_DIR}/../..")
    get_filename_component(BEZEL_QT_LIB_DIR "${BEZEL_QT_LIB_DIR}" ABSOLUTE)
    set_target_properties(bezel PROPERTIES
        BUILD_RPATH   "${BEZEL_QT_LIB_DIR}"
        INSTALL_RPATH "${BEZEL_QT_LIB_DIR};@loader_path")
endif()

# Windows: the BEZEL_EXPORT macro in bezel.h covers dllexport; keep the
# Qt DLLs next to the library for out-of-the-box `racket` runs.
if(WIN32)
    add_custom_command(TARGET bezel POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_FILE:Qt6::Core>
                $<TARGET_FILE:Qt6::Gui>
                $<TARGET_FILE:Qt6::Widgets>
                $<TARGET_FILE_DIR:bezel>)
endif()

install(TARGETS bezel
        LIBRARY DESTINATION lib
        RUNTIME DESTINATION bin
        PUBLIC_HEADER DESTINATION include/bezel)
