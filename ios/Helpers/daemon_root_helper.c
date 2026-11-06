#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <fts.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "spawn_root.h"

#define DEFAULT_SERVICE_ROOT "/var/mobile/Documents/service"
#define ROOT_CONFIG_PATH "/var/mobile/Documents/.trollservice_root"
#define MOBILE_UID 501
#define MOBILE_GID 501
#define MAX_LOG_FILE_BYTES (10 * 1024 * 1024) /* 10 MB 日志自动轮转阈值 */

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE (4 * PATH_MAX)
#endif

extern int proc_pidpath(int pid, void* buffer, uint32_t buffersize);

static char g_service_root[PATH_MAX] = {0};

/**
 * 安全输出 JSON 转义字符串（防止换行符、双引号、反斜杠等破坏 JSON 格式）
 */
static void print_json_escaped(const char* str) {
    if (!str) return;
    for (const unsigned char* p = (const unsigned char*)str; *p; p++) {
        switch (*p) {
            case '"':  fputs("\\\"", stdout); break;
            case '\\': fputs("\\\\", stdout); break;
            case '\b': fputs("\\b", stdout); break;
            case '\f': fputs("\\f", stdout); break;
            case '\n': fputs("\\n", stdout); break;
            case '\r': fputs("\\r", stdout); break;
            case '\t': fputs("\\t", stdout); break;
            default:
                if (*p < 0x20) {
                    printf("\\u%04x", (unsigned int)*p);
                } else {
                    putchar(*p);
                }
                break;
        }
    }
}

static void reply_json_error(const char* err_msg) {
    fputs("{\"ok\":false,\"error\":\"", stdout);
    print_json_escaped(err_msg ? err_msg : "未知错误");
    fputs("\"}\n", stdout);
    fflush(stdout);
}

/**
 * 校验服务标识或可执行文件名是否安全（防止路径穿越 ../ 及 XML 注入）
 */
static bool is_safe_identifier(const char* name) {
    if (!name || name[0] == '\0' || name[0] == '.') return false;
    size_t len = strlen(name);
    if (len > 64) return false;
    for (size_t i = 0; i < len; i++) {
        char c = name[i];
        bool ok = (c >= 'a' && c <= 'z') ||
                  (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') ||
                  c == '_' || c == '-' || c == '.';
        if (!ok) return false;
    }
    if (strstr(name, "..") != NULL) return false;
    return true;
}

/* 递归创建目录并赋予 mobile 权限 */
static int mkdir_p(const char* path, mode_t mode) {
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "%s", path);
    size_t len = strlen(tmp);
    if (len == 0) return -1;
    if (tmp[len - 1] == '/') tmp[len - 1] = '\0';

    for (char* p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, mode);
            chown(tmp, MOBILE_UID, MOBILE_GID);
            *p = '/';
        }
    }
    if (mkdir(tmp, mode) != 0 && errno != EEXIST) {
        return -1;
    }
    chown(tmp, MOBILE_UID, MOBILE_GID);
    return 0;
}

static const char* get_service_root(void) {
    if (g_service_root[0] != '\0') {
        return g_service_root;
    }
    const char* env_root = getenv("TROLLSERVICE_ROOT");
    if (env_root && env_root[0] != '\0') {
        strncpy(g_service_root, env_root, sizeof(g_service_root) - 1);
        g_service_root[sizeof(g_service_root) - 1] = '\0';
        return g_service_root;
    }
    FILE* fp = fopen(ROOT_CONFIG_PATH, "r");
    if (fp) {
        char buf[PATH_MAX] = {0};
        if (fgets(buf, sizeof(buf) - 1, fp)) {
            size_t len = strlen(buf);
            while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r' || buf[len - 1] == ' ')) {
                buf[--len] = '\0';
            }
            if (len > 0) {
                strncpy(g_service_root, buf, sizeof(g_service_root) - 1);
                g_service_root[sizeof(g_service_root) - 1] = '\0';
                fclose(fp);
                return g_service_root;
            }
        }
        fclose(fp);
    }
    strncpy(g_service_root, DEFAULT_SERVICE_ROOT, sizeof(g_service_root) - 1);
    g_service_root[sizeof(g_service_root) - 1] = '\0';
    return g_service_root;
}

static int set_service_root_internal(const char* new_root) {
    if (!new_root || new_root[0] != '/' || strstr(new_root, "..") != NULL) {
        return -1;
    }
    if (mkdir_p(new_root, 0755) != 0) {
        return -2;
    }
    chown(new_root, MOBILE_UID, MOBILE_GID);
    FILE* fp = fopen(ROOT_CONFIG_PATH, "w");
    if (fp) {
        fprintf(fp, "%s\n", new_root);
        fclose(fp);
        chown(ROOT_CONFIG_PATH, MOBILE_UID, MOBILE_GID);
        chmod(ROOT_CONFIG_PATH, 0644);
    }
    strncpy(g_service_root, new_root, sizeof(g_service_root) - 1);
    g_service_root[sizeof(g_service_root) - 1] = '\0';
    return 0;
}

