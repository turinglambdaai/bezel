// widgets.cpp — widget constructors and the shared widget API.
//
// Constructors follow Qt ownership: a non-null parent makes Qt own the
// object; a null parent hands ownership to the caller (Racket attaches
// finalizers). All Qt work goes through on_gui.

#include "internal.h"

#include <QApplication>
#include <QBuffer>

#include <cstdlib>
#include <QAction>
#include <QByteArray>
#include <QCheckBox>
#include <QComboBox>
#include <QDate>
#include <QDateEdit>
#include <QHeaderView>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMainWindow>
#include <QPixmap>
#include <QPlainTextEdit>
#include <QProgressBar>
#include <QPushButton>
#include <QScreen>
#include <QSlider>
#include <QSpinBox>
#include <QTableWidget>
#include <QTableWidgetItem>
#include <QTreeWidget>
#include <QTreeWidgetItem>
#include <QWidget>

namespace {

using namespace bezel;

QWidget* resolve_widget(bezel_handle h, const char* what) {
    return resolve_as<QWidget>(h, what);
}

}  // namespace

// ---- constructors -------------------------------------------------------

using namespace bezel;

BEZEL_EXPORT bezel_handle bezel_window_new(void) {
    return on_gui([]() -> bezel_handle { return register_object(new QMainWindow()); });
}

BEZEL_EXPORT bezel_handle bezel_widget_new(bezel_handle parent) {
    return on_gui([parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_widget_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QWidget(p));
    });
}

BEZEL_EXPORT bezel_handle bezel_label_new(const char* text, bezel_handle parent) {
    return on_gui([text, parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_label_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QLabel(QString::fromUtf8(text ? text : ""), p));
    });
}

BEZEL_EXPORT bezel_handle bezel_button_new(const char* text, bezel_handle parent) {
    return on_gui([text, parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_button_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QPushButton(QString::fromUtf8(text ? text : ""), p));
    });
}

BEZEL_EXPORT bezel_handle bezel_checkbox_new(const char* text, bezel_handle parent) {
    return on_gui([text, parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_checkbox_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QCheckBox(QString::fromUtf8(text ? text : ""), p));
    });
}

BEZEL_EXPORT bezel_handle bezel_lineedit_new(const char* text, bezel_handle parent) {
    return on_gui([text, parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_lineedit_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QLineEdit(QString::fromUtf8(text ? text : ""), p));
    });
}

BEZEL_EXPORT bezel_handle bezel_textedit_new(bezel_handle parent) {
    return on_gui([parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_textedit_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QPlainTextEdit(p));
    });
}

BEZEL_EXPORT bezel_handle bezel_combo_new(bezel_handle parent) {
    return on_gui([parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_combo_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QComboBox(p));
    });
}

BEZEL_EXPORT bezel_handle bezel_spinbox_new(bezel_handle parent) {
    return on_gui([parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_spinbox_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QSpinBox(p));
    });
}

BEZEL_EXPORT bezel_handle bezel_slider_new(int vertical, bezel_handle parent) {
    return on_gui([vertical, parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_slider_new") : nullptr;
        if (parent && !p) return nullptr;
        const Qt::Orientation o = vertical ? Qt::Vertical : Qt::Horizontal;
        return register_object(new QSlider(o, p));
    });
}

BEZEL_EXPORT bezel_handle bezel_progress_new(bezel_handle parent) {
    return on_gui([parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_progress_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QProgressBar(p));
    });
}

BEZEL_EXPORT bezel_handle bezel_list_new(bezel_handle parent) {
    return on_gui([parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_list_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QListWidget(p));
    });
}

// ---- QWidget shared API --------------------------------------------------

BEZEL_EXPORT int bezel_widget_show(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_show");
        if (!w) return 0;
        w->show();
        note_window_shown();  // arms quit-on-last-window-closed for the pump
        return 1;
    });
}

BEZEL_EXPORT int bezel_widget_close(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_close");
        if (!w) return 0;
        return w->close() ? 1 : 0;
    });
}

BEZEL_EXPORT int bezel_widget_hide(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_hide");
        if (!w) return 0;
        w->hide();
        return 1;
    });
}

