#include "spawn_root.h"

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif

#ifndef POSIX_SPAWN_SETSID
#define POSIX_SPAWN_SETSID 0x0400
#endif

int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

static char* read_fd_all(int fd) {
    size_t capacity = 1024;
    size_t length = 0;
    char* buffer = (char*)malloc(capacity);
    if (!buffer) return NULL;

    ssize_t n;
    while ((n = read(fd, buffer + length, capacity - length - 1)) > 0) {
        length += (size_t)n;
        if (length + 256 >= capacity) {
            capacity *= 2;
            char* next = (char*)realloc(buffer, capacity);
            if (!next) {
                free(buffer);
                return NULL;
            }
            buffer = next;
        }
    }
    buffer[length] = '\0';
    return buffer;
}

int spawn_root_sync(
    const char* binary_path,
    char* const argv[],
    char* const envp[],
    char** stdout_buf,
    char** stderr_buf
) {
    if (!binary_path || !argv) return -1;

    int out_pipe[2] = {-1, -1};
    int err_pipe[2] = {-1, -1};
    if (pipe(out_pipe) != 0) return -1;
    if (pipe(err_pipe) != 0) {
        close(out_pipe[0]);
        close(out_pipe[1]);
        return -1;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, out_pipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, err_pipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, out_pipe[0]);
    posix_spawn_file_actions_addclose(&actions, out_pipe[1]);
    posix_spawn_file_actions_addclose(&actions, err_pipe[0]);
    posix_spawn_file_actions_addclose(&actions, err_pipe[1]);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    pid_t pid = 0;
    char* const* use_env = envp ? envp : environ;
    int spawn_err = posix_spawn(&pid, binary_path, &actions, &attr, argv, use_env);

    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);

    close(out_pipe[1]);
    close(err_pipe[1]);

    if (spawn_err != 0) {
        close(out_pipe[0]);
        close(err_pipe[0]);
        return -spawn_err;
    }

    char* out_str = read_fd_all(out_pipe[0]);
    char* err_str = read_fd_all(err_pipe[0]);
    close(out_pipe[0]);
    close(err_pipe[0]);

    if (stdout_buf) {
        *stdout_buf = out_str;
    } else {
        free(out_str);
    }

    if (stderr_buf) {
        *stderr_buf = err_str;
    } else {
        free(err_str);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) == -1) {
        return -errno;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return -1;
}

int spawn_root_detached(
    const char* binary_path,
    char* const argv[],
    char* const envp[],
    pid_t* out_pid
) {
    if (!binary_path || !argv) return -1;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID);

    pid_t pid = 0;
    char* const* use_env = envp ? envp : environ;
    int spawn_err = posix_spawn(&pid, binary_path, &actions, &attr, argv, use_env);

    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);

    if (spawn_err != 0) {
        return -spawn_err;
    }
    if (out_pid) {
        *out_pid = pid;
    }
    return 0;
}