static int cmd_set_root(const char* new_root) {
    int res = set_service_root_internal(new_root);
    if (res == -1) {
        reply_json_error("无效路径（必须是以 / 开头的绝对路径且不含 ..）");
        return 1;
    } else if (res == -2) {
        char msg[PATH_MAX + 64];
        snprintf(msg, sizeof(msg), "无法创建目录: %s", new_root ? new_root : "");
        reply_json_error(msg);
        return 1;
    }
    fputs("{\"ok\":true,\"root\":\"", stdout);
    print_json_escaped(new_root);
    fputs("\"}\n", stdout);
    return 0;
}

/* XNU Private memorystatus_control API for Jetsam exemption */
#define MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK 5
#define MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT 6
extern int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void* buffer, size_t buffersize);

/* Darwin proc_pid_rusage for physical memory footprint */
#ifndef RUSAGE_INFO_V4
#define RUSAGE_INFO_V4 4
typedef void* rusage_info_t;
struct rusage_info_v4 {
    uint8_t ri_uuid[16];
    uint64_t ri_user_time;
    uint64_t ri_system_time;
    uint64_t ri_pkg_idle_wkups;
    uint64_t ri_interrupt_wkups;
    uint64_t ri_pageins;
    uint64_t ri_wired_size;
    uint64_t ri_resident_size;
    uint64_t ri_phys_footprint;
    uint64_t ri_proc_start_abstime;
    uint64_t ri_proc_exit_abstime;
    uint64_t ri_child_user_time;
    uint64_t ri_child_system_time;
    uint64_t ri_child_pkg_idle_wkups;
    uint64_t ri_child_interrupt_wkups;
    uint64_t ri_child_pageins;
    uint64_t ri_child_elapsed_abstime;
    uint64_t ri_diskio_bytesread;
    uint64_t ri_diskio_byteswritten;
    uint64_t ri_cpu_time_qos_default;
    uint64_t ri_cpu_time_qos_maintenance;
    uint64_t ri_cpu_time_qos_background;
    uint64_t ri_cpu_time_qos_utility;
    uint64_t ri_cpu_time_qos_legacy;
    uint64_t ri_cpu_time_qos_user_initiated;
    uint64_t ri_cpu_time_qos_user_interactive;
    uint64_t ri_billed_system_time;
    uint64_t ri_serviced_system_time;
    uint64_t ri_logical_writes;
    uint64_t ri_lifetime_max_phys_footprint;
    uint64_t ri_instructions;
    uint64_t ri_cycles;
    uint64_t ri_billed_energy;
    uint64_t ri_serviced_energy;
    uint64_t ri_interval_max_phys_footprint;
    uint64_t ri_runnable_time;
};
#endif
extern int proc_pid_rusage(int pid, int flavor, rusage_info_t* buffer);

extern char** environ;

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif

#ifndef POSIX_SPAWN_SETSID
#define POSIX_SPAWN_SETSID 0x0400
#endif

extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

static uint32_t swap_uint32(uint32_t val) {
    return ((val >> 24) & 0x000000FF) |
           ((val >> 8)  & 0x0000FF00) |
           ((val << 8)  & 0x00FF0000) |
           ((val << 24) & 0xFF000000);
}

/**
 * 原子化安全复制文件：
 * 先写入同目录临时文件并 fsync，随后 unlink 旧目标文件再 rename 替换。
 * 强制分配全新 inode/vnode，彻底规避 iOS XNU 内核 UBC 代码签名缓存污染导致 SIGKILL (CODESIGNING)。
 */
static int copy_file_binary(const char* src, const char* dst) {
    if (!src || !dst || strcmp(src, dst) == 0) return -1;

    int in_fd = open(src, O_RDONLY);
    if (in_fd < 0) return -1;

    char tmp_dst[PATH_MAX];
    int n_tmp = snprintf(tmp_dst, sizeof(tmp_dst), "%s.tmp.%d", dst, (int)getpid());
    if (n_tmp < 0 || (size_t)n_tmp >= sizeof(tmp_dst)) {
        close(in_fd);
        return -1;
    }
    unlink(tmp_dst);

    int out_fd = open(tmp_dst, O_WRONLY | O_CREAT | O_EXCL | O_TRUNC, 0755);
    if (out_fd < 0) {
        close(in_fd);
        return -1;
    }

    char buf[65536];
    ssize_t n;
    while ((n = read(in_fd, buf, sizeof(buf))) > 0) {
        char* ptr = buf;
        ssize_t remaining = n;
        while (remaining > 0) {
            ssize_t written = write(out_fd, ptr, (size_t)remaining);
            if (written <= 0) {
                close(in_fd);
                close(out_fd);
                unlink(tmp_dst);
                return -1;
            }
            remaining -= written;
            ptr += written;
        }
    }

    if (n < 0) {
        close(in_fd);
        close(out_fd);
        unlink(tmp_dst);
        return -1;
    }

    fsync(out_fd);
    close(in_fd);
    close(out_fd);
    chown(tmp_dst, MOBILE_UID, MOBILE_GID);
    chmod(tmp_dst, 0755);

    unlink(dst);
    if (rename(tmp_dst, dst) != 0) {
        unlink(tmp_dst);
        return -1;
    }
    return 0;
}

