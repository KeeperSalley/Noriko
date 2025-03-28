#include "windivert_helper.h"
#include <windows.h>
#include <windivert.h>
#include <stdio.h>
#include <stdlib.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <process.h>

#pragma comment(lib, "WinDivert.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

// GUID для нашего провайдера
static const GUID PROVIDER_KEY = 
{ 0x12345678, 0x1234, 0x1234, { 0x12, 0x34, 0x12, 0x34, 0x12, 0x34, 0x12, 0x34 } };

// GUID для сублоя перехвата исходящего трафика
static const GUID SUBLAYER_KEY = 
{ 0x87654321, 0x4321, 0x4321, { 0x43, 0x21, 0x43, 0x21, 0x43, 0x21, 0x43, 0x21 } };

// Идентификаторы фильтров
static UINT64 g_filterIds[10]; 
static int g_numFilters = 0;

// Дескриптор движка WFP
static HANDLE g_engineHandle = NULL;

// Дескриптор WinDivert
static HANDLE g_winDivertHandle = NULL;

// Прокси-сервер для перенаправления трафика
static char g_proxyAddress[256] = "127.0.0.1";
static int g_proxyPort = 10810; // Порт прокси для UDP

// Дескриптор потока для UDP прокси
static HANDLE g_udpProxyThread = NULL;

// Флаг для остановки потока UDP прокси
static bool g_stopUdpProxy = false;

// Текущие настройки маршрутизации
static char g_originalGateway[256] = "";
static char g_serverAddress[256] = "";
static char g_tapGateway[256] = "";

// Флаг инициализации Winsock
static bool g_winsockInitialized = false;

// Структура для контекста UDP релея
typedef struct {
    SOCKET sourceSocket;
    SOCKET proxySocket;
    struct sockaddr_in sourceAddr;
    struct sockaddr_in destAddr;
    char buffer[8192];  // Буфер для данных
} UdpRelayContext;

// Инициализация Winsock
static bool InitializeWinsock() {
    if (g_winsockInitialized) return true;
    
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        printf("WSAStartup failed\n");
        return false;
    }
    
    g_winsockInitialized = true;
    return true;
}

// Очистка Winsock
static void CleanupWinsock() {
    if (g_winsockInitialized) {
        WSACleanup();
        g_winsockInitialized = false;
    }
}

// Функция потока для релея UDP трафика
static unsigned __stdcall UdpRelayThreadProc(void* lpParam) {
    UdpRelayContext* context = (UdpRelayContext*)lpParam;
    int sourceAddrLen = sizeof(struct sockaddr_in);
    int bytesReceived;
    fd_set readfds;
    struct timeval timeout;
    
    // Бесконечный цикл для перенаправления трафика
    while (!g_stopUdpProxy) {
        // Подготовка для select()
        FD_ZERO(&readfds);
        FD_SET(context->sourceSocket, &readfds);
        
        // Таймаут 100 мс
        timeout.tv_sec = 0;
        timeout.tv_usec = 100000;
        
        // Ждем данные на исходном сокете
        int result = select(0, &readfds, NULL, NULL, &timeout);
        
        if (result > 0 && FD_ISSET(context->sourceSocket, &readfds)) {
            // Получение данных от исходного сокета
            bytesReceived = recvfrom(
                context->sourceSocket,
                context->buffer,
                sizeof(context->buffer),
                0,
                (struct sockaddr*)&context->sourceAddr,
                &sourceAddrLen
            );
            
            if (bytesReceived > 0) {
                // Отправка данных на прокси-сервер
                sendto(
                    context->proxySocket,
                    context->buffer,
                    bytesReceived,
                    0,
                    (struct sockaddr*)&context->destAddr,
                    sizeof(struct sockaddr_in)
                );
            } else if (bytesReceived <= 0 && WSAGetLastError() != WSAEWOULDBLOCK) {
                // Ошибка или закрытие сокета
                break;
            }
        }
    }
    
    // Освобождение ресурсов
    closesocket(context->sourceSocket);
    closesocket(context->proxySocket);
    free(context);
    
    return 0;
}

