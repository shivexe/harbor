#include "window.h"
#include <QApplication>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QLockFile>
#include <QMessageBox>
int main(int argc, char **argv) {
    QApplication application(argc, argv);
    application.setApplicationName("Harbor");
    application.setOrganizationName("Harbor");
    applyTheme(application);
    const auto directory = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(directory);
    QFile::setPermissions(directory, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    QLockFile lock(directory + "/workspace.lock");
    if (!lock.tryLock(100)) { QMessageBox::warning(nullptr, "Harbor is already open", "Close the other Harbor workspace before opening this vault."); return 1; }
    const auto runtime = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    QDir sessions(runtime);
    for (const auto &name : sessions.entryList({"harbor-*"}, QDir::Dirs | QDir::NoDotAndDotDot)) QDir(sessions.filePath(name)).removeRecursively();
    Vault vault(directory + "/vault.json");
    if (!unlockVault(vault)) return 0;
    Window window(vault);
    window.show();
    return application.exec();
}
