// smctemp.c — читает датчики температуры из SMC (Apple Silicon, root не нужен).
// Вывод: JSON {"cpu": <макс. из Tp*/Te*>, "gpu": <макс. из Tg*>}
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

typedef struct {
    uint8_t  major, minor, build, reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t       key;
    SMCVersion     vers;
    SMCKeyInfoData info;
    uint32_t       status;
    uint8_t        selector;
    uint8_t        data8;
    uint16_t       data16;
    uint32_t       data32;
    uint8_t        bytes[32];
} SMCParamStruct;

#define SMC_CMD_READ_BYTES   5
#define SMC_CMD_READ_INDEX   8
#define SMC_CMD_READ_KEYINFO 9
#define KERNEL_INDEX_SMC     2

static io_connect_t conn;

static uint32_t key4(const char *k) {
    return ((uint32_t)(unsigned char)k[0] << 24) | ((uint32_t)(unsigned char)k[1] << 16) |
           ((uint32_t)(unsigned char)k[2] << 8) | (uint32_t)(unsigned char)k[3];
}

static int smc_call(SMCParamStruct *in, SMCParamStruct *out) {
    size_t size = sizeof(SMCParamStruct);
    memset(out, 0, sizeof(SMCParamStruct));
    return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, sizeof(SMCParamStruct), out, &size);
}

static int smc_keyinfo(const char *k, uint32_t *type, uint32_t *size) {
    SMCParamStruct in, out;
    memset(&in, 0, sizeof in);
    in.key = key4(k);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.status != 0) return -1;
    *type = out.info.dataType;
    *size = out.info.dataSize;
    return 0;
}

static int smc_read(const char *k, uint8_t *buf, uint32_t size) {
    SMCParamStruct in, out;
    memset(&in, 0, sizeof in);
    in.key = key4(k);
    in.data8 = SMC_CMD_READ_BYTES;
    in.info.dataSize = size;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.status != 0) return -1;
    memcpy(buf, out.bytes, size > 32 ? 32 : size);
    return 0;
}

static int smc_key_at(uint32_t index, char *k) {
    SMCParamStruct in, out;
    memset(&in, 0, sizeof in);
    in.data8 = SMC_CMD_READ_INDEX;
    in.data32 = index;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.status != 0) return -1;
    k[0] = (char)((out.key >> 24) & 0xFF);
    k[1] = (char)((out.key >> 16) & 0xFF);
    k[2] = (char)((out.key >> 8) & 0xFF);
    k[3] = (char)(out.key & 0xFF);
    k[4] = 0;
    return 0;
}

static uint32_t smc_key_count(void) {
    uint8_t buf[4];
    if (smc_read("#KEY", buf, 4) != 0) return 0;
    return ((uint32_t)buf[0] << 24) | ((uint32_t)buf[1] << 16) | ((uint32_t)buf[2] << 8) | buf[3];
}

// Значение по типу: Apple Silicon отдаёт температуры как float ('flt '), fallback — fixed point.
static double val_of(uint32_t type, const uint8_t *b) {
    if (type == 0x666C7420) { // 'flt '
        float f;
        memcpy(&f, b, 4);
        return f;
    }
    if (type == 0x73703738 || type == 0x66703166) // 'sp78', 'fp1f'
        return b[0] + b[1] / 256.0;
    if (type == 0x66706532) // 'fpe2'
        return (int16_t)((b[0] << 8) | b[1]) / 64.0;
    return -1000;
}

int main(int argc, char **argv) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) { fprintf(stderr, "no AppleSMC\n"); return 2; }
    if (IOServiceOpen(service, mach_task_self(), 0, &conn) != KERN_SUCCESS) { fprintf(stderr, "open failed\n"); return 2; }
    IOObjectRelease(service);
    if (IOConnectCallStructMethod(conn, 0, NULL, 0, NULL, NULL) != KERN_SUCCESS) { fprintf(stderr, "uc open failed\n"); return 2; }

    if (argc > 1 && strcmp(argv[1], "list") == 0) {
        uint32_t count = smc_key_count();
        printf("keys=%u\n", count);
        char k[5];
        for (uint32_t i = 0; i < count && i < 10000; i++) {
            if (smc_key_at(i, k) != 0) continue;
            if (k[0] != 'T') continue;
            uint32_t type = 0, size = 0;
            if (smc_keyinfo(k, &type, &size) != 0) continue;
            uint8_t b[32] = {0};
            if (smc_read(k, b, size) != 0) continue;
            double v = val_of(type, b);
            printf("%s type=%c%c%c%c size=%u val=%.1f\n", k,
                   (type >> 24) & 0xFF, (type >> 16) & 0xFF, (type >> 8) & 0xFF, type & 0xFF, size, v);
        }
        return 0;
    }

    uint32_t count = smc_key_count();
    if (count == 0) { fprintf(stderr, "no key count\n"); return 2; }
    double cpu = -1000, gpu = -1000;
    char k[5];
    for (uint32_t i = 0; i < count && i < 10000; i++) {
        if (smc_key_at(i, k) != 0) continue;
        if (k[0] != 'T') continue;
        int cpu_like = (strncmp(k, "Tp", 2) == 0 || strncmp(k, "Te", 2) == 0);
        int gpu_like = (strncmp(k, "Tg", 2) == 0);
        if (!cpu_like && !gpu_like) continue;
        uint32_t type = 0, size = 0;
        if (smc_keyinfo(k, &type, &size) != 0) continue;
        if (size < 1 || size > 8) continue;
        uint8_t b[32] = {0};
        if (smc_read(k, b, size) != 0) continue;
        double v = val_of(type, b);
        if (v < 5 || v > 150) continue;
        if (cpu_like && v > cpu) cpu = v;
        if (gpu_like && v > gpu) gpu = v;
    }
    printf("{\"cpu\": %.1f, \"gpu\": %.1f}\n", cpu, gpu);
    return 0;
}