// Инициализировать WinDivert и WFP
bool InitializeWinDivert() {
    // Инициализация Winsock
    if (!InitializeWinsock()) {
        return false;
    }
    
    DWORD result = ERROR_SUCCESS;
    FWPM_SESSION session = {0};
    
    // Начало транзакции с динамической сессией
    session.flags = FWPM_SESSION_FLAG_DYNAMIC;
    
    // Открытие дескриптора к движку фильтрации
    result = FwpmEngineOpen(NULL, RPC_C_AUTHN_WINNT, NULL, &session, &g_engineHandle);
    if (result != ERROR_SUCCESS) {
        printf("FwpmEngineOpen failed: %d\n", result);
        CleanupWinsock();
        return false;
    }
    
    // Начало транзакции для атомарных операций
    result = FwpmTransactionBegin(g_engineHandle, 0);
    if (result != ERROR_SUCCESS) {
        printf("FwpmTransactionBegin failed: %d\n", result);
        FwpmEngineClose(g_engineHandle);
        CleanupWinsock();
        return false;
    }
    
    // Регистрация провайдера
    FWPM_PROVIDER provider = {0};
    provider.providerKey = PROVIDER_KEY;
    provider.displayData.name = L"NorikoVPN Provider";
    provider.displayData.description = L"Provider for Noriko VPN";
    
    result = FwpmProviderAdd(g_engineHandle, &provider, NULL);
    if (result != ERROR_SUCCESS && result != FWP_E_ALREADY_EXISTS) {
        printf("FwpmProviderAdd failed: %d\n", result);
        FwpmTransactionAbort(g_engineHandle);
        FwpmEngineClose(g_engineHandle);
        CleanupWinsock();
        return false;
    }
    
    // Добавление сублоя
    FWPM_SUBLAYER sublayer = {0};
    sublayer.subLayerKey = SUBLAYER_KEY;
    sublayer.displayData.name = L"NorikoVPN Sublayer";
    sublayer.displayData.description = L"Sublayer for Noriko VPN";
    sublayer.providerKey = &PROVIDER_KEY;
    sublayer.weight = 0xFFFF;
    
    result = FwpmSubLayerAdd(g_engineHandle, &sublayer, NULL);
    if (result != ERROR_SUCCESS && result != FWP_E_ALREADY_EXISTS) {
        printf("FwpmSubLayerAdd failed: %d\n", result);
        FwpmTransactionAbort(g_engineHandle);
        FwpmEngineClose(g_engineHandle);
        CleanupWinsock();
        return false;
    }
    
    // Завершение транзакции
    result = FwpmTransactionCommit(g_engineHandle);
    if (result != ERROR_SUCCESS) {
        printf("FwpmTransactionCommit failed: %d\n", result);
        FwpmEngineClose(g_engineHandle);
        CleanupWinsock();
        return false;
    }
    
    // Открываем WinDivert для перехвата пакетов
    g_winDivertHandle = WinDivertOpen(
        "udp",  // Фильтр для UDP-пакетов
        WINDIVERT_LAYER_NETWORK,
        0,      // Приоритет
        0       // Флаги
    );
    
    if (g_winDivertHandle == INVALID_HANDLE_VALUE) {
        printf("WinDivertOpen failed: %d\n", GetLastError());
        FwpmEngineClose(g_engineHandle);
        CleanupWinsock();
        return false;
    }
    
    printf("WinDivert initialized successfully\n");
    return true;
}

