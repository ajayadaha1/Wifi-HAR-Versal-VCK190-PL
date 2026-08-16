#include <stdio.h>
#include "fir_core.h"
#include "stats_core.h"

// Host validation of the composed FIR->stats chain (BLOCK == L == 256).
int main(void) {
    static float x[BLOCK], y[BLOCK], out[NOUT];
    FILE *f = fopen("data/input.txt", "r");
    if (!f) { fprintf(stderr, "cannot open data/input.txt\n"); return 1; }
    for (int i = 0; i < BLOCK; i++)
        if (fscanf(f, "%f", &x[i]) != 1) { fprintf(stderr, "read error at %d\n", i); return 1; }
    fclose(f);

    fir_core(x, y);        // stage 1
    stats_core(y, out);    // stage 2

    FILE *o = fopen("data/host_output.txt", "w");
    for (int i = 0; i < NOUT; i++) fprintf(o, "%.8e\n", out[i]);
    fclose(o);
    printf("mean=%.6f var=%.6f motion_power=%.6f\n", out[0], out[1], out[2]);
    return 0;
}