/**
 * 校验文件是否为合法的 64-bit ARM64 Mach-O 或包含 ARM64 切片的 Fat Mach-O
 */
static bool validate_macho_arm64(const char* path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return false;

    uint32_t magic = 0;
    if (read(fd, &magic, sizeof(magic)) != sizeof(magic)) {
        close(fd);
        return false;
    }

    lseek(fd, 0, SEEK_SET);
    if (magic == MH_MAGIC_64) {
        struct mach_header_64 header;
        if (read(fd, &header, sizeof(header)) == sizeof(header)) {
            close(fd);
            return (header.cputype == CPU_TYPE_ARM64);
        }
    } else if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        struct fat_header fheader;
        if (read(fd, &fheader, sizeof(fheader)) == sizeof(fheader)) {
            uint32_t narch = (magic == FAT_CIGAM) ? swap_uint32(fheader.nfat_arch) : fheader.nfat_arch;
            if (narch > 0 && narch <= 16) {
                for (uint32_t i = 0; i < narch; i++) {
                    struct fat_arch arch;
                    if (read(fd, &arch, sizeof(arch)) != sizeof(arch)) break;
                    cpu_type_t cputype = (magic == FAT_CIGAM)
                        ? (cpu_type_t)swap_uint32((uint32_t)arch.cputype)
                        : arch.cputype;
                    if (cputype == CPU_TYPE_ARM64) {
                        close(fd);
                        return true;
                    }
                }
            }
        }
    }

    close(fd);
    return false;
}

static int get_helper_dir(char* out_dir, size_t size) {
    char exe_path[PATH_MAX];
    uint32_t buf_size = sizeof(exe_path);
    if (_NSGetExecutablePath(exe_path, &buf_size) != 0) {
        return -1;
    }
    char resolved[PATH_MAX];
    if (!realpath(exe_path, resolved)) {
        strncpy(resolved, exe_path, sizeof(resolved) - 1);
        resolved[sizeof(resolved) - 1] = '\0';
    }
    char* dir = dirname(resolved);
    snprintf(out_dir, size, "%s", dir);
    return 0;
}

/**
 * 动态生成受管微服务的专属 Entitlements Plist（严格遵循 TrollStore 规则，不含任何 Banned Keys）
 */
static int write_service_entitlements(const char* plist_path, const char* service_id) {
    if (!is_safe_identifier(service_id)) return -1;
    FILE* fp = fopen(plist_path, "w");
    if (!fp) return -1;

    fprintf(fp,
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        "<plist version=\"1.0\">\n"
        "<dict>\n"
        "\t<key>application-identifier</key>\n"
        "\t<string>com.magicfall.trollservice.svc.%s</string>\n"
        "\t<key>com.apple.developer.team-identifier</key>\n"
        "\t<string>TROLLSTORE</string>\n"
        "\t<key>platform-application</key>\n"
        "\t<true/>\n"
        "\t<key>com.apple.private.security.container-required</key>\n"
        "\t<false/>\n"
        "\t<key>com.apple.private.security.no-sandbox</key>\n"
        "\t<true/>\n"
        "\t<key>com.apple.private.security.storage.AppDataContainers</key>\n"
        "\t<true/>\n"
        "\t<key>com.apple.security.exception.files.absolute-path.read-write</key>\n"
        "\t<array>\n"
        "\t\t<string>/</string>\n"
        "\t</array>\n"
        "\t<key>com.apple.multitasking.unlimitedassertions</key>\n"
        "\t<true/>\n"
        "\t<key>com.apple.multitasking.systemappassertions</key>\n"
        "\t<true/>\n"
        "\t<key>com.apple.private.kernel.jetsam</key>\n"
        "\t<true/>\n"
        "\t<key>com.apple.private.memorystatus</key>\n"
        "\t<true/>\n"
        "\t<key>com.apple.private.network.socket-delegate</key>\n"
        "\t<true/>\n"
        "</dict>\n"
        "</plist>\n",
        service_id
    );
    fclose(fp);
    chown(plist_path, MOBILE_UID, MOBILE_GID);
    chmod(plist_path, 0644);
    return 0;
}

/**
 * 双重接力签名：
 * 1. 调用 ldid -S<entitlements.plist> <target_bin> 注入免沙盒与防挂起权限
 * 2. 调用 fastPathSign <target_bin> 注入 CoreTrust 根证书绕过签名 (CVE-2023-41991)
 */