// Добавить правила фильтрации для UDP трафика
bool AddUdpFilters() {
    if (g_engineHandle == NULL) {
        printf("WFP engine not initialized\n");
        return false;
    }
    
    DWORD result = ERROR_SUCCESS;
    
    // Начало транзакции
    result = FwpmTransactionBegin(g_engineHandle, 0);
    if (result != ERROR_SUCCESS) {
        printf("FwpmTransactionBegin failed: %d\n", result);
        return false;
    }
    
    // Фильтр для перехвата исходящего UDP трафика
    FWPM_FILTER filter = {0};
    FWPM_FILTER_CONDITION condition[2] = {0};
    
    // Настройка фильтра для UDP
    filter.layerKey = FWPM_LAYER_DATAGRAM_DATA_V4;  // Слой для UDP трафика
    filter.displayData.name = L"Noriko UDP Filter";
    filter.displayData.description = L"Filter for outbound UDP traffic";
    filter.action.type = FWP_ACTION_CALLOUT;
    filter.weight.type = FWP_EMPTY;  // Автоматический вес
    filter.filterCondition = condition;
    filter.subLayerKey = SUBLAYER_KEY;
    filter.numFilterConditions = 2;
    
    // Условие 1: Только исходящий трафик
    condition[0].fieldKey = FWPM_CONDITION_DIRECTION;
    condition[0].matchType = FWP_MATCH_EQUAL;
    condition[0].conditionValue.type = FWP_UINT32;
    condition[0].conditionValue.uint32 = FWP_DIRECTION_OUTBOUND;
    
    // Условие 2: Только UDP протокол
    condition[1].fieldKey = FWPM_CONDITION_IP_PROTOCOL;
    condition[1].matchType = FWP_MATCH_EQUAL;
    condition[1].conditionValue.type = FWP_UINT8;
    condition[1].conditionValue.uint8 = IPPROTO_UDP;
    
    // Добавление фильтра в систему
    result = FwpmFilterAdd(g_engineHandle, &filter, NULL, &g_filterIds[g_numFilters++]);
    if (result != ERROR_SUCCESS) {
        printf("FwpmFilterAdd for UDP failed: %d\n", result);
        FwpmTransactionAbort(g_engineHandle);
        return false;
    }
    
    // Фильтр для исключения трафика на прокси-сервер
    memset(&filter, 0, sizeof(FWPM_FILTER));
    
    filter.layerKey = FWPM_LAYER_DATAGRAM_DATA_V4;
    filter.displayData.name = L"Noriko UDP Proxy Bypass";
    filter.displayData.description = L"Bypass filter for UDP proxy traffic";
    filter.action.type = FWP_ACTION_PERMIT;
    filter.weight.type = FWP_UINT8;
    filter.weight.uint8 = 15;  // Более высокий приоритет
    filter.filterCondition = condition;
    filter.subLayerKey = SUBLAYER_KEY;
    filter.numFilterConditions = 2;
    
    // Условие 1: Только для локального адреса
    condition[0].fieldKey = FWPM_CONDITION_IP_LOCAL_ADDRESS;
    condition[0].matchType = FWP_MATCH_EQUAL;
    condition[0].conditionValue.type = FWP_UINT32;
    
    // Преобразование "127.0.0.1" в uint32
    struct in_addr addr;
    inet_pton(AF_INET, "127.0.0.1", &addr);
    condition[0].conditionValue.uint32 = addr.s_addr;
    
    // Условие 2: Только для порта прокси
    condition[1].fieldKey = FWPM_CONDITION_IP_LOCAL_PORT;
    condition[1].matchType = FWP_MATCH_EQUAL;
    condition[1].conditionValue.type = FWP_UINT16;
    condition[1].conditionValue.uint16 = g_proxyPort;
    
    // Добавление фильтра исключения
    result = FwpmFilterAdd(g_engineHandle, &filter, NULL, &g_filterIds[g_numFilters++]);
    if (result != ERROR_SUCCESS) {
        printf("FwpmFilterAdd for proxy bypass failed: %d\n", result);
        FwpmTransactionAbort(g_engineHandle);
        return false;
    }
    
    // Завершение транзакции
    result = FwpmTransactionCommit(g_engineHandle);
    if (result != ERROR_SUCCESS) {
        printf("FwpmTransactionCommit failed: %d\n", result);
        return false;
    }
    
    printf("UDP filters added successfully\n");
    return true;
}

