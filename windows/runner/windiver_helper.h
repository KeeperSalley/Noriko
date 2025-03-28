#ifndef WINDIVERT_HELPER_H
#define WINDIVERT_HELPER_H

#include <windows.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Инициализировать WinDivert и системные фильтры
bool InitializeWinDivert();

// Добавить фильтры для UDP-трафика
bool AddUdpFilters();

// Запустить UDP прокси
bool StartUdpProxy(int proxyPort);

// Очистить все фильтры и ресурсы
bool CleanupWinDivert();

// Установить TAP-адаптер
bool InstallTapAdapter(const char* installerPath);

// Настроить TAP-адаптер
bool ConfigureTapAdapter(const char* adapterName, const char* ipAddress, const char* netmask);

// Получить имя TAP-адаптера
bool GetTapAdapterName(char* adapterName, int bufferSize);

// Настроить маршрутизацию для VPN
bool ConfigureVpnRouting(const char* serverAddress, const char* tapGateway);

// Восстановить маршрутизацию
bool RestoreRouting();

#ifdef __cplusplus
}
#endif

#endif // WINDIVERT_HELPER_H