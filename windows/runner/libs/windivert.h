#ifndef WINDIVERT_HELPER_H
#define WINDIVERT_HELPER_H

#include <windows.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Инициализация модуля
__declspec(dllexport) int32_t InitializeWinDivert();

// Настройка системного прокси
__declspec(dllexport) int32_t SetupSocksProxy(const char* serverAddress, const char* socksPort);

// Настройка поддержки UDP
__declspec(dllexport) int32_t SetupUdpRedirection(int32_t enableUdp);

// Очистка ресурсов и восстановление настроек
__declspec(dllexport) int32_t CleanupWinDivert();

// Получение статистики трафика
__declspec(dllexport) int32_t GetTrafficStats(int64_t* downloadedBytes, int64_t* uploadedBytes, int32_t* ping);

#ifdef __cplusplus
}
#endif

#endif // WINDIVERT_HELPER_H