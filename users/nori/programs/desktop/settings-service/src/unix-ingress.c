/* Linux-only credential boundary for the desktop settings IPC socket. */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

enum { backlog = 16, buffer_size = 16384 };

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
    if (result < 0 || chmod(path, 0600) < 0 || listen(fd, backlog) < 0) {
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

static void relay(int client, int backend) {
  struct pollfd fds[2] = {
    { .fd = client, .events = POLLIN },
    { .fd = backend, .events = POLLIN },
  };
  char buffer[buffer_size];
  bool closed[2] = { false, false };
  for (;;) {
    int ready = poll(fds, 2, -1);
    if (ready < 0) { if (errno == EINTR) continue; return; }
    for (size_t i = 0; i < 2; ++i) {
      if (closed[i]) continue;
      if ((fds[i].revents & (POLLERR | POLLNVAL)) != 0) return;
      if ((fds[i].revents & (POLLIN | POLLHUP)) == 0) continue;
      int from = fds[i].fd;
      int to = fds[1 - i].fd;
      ssize_t count = read(from, buffer, sizeof(buffer));
      if (count < 0) {
        if (errno == EINTR) continue;
        return;
      }
      if (count == 0) {
        shutdown(to, SHUT_WR);
        closed[i] = true;
        fds[i].events = 0;
        if (closed[0] && closed[1]) return;
        continue;
      }
      for (ssize_t written = 0; written < count;) {
        ssize_t next = send(to, buffer + written, (size_t)(count - written), MSG_NOSIGNAL);
        if (next <= 0) return;
        written += next;
      }
    }
  }
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
  signal(SIGCHLD, SIG_IGN);
  for (;;) {
    int client = accept4(listener, NULL, NULL, SOCK_CLOEXEC);
    if (client < 0) { if (errno == EINTR) continue; die("accept"); }
    struct ucred credentials;
    socklen_t size = sizeof(credentials);
    if (getsockopt(client, SOL_SOCKET, SO_PEERCRED, &credentials, &size) < 0 ||
        size != sizeof(credentials) || credentials.uid != (uid_t)requested_uid) {
      close(client);
      continue;
    }
    pid_t child = fork();
    if (child < 0) { close(client); continue; }
    if (child == 0) {
      int backend = unix_socket(argv[2], false);
      if (backend >= 0) relay(client, backend);
      close(client);
      if (backend >= 0) close(backend);
      _exit(EXIT_SUCCESS);
    }
    close(client);
  }
}
