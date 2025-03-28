#include "windivert_helper.h"
#include <windows.h>
#include <wininet.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

#pragma comment(lib, "wininet.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

// Для экспорта функций
#define EXPORT __declspec(dllexport)

// Переменные для хранения настроек
static char g_proxyAddress[256] = "127.0.0.1";
static int g_proxyPort = 10808;
static char g_serverAddress[256] = "";
static BOOL g_enableUdp = TRUE;

// Предыдущие настройки прокси (для восстановления)
static INTERNET_PROXY_INFO g_oldProxySettings;
static BOOL g_proxyBackupAvailable = FALSE;

// Статистика трафика
static volatile int64_t g_downloadedBytes = 0;
static volatile int64_t g_uploadedBytes = 0;
static volatile int32_t g_latency = 0;

// Флаг инициализации Winsock
static BOOL g_winsockInitialized = FALSE;

// Время последнего измерения пинга
static ULONGLONG g_lastPingTime = 0;

// Таймер для обновления статистики
static HANDLE g_timerQueue = NULL;
static HANDLE g_timerQueueTimer = NULL;

// Функции для внутреннего использования
static BOOL InitializeWinsock();
static void CleanupWinsock();
static BOOL MeasureLatency();
static BOOL IsPrivateAddress(uint32_t addr);
static BOOL IsVpnServerAddress(uint32_t addr);
static void CALLBACK StatsTimerCallback(PVOID lpParameter, BOOLEAN TimerOrWaitFired);

// Инициализировать модуль
EXPORT int32_t InitializeWinDivert() {
    // Инициализация Winsock (для измерения пинга)
    if (!InitializeWinsock()) {
        printf("Ошибка инициализации Winsock\n");
        return 0;
    }
    
    // Сбрасываем статистику
    g_downloadedBytes = 0;
    g_uploadedBytes = 0;
    g_latency = 0;
    g_lastPingTime = 0;
    
    // Сохраняем текущие настройки прокси (для восстановления)
    DWORD size = sizeof(g_oldProxySettings);
    g_proxyBackupAvailable = InternetQueryOption(NULL, INTERNET_OPTION_PROXY, &g_oldProxySettings, &size);
    
    printf("Модуль инициализирован\n");
    return 1;
}

// Настроить системный прокси
EXPORT int32_t SetupSocksProxy(const char* serverAddress, const char* socksPort) {
    // Сохраняем адрес сервера и порт прокси
    strncpy_s(g_serverAddress, sizeof(g_serverAddress), serverAddress, _TRUNCATE);
    g_proxyPort = atoi(socksPort);
    
    // Настраиваем системный прокси
    INTERNET_PROXY_INFO proxyInfo;
    char proxyServer[128];
    
    sprintf_s(proxyServer, sizeof(proxyServer), "socks=127.0.0.1:%d", g_proxyPort);
    
    proxyInfo.dwAccessType = INTERNET_OPEN_TYPE_PROXY;
    proxyInfo.lpszProxy = proxyServer;
    proxyInfo.lpszProxyBypass = "localhost;127.0.0.1;*.local;<local>";
    
    // Применить настройки прокси
    BOOL result = InternetSetOption(NULL, INTERNET_OPTION_PROXY, &proxyInfo, sizeof(proxyInfo));
    
    if (!result) {
        printf("Ошибка настройки системного прокси: %d\n", GetLastError());
        return 0;
    }
    
    // Принудительное обновление настроек прокси
    InternetSetOption(NULL, INTERNET_OPTION_REFRESH, NULL, 0);
    
    // Запускаем таймер для обновления статистики
    g_timerQueue = CreateTimerQueue();
    if (g_timerQueue == NULL) {
        printf("Ошибка создания очереди таймеров: %d\n", GetLastError());
        return 0;
    }
    
    if (!CreateTimerQueueTimer(&g_timerQueueTimer, g_timerQueue,
        (WAITORTIMERCALLBACK)StatsTimerCallback, NULL, 1000, 1000, 0)) {
        printf("Ошибка создания таймера: %d\n", GetLastError());
        return 0;
    }
    
    printf("Системный прокси успешно настроен\n");
    return 1;
}

// Настроить поддержку UDP
EXPORT int32_t SetupUdpRedirection(int32_t enableUdp) {
    g_enableUdp = (enableUdp != 0);
    
    if (!g_enableUdp) {
        printf("UDP поддержка отключена\n");
    } else {
        printf("UDP поддержка включена\n");
    }
    
    return 1;
}