// Запуск UDP прокси
bool StartUdpProxy(int proxyPort) {
    // Сохраняем порт прокси
    g_proxyPort = proxyPort;
    
    // Создание сокета для прослушивания локального трафика
    SOCKET listenSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (listenSocket == INVALID_SOCKET) {
        printf("socket failed: %d\n", WSAGetLastError());
        return false;
    }
    
    // Настройка адреса прослушивания
    struct sockaddr_in listenAddr;
    memset(&listenAddr, 0, sizeof(listenAddr));
    listenAddr.sin_family = AF_INET;
    listenAddr.sin_addr.s_addr = htonl(INADDR_ANY);
    listenAddr.sin_port = htons(0);  // Любой свободный порт
    
    // Привязка сокета
    if (bind(listenSocket, (struct sockaddr*)&listenAddr, sizeof(listenAddr)) == SOCKET_ERROR) {
        printf("bind failed: %d\n", WSAGetLastError());
        closesocket(listenSocket);
        return false;
    }
    
    // Получение назначенного порта
    int addrLen = sizeof(listenAddr);
    if (getsockname(listenSocket, (struct sockaddr*)&listenAddr, &addrLen) == SOCKET_ERROR) {
        printf("getsockname failed: %d\n", WSAGetLastError());
        closesocket(listenSocket);
        return false;
    }
    
    int localPort = ntohs(listenAddr.sin_port);
    printf("UDP proxy listening on port %d\n", localPort);
    
    // Создание сокета для связи с V2Ray
    SOCKET proxySocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (proxySocket == INVALID_SOCKET) {
        printf("socket failed: %d\n", WSAGetLastError());
        closesocket(listenSocket);
        return false;
    }
    
    // Настройка адреса прокси
    struct sockaddr_in proxyAddr;
    memset(&proxyAddr, 0, sizeof(proxyAddr));
    proxyAddr.sin_family = AF_INET;
    inet_pton(AF_INET, g_proxyAddress, &proxyAddr.sin_addr);
    proxyAddr.sin_port = htons(g_proxyPort);
    
    // Создание контекста релея
    UdpRelayContext* context = (UdpRelayContext*)malloc(sizeof(UdpRelayContext));
    if (context == NULL) {
        printf("Failed to allocate memory for relay context\n");
        closesocket(listenSocket);
        closesocket(proxySocket);
        return false;
    }
    
    context->sourceSocket = listenSocket;
    context->proxySocket = proxySocket;
    context->destAddr = proxyAddr;
    
    // Сброс флага остановки
    g_stopUdpProxy = false;
    
    // Создание потока для релея
    g_udpProxyThread = (HANDLE)_beginthreadex(
        NULL,
        0,
        UdpRelayThreadProc,
        context,
        0,
        NULL
    );
    
    if (g_udpProxyThread == NULL) {
        printf("_beginthreadex failed: %d\n", GetLastError());
        free(context);
        closesocket(listenSocket);
        closesocket(proxySocket);
        return false;
    }
    
    printf("UDP proxy started successfully\n");
    return true;
}