BEZEL_EXPORT int bezel_widget_set_enabled(bezel_handle h, int enabled) {
    return on_gui([h, enabled]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_set_enabled");
        if (!w) return 0;
        w->setEnabled(enabled != 0);
        return 1;
    });
}

BEZEL_EXPORT int bezel_widget_is_enabled(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_is_enabled");
        return w ? (w->isEnabled() ? 1 : 0) : -1;
    });
}

BEZEL_EXPORT int bezel_widget_resize(bezel_handle h, int w, int hgt) {
    return on_gui([h, w, hgt]() -> int {
        QWidget* widget = resolve_widget(h, "bezel_widget_resize");
        if (!widget) return 0;
        widget->resize(w, hgt);
        return 1;
    });
}

BEZEL_EXPORT int bezel_widget_move(bezel_handle h, int x, int y) {
    return on_gui([h, x, y]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_move");
        if (!w) return 0;
        w->move(x, y);
        return 1;
    });
}

BEZEL_EXPORT int bezel_window_set_title(bezel_handle h, const char* title) {
    return on_gui([h, title]() -> int {
        QWidget* w = resolve_widget(h, "bezel_window_set_title");
        if (!w) return 0;
        w->setWindowTitle(QString::fromUtf8(title ? title : ""));
        return 1;
    });
}

BEZEL_EXPORT int bezel_widget_set_stylesheet(bezel_handle h, const char* qss) {
    return on_gui([h, qss]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_set_stylesheet");
        if (!w) return 0;
        w->setStyleSheet(QString::fromUtf8(qss ? qss : ""));
        return 1;
    });
}

BEZEL_EXPORT const unsigned char* bezel_widget_grab_png(bezel_handle h, int* len_out) {
    return on_gui([h, len_out]() -> const unsigned char* {
        QWidget* w = resolve_widget(h, "bezel_widget_grab_png");
        if (!w || !len_out) {
            if (len_out) *len_out = 0;
            set_error("bezel_widget_grab_png: dead or unknown handle %p", h);
            return nullptr;
        }
        const QPixmap pm = w->grab();
        QByteArray png;
        QBuffer buf(&png);
        buf.open(QIODevice::WriteOnly);
        pm.toImage().save(&buf, "PNG");
        const auto n = static_cast<size_t>(png.size());
        void* copy = std::malloc(n > 0 ? n : 1);
        if (!copy) {
            *len_out = 0;
            set_error("bezel_widget_grab_png: out of memory");
            return nullptr;
        }
        std::memcpy(copy, png.constData(), n);
        *len_out = static_cast<int>(n);
        return static_cast<const unsigned char*>(copy);
    });
}

// ---- tooltips / geometry -------------------------------------------------

BEZEL_EXPORT int bezel_widget_set_tooltip(bezel_handle h, const char* text) {
    return on_gui([h, text]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_set_tooltip");
        if (!w) return 0;
        w->setToolTip(QString::fromUtf8(text ? text : ""));
        return 1;
    });
}

BEZEL_EXPORT const char* bezel_widget_tooltip(bezel_handle h) {
    return on_gui([h]() -> const char* {
        QWidget* w = resolve_widget(h, "bezel_widget_tooltip");
        return w ? strdup_q(w->toolTip()) : nullptr;
    });
}

BEZEL_EXPORT int bezel_widget_set_focus(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_set_focus");
        if (!w) return 0;
        w->setFocus(Qt::OtherFocusReason);
        return 1;
    });
}

BEZEL_EXPORT int bezel_widget_is_visible(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_is_visible");
        return w ? (w->isVisible() ? 1 : 0) : -1;
    });
}

BEZEL_EXPORT const char* bezel_window_title(bezel_handle h) {
    return on_gui([h]() -> const char* {
        QWidget* w = resolve_widget(h, "bezel_window_title");
        return w ? strdup_q(w->windowTitle()) : nullptr;
    });
}

BEZEL_EXPORT int bezel_widget_width(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_width");
        return w ? w->width() : -1;
    });
}

BEZEL_EXPORT int bezel_widget_height(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_height");
        return w ? w->height() : -1;
    });
}

BEZEL_EXPORT int bezel_widget_x(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_x");
        return w ? w->x() : -1;
    });
}

