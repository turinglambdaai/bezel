#include <bezel/bezel.h>

int main() {
    return bezel_version() == 1 ? 0 : 1;
}