static int sign_and_entitle_binary(const char* ents_plist, const char* target_bin, char* err_msg, size_t err_size) {
    char helper_dir[PATH_MAX];
    if (get_helper_dir(helper_dir, sizeof(helper_dir)) != 0) {
        snprintf(err_msg, err_size, "无法定位 Helpers 目录");
        return -1;
    }

    char ldid_path[PATH_MAX];
    char fps_path[PATH_MAX];
    snprintf(ldid_path, sizeof(ldid_path), "%s/ldid", helper_dir);
    snprintf(fps_path, sizeof(fps_path), "%s/fastPathSign", helper_dir);

    char s_arg[PATH_MAX + 8];
    snprintf(s_arg, sizeof(s_arg), "-S%s", ents_plist);

    char* ldid_argv[] = { ldid_path, s_arg, (char*)target_bin, NULL };
    char* out_buf = NULL;
    char* err_buf = NULL;
    int ret1 = spawn_root_sync(ldid_path, ldid_argv, NULL, &out_buf, &err_buf);
    if (ret1 != 0) {
        snprintf(err_msg, err_size, "ldid 赋权失败 (code=%d): %s", ret1, err_buf ? err_buf : "");
        free(out_buf);
        free(err_buf);
        return -1;
    }
    free(out_buf);
    free(err_buf);

    char* fps_argv[] = { fps_path, (char*)target_bin, NULL };
    out_buf = NULL;
    err_buf = NULL;
    int ret2 = spawn_root_sync(fps_path, fps_argv, NULL, &out_buf, &err_buf);
    if (ret2 != 0) {
        snprintf(err_msg, err_size, "fastPathSign 注入 CoreTrust 签名失败 (code=%d): %s", ret2, err_buf ? err_buf : "");
        free(out_buf);
        free(err_buf);
        return -1;
    }
    free(out_buf);
    free(err_buf);

    chmod(target_bin, 0755);
    chown(target_bin, MOBILE_UID, MOBILE_GID);
    return 0;
}

static pid_t read_pid_file(const char* pid_file) {
    FILE* fp = fopen(pid_file, "r");
    if (!fp) return 0;
    int pid = 0;
    if (fscanf(fp, "%d", &pid) != 1) {
        pid = 0;
    }
    fclose(fp);
    return (pid_t)pid;
}

static void write_pid_file(const char* pid_file, pid_t pid) {
    FILE* fp = fopen(pid_file, "w");
    if (!fp) return;
    fprintf(fp, "%d\n", (int)pid);
    fclose(fp);
    chown(pid_file, MOBILE_UID, MOBILE_GID);
}

static bool is_pid_alive(pid_t pid) {
    if (pid <= 1) return false;
    if (kill(pid, 0) == 0) return true;
    return (errno == EPERM);
}

/**
 * 规范化 Darwin 路径（处理 iOS /private/var 与 /var 软链差异）
 */
static void normalize_darwin_path(const char* raw_path, char* out, size_t out_size) {
    if (!raw_path || out_size == 0) {
        if (out_size > 0) out[0] = '\0';
        return;
    }
    char resolved[PATH_MAX];
    const char* src = raw_path;
    if (realpath(raw_path, resolved) != NULL) {
        src = resolved;
    }
    if (strncmp(src, "/private/var/", 13) == 0) {
        src += 8;
    } else if (strncmp(src, "/private/tmp/", 13) == 0) {
        src += 8;
    }
    snprintf(out, out_size, "%s", src);
}

/**
 * 精确校验指定 PID 是否存活且属于当前服务的受管进程（防范 PID 复用误判与误杀）
 */
static bool is_service_pid_alive(pid_t pid, const char* service_id) {
    if (!is_pid_alive(pid) || !is_safe_identifier(service_id)) {
        return false;
    }
    char proc_path[PROC_PIDPATHINFO_MAXSIZE];
    memset(proc_path, 0, sizeof(proc_path));
    if (proc_pidpath((int)pid, proc_path, sizeof(proc_path)) <= 0) {
        return false;
    }

    char raw_bin_dir[PATH_MAX];
    char norm_bin_dir[PATH_MAX];
    char norm_proc_path[PATH_MAX];
    snprintf(raw_bin_dir, sizeof(raw_bin_dir), "%s/%s/bin", get_service_root(), service_id);
    normalize_darwin_path(raw_bin_dir, norm_bin_dir, sizeof(norm_bin_dir));
    normalize_darwin_path(proc_path, norm_proc_path, sizeof(norm_proc_path));

    size_t dir_len = strlen(norm_bin_dir);
    if (dir_len == 0) return false;
    return (strncmp(norm_proc_path, norm_bin_dir, dir_len) == 0 &&
            norm_proc_path[dir_len] == '/');
}

static void elevate_jetsam_limits(pid_t pid) {
    memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT, (int32_t)pid, 0, NULL, 0);
    memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK, (int32_t)pid, (uint32_t)-1, NULL, 0);
}

/**
 * 按服务专属 bin 目录精确匹配并清理残留进程（绝不误杀系统守护进程或其他服务）
 */