BEZEL_EXPORT int bezel_widget_y(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_y");
        return w ? w->y() : -1;
    });
}

BEZEL_EXPORT int bezel_widget_center(bezel_handle h) {
    return on_gui([h]() -> int {
        QWidget* w = resolve_widget(h, "bezel_widget_center");
        if (!w) return 0;
        if (QWidget* p = w->parentWidget()) {
            w->move((p->width() - w->width()) / 2, (p->height() - w->height()) / 2);
        } else if (QScreen* s = w->screen()) {
            const QRect g = s->availableGeometry();
            w->move(g.center().x() - w->width() / 2, g.center().y() - w->height() / 2);
        } else {
            set_error("bezel_widget_center: no screen for handle %p", h);
            return 0;
        }
        return 1;
    });
}

// ---- table widget ----------------------------------------------------------

BEZEL_EXPORT bezel_handle bezel_table_new(bezel_handle parent) {
    return on_gui([parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_table_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QTableWidget(p));
    });
}

BEZEL_EXPORT int bezel_table_set_dimensions(bezel_handle h, int rows, int cols) {
    return on_gui([h, rows, cols]() -> int {
        QTableWidget* t = resolve_as<QTableWidget>(h, "bezel_table_set_dimensions");
        if (!t) return 0;
        t->setRowCount(rows);
        t->setColumnCount(cols);
        return 1;
    });
}

BEZEL_EXPORT int bezel_table_row_count(bezel_handle h) {
    return on_gui([h]() -> int {
        QTableWidget* t = resolve_as<QTableWidget>(h, "bezel_table_row_count");
        return t ? t->rowCount() : -1;
    });
}

BEZEL_EXPORT int bezel_table_column_count(bezel_handle h) {
    return on_gui([h]() -> int {
        QTableWidget* t = resolve_as<QTableWidget>(h, "bezel_table_column_count");
        return t ? t->columnCount() : -1;
    });
}

BEZEL_EXPORT int bezel_table_set_header_labels(bezel_handle h, const char* labels) {
    return on_gui([h, labels]() -> int {
        QTableWidget* t = resolve_as<QTableWidget>(h, "bezel_table_set_header_labels");
        if (!t) return 0;
        // '\n'-separated labels follow Qt's own setHorizontalHeaderLabels
        // input convention (QAbstractItemModel::setHorizontalHeaderLabels).
        t->setHorizontalHeaderLabels(
            QString::fromUtf8(labels ? labels : "").split(QLatin1Char('\n')));
        return 1;
    });
}

BEZEL_EXPORT int bezel_table_set_cell_text(bezel_handle h, int row, int col, const char* text) {
    return on_gui([h, row, col, text]() -> int {
        QTableWidget* t = resolve_as<QTableWidget>(h, "bezel_table_set_cell_text");
        if (!t) return 0;
        if (row < 0 || row >= t->rowCount() || col < 0 || col >= t->columnCount()) {
            set_error("bezel_table_set_cell_text: cell (%d,%d) outside %dx%d table",
                      row, col, t->rowCount(), t->columnCount());
            return 0;
        }
        // The table owns the item (QTableWidgetItem has no parent pointer;
        // the view deletes items it holds).
        t->setItem(row, col, new QTableWidgetItem(QString::fromUtf8(text ? text : "")));
        return 1;
    });
}

BEZEL_EXPORT const char* bezel_table_cell_text(bezel_handle h, int row, int col) {
    return on_gui([h, row, col]() -> const char* {
        QTableWidget* t = resolve_as<QTableWidget>(h, "bezel_table_cell_text");
        if (!t) return nullptr;
        if (row < 0 || row >= t->rowCount() || col < 0 || col >= t->columnCount()) {
            set_error("bezel_table_cell_text: cell (%d,%d) outside %dx%d table",
                      row, col, t->rowCount(), t->columnCount());
            return nullptr;
        }
        QTableWidgetItem* item = t->item(row, col);
        return strdup_q(item ? item->text() : QString());
    });
}

// ---- action shortcut --------------------------------------------------------