// Очистка всех ресурсов WinDivert и WFP
bool CleanupWinDivert() {
    // Останавливаем UDP прокси
    if (g_udpProxyThread != NULL) {
        g_stopUdpProxy = true;
        
        // Ждем завершения потока (с таймаутом 5 секунд)
        if (WaitForSingleObject(g_udpProxyThread, 5000) == WAIT_TIMEOUT) {
            // Принудительно завершаем поток, если он не завершился сам
            TerminateThread(g_udpProxyThread, 0);
        }
        
        CloseHandle(g_udpProxyThread);
        g_udpProxyThread = NULL;
    }
    
    // Закрываем WinDivert
    if (g_winDivertHandle != INVALID_HANDLE_VALUE && g_winDivertHandle != NULL) {
        WinDivertClose(g_winDivertHandle);
        g_winDivertHandle = NULL;
    }
    
    // Очистка WFP фильтров
    if (g_engineHandle != NULL) {
        DWORD result = ERROR_SUCCESS;
        
        // Начало транзакции
        result = FwpmTransactionBegin(g_engineHandle, 0);
        if (result != ERROR_SUCCESS) {
            printf("FwpmTransactionBegin failed: %d\n", result);
            return false;
        }
        
        // Удаление всех фильтров
        for (int i = 0; i < g_numFilters; i++) {
            result = FwpmFilterDeleteById(g_engineHandle, g_filterIds[i]);
            if (result != ERROR_SUCCESS && result != FWP_E_FILTER_NOT_FOUND) {
                printf("FwpmFilterDeleteById failed for filter %d: %d\n", i, result);
                // Продолжаем удалять другие фильтры
            }
        }
        
        // Удаление сублоя
        result = FwpmSubLayerDeleteByKey(g_engineHandle, &SUBLAYER_KEY);
        if (result != ERROR_SUCCESS && result != FWP_E_SUBLAYER_NOT_FOUND) {
            printf("FwpmSubLayerDeleteByKey failed: %d\n", result);
            // Продолжаем выполнение
        }
        
        // Удаление провайдера
        result = FwpmProviderDeleteByKey(g_engineHandle, &PROVIDER_KEY);
        if (result != ERROR_SUCCESS && result != FWP_E_PROVIDER_NOT_FOUND) {
            printf("FwpmProviderDeleteByKey failed: %d\n", result);
            // Продолжаем выполнение
        }
        
        // Завершение транзакции
        result = FwpmTransactionCommit(g_engineHandle);
        if (result != ERROR_SUCCESS) {
            printf("FwpmTransactionCommit failed: %d\n", result);
            FwpmTransactionAbort(g_engineHandle);
            FwpmEngineClose(g_engineHandle);
            CleanupWinsock();
            return false;
        }
        
        // Закрытие движка
        FwpmEngineClose(g_engineHandle);
        g_engineHandle = NULL;
    }
    
    // Очистка Winsock
    CleanupWinsock();
    
    g_numFilters = 0;
    
    printf("WinDivert cleanup completed successfully\n");
    return true;
}

// Установить TAP-адаптер
bool InstallTapAdapter(const char* installerPath) {
    // Проверка существования инсталлятора
    DWORD fileAttributes = GetFileAttributesA(installerPath);
    if (fileAttributes == INVALID_FILE_ATTRIBUTES) {
        printf("TAP installer not found at: %s\n", installerPath);
        return false;
    }
    
    // Запуск процесса установки с правами администратора
    SHELLEXECUTEINFOA shExInfo = {0};
    shExInfo.cbSize = sizeof(SHELLEXECUTEINFOA);
    shExInfo.fMask = SEE_MASK_NOCLOSEPROCESS;
    shExInfo.hwnd = NULL;
    shExInfo.lpVerb = "runas";  // Запуск с повышенными привилегиями
    shExInfo.lpFile = installerPath;
    shExInfo.lpParameters = "/S";  // Тихая установка
    shExInfo.lpDirectory = NULL;
    shExInfo.nShow = SW_HIDE;
    shExInfo.hInstApp = NULL;
    
    if (!ShellExecuteExA(&shExInfo)) {
        printf("ShellExecuteEx failed: %d\n", GetLastError());
        return false;
    }
    
    // Ждем завершения процесса установки
    if (shExInfo.hProcess) {
        WaitForSingleObject(shExInfo.hProcess, INFINITE);
        
        DWORD exitCode = 0;
        if (GetExitCodeProcess(shExInfo.hProcess, &exitCode) && exitCode != 0) {
            printf("TAP installer exited with code: %d\n", exitCode);
            CloseHandle(shExInfo.hProcess);
            return false;
        }
        
        CloseHandle(shExInfo.hProcess);
    }
    
    printf("TAP adapter installed successfully\n");
    return true;
}

