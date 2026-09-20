#include <QCoreApplication>
#include <QLocalSocket>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <cstdio>
#include <cerrno>
#include <unistd.h>
int main(int argc, char **argv) {
    QCoreApplication application(argc, argv);
    if (argc != 2) return 1;
    bool descriptorOk = false;
    const auto descriptor = qEnvironmentVariableIntValue("HARBOR_ASKPASS_FD", &descriptorOk);
    if (descriptorOk && descriptor >= 3) {
        QByteArray answer;
        if (lseek(descriptor, 0, SEEK_SET) != 0) return 1;
        char bytes[4096];
        bool complete = false;
        while (answer.size() <= 32768 && !complete) {
            const auto count = read(descriptor, bytes, sizeof(bytes));
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) return 1;
            const auto newline = QByteArrayView(bytes, count).indexOf('\n');
            answer.append(bytes, newline < 0 ? count : newline);
            complete = newline >= 0;
        }
        if (close(descriptor) != 0 || !complete || answer.isEmpty() || answer.size() > 32768 || std::fwrite(answer.constData(), 1, answer.size(), stdout) != static_cast<size_t>(answer.size()) || std::fputc('\n', stdout) == EOF || std::fflush(stdout) != 0) return 1;
        return 0;
    }
    const auto path = qEnvironmentVariable("HARBOR_ASKPASS_SOCKET");
    if (path.isEmpty()) return 1;
    QLocalSocket socket;
    socket.connectToServer(path);
    if (!socket.waitForConnected(5000)) return 1;
    auto prompt = QByteArray(argv[1]).left(4095);
    prompt.replace('\n', ' ');
    const QJsonObject request{{"prompt", QString::fromUtf8(prompt)}, {"capability", qEnvironmentVariable("HARBOR_ASKPASS_CAPABILITY")}};
    socket.write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
    if (!socket.waitForBytesWritten(5000)) return 1;
    QByteArray answer;
    while (!answer.contains('\n') && answer.size() <= 65536) {
        if (!socket.waitForReadyRead(5000)) return 1;
        answer += socket.readAll();
    }
    if (!answer.contains('\n') || answer.size() > 65536) return 1;
    const auto decoded = QByteArray::fromBase64(answer.split('\n').first(), QByteArray::AbortOnBase64DecodingErrors);
    if (decoded.isEmpty()) return 1;
    if (std::fwrite(decoded.constData(), 1, decoded.size(), stdout) != static_cast<size_t>(decoded.size())) return 1;
    std::fputc('\n', stdout);
    return 0;
}
