#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define MAX_STATE_BYTES 65536U
#define RETRY_INTERVAL_MS 1000
#define EVENT_BUFFER_BYTES (16U * 1024U)

static int write_all(int descriptor, const void *buffer, size_t length) {
  const unsigned char *cursor = buffer;

  while (length > 0) {
    ssize_t written = write(descriptor, cursor, length);
    if (written > 0) {
      cursor += (size_t)written;
      length -= (size_t)written;
      continue;
    }
    if (written < 0 && errno == EINTR) {
      continue;
    }
    return -1;
  }

  return 0;
}

static int send_theme_message(const char *message, size_t message_length) {
  if (message_length > UINT32_MAX) {
    return -1;
  }

  uint32_t native_length = (uint32_t)message_length;
  if (write_all(STDOUT_FILENO, &native_length, sizeof(native_length)) < 0
      || write_all(STDOUT_FILENO, message, message_length) < 0) {
    return -1;
  }

  return 0;
}

static int read_theme_message(const char *path, char *message,
                              size_t *message_length) {
  int descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (descriptor < 0) {
    return 0;
  }

  struct stat metadata;
  if (fstat(descriptor, &metadata) < 0 || !S_ISREG(metadata.st_mode)
      || metadata.st_size < 0
      || (uintmax_t)metadata.st_size > MAX_STATE_BYTES) {
    close(descriptor);
    return 0;
  }

  size_t total = 0;
  while (total < MAX_STATE_BYTES + 1U) {
    ssize_t amount = read(descriptor, message + total,
                          MAX_STATE_BYTES + 1U - total);
    if (amount > 0) {
      total += (size_t)amount;
      continue;
    }
    if (amount < 0 && errno == EINTR) {
      continue;
    }
    if (amount < 0) {
      close(descriptor);
      return 0;
    }
    break;
  }
  close(descriptor);

  if (total > MAX_STATE_BYTES) {
    return 0;
  }
  while (total > 0 && (message[total - 1U] == ' '
                       || message[total - 1U] == '\t'
                       || message[total - 1U] == '\r'
                       || message[total - 1U] == '\n')) {
    total--;
  }
  if (total < 2U || message[0] != '{'
      || message[total - 1U] != '}'
      || memchr(message, '\0', total) != NULL) {
    return 0;
  }

  message[total] = '\0';
  *message_length = total;
  return 1;
}

static int check_theme(const char *state_path, char *last_message,
                       size_t *last_length) {
  char message[MAX_STATE_BYTES + 1U];
  size_t message_length = 0;

  if (!read_theme_message(state_path, message, &message_length)) {
    return 0;
  }
  if (message_length == *last_length
      && memcmp(message, last_message, message_length) == 0) {
    return 0;
  }
  if (send_theme_message(message, message_length) < 0) {
    return -1;
  }

  memcpy(last_message, message, message_length + 1U);
  *last_length = message_length;
  return 0;
}

static int split_state_path(const char *state_path, char *directory,
                            size_t directory_size, const char **filename) {
  const char *separator = strrchr(state_path, '/');
  if (separator == NULL) {
    if (directory_size < 2U) {
      return -1;
    }
    memcpy(directory, ".", 2U);
    *filename = state_path;
    return 0;
  }

  size_t directory_length = separator == state_path
                          ? 1U
                          : (size_t)(separator - state_path);
  if (directory_length + 1U > directory_size || separator[1] == '\0') {
    return -1;
  }

  memcpy(directory, state_path, directory_length);
  directory[directory_length] = '\0';
  *filename = separator + 1;
  return 0;
}

static int resolve_state_path(char *state_path, size_t state_path_size) {
  const char *override = getenv("OMAFOX_STATE_FILE");
  if (override != NULL && override[0] != '\0') {
    int length = snprintf(state_path, state_path_size, "%s", override);
    return length >= 0 && (size_t)length < state_path_size ? 0 : -1;
  }

  const char *home = getenv("HOME");
  if (home == NULL || home[0] == '\0') {
    return -1;
  }
  int length = snprintf(state_path, state_path_size,
                        "%s/.local/state/omafox/theme.json", home);
  return length >= 0 && (size_t)length < state_path_size ? 0 : -1;
}