BEZEL_EXPORT int bezel_action_set_shortcut(bezel_handle h, const char* key) {
    return on_gui([h, key]() -> int {
        QAction* a = resolve_as<QAction>(h, "bezel_action_set_shortcut");
        if (!a) return 0;
        a->setShortcut(QKeySequence(QString::fromUtf8(key ? key : "")));
        return 1;
    });
}

// ---- tree widget ------------------------------------------------------------
//
// QTreeWidgetItem is not a QObject, so items never join the handle
// registry; the API addresses them by (top-row) / (top-row, child-row).
// The view owns every item it holds.

namespace {

QStringList split_columns(const char* text) {
    // '\n'-separated per-column texts, the same convention as the table
    // headers (QTreeWidgetItem takes a QStringList).
    return QString::fromUtf8(text ? text : "").split(QLatin1Char('\n'));
}

}  // namespace

BEZEL_EXPORT bezel_handle bezel_tree_new(bezel_handle parent) {
    return on_gui([parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_tree_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QTreeWidget(p));
    });
}

BEZEL_EXPORT int bezel_tree_column_count(bezel_handle h) {
    return on_gui([h]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_column_count");
        return t ? t->columnCount() : -1;
    });
}

BEZEL_EXPORT int bezel_tree_set_header_labels(bezel_handle h, const char* labels) {
    return on_gui([h, labels]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_set_header_labels");
        if (!t) return 0;
        t->setHeaderLabels(split_columns(labels));
        return 1;
    });
}

BEZEL_EXPORT int bezel_tree_add(bezel_handle h, const char* text) {
    return on_gui([h, text]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_add");
        if (!t) return -1;
        const int row = t->topLevelItemCount();
        t->addTopLevelItem(new QTreeWidgetItem(split_columns(text)));
        return row;
    });
}

BEZEL_EXPORT int bezel_tree_count(bezel_handle h) {
    return on_gui([h]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_count");
        return t ? t->topLevelItemCount() : -1;
    });
}

BEZEL_EXPORT int bezel_tree_add_child(bezel_handle h, int row, const char* text) {
    return on_gui([h, row, text]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_add_child");
        if (!t) return -1;
        QTreeWidgetItem* parent = t->topLevelItem(row);
        if (!parent) {
            set_error("bezel_tree_add_child: no top-level item %d in a tree of %d items",
                      row, t->topLevelItemCount());
            return -1;
        }
        // QTreeWidgetItem::addChild returns void; the new child's index
        // is the pre-add child count.
        const int child = parent->childCount();
        parent->addChild(new QTreeWidgetItem(split_columns(text)));
        return child;
    });
}

BEZEL_EXPORT int bezel_tree_child_count(bezel_handle h, int row) {
    return on_gui([h, row]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_child_count");
        if (!t) return -1;
        QTreeWidgetItem* item = t->topLevelItem(row);
        if (!item) {
            set_error("bezel_tree_child_count: no top-level item %d in a tree of %d items",
                      row, t->topLevelItemCount());
            return -1;
        }
        return item->childCount();
    });
}

BEZEL_EXPORT const char* bezel_tree_item_text(bezel_handle h, int row, int col) {
    return on_gui([h, row, col]() -> const char* {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_item_text");
        if (!t) return nullptr;
        QTreeWidgetItem* item = t->topLevelItem(row);
        if (!item) {
            set_error("bezel_tree_item_text: no top-level item %d in a tree of %d items",
                      row, t->topLevelItemCount());
            return nullptr;
        }
        return strdup_q(item->text(col));
    });
}

BEZEL_EXPORT int bezel_tree_set_item_text(bezel_handle h, int row, int col, const char* text) {
    return on_gui([h, row, col, text]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_set_item_text");
        if (!t) return 0;
        QTreeWidgetItem* item = t->topLevelItem(row);
        if (!item) {
            set_error("bezel_tree_set_item_text: no top-level item %d in a tree of %d items",
                      row, t->topLevelItemCount());
            return 0;
        }
        item->setText(col, QString::fromUtf8(text ? text : ""));
        return 1;
    });
}

