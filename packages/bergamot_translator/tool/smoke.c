// Vommet: native smoke test for the plugin's C API (CI only; not shipped).
// Usage: smoke <model config yaml> <text>
// Loads one model, translates <text>, detects the language of a Spanish
// sentence, and exits non-zero if any step fails or returns nothing.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bergamot_translator.h"

static char *read_file(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  char *buf = malloc((size_t)n + 1);
  if (!buf || fread(buf, 1, (size_t)n, f) != (size_t)n) {
    fclose(f);
    free(buf);
    return NULL;
  }
  buf[n] = '\0';
  fclose(f);
  return buf;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s <config.yml> <text>\n", argv[0]);
    return 2;
  }
  char *cfg = read_file(argv[1]);
  if (!cfg) {
    fprintf(stderr, "cannot read %s\n", argv[1]);
    return 2;
  }
  if (bergamot_initialize_service() != 0) return 3;
  if (bergamot_load_model(cfg, "smoke") != 0) return 4;

  const char *inputs[] = {argv[2]};
  char **outputs = NULL;
  int count = 0;
  if (bergamot_translate_multiple(inputs, 1, "smoke", &outputs, &count) != 0) return 5;
  if (count != 1 || outputs[0] == NULL || outputs[0][0] == '\0') return 6;
  printf("translation: %s\n", outputs[0]);
  bergamot_free_string_array(outputs, count);

  BergamotDetectionResult det;
  if (bergamot_detect_language("Hola, ¿cómo estás? Me alegro mucho de verte otra vez.", NULL, &det) != 0) return 7;
  printf("detected: %s reliable=%d confidence=%d\n", det.language, det.is_reliable, det.confidence);
  if (strcmp(det.language, "es") != 0) return 8;

  bergamot_cleanup(1);
  free(cfg);
  return 0;
}
