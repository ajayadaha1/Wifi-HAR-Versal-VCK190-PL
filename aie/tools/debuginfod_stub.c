/* Stub libdebuginfod.so.1 (glibc-2.31 compatible).
 *
 * Ubuntu 20 ships no libdebuginfod, and the 2025.2 toolchain's bundled copy
 * needs glibc 2.34+. The toolchain readelf hard-links libdebuginfod only to
 * (optionally) fetch missing debug info from a server; for local ELF files
 * (AIE elfgen `readelf --debug-dump=decodedline`) it is never needed. These
 * no-op stubs satisfy the dynamic dependency; every lookup reports "not found".
 */
struct debuginfod_client;

struct debuginfod_client *debuginfod_begin(void) { return 0; }
void debuginfod_end(struct debuginfod_client *c) { (void)c; }

int debuginfod_find_debuginfo(struct debuginfod_client *c, const unsigned char *id, int t, char **p) {
    (void)c; (void)id; (void)t; if (p) *p = 0; return -38; }
int debuginfod_find_executable(struct debuginfod_client *c, const unsigned char *id, int t, char **p) {
    (void)c; (void)id; (void)t; if (p) *p = 0; return -38; }
int debuginfod_find_source(struct debuginfod_client *c, const unsigned char *id, int t, const char *f, char **p) {
    (void)c; (void)id; (void)t; (void)f; if (p) *p = 0; return -38; }
int debuginfod_find_section(struct debuginfod_client *c, const unsigned char *id, int t, const char *s, char **p) {
    (void)c; (void)id; (void)t; (void)s; if (p) *p = 0; return -38; }

void debuginfod_set_progressfn(struct debuginfod_client *c, void *fn) { (void)c; (void)fn; }
void debuginfod_set_verbose_fd(struct debuginfod_client *c, int fd) { (void)c; (void)fd; }
void debuginfod_set_user_data(struct debuginfod_client *c, void *d) { (void)c; (void)d; }
void *debuginfod_get_user_data(struct debuginfod_client *c) { (void)c; return 0; }
const char *debuginfod_get_url(struct debuginfod_client *c) { (void)c; return 0; }
int debuginfod_add_http_header(struct debuginfod_client *c, const char *h) { (void)c; (void)h; return 0; }