BEZEL_EXPORT const char* bezel_tree_child_text(bezel_handle h, int row, int child, int col) {
    return on_gui([h, row, child, col]() -> const char* {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_child_text");
        if (!t) return nullptr;
        QTreeWidgetItem* item = t->topLevelItem(row);
        if (!item || !item->child(child)) {
            set_error("bezel_tree_child_text: no child %d under top-level item %d",
                      child, row);
            return nullptr;
        }
        return strdup_q(item->child(child)->text(col));
    });
}

BEZEL_EXPORT int bezel_tree_set_child_text(bezel_handle h, int row, int child, int col,
                                           const char* text) {
    return on_gui([h, row, child, col, text]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_set_child_text");
        if (!t) return 0;
        QTreeWidgetItem* item = t->topLevelItem(row);
        if (!item || !item->child(child)) {
            set_error("bezel_tree_set_child_text: no child %d under top-level item %d",
                      child, row);
            return 0;
        }
        item->child(child)->setText(col, QString::fromUtf8(text ? text : ""));
        return 1;
    });
}

BEZEL_EXPORT int bezel_tree_current_row(bezel_handle h) {
    return on_gui([h]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_current_row");
        if (!t) return -1;
        return t->indexOfTopLevelItem(t->currentItem());
    });
}

BEZEL_EXPORT int bezel_tree_select(bezel_handle h, int row) {
    return on_gui([h, row]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_select");
        if (!t) return 0;
        QTreeWidgetItem* item = t->topLevelItem(row);
        if (!item) {
            set_error("bezel_tree_select: no top-level item %d in a tree of %d items",
                      row, t->topLevelItemCount());
            return 0;
        }
        t->setCurrentItem(item);
        return 1;
    });
}

BEZEL_EXPORT int bezel_tree_set_item_expanded(bezel_handle h, int row, int expanded) {
    return on_gui([h, row, expanded]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_set_item_expanded");
        if (!t) return 0;
        QTreeWidgetItem* item = t->topLevelItem(row);
        if (!item) {
            set_error("bezel_tree_set_item_expanded: no top-level item %d in a tree of %d items",
                      row, t->topLevelItemCount());
            return 0;
        }
        if (expanded) t->expandItem(item); else t->collapseItem(item);
        return 1;
    });
}

BEZEL_EXPORT int bezel_tree_clear(bezel_handle h) {
    return on_gui([h]() -> int {
        QTreeWidget* t = resolve_as<QTreeWidget>(h, "bezel_tree_clear");
        if (!t) return 0;
        t->clear();
        return 1;
    });
}

// ---- date editor -------------------------------------------------------------

BEZEL_EXPORT bezel_handle bezel_dateedit_new(bezel_handle parent) {
    return on_gui([parent]() -> bezel_handle {
        QWidget* p = parent ? resolve_widget(parent, "bezel_dateedit_new") : nullptr;
        if (parent && !p) return nullptr;
        return register_object(new QDateEdit(p));
    });
}

BEZEL_EXPORT int bezel_dateedit_set_date(bezel_handle h, int year, int month, int day) {
    return on_gui([h, year, month, day]() -> int {
        QDateEdit* e = resolve_as<QDateEdit>(h, "bezel_dateedit_set_date");
        if (!e) return 0;
        const QDate d(year, month, day);
        if (!d.isValid()) {
            set_error("bezel_dateedit_set_date: %04d-%02d-%02d is not a valid date",
                      year, month, day);
            return 0;
        }
        e->setDate(d);
        return 1;
    });
}

BEZEL_EXPORT int bezel_dateedit_date(bezel_handle h) {
    return on_gui([h]() -> int {
        QDateEdit* e = resolve_as<QDateEdit>(h, "bezel_dateedit_date");
        if (!e) return -1;
        const QDate d = e->date();
        return d.year() * 10000 + d.month() * 100 + d.day();
    });
}

BEZEL_EXPORT int bezel_dateedit_set_calendar_popup(bezel_handle h, int popup) {
    return on_gui([h, popup]() -> int {
        QDateEdit* e = resolve_as<QDateEdit>(h, "bezel_dateedit_set_calendar_popup");
        if (!e) return 0;
        e->setCalendarPopup(popup != 0);
        return 1;
    });
}

