set(TARGET whisper-server)
add_executable(${TARGET} server.cpp httplib.h websocket.h)

include(DefaultTargetOptions)

target_link_libraries(${TARGET} PRIVATE whisper ${CMAKE_THREAD_LIBS_INIT})

if (WIN32)
    target_link_libraries(${TARGET} PRIVATE ws2_32)
endif()

# Ensure threading support
find_package(Threads REQUIRED)
target_link_libraries(${TARGET} PRIVATE Threads::Threads)

install(TARGETS ${TARGET} RUNTIME)