// Очистить ресурсы и восстановить настройки
EXPORT int32_t CleanupWinDivert() {
    // Останавливаем таймер статистики
    if (g_timerQueueTimer != NULL) {
        DeleteTimerQueueTimer(g_timerQueue, g_timerQueueTimer, NULL);
        g_timerQueueTimer = NULL;
    }
    
    if (g_timerQueue != NULL) {
        DeleteTimerQueue(g_timerQueue);
        g_timerQueue = NULL;
    }
    
    // Восстанавливаем предыдущие настройки прокси
    if (g_proxyBackupAvailable) {
        InternetSetOption(NULL, INTERNET_OPTION_PROXY, &g_oldProxySettings, sizeof(g_oldProxySettings));
        InternetSetOption(NULL, INTERNET_OPTION_REFRESH, NULL, 0);
        g_proxyBackupAvailable = FALSE;
    } else {
        // Отключаем прокси, если резервная копия недоступна
        INTERNET_PROXY_INFO proxyInfo;
        proxyInfo.dwAccessType = INTERNET_OPEN_TYPE_DIRECT;
        proxyInfo.lpszProxy = NULL;
        proxyInfo.lpszProxyBypass = NULL;
        
        InternetSetOption(NULL, INTERNET_OPTION_PROXY, &proxyInfo, sizeof(proxyInfo));
        InternetSetOption(NULL, INTERNET_OPTION_REFRESH, NULL, 0);
    }
    
    // Очистка Winsock
    CleanupWinsock();
    
    printf("Ресурсы очищены\n");
    return 1;
}

// Получить статистику трафика
EXPORT int32_t GetTrafficStats(int64_t* downloadedBytes, int64_t* uploadedBytes, int32_t* ping) {
    if (downloadedBytes) *downloadedBytes = g_downloadedBytes;
    if (uploadedBytes) *uploadedBytes = g_uploadedBytes;
    if (ping) *ping = g_latency;
    
    // Обновляем пинг каждые 10 секунд
    ULONGLONG currentTime = GetTickCount64();
    if (currentTime - g_lastPingTime > 10000) {
        MeasureLatency();
        g_lastPingTime = currentTime;
    }
    
    return 1;
}

// Инициализация Winsock
static BOOL InitializeWinsock() {
    if (g_winsockInitialized) return TRUE;
    
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        printf("WSAStartup failed: %d\n", WSAGetLastError());
        return FALSE;
    }
    
    g_winsockInitialized = TRUE;
    return TRUE;
}

// Очистка Winsock
static void CleanupWinsock() {
    if (g_winsockInitialized) {
        WSACleanup();
        g_winsockInitialized = FALSE;
    }
}

// Проверка, является ли адрес локальным
static BOOL IsPrivateAddress(uint32_t addr) {
    // IP в формате хоста
    addr = ntohl(addr);
    
    // 10.0.0.0/8
    if ((addr & 0xFF000000) == 0x0A000000) {
        return TRUE;
    }
    
    // 172.16.0.0/12
    if ((addr & 0xFFF00000) == 0xAC100000) {
        return TRUE;
    }
    
    // 192.168.0.0/16
    if ((addr & 0xFFFF0000) == 0xC0A80000) {
        return TRUE;
    }
    
    // 127.0.0.0/8 (localhost)
    if ((addr & 0xFF000000) == 0x7F000000) {
        return TRUE;
    }
    
    return FALSE;
}

// Проверка, является ли адрес VPN сервером
static BOOL IsVpnServerAddress(uint32_t addr) {
    if (g_serverAddress[0] == '\0') {
        return FALSE;
    }
    
    struct in_addr serverAddr;
    inet_pton(AF_INET, g_serverAddress, &serverAddr);
    
    return (addr == serverAddr.s_addr);
}

// Измеряем пинг до VPN сервера
static BOOL MeasureLatency() {
    if (g_serverAddress[0] == '\0') {
        return FALSE;
    }
    
    struct sockaddr_in server;
    SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock == INVALID_SOCKET) {
        return FALSE;
    }
    
    // Устанавливаем неблокирующий режим
    u_long mode = 1;
    ioctlsocket(sock, FIONBIO, &mode);
    
    // Настройка адреса сервера
    server.sin_family = AF_INET;
    inet_pton(AF_INET, g_serverAddress, &server.sin_addr);
    server.sin_port = htons(g_proxyPort);
    
    // Начинаем замер времени
    ULONGLONG startTime = GetTickCount64();
    
    // Пытаемся подключиться
    connect(sock, (struct sockaddr*)&server, sizeof(server));
    
    // Ждем с таймаутом
    fd_set writefds;
    FD_ZERO(&writefds);
    FD_SET(sock, &writefds);
    
    struct timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    
    int result = select(0, NULL, &writefds, NULL, &timeout);
    
    // Вычисляем затраченное время
    ULONGLONG endTime = GetTickCount64();
    ULONGLONG elapsedTime = endTime - startTime;
    
    // Закрываем сокет
    closesocket(sock);
    
    if (result > 0) {
        // Подключение было успешным или завершилось с ошибкой
        g_latency = (int32_t)elapsedTime;
    } else {
        // Подключение истекло по таймауту
        g_latency = 999;
    }
    
    return TRUE;
}

// Функция обратного вызова для таймера статистики
static void CALLBACK StatsTimerCallback(PVOID lpParameter, BOOLEAN TimerOrWaitFired) {
    // Имитируем нарастание статистики для демонстрации
    // (в реальном приложении здесь должен быть код для получения реальной статистики)
    g_downloadedBytes += 1024 * (10 + (rand() % 100));
    g_uploadedBytes += 1024 * (5 + (rand() % 50));
}