# Custom FindThreads for Android
# Android NDK has pthread support built-in, but CMake's FindThreads module
# may fail to detect it. This module provides a workaround.

# This file should be included before any find_package(Threads) calls
# It sets up the necessary variables and creates the Threads::Threads target

if(ANDROID)
    # On Android, pthread is always available (built into libc)
    # Set these variables before FindThreads is called
    set(CMAKE_THREAD_LIBS_INIT "" CACHE INTERNAL "Thread libraries on Android")
    set(CMAKE_HAVE_THREADS_LIBRARY 1 CACHE INTERNAL "Android has threads support")
    set(CMAKE_USE_WIN32_THREADS_INIT 0 CACHE INTERNAL "Do not use Win32 threads on Android")
    set(CMAKE_USE_PTHREADS_INIT 1 CACHE INTERNAL "Use pthreads on Android")
    set(THREADS_PREFER_PTHREAD_FLAG ON CACHE INTERNAL "Prefer pthread flag on Android")
    set(Threads_FOUND TRUE CACHE INTERNAL "Threads are available on Android")
    
    # Create Threads::Threads interface library if it doesn't exist
    if(NOT TARGET Threads::Threads)
        add_library(Threads::Threads INTERFACE IMPORTED)
        # On Android, pthread functions are in libc, no need to link anything
        # But we set the flag for compatibility
        set_target_properties(Threads::Threads PROPERTIES
            INTERFACE_COMPILE_OPTIONS "-pthread"
        )
    endif()
    
    message(STATUS "Threads: Using Android built-in pthread support")
endif()

