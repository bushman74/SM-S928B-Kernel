#ifndef __SEC_QC_USER_RESET_H__
#define __SEC_QC_USER_RESET_H__

#include "sec_qc_user_reset_type.h"
#include "sec_qc_dbg_partition_type.h"

#if IS_ENABLED(CONFIG_SEC_QC_USER_RESET)
extern struct debug_reset_header *sec_qc_user_reset_get_reset_header(void);
extern int sec_qc_get_reset_write_cnt(void);
extern ap_health_t *sec_qc_ap_health_data_read(void);
extern int sec_qc_ap_health_data_write(ap_health_t *data);
extern int sec_qc_ap_health_data_write_delayed(ap_health_t *data);
extern unsigned int sec_qc_reset_reason_get(void);
extern const char *sec_qc_reset_reason_to_str(unsigned int reason);
#else
static inline struct debug_reset_header *sec_qc_user_reset_get_reset_header(void) { return NULL; }
static inline int sec_qc_get_reset_write_cnt(void) { return 0; }
static inline ap_health_t *sec_qc_ap_health_data_read(void) { return NULL; }
static inline int sec_qc_ap_health_data_write(ap_health_t *data) { return 0; }
static inline int sec_qc_ap_health_data_write_delayed(ap_health_t *data) { return 0; }
static inline unsigned int sec_qc_reset_reason_get(void) { return 0xFFEEFFEE; }
static inline const char *sec_qc_reset_reason_to_str(unsigned int reason) { return "NP"; }
#endif

#endif // __SEC_QC_USER_RESET_H__
