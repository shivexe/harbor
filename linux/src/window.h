#pragma once
#include "vault.h"
#include "sync.h"
#include <QMainWindow>
class QTreeWidget;
class QLineEdit;
class QTabWidget;
class QLabel;
class QPushButton;
class Window : public QMainWindow {
    Q_OBJECT
public:
    explicit Window(Vault &vault);
private:
    Vault &vault_;
    SyncServer sync_;
    QTreeWidget *hosts_;
    QLineEdit *search_;
    QTabWidget *tabs_;
    QLabel *title_;
    QLabel *details_;
    QLabel *status_;
    QPushButton *connect_;
    QPushButton *edit_;
    QPushButton *remove_;
    QPushButton *sharing_;
    QString selected_;
    QJsonObject selectedHost() const;
    void refresh();
    void select();
    void editHost(bool creating);
    void connectHost();
    void removeHost();
    void pair();
    void devices();
    void lockVault();
    void sharing(bool enabled);
    void error(const std::exception &exception);
};
bool unlockVault(Vault &vault, QWidget *parent = nullptr);
void applyTheme(class QApplication &application);
