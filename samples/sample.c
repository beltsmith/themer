#include <stdbool.h>
#include <stdio.h>

#define MAX_ITEMS 64
#define SQUARE(x) ((x) * (x))

typedef struct node {
    int value;
    struct node *next;
} node_t;

static const double RATIO = 0.75;
static int counter = 0;

/* Sum a list, stopping at a negative value. */
// TODO: guard against cycles
// printf("debug\n");
int sum_list(const node_t *head, int limit)
{
    int total = 0;
    bool done = false;
    for (const node_t *n = head; n != NULL; n = n->next) {
        if (n->value < 0)
            break;
        if (n->value == 0)
            continue;
        total += SQUARE(n->value);
        if (total > limit)
            return -1;
    }
    printf("total: %d\n", total);
    counter++;
    return done ? 0 : total;
}