static int consume_inotify_events(int descriptor, int watch_descriptor,
                                  const char *filename, int *watch_lost,
                                  int *state_removed) {
  char buffer[EVENT_BUFFER_BYTES]
      __attribute__((aligned(__alignof__(struct inotify_event))));
  int should_check = 0;

  while (1) {
    ssize_t amount = read(descriptor, buffer, sizeof(buffer));
    if (amount < 0 && errno == EINTR) {
      continue;
    }
    if (amount < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      break;
    }
    if (amount <= 0) {
      return -1;
    }

    for (char *cursor = buffer; cursor < buffer + amount;) {
      const struct inotify_event *event = (const struct inotify_event *)cursor;
      if ((event->mask & IN_Q_OVERFLOW) != 0) {
        should_check = 1;
      }
      if (event->wd == watch_descriptor) {
        if ((event->mask
             & (IN_DELETE_SELF | IN_MOVE_SELF | IN_UNMOUNT | IN_IGNORED)) != 0) {
          *watch_lost = 1;
        }
        if (event->len > 0 && strcmp(event->name, filename) == 0) {
          should_check = 1;
          if ((event->mask & (IN_DELETE | IN_MOVED_FROM)) != 0) {
            *state_removed = 1;
          }
        }
      }
      cursor += sizeof(struct inotify_event) + event->len;
    }
  }

  return should_check;
}

int main(void) {
  char state_path[PATH_MAX];
  char state_directory[PATH_MAX];
  char last_message[MAX_STATE_BYTES + 1U] = {0};
  size_t last_length = 0;
  const char *state_filename = NULL;

  if (resolve_state_path(state_path, sizeof(state_path)) < 0
      || split_state_path(state_path, state_directory,
                          sizeof(state_directory), &state_filename) < 0) {
    fprintf(stderr, "omafox native host: invalid state path\n");
    return 1;
  }

  signal(SIGPIPE, SIG_IGN);
  int inotify_descriptor = inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
  if (inotify_descriptor < 0) {
    fprintf(stderr, "omafox native host: inotify initialization failed\n");
    return 1;
  }

  int watch_descriptor = -1;
  while (1) {
    if (watch_descriptor < 0) {
      watch_descriptor = inotify_add_watch(
          inotify_descriptor,
          state_directory,
          IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE
              | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF);
      if (watch_descriptor >= 0
          && check_theme(state_path, last_message, &last_length) < 0) {
        break;
      }
    }

    struct pollfd descriptors[2] = {
        {.fd = STDIN_FILENO, .events = POLLIN},
        {.fd = inotify_descriptor, .events = POLLIN},
    };
    int poll_result = poll(descriptors, 2,
                           watch_descriptor >= 0 ? -1 : RETRY_INTERVAL_MS);
    if (poll_result < 0 && errno == EINTR) {
      continue;
    }
    if (poll_result < 0) {
      break;
    }
    if ((descriptors[0].revents & (POLLHUP | POLLERR | POLLNVAL)) != 0) {
      break;
    }
    if ((descriptors[0].revents & POLLIN) != 0) {
      char discard[4096];
      ssize_t amount;
      do {
        amount = read(STDIN_FILENO, discard, sizeof(discard));
      } while (amount < 0 && errno == EINTR);
      if (amount <= 0) {
        break;
      }
    }
    if ((descriptors[1].revents & POLLIN) != 0) {
      int watch_lost = 0;
      int state_removed = 0;
      int should_check = consume_inotify_events(
          inotify_descriptor, watch_descriptor, state_filename, &watch_lost,
          &state_removed);
      if (should_check < 0) {
        break;
      }
      if (state_removed) {
        last_length = 0;
      }
      if (watch_lost) {
        watch_descriptor = -1;
        last_length = 0;
      }
      if (should_check > 0
          && check_theme(state_path, last_message, &last_length) < 0) {
        break;
      }
    }
    if ((descriptors[1].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
      break;
    }
  }

  close(inotify_descriptor);
  return 0;
}
