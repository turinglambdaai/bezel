#include <QApplication>

#include <bezel/bezel.h>

int main(int argc, char** argv) {
    QApplication app(argc, argv);
    return bezel_version() == 1 ? 0 : 1;
}
