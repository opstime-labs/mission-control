#ifndef SENSOR_HAL_H
#define SENSOR_HAL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t sequence_id;
    int32_t temperature_mc;   /* Millidegrees Celsius */
    uint16_t bus_voltage_mv;  /* Millivolts */
    uint8_t hardware_present; /* 1 if /dev/i2c-1 opened, 0 if simulated */
} sensor_frame_t;

int read_sensor_frame(const char* device_path, uint32_t seq, sensor_frame_t* out_frame);

#ifdef __cplusplus
}
#endif

#endif /* SENSOR_HAL_H */