static void kill_service_processes_by_bin_dir(const char* service_id, int sig) {
    if (!is_safe_identifier(service_id)) return;

    char raw_bin_dir[PATH_MAX];
    char norm_bin_dir[PATH_MAX];
    snprintf(raw_bin_dir, sizeof(raw_bin_dir), "%s/%s/bin", get_service_root(), service_id);
    normalize_darwin_path(raw_bin_dir, norm_bin_dir, sizeof(norm_bin_dir));
    size_t dir_len = strlen(norm_bin_dir);
    if (dir_len == 0) return;

    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    size_t buf_size = 0;
    if (sysctl(mib, 3, NULL, &buf_size, NULL, 0) != 0 || buf_size == 0) return;

    size_t alloc_size = buf_size + sizeof(struct kinfo_proc) * 16;
    struct kinfo_proc* procs = (struct kinfo_proc*)malloc(alloc_size);
    if (!procs) return;

    if (sysctl(mib, 3, procs, &alloc_size, NULL, 0) == 0) {
        size_t count = alloc_size / sizeof(struct kinfo_proc);
        pid_t self_pid = getpid();
        for (size_t i = 0; i < count; i++) {
            pid_t p = procs[i].kp_proc.p_pid;
            if (p <= 1 || p == self_pid) continue;
            char proc_path[PROC_PIDPATHINFO_MAXSIZE];
            memset(proc_path, 0, sizeof(proc_path));
            if (proc_pidpath((int)p, proc_path, sizeof(proc_path)) > 0) {
                char norm_proc[PATH_MAX];
                normalize_darwin_path(proc_path, norm_proc, sizeof(norm_proc));
                if (strncmp(norm_proc, norm_bin_dir, dir_len) == 0 &&
                    norm_proc[dir_len] == '/') {
                    kill(p, sig);
                }
            }
        }
    }
    free(procs);
}

static int stop_service_internal(const char* service_id) {
    if (!is_safe_identifier(service_id)) return -1;

    char sup_pid_path[PATH_MAX];
    char svc_pid_path[PATH_MAX];
    snprintf(sup_pid_path, sizeof(sup_pid_path), "%s/%s/runtime/supervisor.pid", get_service_root(), service_id);
    snprintf(svc_pid_path, sizeof(svc_pid_path), "%s/%s/runtime/service.pid", get_service_root(), service_id);

    pid_t svc_pid = read_pid_file(svc_pid_path);
    if (is_service_pid_alive(svc_pid, service_id)) {
        kill(svc_pid, SIGTERM);
        for (int i = 0; i < 20; i++) {
            if (!is_service_pid_alive(svc_pid, service_id)) break;
            usleep(100000); /* 100ms * 20 = 2s */
        }
        if (is_service_pid_alive(svc_pid, service_id)) {
            kill(svc_pid, SIGKILL);
        }
    }

    /* 兜底：若 .pid 文件已被删除但该服务 bin/ 下的进程仍在运行，按精确二进制路径清理 */
    kill_service_processes_by_bin_dir(service_id, SIGTERM);
    usleep(100000);
    kill_service_processes_by_bin_dir(service_id, SIGKILL);

    unlink(sup_pid_path);
    unlink(svc_pid_path);
    return 0;
}

static void rotate_log_if_needed(const char* log_path) {
    if (!log_path || log_path[0] == '\0') return;
    struct stat st;
    if (stat(log_path, &st) == 0 && st.st_size > MAX_LOG_FILE_BYTES) {
        char old_log_path[PATH_MAX];
        snprintf(old_log_path, sizeof(old_log_path), "%s.1", log_path);
        unlink(old_log_path);
        rename(log_path, old_log_path);
        chown(old_log_path, MOBILE_UID, MOBILE_GID);
    }
}

static void load_dotenv_into_environ(const char* env_file_path) {
    FILE* fp = fopen(env_file_path, "r");
    if (!fp) return;

    char line[2048];
    while (fgets(line, sizeof(line), fp)) {
        char* p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '\0' || *p == '#' || *p == '\r' || *p == '\n') continue;

        char* eq = strchr(p, '=');
        if (!eq) continue;
        *eq = '\0';
        char* key = p;
        char* val = eq + 1;

        /* Trim trailing whitespace from key */
        char* kend = eq - 1;
        while (kend > key && (*kend == ' ' || *kend == '\t')) {
            *kend = '\0';
            kend--;
        }

        /* Trim newline and quotes from val */
        size_t vlen = strlen(val);
        while (vlen > 0 && (val[vlen - 1] == '\n' || val[vlen - 1] == '\r' || val[vlen - 1] == ' ')) {
            val[vlen - 1] = '\0';
            vlen--;
        }
        if (vlen >= 2 && ((val[0] == '"' && val[vlen - 1] == '"') || (val[0] == '\'' && val[vlen - 1] == '\''))) {
            val[vlen - 1] = '\0';
            val++;
        }

        if (*key != '\0') {
            setenv(key, val, 1);
        }
    }
    fclose(fp);
}

static int cmd_init_workspace(const char* custom_root) {
    if (custom_root && custom_root[0] != '\0') {
        set_service_root_internal(custom_root);
    }
    const char* root = get_service_root();
    if (mkdir_p(root, 0755) != 0) {
        char msg[PATH_MAX + 64];
        snprintf(msg, sizeof(msg), "创建 %s 失败", root);
        reply_json_error(msg);
        return 1;
    }
    fputs("{\"ok\":true,\"root\":\"", stdout);
    print_json_escaped(root);
    fputs("\"}\n", stdout);
    return 0;
}

