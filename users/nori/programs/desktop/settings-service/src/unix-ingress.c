/* Linux-only credential boundary for the desktop settings IPC socket. */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

enum {
  backlog = 16,
  buffer_size = 16384,
  max_frame_bytes = 64 * 1024,
  max_active_children = 8,
  relay_timeout_ms = 5000,
};

static volatile sig_atomic_t active_children = 0;

static void reap_children(int signal_number) {
  (void)signal_number;
  int saved_errno = errno;
  while (waitpid(-1, NULL, WNOHANG) > 0) {
    if (active_children > 0) --active_children;
  }
  errno = saved_errno;
}

static bool set_relay_timeout(int fd) {
  const struct timeval timeout = {
    .tv_sec = relay_timeout_ms / 1000,
    .tv_usec = (relay_timeout_ms % 1000) * 1000,
  };
  return setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) == 0 &&
         setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) == 0;
}

static void die(const char *message) {
  perror(message);
  exit(EXIT_FAILURE);
}

static int unix_socket(const char *path, bool listener) {
  struct sockaddr_un address = { .sun_family = AF_UNIX };
  size_t length = strlen(path);
  if (length == 0 || length >= sizeof(address.sun_path)) {
    errno = ENAMETOOLONG;
    return -1;
  }
  memcpy(address.sun_path, path, length + 1);
  int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) return -1;
  if (listener) {
    struct stat existing;
    if (lstat(path, &existing) == 0) {
      if (!S_ISSOCK(existing.st_mode) || existing.st_uid != getuid()) {
        close(fd);
        errno = EPERM;
        return -1;
      }
      if (unlink(path) < 0) {
        close(fd);
        return -1;
      }
    } else if (errno != ENOENT) {
      close(fd);
      return -1;
    }
    mode_t old_mask = umask(0077);
    int result = bind(fd, (const struct sockaddr *)&address,
                      offsetof(struct sockaddr_un, sun_path) + length + 1);
    umask(old_mask);
    if (result < 0 || chmod(path, 0660) < 0 || listen(fd, backlog) < 0) {
      int saved = errno;
      close(fd);
      unlink(path);
      errno = saved;
      return -1;
    }
  } else if (connect(fd, (const struct sockaddr *)&address,
                     offsetof(struct sockaddr_un, sun_path) + length + 1) < 0) {
    close(fd);
    return -1;
  }
  return fd;
}

static bool receive_exact(int fd, void *buffer, size_t length) {
  char *bytes = buffer;
  size_t received = 0;
  while (received < length) {
    ssize_t next = recv(fd, bytes + received, length - received, 0);
    if (next < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    if (next == 0) return false;
    received += (size_t)next;
  }
  return true;
}

static bool send_exact(int fd, const void *buffer, size_t length) {
  const char *bytes = buffer;
  size_t written = 0;
  while (written < length) {
    ssize_t next = send(fd, bytes + written, length - written, MSG_NOSIGNAL);
    if (next < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    if (next == 0) return false;
    written += (size_t)next;
  }
  return true;
}

static bool reject_buffered_trailing_bytes(int fd) {
  char trailing;
  for (;;) {
    ssize_t next = recv(fd, &trailing, sizeof(trailing), MSG_DONTWAIT);
    if (next < 0 && errno == EINTR) continue;
    return next <= 0 && (next == 0 || errno == EAGAIN || errno == EWOULDBLOCK);
  }
}

static bool relay_frame(int from, int to) {
  uint8_t header[4];
  if (!receive_exact(from, header, sizeof(header))) return false;
  uint32_t length = ((uint32_t)header[0] << 24) |
                    ((uint32_t)header[1] << 16) |
                    ((uint32_t)header[2] << 8) |
                    (uint32_t)header[3];
  if (length > max_frame_bytes || !send_exact(to, header, sizeof(header))) return false;

  char buffer[buffer_size];
  uint32_t remaining = length;
  while (remaining > 0) {
    size_t chunk = remaining < sizeof(buffer) ? remaining : sizeof(buffer);
    if (!receive_exact(from, buffer, chunk) || !send_exact(to, buffer, chunk)) return false;
    remaining -= (uint32_t)chunk;
  }
  if (!reject_buffered_trailing_bytes(from)) return false;
  shutdown(from, SHUT_RD);
  return true;
}

static void relay(int client, int backend) {
  if (!relay_frame(client, backend)) return;
  relay_frame(backend, client);
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: nori-desktop-settings-ingress SOCKET BACKEND UID\\n");
    return EXIT_FAILURE;
  }
  char *end = NULL;
  errno = 0;
  unsigned long requested_uid = strtoul(argv[3], &end, 10);
  if (errno != 0 || *argv[3] == '\0' || *end != '\0' || requested_uid != (uid_t)requested_uid) {
    fputs("invalid service UID\\n", stderr);
    return EXIT_FAILURE;
  }
  int listener = unix_socket(argv[1], true);
  if (listener < 0) die("cannot create public settings socket");
  struct sigaction child_action = {
    .sa_handler = reap_children,
    .sa_flags = SA_NOCLDSTOP,
  };
  sigemptyset(&child_action.sa_mask);
  if (sigaction(SIGCHLD, &child_action, NULL) < 0) die("sigaction");

  sigset_t child_signal;
  sigemptyset(&child_signal);
  sigaddset(&child_signal, SIGCHLD);
  for (;;) {
    int client = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
    if (client < 0) {
      if (errno == EINTR) continue;
      die("accept");
    }
    struct ucred credentials;
    socklen_t size = sizeof(credentials);
    if (getsockopt(client, SOL_SOCKET, SO_PEERCRED, &credentials, &size) < 0 ||
        size != sizeof(credentials) || credentials.uid != (uid_t)requested_uid) {
      close(client);
      continue;
    }

    sigset_t previous_mask;
    if (sigprocmask(SIG_BLOCK, &child_signal, &previous_mask) < 0) {
      close(client);
      continue;
    }
    if (active_children >= max_active_children) {
      sigprocmask(SIG_SETMASK, &previous_mask, NULL);
      close(client);
      continue;
    }

    pid_t child = fork();
    if (child < 0) {
      sigprocmask(SIG_SETMASK, &previous_mask, NULL);
      close(client);
      continue;
    }
    if (child == 0) {
      close(listener);
      sigprocmask(SIG_SETMASK, &previous_mask, NULL);
      int backend = unix_socket(argv[2], false);
      if (backend >= 0 && set_relay_timeout(client) && set_relay_timeout(backend)) {
        relay(client, backend);
      }
      close(client);
      if (backend >= 0) close(backend);
      _exit(EXIT_SUCCESS);
    }

    ++active_children;
    sigprocmask(SIG_SETMASK, &previous_mask, NULL);
    close(client);
  }
}
