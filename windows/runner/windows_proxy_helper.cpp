#include "windows_proxy_helper.h"
#include <windows.h>
#include <winreg.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>
#include <string.h>

// Для экспорта функций
#define EXPORT __declspec(dllexport)

// Настройки прокси
static char g_proxyAddress[256] = "127.0.0.1";
static int g_proxyPort = 10808;
static BOOL g_proxyEnabled = FALSE;

// Резервные копии настроек
static char g_oldProxyServer[512] = "";
static BOOL g_oldProxyEnable = FALSE;

// Статистика трафика
static volatile int64_t g_downloadedBytes = 0;
static volatile int64_t g_uploadedBytes = 0;
static volatile int32_t g_latency = 0;

// Инициализация
EXPORT int32_t InitializeProxy() {
    // Сохраняем текущие настройки прокси
    ReadProxySettings();
    
    // Сбрасываем статистику
    g_downloadedBytes = 0;
    g_uploadedBytes = 0;
    g_latency = 0;
    
    printf("Модуль прокси инициализирован\n");
    return 1;
}

// Настройка системного прокси
EXPORT int32_t SetupProxy(const char* socksPort) {
    // Запоминаем порт
    g_proxyPort = atoi(socksPort);
    
    // Настраиваем прокси тремя способами для максимальной надежности
    BOOL success = FALSE;
    
    // 1. Через реестр для Internet Explorer / Edge Legacy
    success = SetProxySettingsViaRegistry();
    
    // 2. Через WinHTTP для большинства приложений
    success = success || SetProxySettingsViaWinHTTP();
    
    // 3. Через командную строку для дополнительной надежности
    success = success || SetProxySettingsViaCommandLine();
    
    if (!success) {
        printf("Не удалось настроить прокси ни одним из методов\n");
        return 0;
    }
    
    g_proxyEnabled = TRUE;
    printf("Прокси успешно настроен на порт %d\n", g_proxyPort);
    return 1;
}

// Отключение прокси и восстановление настроек
EXPORT int32_t DisableProxy() {
    // Отключаем прокси и восстанавливаем настройки
    if (g_proxyEnabled) {
        // 1. Восстановление через реестр
        RestoreProxySettingsViaRegistry();
        
        // 2. Восстановление через WinHTTP
        RestoreProxySettingsViaWinHTTP();
        
        // 3. Восстановление через командную строку
        RestoreProxySettingsViaCommandLine();
        
        g_proxyEnabled = FALSE;
        printf("Прокси отключен и настройки восстановлены\n");
    }
    
    return 1;
}

// Получение статистики
EXPORT int32_t GetStatistics(int64_t* downloaded, int64_t* uploaded, int32_t* ping) {
    // В демонстрационных целях увеличиваем статистику
    static DWORD lastTick = GetTickCount();
    DWORD currentTick = GetTickCount();
    DWORD elapsed = currentTick - lastTick;
    
    if (elapsed > 1000) {
        g_downloadedBytes += 1024 * (10 + rand() % 90);
        g_uploadedBytes += 1024 * (5 + rand() % 45);
        g_latency = 30 + rand() % 70;
        lastTick = currentTick;
    }
    
    if (downloaded) *downloaded = g_downloadedBytes;
    if (uploaded) *uploaded = g_uploadedBytes;
    if (ping) *ping = g_latency;
    
    return 1;
}

// Чтение текущих настроек прокси
static BOOL ReadProxySettings() {
    HKEY hKey;
    DWORD type = REG_SZ;
    DWORD dataSize = sizeof(g_oldProxyServer);
    DWORD enableSize = sizeof(g_oldProxyEnable);
    
    // Открываем ключ реестра
    if (RegOpenKeyExA(HKEY_CURRENT_USER, 
                     "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings", 
                     0, KEY_READ, &hKey) != ERROR_SUCCESS) {
        printf("Не удалось открыть ключ реестра\n");
        return FALSE;
    }
    
    // Читаем текущие настройки
    RegQueryValueExA(hKey, "ProxyServer", NULL, &type, (LPBYTE)g_oldProxyServer, &dataSize);
    
    DWORD enable;
    RegQueryValueExA(hKey, "ProxyEnable", NULL, &type, (LPBYTE)&enable, &enableSize);
    g_oldProxyEnable = (enable != 0);
    
    RegCloseKey(hKey);
    return TRUE;
}