static int cmd_install(const char* service_id, const char* src_path, const char* binary_name, const char* custom_ents_path) {
    if (!is_safe_identifier(service_id) || !is_safe_identifier(binary_name)) {
        reply_json_error("服务标识或可执行文件名包含非法字符（仅允许字母、数字、下划线、连字符和点）");
        return 1;
    }
    if (!validate_macho_arm64(src_path)) {
        reply_json_error("文件不是有效的 iOS/Darwin ARM64 Mach-O 可执行文件");
        return 1;
    }

    char base_dir[PATH_MAX];
    char bin_dir[PATH_MAX];
    char cfg_dir[PATH_MAX];
    char run_dir[PATH_MAX];
    snprintf(base_dir, sizeof(base_dir), "%s/%s", get_service_root(), service_id);
    snprintf(bin_dir, sizeof(bin_dir), "%s/bin", base_dir);
    snprintf(cfg_dir, sizeof(cfg_dir), "%s/config", base_dir);
    snprintf(run_dir, sizeof(run_dir), "%s/runtime", base_dir);

    mkdir_p(bin_dir, 0755);
    mkdir_p(cfg_dir, 0755);
    mkdir_p(run_dir, 0755);

    char dst_bin[PATH_MAX];
    char ents_plist[PATH_MAX];
    snprintf(dst_bin, sizeof(dst_bin), "%s/%s", bin_dir, binary_name);
    snprintf(ents_plist, sizeof(ents_plist), "%s/entitlements.plist", cfg_dir);

    if (copy_file_binary(src_path, dst_bin) != 0) {
        char msg[PATH_MAX + 64];
        snprintf(msg, sizeof(msg), "复制程序文件到 %s 失败", dst_bin);
        reply_json_error(msg);
        return 1;
    }

    if (custom_ents_path && custom_ents_path[0] != '\0' && access(custom_ents_path, R_OK) == 0) {
        if (copy_file_binary(custom_ents_path, ents_plist) != 0) {
            reply_json_error("应用自定义 entitlements.plist 失败");
            return 1;
        }
        chown(ents_plist, MOBILE_UID, MOBILE_GID);
        chmod(ents_plist, 0644);
    } else {
        if (write_service_entitlements(ents_plist, service_id) != 0) {
            reply_json_error("生成 entitlements.plist 失败");
            return 1;
        }
    }

    char err_msg[1024] = {0};
    if (sign_and_entitle_binary(ents_plist, dst_bin, err_msg, sizeof(err_msg)) != 0) {
        reply_json_error(err_msg);
        return 1;
    }

    fputs("{\"ok\":true,\"action\":\"install\",\"binary\":\"", stdout);
    print_json_escaped(dst_bin);
    fputs("\"}\n", stdout);
    return 0;
}

/**
 * 更新程序命令：
 * 1. 先校验新文件架构合法性（不合法直接中止，绝不破坏原程序）
 * 2. 若服务正在运行，先优雅停止进程释放文件锁与数据库锁
 * 3. 仅原子替换 bin/<binary_name> 并重新执行 ldid -S + fastPathSign 签名赋权
 * 4. 100% 原样保留服务目录下的 config/, runtime/, accounts/, 数据库等全部数据
 * 5. 支持传入自定义 entitlements.plist
 */
static int cmd_update(const char* service_id, const char* new_src_path, const char* binary_name, const char* custom_ents_path) {
    if (!is_safe_identifier(service_id) || !is_safe_identifier(binary_name)) {
        reply_json_error("服务标识或可执行文件名包含非法字符");
        return 1;
    }
    if (!validate_macho_arm64(new_src_path)) {
        reply_json_error("新文件不是有效的 iOS/Darwin ARM64 Mach-O 可执行文件，已中止更新，原程序与数据未受影响");
        return 1;
    }

    char base_dir[PATH_MAX];
    char bin_dir[PATH_MAX];
    char cfg_dir[PATH_MAX];
    char run_dir[PATH_MAX];
    snprintf(base_dir, sizeof(base_dir), "%s/%s", get_service_root(), service_id);
    snprintf(bin_dir, sizeof(bin_dir), "%s/bin", base_dir);
    snprintf(cfg_dir, sizeof(cfg_dir), "%s/config", base_dir);
    snprintf(run_dir, sizeof(run_dir), "%s/runtime", base_dir);

    mkdir_p(bin_dir, 0755);
    mkdir_p(cfg_dir, 0755);
    mkdir_p(run_dir, 0755);

    char svc_pid_path[PATH_MAX];
    snprintf(svc_pid_path, sizeof(svc_pid_path), "%s/service.pid", run_dir);
    pid_t old_pid = read_pid_file(svc_pid_path);
    bool was_running = is_service_pid_alive(old_pid, service_id);

    if (was_running) {
        stop_service_internal(service_id);
    }

    char dst_bin[PATH_MAX];
    char ents_plist[PATH_MAX];
    snprintf(dst_bin, sizeof(dst_bin), "%s/%s", bin_dir, binary_name);
    snprintf(ents_plist, sizeof(ents_plist), "%s/entitlements.plist", cfg_dir);

    if (custom_ents_path && custom_ents_path[0] != '\0' && access(custom_ents_path, R_OK) == 0) {
        if (copy_file_binary(custom_ents_path, ents_plist) != 0) {
            reply_json_error("应用自定义 entitlements.plist 失败");
            return 1;
        }
        chown(ents_plist, MOBILE_UID, MOBILE_GID);
        chmod(ents_plist, 0644);
    } else {
        struct stat st;
        if (stat(ents_plist, &st) != 0) {
            write_service_entitlements(ents_plist, service_id);
        }
    }

    if (copy_file_binary(new_src_path, dst_bin) != 0) {
        char msg[PATH_MAX + 64];
        snprintf(msg, sizeof(msg), "替换可执行文件 %s 失败", dst_bin);
        reply_json_error(msg);
        return 1;
    }

    char err_msg[1024] = {0};
    if (sign_and_entitle_binary(ents_plist, dst_bin, err_msg, sizeof(err_msg)) != 0) {
        reply_json_error(err_msg);
        return 1;
    }

    printf("{\"ok\":true,\"action\":\"update\",\"was_running\":%s,\"preserved_data\":true,\"binary\":\"",
           was_running ? "true" : "false");
    print_json_escaped(dst_bin);
    fputs("\"}\n", stdout);
    return 0;
}

