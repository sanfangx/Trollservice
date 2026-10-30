#ifndef SPAWN_ROOT_H
#define SPAWN_ROOT_H

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 以 root (UID 0, GID 0, persona 99) 同步拉起子进程并等待结束，收集标准输出与标准错误。
 * 调用方负责 free(*stdout_buf) 与 free(*stderr_buf)。
 */
int spawn_root_sync(
    const char* binary_path,
    char* const argv[],
    char* const envp[],
    char** stdout_buf,
    char** stderr_buf
);

/**
 * 以 root (UID 0, GID 0, persona 99) + POSIX_SPAWN_SETSID 独立会话拉起后台子进程，不阻塞等待。
 */
int spawn_root_detached(
    const char* binary_path,
    char* const argv[],
    char* const envp[],
    pid_t* out_pid
);

#ifdef __cplusplus
}
#endif

#endif /* SPAWN_ROOT_H */
