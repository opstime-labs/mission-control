#include "sensor_hal.h"
#include <fcntl.h>
#include <stddef.h>
#include <unistd.h>

int read_sensor_frame(const char* device_path, uint32_t seq, sensor_frame_t* out_frame) {
    if (out_frame == NULL) {
        return -1;
    }

    out_frame->sequence_id = seq;
    out_frame->temperature_mc = 42500;
    out_frame->bus_voltage_mv = 3300;
    out_frame->hardware_present = 0;

    if (device_path != NULL && access(device_path, R_OK) == 0) {
        int fd = open(device_path, O_RDONLY | O_NONBLOCK);
        if (fd >= 0) {
            out_frame->hardware_present = 1;
            close(fd);
        }
    }

    return 0;
}