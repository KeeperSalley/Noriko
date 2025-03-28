#ifndef WINDIVERT_H
#define WINDIVERT_H

#include <windows.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Определения WinDivert
#define WINDIVERT_LAYER_NETWORK            0
#define WINDIVERT_LAYER_NETWORK_FORWARD    1

typedef void *HANDLE_WINDIVERT;

// Открыть WinDivert
HANDLE_WINDIVERT WinDivertOpen(
    const char *filter,
    UINT8 layer,
    INT16 priority,
    UINT64 flags);

// Закрыть WinDivert
BOOL WinDivertClose(
    HANDLE_WINDIVERT handle);

// Получить пакет
BOOL WinDivertRecv(
    HANDLE_WINDIVERT handle,
    PVOID pPacket,
    UINT packetLen,
    PVOID pAddr,
    UINT *pAddrLen);

// Отправить пакет
BOOL WinDivertSend(
    HANDLE_WINDIVERT handle,
    PVOID pPacket,
    UINT packetLen,
    PVOID pAddr,
    UINT *pAddrLen);

// Установить параметр
BOOL WinDivertSetParam(
    HANDLE_WINDIVERT handle,
    INT param,
    UINT64 value);

#ifdef __cplusplus
}
#endif

#endif /* WINDIVERT_H */