static int cmd_start(int argc, char* argv[]) {
    if (argc < 4) {
        reply_json_error("参数不足");
        return 1;
    }
    const char* service_id = argv[2];
    const char* binary_name = argv[3];
    if (!is_safe_identifier(service_id) || !is_safe_identifier(binary_name)) {
        reply_json_error("服务标识或可执行文件名包含非法字符");
        return 1;
    }

    char base_dir[PATH_MAX];
    char bin_path[PATH_MAX];
    char env_cfg_path[PATH_MAX];
    char env_work_path[PATH_MAX];
    char log_path[PATH_MAX];
    char svc_pid_path[PATH_MAX];

    snprintf(base_dir, sizeof(base_dir), "%s/%s", get_service_root(), service_id);
    snprintf(bin_path, sizeof(bin_path), "%s/bin/%s", base_dir, binary_name);
    snprintf(env_cfg_path, sizeof(env_cfg_path), "%s/config/.env", base_dir);
    snprintf(env_work_path, sizeof(env_work_path), "%s/.env", base_dir);
    snprintf(log_path, sizeof(log_path), "%s/runtime/stdout.log", base_dir);
    snprintf(svc_pid_path, sizeof(svc_pid_path), "%s/runtime/service.pid", base_dir);

    pid_t existing_pid = read_pid_file(svc_pid_path);
    if (is_service_pid_alive(existing_pid, service_id)) {
        printf("{\"ok\":true,\"already_running\":true,\"pid\":%d}\n", (int)existing_pid);
        return 0;
    } else if (existing_pid > 0) {
        unlink(svc_pid_path);
    }

    if (chdir(base_dir) != 0) {
        char msg[PATH_MAX + 64];
        snprintf(msg, sizeof(msg), "无法进入服务目录 %s", base_dir);
        reply_json_error(msg);
        return 1;
    }

    setenv("HOME", "/var/mobile", 1);
    struct stat st_work;
    struct stat st_cfg;
    if (stat(env_work_path, &st_work) == 0) {
        load_dotenv_into_environ(env_work_path);
    } else if (stat(env_cfg_path, &st_cfg) == 0) {
        load_dotenv_into_environ(env_cfg_path);
        copy_file_binary(env_cfg_path, env_work_path);
        chmod(env_work_path, 0644);
    }

    int extra_args = argc - 4;
    char** child_argv = (char**)calloc((size_t)(extra_args + 2), sizeof(char*));
    if (!child_argv) {
        reply_json_error("分配参数内存失败");
        return 1;
    }
    child_argv[0] = (char*)bin_path;
    for (int i = 0; i < extra_args; i++) {
        child_argv[i + 1] = argv[4 + i];
    }
    child_argv[extra_args + 1] = NULL;

    rotate_log_if_needed(log_path);
    int log_fd = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    chown(log_path, MOBILE_UID, MOBILE_GID);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    if (log_fd >= 0) {
        posix_spawn_file_actions_adddup2(&actions, log_fd, STDOUT_FILENO);
        posix_spawn_file_actions_adddup2(&actions, log_fd, STDERR_FILENO);
        posix_spawn_file_actions_addclose(&actions, log_fd);
    }

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID);

    pid_t child_pid = 0;
    int spawn_err = posix_spawn(&child_pid, bin_path, &actions, &attr, child_argv, environ);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);
    if (log_fd >= 0) close(log_fd);
    free(child_argv);

    if (spawn_err != 0) {
        char msg[128];
        snprintf(msg, sizeof(msg), "启动进程失败 (errno=%d)", spawn_err);
        reply_json_error(msg);
        return 1;
    }

    elevate_jetsam_limits(child_pid);
    write_pid_file(svc_pid_path, child_pid);

    /* 等待 250ms 检测是否因配置错误立即退出，若是则立即清理 pid 文件并返回失败提示 */
    usleep(250000);
    int status = 0;
    pid_t w = waitpid(child_pid, &status, WNOHANG);
    if (w == child_pid || !is_pid_alive(child_pid)) {
        unlink(svc_pid_path);
        reply_json_error("程序启动后立即退出，请打开实时日志查看报错原因");
        return 1;
    }

    printf("{\"ok\":true,\"pid\":%d}\n", (int)child_pid);
    return 0;
}