// Настройка прокси через реестр Windows
static BOOL SetProxySettingsViaRegistry() {
    HKEY hKey;
    
    // Открываем ключ реестра для записи
    if (RegOpenKeyExA(HKEY_CURRENT_USER, 
                     "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings", 
                     0, KEY_WRITE, &hKey) != ERROR_SUCCESS) {
        printf("Не удалось открыть ключ реестра для записи\n");
        return FALSE;
    }
    
    // Формируем строку прокси
    char proxyServer[256];
    sprintf_s(proxyServer, sizeof(proxyServer), "socks=127.0.0.1:%d", g_proxyPort);
    
    // Устанавливаем настройки прокси
    DWORD enable = 1;
    RegSetValueExA(hKey, "ProxyEnable", 0, REG_DWORD, (LPBYTE)&enable, sizeof(enable));
    RegSetValueExA(hKey, "ProxyServer", 0, REG_SZ, (LPBYTE)proxyServer, strlen(proxyServer) + 1);
    
    // Обходной список
    const char* proxyBypass = "localhost;127.0.0.1;<local>";
    RegSetValueExA(hKey, "ProxyOverride", 0, REG_SZ, (LPBYTE)proxyBypass, strlen(proxyBypass) + 1);
    
    RegCloseKey(hKey);
    
    // Уведомляем систему об изменениях
    InternetSetOptionA(NULL, INTERNET_OPTION_REFRESH, NULL, 0);
    
    return TRUE;
}

// Настройка прокси через WinHTTP
static BOOL SetProxySettingsViaWinHTTP() {
    // Этот метод требует WinHTTP.dll
    // Для простоты демонстрации опущен
    // В реальной реализации использовать WinHttpSetDefaultProxyConfiguration
    
    return FALSE; // Демонстрационная заглушка
}

// Настройка прокси через командную строку
static BOOL SetProxySettingsViaCommandLine() {
    char command[512];
    
    // Формируем команду для netsh
    sprintf_s(command, sizeof(command), 
              "netsh winhttp set proxy 127.0.0.1:%d \"localhost;127.0.0.1;<local>\"", 
              g_proxyPort);
    
    // Выполняем команду
    int result = system(command);
    
    return (result == 0);
}

// Восстановление настроек прокси через реестр
static BOOL RestoreProxySettingsViaRegistry() {
    HKEY hKey;
    
    // Открываем ключ реестра для записи
    if (RegOpenKeyExA(HKEY_CURRENT_USER, 
                     "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings", 
                     0, KEY_WRITE, &hKey) != ERROR_SUCCESS) {
        printf("Не удалось открыть ключ реестра для восстановления\n");
        return FALSE;
    }
    
    // Восстанавливаем настройки
    DWORD enable = g_oldProxyEnable ? 1 : 0;
    RegSetValueExA(hKey, "ProxyEnable", 0, REG_DWORD, (LPBYTE)&enable, sizeof(enable));
    
    if (g_oldProxyServer[0] != '\0') {
        RegSetValueExA(hKey, "ProxyServer", 0, REG_SZ, (LPBYTE)g_oldProxyServer, strlen(g_oldProxyServer) + 1);
    } else {
        RegDeleteValueA(hKey, "ProxyServer");
    }
    
    RegCloseKey(hKey);
    
    // Уведомляем систему об изменениях
    InternetSetOptionA(NULL, INTERNET_OPTION_REFRESH, NULL, 0);
    
    return TRUE;
}

// Восстановление настроек прокси через WinHTTP
static BOOL RestoreProxySettingsViaWinHTTP() {
    // Этот метод требует WinHTTP.dll
    // Для простоты демонстрации опущен
    
    return FALSE; // Демонстрационная заглушка
}

// Восстановление настроек прокси через командную строку
static BOOL RestoreProxySettingsViaCommandLine() {
    // Отключаем прокси через netsh
    int result = system("netsh winhttp reset proxy");
    
    return (result == 0);
}