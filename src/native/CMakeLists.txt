cmake_minimum_required(VERSION 3.16)
project(sensor_hal C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_compile_options(-Wall -Wextra -Werror -fstack-protector-strong)

# Shared library for .NET P/Invoke runtime binding
add_library(sensor_hal SHARED sensor_hal.c)

# Standalone test harness for Valgrind memory-leak verification
add_executable(test_sensor_hal test_sensor_hal.c sensor_hal.c)