static int cmd_status(const char* service_id) {
    if (!is_safe_identifier(service_id)) {
        reply_json_error("非法服务标识");
        return 1;
    }
    char svc_pid_path[PATH_MAX];
    snprintf(svc_pid_path, sizeof(svc_pid_path), "%s/%s/runtime/service.pid", get_service_root(), service_id);
    pid_t pid = read_pid_file(svc_pid_path);

    if (!is_service_pid_alive(pid, service_id)) {
        if (pid > 0) {
            unlink(svc_pid_path);
        }
        printf("{\"ok\":true,\"running\":false,\"pid\":0,\"memory_bytes\":0,\"uptime_sec\":0}\n");
        return 0;
    }

    uint64_t mem_bytes = 0;
    struct rusage_info_v4 ru;
    memset(&ru, 0, sizeof(ru));
    if (proc_pid_rusage((int)pid, RUSAGE_INFO_V4, (rusage_info_t*)&ru) == 0) {
        mem_bytes = ru.ri_phys_footprint;
    }

    long uptime_sec = 0;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)pid };
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    if (sysctl(mib, 4, &kp, &len, NULL, 0) == 0 && len > 0) {
        time_t now = time(NULL);
        if (now > kp.kp_proc.p_starttime.tv_sec && kp.kp_proc.p_starttime.tv_sec > 0) {
            uptime_sec = (long)(now - kp.kp_proc.p_starttime.tv_sec);
        }
    }

    printf("{\"ok\":true,\"running\":true,\"pid\":%d,\"memory_bytes\":%llu,\"uptime_sec\":%ld}\n",
           (int)pid, (unsigned long long)mem_bytes, uptime_sec);
    return 0;
}

static int remove_directory_recursive(const char* path) {
    char* const paths[] = { (char*)path, NULL };
    FTS* fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR, NULL);
    if (!fts) return -1;

    FTSENT* ent;
    while ((ent = fts_read(fts)) != NULL) {
        switch (ent->fts_info) {
            case FTS_DP:
                rmdir(ent->fts_accpath);
                break;
            case FTS_F:
            case FTS_SL:
            case FTS_SLNONE:
            case FTS_DEFAULT:
                unlink(ent->fts_accpath);
                break;
            default:
                break;
        }
    }
    fts_close(fts);
    return 0;
}

static int cmd_uninstall(const char* service_id) {
    if (!is_safe_identifier(service_id)) {
        reply_json_error("非法服务标识，拒绝卸载清理");
        return 1;
    }
    stop_service_internal(service_id);
    char base_dir[PATH_MAX];
    snprintf(base_dir, sizeof(base_dir), "%s/%s", get_service_root(), service_id);
    remove_directory_recursive(base_dir);
    printf("{\"ok\":true,\"action\":\"uninstall\"}\n");
    return 0;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        reply_json_error("用法: daemon_root_helper <init-workspace|set-root|install|update|start|stop|status|uninstall>");
        return 1;
    }

    setuid(0);
    setgid(0);

    const char* cmd = argv[1];
    if (strcmp(cmd, "init-workspace") == 0) {
        return cmd_init_workspace(argc >= 3 ? argv[2] : NULL);
    } else if (strcmp(cmd, "set-root") == 0 && argc >= 3) {
        return cmd_set_root(argv[2]);
    } else if (strcmp(cmd, "install") == 0 && argc >= 5) {
        return cmd_install(argv[2], argv[3], argv[4], argc >= 6 ? argv[5] : NULL);
    } else if (strcmp(cmd, "update") == 0 && argc >= 5) {
        return cmd_update(argv[2], argv[3], argv[4], argc >= 6 ? argv[5] : NULL);
    } else if (strcmp(cmd, "start") == 0) {
        return cmd_start(argc, argv);
    } else if (strcmp(cmd, "stop") == 0 && argc >= 3) {
        if (!is_safe_identifier(argv[2])) {
            reply_json_error("非法服务标识");
            return 1;
        }
        stop_service_internal(argv[2]);
        printf("{\"ok\":true,\"action\":\"stop\"}\n");
        return 0;
    } else if (strcmp(cmd, "status") == 0 && argc >= 3) {
        return cmd_status(argv[2]);
    } else if (strcmp(cmd, "uninstall") == 0 && argc >= 3) {
        return cmd_uninstall(argv[2]);
    }

    char msg[256];
    snprintf(msg, sizeof(msg), "未知命令或参数不足: %s", cmd);
    reply_json_error(msg);
    return 1;
}