BEZEL_EXPORT int bezel_dateedit_set_display_format(bezel_handle h, const char* format) {
    return on_gui([h, format]() -> int {
        QDateEdit* e = resolve_as<QDateEdit>(h, "bezel_dateedit_set_display_format");
        if (!e) return 0;
        e->setDisplayFormat(QString::fromUtf8(format ? format : ""));
        return 1;
    });
}

// ---- value API -----------------------------------------------------------

BEZEL_EXPORT int bezel_widget_set_text(bezel_handle h, const char* text) {
    return on_gui([h, text]() -> int {
        const QString s = QString::fromUtf8(text ? text : "");
        if (auto* w = resolve_as<QLabel>(h, "bezel_widget_set_text")) { w->setText(s); return 1; }
        if (auto* w = resolve_as<QPushButton>(h, "bezel_widget_set_text")) { w->setText(s); return 1; }
        if (auto* w = resolve_as<QCheckBox>(h, "bezel_widget_set_text")) { w->setText(s); return 1; }
        if (auto* w = resolve_as<QLineEdit>(h, "bezel_widget_set_text")) { w->setText(s); return 1; }
        if (auto* w = resolve_as<QPlainTextEdit>(h, "bezel_widget_set_text")) { w->setPlainText(s); return 1; }
        set_error("bezel_widget_set_text: handle %p does not carry text", h);
        return 0;
    });
}

BEZEL_EXPORT const char* bezel_widget_text(bezel_handle h) {
    return on_gui([h]() -> const char* {
        QString s;
        if (auto* w = qobject_cast<QLabel*>(resolve(h))) s = w->text();
        else if (auto* w = qobject_cast<QPushButton*>(resolve(h))) s = w->text();
        else if (auto* w = qobject_cast<QCheckBox*>(resolve(h))) s = w->text();
        else if (auto* w = qobject_cast<QLineEdit*>(resolve(h))) s = w->text();
        else if (auto* w = qobject_cast<QPlainTextEdit*>(resolve(h))) s = w->toPlainText();
        else if (auto* w = qobject_cast<QComboBox*>(resolve(h))) s = w->currentText();
        else if (auto* w = qobject_cast<QListWidget*>(resolve(h))) {
            if (w->currentItem()) s = w->currentItem()->text();
        } else {
            set_error("bezel_widget_text: handle %p does not carry text", h);
            return nullptr;
        }
        return strdup_q(s);
    });
}

BEZEL_EXPORT int bezel_widget_set_checked(bezel_handle h, int checked) {
    return on_gui([h, checked]() -> int {
        if (auto* w = resolve_as<QCheckBox>(h, "bezel_widget_set_checked")) {
            w->setChecked(checked != 0);
            return 1;
        }
        return 0;
    });
}

BEZEL_EXPORT int bezel_widget_is_checked(bezel_handle h) {
    return on_gui([h]() -> int {
        if (auto* w = resolve_as<QCheckBox>(h, "bezel_widget_is_checked")) return w->isChecked() ? 1 : 0;
        return -1;
    });
}

BEZEL_EXPORT int bezel_widget_set_value(bezel_handle h, int value) {
    return on_gui([h, value]() -> int {
        if (auto* w = resolve_as<QSlider>(h, "bezel_widget_set_value")) { w->setValue(value); return 1; }
        if (auto* w = resolve_as<QSpinBox>(h, "bezel_widget_set_value")) { w->setValue(value); return 1; }
        if (auto* w = resolve_as<QProgressBar>(h, "bezel_widget_set_value")) { w->setValue(value); return 1; }
        set_error("bezel_widget_set_value: handle %p has no int value", h);
        return 0;
    });
}

BEZEL_EXPORT int bezel_widget_value(bezel_handle h) {
    return on_gui([h]() -> int {
        if (auto* w = qobject_cast<QSlider*>(resolve(h))) return w->value();
        if (auto* w = qobject_cast<QSpinBox*>(resolve(h))) return w->value();
        if (auto* w = qobject_cast<QProgressBar*>(resolve(h))) return w->value();
        set_error("bezel_widget_value: handle %p has no int value", h);
        return -1;
    });
}

