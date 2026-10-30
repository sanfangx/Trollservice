#include "coretrust_bug.h"
#include "FAT.h"
#include "MachO.h"
#include "FileStream.h"
#include "Host.h"
#include <copyfile.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

/**
 * fastPathSign_ios.c
 *
 * 在 iOS 设备端由 TrollService 的 daemon_root_helper 调用，
 * 专门用于对安装到 /var/mobile/Documents/service/<id>/bin/<binary_name> 的目标程序
 * 注入 CoreTrust 根证书绕过签名 (CVE-2023-41991)。
 *
 * 注意：调用此工具前，daemon_root_helper 已先通过 iOS 端 ldid -S<entitlements.plist>
 * 完成了 Ad-Hoc 签名与权限块注入，因此此处直接提取最优 arm64/arm64e Slice 并应用
 * apply_coretrust_bypass。
 */

static char *extract_preferred_slice(const char *fatPath) {
    FAT *fat = fat_init_from_path(fatPath);
    if (!fat) return NULL;
    MachO *macho = fat_find_preferred_slice(fat);
    if (!macho) {
        macho = fat_find_slice(fat, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_V8);
        if (!macho) {
            macho = fat_find_slice(fat, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL);
        }
    }
    if (!macho) {
        fat_free(fat);
        return NULL;
    }

    char *temp = strdup("/tmp/trollservice_slice_XXXXXX");
    int fd = mkstemp(temp);
    if (fd < 0) {
        fat_free(fat);
        free(temp);
        return NULL;
    }

    MemoryStream *outStream = file_stream_init_from_path(
        temp, 0, 0, FILE_STREAM_FLAG_WRITABLE | FILE_STREAM_FLAG_AUTO_EXPAND);
    if (!outStream) {
        fat_free(fat);
        close(fd);
        unlink(temp);
        free(temp);
        return NULL;
    }

    MemoryStream *machoStream = macho_get_stream(macho);
    memory_stream_copy_data(machoStream, 0, outStream, 0, memory_stream_get_size(machoStream));

    fat_free(fat);
    memory_stream_free(outStream);
    close(fd);
    return temp;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: fastPathSign <macho_binary_path>\n");
        return -1;
    }

    const char *input = argv[argc - 1];

    char *machoPath = extract_preferred_slice(input);
    if (!machoPath) {
        fprintf(stderr, "Failed extracting best arm64 slice from %s\n", input);
        return -1;
    }

    int r = apply_coretrust_bypass(machoPath);
    if (r != 0) {
        fprintf(stderr, "Failed applying CoreTrust bypass (code=%d)\n", r);
        unlink(machoPath);
        free(machoPath);
        return r;
    }

    if (copyfile(machoPath, input, 0, COPYFILE_ALL | COPYFILE_MOVE | COPYFILE_UNLINK) == 0) {
        chmod(input, 0755);
        printf("Applied CoreTrust Bypass to target service binary: %s\n", input);
    } else {
        perror("copyfile");
        unlink(machoPath);
        free(machoPath);
        return -1;
    }

    free(machoPath);
    return 0;
}
