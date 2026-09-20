#pragma once
#include "vault.h"
#include "sync.h"
#include <QMainWindow>
class QTreeWidget;
class QLineEdit;
class QTabWidget;
class QLabel;
class QPushButton;
class QToolButton;
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
    QLabel *endpoint_;
    QLabel *username_;
    QLabel *port_;
    QLabel *authentication_;
    QLabel *fingerprint_;
    QLabel *notes_;
    QWidget *hostFields_;
    QLabel *connectionHeading_;
    QLabel *status_;
    QPushButton *connect_;
    QToolButton *hostMenu_;
    QPushButton *add_;
    QPushButton *emptyAdd_;
    QPushButton *clearSearch_;
    QString selected_;
    QJsonObject selectedHost() const;
    QJsonObject hostById(const QString &id) const;
    void refresh();
    void select();
    void editHost(bool creating, const QString &id = {});
    void connectHost();
    void openHost(const QJsonObject &host);
    void removeHost();
    void pair();
    void devices();
    void lockVault();
    void sharing(bool enabled);
    void error(const std::exception &exception);
};
bool unlockVault(Vault &vault, QWidget *parent = nullptr);
void applyTheme(class QApplication &application);