BEZEL_EXPORT int bezel_widget_set_range(bezel_handle h, int min, int max) {
    return on_gui([h, min, max]() -> int {
        if (auto* w = resolve_as<QSlider>(h, "bezel_widget_set_range")) { w->setRange(min, max); return 1; }
        if (auto* w = resolve_as<QSpinBox>(h, "bezel_widget_set_range")) { w->setRange(min, max); return 1; }
        if (auto* w = resolve_as<QProgressBar>(h, "bezel_widget_set_range")) { w->setRange(min, max); return 1; }
        set_error("bezel_widget_set_range: handle %p has no int range", h);
        return 0;
    });
}

BEZEL_EXPORT int bezel_combo_add(bezel_handle h, const char* item) {
    return on_gui([h, item]() -> int {
        if (auto* w = resolve_as<QComboBox>(h, "bezel_combo_add")) {
            w->addItem(QString::fromUtf8(item ? item : ""));
            return 1;
        }
        return 0;
    });
}

BEZEL_EXPORT int bezel_combo_current_index(bezel_handle h) {
    return on_gui([h]() -> int {
        if (auto* w = resolve_as<QComboBox>(h, "bezel_combo_current_index")) return w->currentIndex();
        return -1;
    });
}

BEZEL_EXPORT const char* bezel_combo_current_text(bezel_handle h) {
    return on_gui([h]() -> const char* {
        if (auto* w = resolve_as<QComboBox>(h, "bezel_combo_current_text")) return strdup_q(w->currentText());
        return nullptr;
    });
}

BEZEL_EXPORT int bezel_list_add(bezel_handle h, const char* item) {
    return on_gui([h, item]() -> int {
        if (auto* w = resolve_as<QListWidget>(h, "bezel_list_add")) {
            w->addItem(QString::fromUtf8(item ? item : ""));
            return 1;
        }
        return 0;
    });
}

BEZEL_EXPORT int bezel_list_current_row(bezel_handle h) {
    return on_gui([h]() -> int {
        if (auto* w = resolve_as<QListWidget>(h, "bezel_list_current_row")) return w->currentRow();
        return -1;
    });
}

BEZEL_EXPORT int bezel_list_set_current_row(bezel_handle h, int row) {
    return on_gui([h, row]() -> int {
        if (auto* w = resolve_as<QListWidget>(h, "bezel_list_set_current_row")) {
            w->setCurrentRow(row);
            return 1;
        }
        return 0;
    });
}

BEZEL_EXPORT int bezel_combo_set_index(bezel_handle h, int index) {
    return on_gui([h, index]() -> int {
        if (auto* w = resolve_as<QComboBox>(h, "bezel_combo_set_index")) {
            w->setCurrentIndex(index);
            return 1;
        }
        return 0;
    });
}

BEZEL_EXPORT const char* bezel_list_current_text(bezel_handle h) {
    return on_gui([h]() -> const char* {
        if (auto* w = resolve_as<QListWidget>(h, "bezel_list_current_text")) {
            return strdup_q(w->currentItem() ? w->currentItem()->text() : QString());
        }
        return nullptr;
    });
}

BEZEL_EXPORT int bezel_widget_set_placeholder(bezel_handle h, const char* text) {
    return on_gui([h, text]() -> int {
        const QString s = QString::fromUtf8(text ? text : "");
        if (auto* w = resolve_as<QLineEdit>(h, "bezel_widget_set_placeholder")) { w->setPlaceholderText(s); return 1; }
        if (auto* w = resolve_as<QPlainTextEdit>(h, "bezel_widget_set_placeholder")) { w->setPlaceholderText(s); return 1; }
        set_error("bezel_widget_set_placeholder: handle %p has no placeholder", h);
        return 0;
    });
}

BEZEL_EXPORT int bezel_widget_set_readonly(bezel_handle h, int readonly) {
    return on_gui([h, readonly]() -> int {
        if (auto* w = resolve_as<QLineEdit>(h, "bezel_widget_set_readonly")) { w->setReadOnly(readonly != 0); return 1; }
        if (auto* w = resolve_as<QPlainTextEdit>(h, "bezel_widget_set_readonly")) { w->setReadOnly(readonly != 0); return 1; }
        set_error("bezel_widget_set_readonly: handle %p is not a text input", h);
        return 0;
    });
}
