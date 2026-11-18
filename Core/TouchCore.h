#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
  uint64_t samples, intervals, latency_count, cancelled, strokes;
  int32_t peak_fingers;
  double median_hz, p95_gap_ms, mean_delivery_ms, straight_rms_pt;
} TCStats;
void* tc_create(void);
void tc_destroy(void*);
void tc_reset(void*);
void tc_begin(void*, int64_t);
void tc_sample(void*, int64_t, double, double, double, double);
void tc_end(void*, int64_t, int32_t);
TCStats tc_stats(void*);
#ifdef __cplusplus
}
#endif