// Получить имя TAP-адаптера
bool GetTapAdapterName(char* adapterName, int bufferSize) {
    // Получение списка сетевых адаптеров
    IP_ADAPTER_ADDRESSES* pAddresses = NULL;
    ULONG outBufLen = 0;
    ULONG result = 0;
    
    // Определение размера буфера
    result = GetAdaptersAddresses(AF_INET, 0, NULL, NULL, &outBufLen);
    if (result != ERROR_BUFFER_OVERFLOW) {
        printf("GetAdaptersAddresses failed to get size: %d\n", result);
        return false;
    }
    
    // Выделение памяти для буфера
    pAddresses = (IP_ADAPTER_ADDRESSES*)malloc(outBufLen);
    if (pAddresses == NULL) {
        printf("Memory allocation failed\n");
        return false;
    }
    
    // Получение адаптеров
    result = GetAdaptersAddresses(AF_INET, 0, NULL, pAddresses, &outBufLen);
    if (result != NO_ERROR) {
        printf("GetAdaptersAddresses failed: %d\n", result);
        free(pAddresses);
        return false;
    }
    
    // Поиск TAP-адаптера
    bool found = false;
    IP_ADAPTER_ADDRESSES* pCurrent = pAddresses;
    while (pCurrent) {
        if (wcsstr(pCurrent->Description, L"TAP-Windows Adapter") ||
            wcsstr(pCurrent->Description, L"TAP Windows Adapter") ||
            wcsstr(pCurrent->Description, L"TAP Adapter")) {
            
            // Конвертация имени адаптера из wide char в multibyte
            WideCharToMultiByte(
                CP_ACP,
                0,
                pCurrent->FriendlyName,
                -1,
                adapterName,
                bufferSize,
                NULL,
                NULL
            );
            
            found = true;
            break;
        }
        pCurrent = pCurrent->Next;
    }
    
    free(pAddresses);
    
    if (!found) {
        printf("TAP adapter not found\n");
        return false;
    }
    
    printf("Found TAP adapter: %s\n", adapterName);
    return true;
}

// Настроить TAP-адаптер
bool ConfigureTapAdapter(const char* adapterName, const char* ipAddress, const char* netmask) {
    // Команда для настройки IP-адреса
    char command[1024];
    snprintf(
        command,
        sizeof(command),
        "netsh interface ip set address name=\"%s\" static %s %s",
        adapterName,
        ipAddress,
        netmask
    );
    
    // Выполнение команды
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    
    if (!CreateProcessA(
        NULL,
        command,
        NULL,
        NULL,
        FALSE,
        0,
        NULL,
        NULL,
        &si,
        &pi
    )) {
        printf("CreateProcess failed: %d\n", GetLastError());
        return false;
    }
    
    // Ждем завершения процесса
    WaitForSingleObject(pi.hProcess, INFINITE);
    
    DWORD exitCode = 0;
    if (!GetExitCodeProcess(pi.hProcess, &exitCode) || exitCode != 0) {
        printf("netsh command failed with code: %d\n", exitCode);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        return false;
    }
    
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    
    // Сохраняем IP TAP-адаптера как шлюз
    strcpy_s(g_tapGateway, sizeof(g_tapGateway), ipAddress);
    
    printf("TAP adapter configured successfully\n");
    return true;
}

