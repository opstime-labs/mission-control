#include "sensor_hal.h"
#include <stdlib.h>

int main(void) {
    sensor_frame_t* frame = (sensor_frame_t*)malloc(sizeof(sensor_frame_t));
    if (frame == NULL) {
        return 1;
    }

    /* Null pointer guard check */
    if (read_sensor_frame("/dev/i2c-1", 1, NULL) != -1) {
        free(frame);
        return 1;
    }

    /* Valid frame read (handles both physical RPi /dev/i2c-1 and CI fallback) */
    int rc = read_sensor_frame("/dev/i2c-1", 42, frame);
    if (rc != 0 || frame->sequence_id != 42 || frame->bus_voltage_mv != 3300) {
        free(frame);
        return 1;
    }

    free(frame);
    return 0;
}