// Получить адрес шлюза по умолчанию
static bool GetDefaultGateway(char* gateway, int bufferSize) {
    // Получение списка маршрутов
    MIB_IPFORWARDTABLE* pIpForwardTable = NULL;
    ULONG dwSize = 0;
    DWORD result = 0;
    
    // Определение размера буфера
    result = GetIpForwardTable(NULL, &dwSize, FALSE);
    if (result != ERROR_INSUFFICIENT_BUFFER) {
        printf("GetIpForwardTable failed to get size: %d\n", result);
        return false;
    }
    
    // Выделение памяти для буфера
    pIpForwardTable = (MIB_IPFORWARDTABLE*)malloc(dwSize);
    if (pIpForwardTable == NULL) {
        printf("Memory allocation failed\n");
        return false;
    }
    
    // Получение таблицы маршрутизации
    result = GetIpForwardTable(pIpForwardTable, &dwSize, FALSE);
    if (result != NO_ERROR) {
        printf("GetIpForwardTable failed: %d\n", result);
        free(pIpForwardTable);
        return false;
    }
    
    // Поиск маршрута по умолчанию (0.0.0.0/0)
    bool found = false;
    for (DWORD i = 0; i < pIpForwardTable->dwNumEntries; i++) {
        if (pIpForwardTable->table[i].dwForwardDest == 0 &&
            pIpForwardTable->table[i].dwForwardMask == 0) {
            
            struct in_addr addr;
            addr.s_addr = pIpForwardTable->table[i].dwForwardNextHop;
            inet_ntop(AF_INET, &addr, gateway, bufferSize);
            
            found = true;
            break;
        }
    }
    
    free(pIpForwardTable);
    
    if (!found) {
        printf("Default gateway not found\n");
        return false;
    }
    
    printf("Found default gateway: %s\n", gateway);
    return true;
}

// Настроить маршрутизацию для VPN
bool ConfigureVpnRouting(const char* serverAddress, const char* tapGateway) {
    // Сохраняем адрес сервера
    strcpy_s(g_serverAddress, sizeof(g_serverAddress), serverAddress);
    
    // Получаем текущий шлюз по умолчанию
    if (!GetDefaultGateway(g_originalGateway, sizeof(g_originalGateway))) {
        return false;
    }
    
    // Добавляем прямой маршрут к VPN-серверу через оригинальный шлюз
    char command[1024];
    snprintf(
        command,
        sizeof(command),
        "route add %s mask 255.255.255.255 %s metric 1",
        serverAddress,
        g_originalGateway
    );
    
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    
    if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        printf("CreateProcess failed for adding server route: %d\n", GetLastError());
        return false;
    }
    
    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    
    // Изменяем маршрут по умолчанию через TAP-адаптер
    memset(&si, 0, sizeof(si));
    memset(&pi, 0, sizeof(pi));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    
    snprintf(
        command,
        sizeof(command),
        "route change 0.0.0.0 mask 0.0.0.0 %s metric 5",
        tapGateway
    );
    
    if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        printf("CreateProcess failed for changing default route: %d\n", GetLastError());
        return false;
    }
    
    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    
    printf("VPN routing configured successfully\n");
    return true;
}

// Восстановить маршрутизацию
bool RestoreRouting() {
    if (g_originalGateway[0] == '\0') {
        printf("No original gateway to restore\n");
        return false;
    }
    
    // Восстанавливаем маршрут по умолчанию
    char command[1024];
    snprintf(
        command,
        sizeof(command),
        "route change 0.0.0.0 mask 0.0.0.0 %s metric 1",
        g_originalGateway
    );
    
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    
    if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        printf("CreateProcess failed for restoring default route: %d\n", GetLastError());
        return false;
    }
    
    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    
    // Удаляем маршрут к VPN-серверу, если он был добавлен
    if (g_serverAddress[0] != '\0') {
        memset(&si, 0, sizeof(si));
        memset(&pi, 0, sizeof(pi));
        si.cb = sizeof(si);
        si.dwFlags = STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;
        
        snprintf(
            command,
            sizeof(command),
            "route delete %s",
            g_serverAddress
        );
        
        if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
            printf("CreateProcess failed for deleting server route: %d\n", GetLastError());
            return false;
        }
        
        WaitForSingleObject(pi.hProcess, INFINITE);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }
    
    printf("Routing restored successfully\n");
    return true;
}