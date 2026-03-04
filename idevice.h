#ifdef _WIN32
  #ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN
  #endif
  #include <winsock2.h>
  #include <ws2tcpip.h>
  typedef int                idevice_socklen_t;
  typedef struct sockaddr    idevice_sockaddr;
#else
  #include <sys/types.h>
  #include <sys/socket.h>
  typedef socklen_t          idevice_socklen_t;
  typedef struct sockaddr    idevice_sockaddr;
#endif
#ifndef IDEVICE_H
#define IDEVICE_H
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#define LOCKDOWN_PORT 62078
typedef enum AfcFopenMode {
  AfcRdOnly = 1,
  AfcRw = 2,
  AfcWrOnly = 3,
  AfcWr = 4,
  AfcAppend = 5,
  AfcRdAppend = 6,
} AfcFopenMode;
typedef enum AfcLinkType {
  Hard = 1,
  Symbolic = 2,
} AfcLinkType;
typedef enum IdeviceLoggerError {
  Success = 0,
  FileError = -1,
  AlreadyInitialized = -2,
  InvalidPathString = -3,
} IdeviceLoggerError;
typedef enum IdeviceLogLevel {
  Disabled = 0,
  ErrorLevel = 1,
  Warn = 2,
  Info = 3,
  Debug = 4,
  Trace = 5,
} IdeviceLogLevel;
typedef struct AdapterHandle AdapterHandle;
typedef struct AdapterStreamHandle AdapterStreamHandle;
typedef struct AfcClientHandle AfcClientHandle;
typedef struct AfcFileHandle AfcFileHandle;
typedef struct AmfiClientHandle AmfiClientHandle;
typedef struct AppServiceHandle AppServiceHandle;
typedef struct CoreDeviceProxyHandle CoreDeviceProxyHandle;
typedef struct CrashReportCopyMobileHandle CrashReportCopyMobileHandle;
typedef struct DebugProxyHandle DebugProxyHandle;
typedef struct DiagnosticsRelayClientHandle DiagnosticsRelayClientHandle;
typedef struct DiagnosticsServiceHandle DiagnosticsServiceHandle;
typedef struct HeartbeatClientHandle HeartbeatClientHandle;
typedef struct HouseArrestClientHandle HouseArrestClientHandle;
typedef struct IdeviceHandle IdeviceHandle;
typedef struct IdevicePairingFile IdevicePairingFile;
typedef struct IdeviceProviderHandle IdeviceProviderHandle;
typedef struct IdeviceSocketHandle IdeviceSocketHandle;
typedef struct ImageMounterHandle ImageMounterHandle;
typedef struct InstallationProxyClientHandle InstallationProxyClientHandle;
typedef struct LocationSimulationHandle LocationSimulationHandle;
typedef struct LocationSimulationServiceHandle LocationSimulationServiceHandle;
typedef struct LockdowndClientHandle LockdowndClientHandle;
typedef struct MisagentClientHandle MisagentClientHandle;
typedef struct NotificationProxyClientHandle NotificationProxyClientHandle;
typedef struct OsTraceRelayClientHandle OsTraceRelayClientHandle;
typedef struct OsTraceRelayReceiverHandle OsTraceRelayReceiverHandle;
typedef struct ProcessControlHandle ProcessControlHandle;
typedef struct ReadWriteOpaque ReadWriteOpaque;
typedef struct RemoteServerHandle RemoteServerHandle;
typedef struct RsdHandshakeHandle RsdHandshakeHandle;
typedef struct ScreenshotClientHandle ScreenshotClientHandle;
typedef struct ScreenshotrClientHandle ScreenshotrClientHandle;
typedef struct SpringBoardServicesClientHandle SpringBoardServicesClientHandle;
typedef struct SysdiagnoseStreamHandle SysdiagnoseStreamHandle;
typedef struct SyslogRelayClientHandle SyslogRelayClientHandle;
typedef struct TcpEatObject TcpEatObject;
typedef struct TcpFeedObject TcpFeedObject;
typedef struct UsbmuxdAddrHandle UsbmuxdAddrHandle;
typedef struct UsbmuxdConnectionHandle UsbmuxdConnectionHandle;
typedef struct UsbmuxdDeviceHandle UsbmuxdDeviceHandle;
typedef struct UsbmuxdListenerHandle UsbmuxdListenerHandle;
typedef struct Vec_u64 Vec_u64;
typedef struct IdeviceFfiError {
  int32_t code;
  const char *message;
} IdeviceFfiError;
typedef void *plist_t;
typedef struct AfcFileInfo {
  size_t size;
  size_t blocks;
  int64_t creation;
  int64_t modified;
  char *st_nlink;
  char *st_ifmt;
  char *st_link_target;
} AfcFileInfo;
typedef struct AfcDeviceInfo {
  char *model;
  size_t total_bytes;
  size_t free_bytes;
  size_t block_size;
} AfcDeviceInfo;
typedef struct AppListEntryC {
  int is_removable;
  char *name;
  int is_first_party;
  char *path;
  char *bundle_identifier;
  int is_developer_app;
  char *bundle_version;
  int is_internal;
  int is_hidden;
  int is_app_clip;
  char *version;
} AppListEntryC;
typedef struct LaunchResponseC {
  uint32_t process_identifier_version;
  uint32_t pid;
  char *executable_url;
  uint32_t *audit_token;
  uintptr_t audit_token_len;
} LaunchResponseC;
typedef struct ProcessTokenC {
  uint32_t pid;
  char *executable_url;
} ProcessTokenC;
typedef struct SignalResponseC {
  uint32_t pid;
  char *executable_url;
  uint64_t device_timestamp;
  uint32_t signal;
} SignalResponseC;
typedef struct IconDataC {
  uint8_t *data;
  uintptr_t data_len;
  double icon_width;
  double icon_height;
  double minimum_width;
  double minimum_height;
} IconDataC;
typedef struct DebugserverCommandHandle {
  char *name;
  char **argv;
  uintptr_t argv_count;
} DebugserverCommandHandle;
typedef struct SyslogLabel {
  const char *subsystem;
  const char *category;
} SyslogLabel;
typedef struct OsTraceLog {
  uint32_t pid;
  int64_t timestamp;
  uint8_t level;
  const char *image_name;
  const char *filename;
  const char *message;
  const struct SyslogLabel *label;
} OsTraceLog;
typedef struct CRsdService {
  char *name;
  char *entitlement;
  uint16_t port;
  bool uses_remote_xpc;
  size_t features_count;
  char **features;
  int64_t service_version;
} CRsdService;
typedef struct CRsdServiceArray {
  struct CRsdService *services;
  size_t count;
} CRsdServiceArray;
typedef struct ScreenshotData {
  uint8_t *data;
  uintptr_t length;
} ScreenshotData;
struct IdeviceFfiError *idevice_new(struct IdeviceSocketHandle *socket,
                                    const char *label,
                                    struct IdeviceHandle **idevice);
struct IdeviceFfiError *idevice_from_fd(int32_t fd,
                                        const char *label,
                                        struct IdeviceHandle **idevice);
struct IdeviceFfiError *idevice_new_tcp_socket(const idevice_sockaddr *addr,
                                               idevice_socklen_t addr_len,
                                               const char *label,
                                               struct IdeviceHandle **idevice);
struct IdeviceFfiError *idevice_get_type(struct IdeviceHandle *idevice,
                                         char **device_type);
struct IdeviceFfiError *idevice_rsd_checkin(struct IdeviceHandle *idevice);
struct IdeviceFfiError *idevice_start_session(struct IdeviceHandle *idevice,
                                              const struct IdevicePairingFile *pairing_file,
                                              bool legacy);
void idevice_free(struct IdeviceHandle *idevice);
void idevice_stream_free(struct ReadWriteOpaque *stream_handle);
void idevice_string_free(char *string);
void idevice_data_free(uint8_t *data, uintptr_t len);
void idevice_plist_array_free(plist_t *plists, uintptr_t len);
void idevice_outer_slice_free(void *slice, uintptr_t len);
struct IdeviceFfiError *adapter_connect(struct AdapterHandle *adapter_handle,
                                        uint16_t port,
                                        struct ReadWriteOpaque **stream_handle);
struct IdeviceFfiError *adapter_pcap(struct AdapterHandle *handle, const char *path);
struct IdeviceFfiError *adapter_stream_close(struct AdapterStreamHandle *handle);
struct IdeviceFfiError *adapter_close(struct AdapterHandle *handle);
struct IdeviceFfiError *adapter_send(struct AdapterStreamHandle *handle,
                                     const uint8_t *data,
                                     uintptr_t length);
struct IdeviceFfiError *adapter_recv(struct AdapterStreamHandle *handle,
                                     uint8_t *data,
                                     uintptr_t *length,
                                     uintptr_t max_length);
struct IdeviceFfiError *afc_client_connect(struct IdeviceProviderHandle *provider,
                                           struct AfcClientHandle **client);
struct IdeviceFfiError *afc2_client_connect(struct IdeviceProviderHandle *provider,
                                            struct AfcClientHandle **client);
struct IdeviceFfiError *afc_client_new(struct IdeviceHandle *socket,
                                       struct AfcClientHandle **client);
void afc_client_free(struct AfcClientHandle *handle);
struct IdeviceFfiError *afc_list_directory(struct AfcClientHandle *client,
                                           const char *path,
                                           char ***entries,
                                           size_t *count);
struct IdeviceFfiError *afc_make_directory(struct AfcClientHandle *client, const char *path);
struct IdeviceFfiError *afc_get_file_info(struct AfcClientHandle *client,
                                          const char *path,
                                          struct AfcFileInfo *info);
void afc_file_info_free(struct AfcFileInfo *info);
struct IdeviceFfiError *afc_get_device_info(struct AfcClientHandle *client,
                                            struct AfcDeviceInfo *info);
void afc_device_info_free(struct AfcDeviceInfo *info);
struct IdeviceFfiError *afc_remove_path(struct AfcClientHandle *client, const char *path);
struct IdeviceFfiError *afc_remove_path_and_contents(struct AfcClientHandle *client,
                                                     const char *path);
struct IdeviceFfiError *afc_file_open(struct AfcClientHandle *client,
                                      const char *path,
                                      enum AfcFopenMode mode,
                                      struct AfcFileHandle **handle);
struct IdeviceFfiError *afc_file_close(struct AfcFileHandle *handle);
struct IdeviceFfiError *afc_file_read(struct AfcFileHandle *handle,
                                      uint8_t **data,
                                      uintptr_t len,
                                      size_t *bytes_read);
struct IdeviceFfiError *afc_file_read_entire(struct AfcFileHandle *handle,
                                             uint8_t **data,
                                             size_t *length);
struct IdeviceFfiError *afc_file_seek(struct AfcFileHandle *handle,
                                      int64_t offset,
                                      int whence,
                                      int64_t *new_pos);
struct IdeviceFfiError *afc_file_tell(struct AfcFileHandle *handle, int64_t *pos);
struct IdeviceFfiError *afc_file_write(struct AfcFileHandle *handle,
                                       const uint8_t *data,
                                       size_t length);
struct IdeviceFfiError *afc_make_link(struct AfcClientHandle *client,
                                      const char *target,
                                      const char *source,
                                      enum AfcLinkType link_type);
struct IdeviceFfiError *afc_rename_path(struct AfcClientHandle *client,
                                        const char *source,
                                        const char *target);
void afc_file_read_data_free(uint8_t *data,
                             size_t length);
struct IdeviceFfiError *amfi_connect(struct IdeviceProviderHandle *provider,
                                     struct AmfiClientHandle **client);
struct IdeviceFfiError *amfi_new(struct IdeviceHandle *socket, struct AmfiClientHandle **client);
struct IdeviceFfiError *amfi_reveal_developer_mode_option_in_ui(struct AmfiClientHandle *client);
struct IdeviceFfiError *amfi_enable_developer_mode(struct AmfiClientHandle *client);
struct IdeviceFfiError *amfi_accept_developer_mode(struct AmfiClientHandle *client);
void amfi_client_free(struct AmfiClientHandle *handle);
struct IdeviceFfiError *app_service_connect_rsd(struct AdapterHandle *provider,
                                                struct RsdHandshakeHandle *handshake,
                                                struct AppServiceHandle **handle);
struct IdeviceFfiError *app_service_new(struct ReadWriteOpaque *socket,
                                        struct AppServiceHandle **handle);
void app_service_free(struct AppServiceHandle *handle);
struct IdeviceFfiError *app_service_list_apps(struct AppServiceHandle *handle,
                                              int app_clips,
                                              int removable_apps,
                                              int hidden_apps,
                                              int internal_apps,
                                              int default_apps,
                                              struct AppListEntryC **apps,
                                              uintptr_t *count);
void app_service_free_app_list(struct AppListEntryC *apps, uintptr_t count);
struct IdeviceFfiError *app_service_launch_app(struct AppServiceHandle *handle,
                                               const char *bundle_id,
                                               const char *const *argv,
                                               uintptr_t argc,
                                               int kill_existing,
                                               int start_suspended,
                                               const uint8_t *stdio_uuid,
                                               struct LaunchResponseC **response);
void app_service_free_launch_response(struct LaunchResponseC *response);
struct IdeviceFfiError *app_service_list_processes(struct AppServiceHandle *handle,
                                                   struct ProcessTokenC **processes,
                                                   uintptr_t *count);
void app_service_free_process_list(struct ProcessTokenC *processes, uintptr_t count);
struct IdeviceFfiError *app_service_uninstall_app(struct AppServiceHandle *handle,
                                                  const char *bundle_id);
struct IdeviceFfiError *app_service_send_signal(struct AppServiceHandle *handle,
                                                uint32_t pid,
                                                uint32_t signal,
                                                struct SignalResponseC **response);
void app_service_free_signal_response(struct SignalResponseC *response);
struct IdeviceFfiError *app_service_fetch_app_icon(struct AppServiceHandle *handle,
                                                   const char *bundle_id,
                                                   float width,
                                                   float height,
                                                   float scale,
                                                   int allow_placeholder,
                                                   struct IconDataC **icon_data);
void app_service_free_icon_data(struct IconDataC *icon_data);
struct IdeviceFfiError *diagnostics_service_connect_rsd(struct AdapterHandle *provider,
                                                        struct RsdHandshakeHandle *handshake,
                                                        struct DiagnosticsServiceHandle **handle);
struct IdeviceFfiError *diagnostics_service_new(struct ReadWriteOpaque *socket,
                                                struct DiagnosticsServiceHandle **handle);
struct IdeviceFfiError *diagnostics_service_capture_sysdiagnose(struct DiagnosticsServiceHandle *handle,
                                                                bool dry_run,
                                                                char **preferred_filename,
                                                                uintptr_t *expected_length,
                                                                struct SysdiagnoseStreamHandle **stream_handle);
struct IdeviceFfiError *sysdiagnose_stream_next(struct SysdiagnoseStreamHandle *handle,
                                                uint8_t **data,
                                                uintptr_t *len);
void diagnostics_service_free(struct DiagnosticsServiceHandle *handle);
void sysdiagnose_stream_free(struct SysdiagnoseStreamHandle *handle);
struct IdeviceFfiError *core_device_proxy_connect(struct IdeviceProviderHandle *provider,
                                                  struct CoreDeviceProxyHandle **client);
struct IdeviceFfiError *core_device_proxy_new(struct IdeviceHandle *socket,
                                              struct CoreDeviceProxyHandle **client);
struct IdeviceFfiError *core_device_proxy_send(struct CoreDeviceProxyHandle *handle,
                                               const uint8_t *data,
                                               uintptr_t length);
struct IdeviceFfiError *core_device_proxy_recv(struct CoreDeviceProxyHandle *handle,
                                               uint8_t *data,
                                               uintptr_t *length,
                                               uintptr_t max_length);
struct IdeviceFfiError *core_device_proxy_get_client_parameters(struct CoreDeviceProxyHandle *handle,
                                                                uint16_t *mtu,
                                                                char **address,
                                                                char **netmask);
struct IdeviceFfiError *core_device_proxy_get_server_address(struct CoreDeviceProxyHandle *handle,
                                                             char **address);
struct IdeviceFfiError *core_device_proxy_get_server_rsd_port(struct CoreDeviceProxyHandle *handle,
                                                              uint16_t *port);
struct IdeviceFfiError *core_device_proxy_create_tcp_adapter(struct CoreDeviceProxyHandle *handle,
                                                             struct AdapterHandle **adapter);
void core_device_proxy_free(struct CoreDeviceProxyHandle *handle);
void adapter_free(struct AdapterHandle *handle);
struct IdeviceFfiError *crash_report_client_connect(struct IdeviceProviderHandle *provider,
                                                    struct CrashReportCopyMobileHandle **client);
struct IdeviceFfiError *crash_report_client_new(struct IdeviceHandle *socket,
                                                struct CrashReportCopyMobileHandle **client);
struct IdeviceFfiError *crash_report_client_ls(struct CrashReportCopyMobileHandle *client,
                                               const char *dir_path,
                                               char ***entries,
                                               size_t *count);
struct IdeviceFfiError *crash_report_client_pull(struct CrashReportCopyMobileHandle *client,
                                                 const char *log_name,
                                                 uint8_t **data,
                                                 size_t *length);
struct IdeviceFfiError *crash_report_client_remove(struct CrashReportCopyMobileHandle *client,
                                                   const char *log_name);
struct IdeviceFfiError *crash_report_client_to_afc(struct CrashReportCopyMobileHandle *client,
                                                   struct AfcClientHandle **afc_client);
struct IdeviceFfiError *crash_report_flush(struct IdeviceProviderHandle *provider);
void crash_report_client_free(struct CrashReportCopyMobileHandle *handle);
struct DebugserverCommandHandle *debugserver_command_new(const char *name,
                                                         const char *const *argv,
                                                         uintptr_t argv_count);
void debugserver_command_free(struct DebugserverCommandHandle *command);
struct IdeviceFfiError *debug_proxy_connect_rsd(struct AdapterHandle *provider,
                                                struct RsdHandshakeHandle *handshake,
                                                struct DebugProxyHandle **handle);
struct IdeviceFfiError *debug_proxy_new(struct ReadWriteOpaque *socket,
                                        struct DebugProxyHandle **handle);
void debug_proxy_free(struct DebugProxyHandle *handle);
struct IdeviceFfiError *debug_proxy_send_command(struct DebugProxyHandle *handle,
                                                 struct DebugserverCommandHandle *command,
                                                 char **response);
struct IdeviceFfiError *debug_proxy_read_response(struct DebugProxyHandle *handle, char **response);
struct IdeviceFfiError *debug_proxy_send_raw(struct DebugProxyHandle *handle,
                                             const uint8_t *data,
                                             uintptr_t len);
struct IdeviceFfiError *debug_proxy_read(struct DebugProxyHandle *handle,
                                         uintptr_t len,
                                         char **response);
struct IdeviceFfiError *debug_proxy_set_argv(struct DebugProxyHandle *handle,
                                             const char *const *argv,
                                             uintptr_t argv_count,
                                             char **response);
struct IdeviceFfiError *debug_proxy_send_ack(struct DebugProxyHandle *handle);
struct IdeviceFfiError *debug_proxy_send_nack(struct DebugProxyHandle *handle);
void debug_proxy_set_ack_mode(struct DebugProxyHandle *handle, int enabled);
struct IdeviceFfiError *diagnostics_relay_client_connect(struct IdeviceProviderHandle *provider,
                                                         struct DiagnosticsRelayClientHandle **client);
struct IdeviceFfiError *diagnostics_relay_client_new(struct IdeviceHandle *socket,
                                                     struct DiagnosticsRelayClientHandle **client);
struct IdeviceFfiError *diagnostics_relay_client_ioregistry(struct DiagnosticsRelayClientHandle *client,
                                                            const char *current_plane,
                                                            const char *entry_name,
                                                            const char *entry_class,
                                                            plist_t *res);
struct IdeviceFfiError *diagnostics_relay_client_mobilegestalt(struct DiagnosticsRelayClientHandle *client,
                                                               const char *const *keys,
                                                               uintptr_t keys_len,
                                                               plist_t *res);
struct IdeviceFfiError *diagnostics_relay_client_gasguage(struct DiagnosticsRelayClientHandle *client,
                                                          plist_t *res);
struct IdeviceFfiError *diagnostics_relay_client_nand(struct DiagnosticsRelayClientHandle *client,
                                                      plist_t *res);
struct IdeviceFfiError *diagnostics_relay_client_all(struct DiagnosticsRelayClientHandle *client,
                                                     plist_t *res);
struct IdeviceFfiError *diagnostics_relay_client_restart(struct DiagnosticsRelayClientHandle *client);
struct IdeviceFfiError *diagnostics_relay_client_shutdown(struct DiagnosticsRelayClientHandle *client);
struct IdeviceFfiError *diagnostics_relay_client_sleep(struct DiagnosticsRelayClientHandle *client);
struct IdeviceFfiError *diagnostics_relay_client_wifi(struct DiagnosticsRelayClientHandle *client,
                                                      plist_t *res);
struct IdeviceFfiError *diagnostics_relay_client_goodbye(struct DiagnosticsRelayClientHandle *client);
void diagnostics_relay_client_free(struct DiagnosticsRelayClientHandle *handle);
struct IdeviceFfiError *location_simulation_new(struct RemoteServerHandle *server,
                                                struct LocationSimulationHandle **handle);
void location_simulation_free(struct LocationSimulationHandle *handle);
struct IdeviceFfiError *location_simulation_clear(struct LocationSimulationHandle *handle);
struct IdeviceFfiError *location_simulation_set(struct LocationSimulationHandle *handle,
                                                double latitude,
                                                double longitude);
struct IdeviceFfiError *process_control_new(struct RemoteServerHandle *server,
                                            struct ProcessControlHandle **handle);
void process_control_free(struct ProcessControlHandle *handle);
struct IdeviceFfiError *process_control_launch_app(struct ProcessControlHandle *handle,
                                                   const char *bundle_id,
                                                   const char *const *env_vars,
                                                   uintptr_t env_vars_count,
                                                   const char *const *arguments,
                                                   uintptr_t arguments_count,
                                                   bool start_suspended,
                                                   bool kill_existing,
                                                   uint64_t *pid);
struct IdeviceFfiError *process_control_kill_app(struct ProcessControlHandle *handle, uint64_t pid);
struct IdeviceFfiError *process_control_disable_memory_limit(struct ProcessControlHandle *handle,
                                                             uint64_t pid);
struct IdeviceFfiError *remote_server_new(struct ReadWriteOpaque *socket,
                                          struct RemoteServerHandle **handle);
struct IdeviceFfiError *remote_server_connect_rsd(struct AdapterHandle *provider,
                                                  struct RsdHandshakeHandle *handshake,
                                                  struct RemoteServerHandle **handle);
void remote_server_free(struct RemoteServerHandle *handle);
struct IdeviceFfiError *screenshot_client_new(struct RemoteServerHandle *server,
                                              struct ScreenshotClientHandle **handle);
void screenshot_client_free(struct ScreenshotClientHandle *handle);
struct IdeviceFfiError *screenshot_client_take_screenshot(struct ScreenshotClientHandle *handle,
                                                          uint8_t **data,
                                                          uintptr_t *len);
void idevice_error_free(struct IdeviceFfiError *err);
struct IdeviceFfiError *heartbeat_connect(struct IdeviceProviderHandle *provider,
                                          struct HeartbeatClientHandle **client);
struct IdeviceFfiError *heartbeat_new(struct IdeviceHandle *socket,
                                      struct HeartbeatClientHandle **client);
struct IdeviceFfiError *heartbeat_send_polo(struct HeartbeatClientHandle *client);
struct IdeviceFfiError *heartbeat_get_marco(struct HeartbeatClientHandle *client,
                                            uint64_t interval,
                                            uint64_t *new_interval);
void heartbeat_client_free(struct HeartbeatClientHandle *handle);
struct IdeviceFfiError *house_arrest_client_connect(struct IdeviceProviderHandle *provider,
                                                    struct HouseArrestClientHandle **client);
struct IdeviceFfiError *house_arrest_client_new(struct IdeviceHandle *socket,
                                                struct HouseArrestClientHandle **client);
struct IdeviceFfiError *house_arrest_vend_container(struct HouseArrestClientHandle *client,
                                                    const char *bundle_id,
                                                    struct AfcClientHandle **afc_client);
struct IdeviceFfiError *house_arrest_vend_documents(struct HouseArrestClientHandle *client,
                                                    const char *bundle_id,
                                                    struct AfcClientHandle **afc_client);
void house_arrest_client_free(struct HouseArrestClientHandle *handle);
struct IdeviceFfiError *installation_proxy_connect(struct IdeviceProviderHandle *provider,
                                                   struct InstallationProxyClientHandle **client);
struct IdeviceFfiError *installation_proxy_new(struct IdeviceHandle *socket,
                                               struct InstallationProxyClientHandle **client);
struct IdeviceFfiError *installation_proxy_get_apps(struct InstallationProxyClientHandle *client,
                                                    const char *application_type,
                                                    const char *const *bundle_identifiers,
                                                    size_t bundle_identifiers_len,
                                                    void **out_result,
                                                    size_t *out_result_len);
void installation_proxy_client_free(struct InstallationProxyClientHandle *handle);
struct IdeviceFfiError *installation_proxy_install(struct InstallationProxyClientHandle *client,
                                                   const char *package_path,
                                                   plist_t options);
struct IdeviceFfiError *installation_proxy_install_with_callback(struct InstallationProxyClientHandle *client,
                                                                 const char *package_path,
                                                                 plist_t options,
                                                                 void (*callback)(uint64_t progress,
                                                                                  void *context),
                                                                 void *context);
struct IdeviceFfiError *installation_proxy_upgrade(struct InstallationProxyClientHandle *client,
                                                   const char *package_path,
                                                   plist_t options);
struct IdeviceFfiError *installation_proxy_upgrade_with_callback(struct InstallationProxyClientHandle *client,
                                                                 const char *package_path,
                                                                 plist_t options,
                                                                 void (*callback)(uint64_t progress,
                                                                                  void *context),
                                                                 void *context);
struct IdeviceFfiError *installation_proxy_uninstall(struct InstallationProxyClientHandle *client,
                                                     const char *bundle_id,
                                                     plist_t options);
struct IdeviceFfiError *installation_proxy_uninstall_with_callback(struct InstallationProxyClientHandle *client,
                                                                   const char *bundle_id,
                                                                   plist_t options,
                                                                   void (*callback)(uint64_t progress,
                                                                                    void *context),
                                                                   void *context);
struct IdeviceFfiError *installation_proxy_check_capabilities_match(struct InstallationProxyClientHandle *client,
                                                                    const plist_t *capabilities,
                                                                    size_t capabilities_len,
                                                                    plist_t options,
                                                                    bool *out_result);
struct IdeviceFfiError *installation_proxy_browse(struct InstallationProxyClientHandle *client,
                                                  plist_t options,
                                                  plist_t **out_result,
                                                  size_t *out_result_len);
struct IdeviceFfiError *lockdown_location_simulation_connect(struct IdeviceProviderHandle *provider,
                                                             struct LocationSimulationServiceHandle **handle);
struct IdeviceFfiError *lockdown_location_simulation_new(struct IdeviceHandle *socket,
                                                         struct LocationSimulationServiceHandle **client);
struct IdeviceFfiError *lockdown_location_simulation_set(struct LocationSimulationServiceHandle *handle,
                                                         const char *latitude,
                                                         const char *longitude);
struct IdeviceFfiError *lockdown_location_simulation_clear(struct LocationSimulationServiceHandle *handle);
void lockdown_location_simulation_free(struct LocationSimulationServiceHandle *handle);
struct IdeviceFfiError *lockdownd_connect(struct IdeviceProviderHandle *provider,
                                          struct LockdowndClientHandle **client);
struct IdeviceFfiError *lockdownd_new(struct IdeviceHandle *socket,
                                      struct LockdowndClientHandle **client);
struct IdeviceFfiError *lockdownd_start_session(struct LockdowndClientHandle *client,
                                                struct IdevicePairingFile *pairing_file);
struct IdeviceFfiError *lockdownd_start_service(struct LockdowndClientHandle *client,
                                                const char *identifier,
                                                uint16_t *port,
                                                bool *ssl);
struct IdeviceFfiError *lockdownd_pair(struct LockdowndClientHandle *client,
                                       const char *host_id,
                                       const char *system_buid,
                                       const char *host_name,
                                       struct IdevicePairingFile **pairing_file);
struct IdeviceFfiError *lockdownd_get_value(struct LockdowndClientHandle *client,
                                            const char *key,
                                            const char *domain,
                                            plist_t *out_plist);
struct IdeviceFfiError *lockdownd_enter_recovery(struct LockdowndClientHandle *client);
struct IdeviceFfiError *lockdownd_set_value(struct LockdowndClientHandle *client,
                                            const char *key,
                                            plist_t value,
                                            const char *domain);
void lockdownd_client_free(struct LockdowndClientHandle *handle);
enum IdeviceLoggerError idevice_init_logger(enum IdeviceLogLevel console_level,
                                            enum IdeviceLogLevel file_level,
                                            char *file_path);
struct IdeviceFfiError *misagent_connect(struct IdeviceProviderHandle *provider,
                                         struct MisagentClientHandle **client);
struct IdeviceFfiError *misagent_install(struct MisagentClientHandle *client,
                                         const uint8_t *profile_data,
                                         size_t profile_len);
struct IdeviceFfiError *misagent_remove(struct MisagentClientHandle *client,
                                        const char *profile_id);
struct IdeviceFfiError *misagent_copy_all(struct MisagentClientHandle *client,
                                          uint8_t ***out_profiles,
                                          size_t **out_profiles_len,
                                          size_t *out_count);
void misagent_free_profiles(uint8_t **profiles, size_t *lens, size_t count);
void misagent_client_free(struct MisagentClientHandle *handle);
struct IdeviceFfiError *image_mounter_connect(struct IdeviceProviderHandle *provider,
                                              struct ImageMounterHandle **client);
struct IdeviceFfiError *image_mounter_new(struct IdeviceHandle *socket,
                                          struct ImageMounterHandle **client);
void image_mounter_free(struct ImageMounterHandle *handle);
struct IdeviceFfiError *image_mounter_copy_devices(struct ImageMounterHandle *client,
                                                   plist_t **devices,
                                                   size_t *devices_len);
struct IdeviceFfiError *image_mounter_lookup_image(struct ImageMounterHandle *client,
                                                   const char *image_type,
                                                   uint8_t **signature,
                                                   size_t *signature_len);
struct IdeviceFfiError *image_mounter_upload_image(struct ImageMounterHandle *client,
                                                   const char *image_type,
                                                   const uint8_t *image,
                                                   size_t image_len,
                                                   const uint8_t *signature,
                                                   size_t signature_len);
struct IdeviceFfiError *image_mounter_mount_image(struct ImageMounterHandle *client,
                                                  const char *image_type,
                                                  const uint8_t *signature,
                                                  size_t signature_len,
                                                  const uint8_t *trust_cache,
                                                  size_t trust_cache_len,
                                                  const void *info_plist);
struct IdeviceFfiError *image_mounter_unmount_image(struct ImageMounterHandle *client,
                                                    const char *mount_path);
struct IdeviceFfiError *image_mounter_query_developer_mode_status(struct ImageMounterHandle *client,
                                                                  int *status);
struct IdeviceFfiError *image_mounter_mount_developer(struct ImageMounterHandle *client,
                                                      const uint8_t *image,
                                                      size_t image_len,
                                                      const uint8_t *signature,
                                                      size_t signature_len);
struct IdeviceFfiError *image_mounter_query_personalization_manifest(struct ImageMounterHandle *client,
                                                                     const char *image_type,
                                                                     const uint8_t *signature,
                                                                     size_t signature_len,
                                                                     uint8_t **manifest,
                                                                     size_t *manifest_len);
struct IdeviceFfiError *image_mounter_query_nonce(struct ImageMounterHandle *client,
                                                  const char *personalized_image_type,
                                                  uint8_t **nonce,
                                                  size_t *nonce_len);
struct IdeviceFfiError *image_mounter_query_personalization_identifiers(struct ImageMounterHandle *client,
                                                                        const char *image_type,
                                                                        plist_t *identifiers);
struct IdeviceFfiError *image_mounter_roll_personalization_nonce(struct ImageMounterHandle *client);
struct IdeviceFfiError *image_mounter_roll_cryptex_nonce(struct ImageMounterHandle *client);
struct IdeviceFfiError *image_mounter_mount_personalized(struct ImageMounterHandle *client,
                                                         struct IdeviceProviderHandle *provider,
                                                         const uint8_t *image,
                                                         size_t image_len,
                                                         const uint8_t *trust_cache,
                                                         size_t trust_cache_len,
                                                         const uint8_t *build_manifest,
                                                         size_t build_manifest_len,
                                                         const void *info_plist,
                                                         uint64_t unique_chip_id);
struct IdeviceFfiError *image_mounter_mount_personalized_with_callback(struct ImageMounterHandle *client,
                                                                       struct IdeviceProviderHandle *provider,
                                                                       const uint8_t *image,
                                                                       size_t image_len,
                                                                       const uint8_t *trust_cache,
                                                                       size_t trust_cache_len,
                                                                       const uint8_t *build_manifest,
                                                                       size_t build_manifest_len,
                                                                       const void *info_plist,
                                                                       uint64_t unique_chip_id,
                                                                       void (*callback)(size_t progress,
                                                                                        size_t total,
                                                                                        void *context),
                                                                       void *context);
struct IdeviceFfiError *notification_proxy_connect(struct IdeviceProviderHandle *provider,
                                                   struct NotificationProxyClientHandle **client);
struct IdeviceFfiError *notification_proxy_new(struct IdeviceHandle *socket,
                                               struct NotificationProxyClientHandle **client);
struct IdeviceFfiError *notification_proxy_post(struct NotificationProxyClientHandle *client,
                                                const char *name);
struct IdeviceFfiError *notification_proxy_observe(struct NotificationProxyClientHandle *client,
                                                   const char *name);
struct IdeviceFfiError *notification_proxy_observe_multiple(struct NotificationProxyClientHandle *client,
                                                            const char *const *names);
struct IdeviceFfiError *notification_proxy_receive(struct NotificationProxyClientHandle *client,
                                                   char **name_out);
struct IdeviceFfiError *notification_proxy_receive_with_timeout(struct NotificationProxyClientHandle *client,
                                                                uint64_t interval,
                                                                char **name_out);
void notification_proxy_free_string(char *s);
void notification_proxy_client_free(struct NotificationProxyClientHandle *handle);
struct IdeviceFfiError *os_trace_relay_connect(struct IdeviceProviderHandle *provider,
                                               struct OsTraceRelayClientHandle **client);
void os_trace_relay_free(struct OsTraceRelayClientHandle *handle);
struct IdeviceFfiError *os_trace_relay_start_trace(struct OsTraceRelayClientHandle *client,
                                                   struct OsTraceRelayReceiverHandle **receiver,
                                                   const uint32_t *pid);
void os_trace_relay_receiver_free(struct OsTraceRelayReceiverHandle *handle);
struct IdeviceFfiError *os_trace_relay_get_pid_list(struct OsTraceRelayClientHandle *client,
                                                    struct Vec_u64 **list);
struct IdeviceFfiError *os_trace_relay_next(struct OsTraceRelayReceiverHandle *client,
                                            struct OsTraceLog **log);
void os_trace_relay_free_log(struct OsTraceLog *log);
struct IdeviceFfiError *idevice_pairing_file_read(const char *path,
                                                  struct IdevicePairingFile **pairing_file);
struct IdeviceFfiError *idevice_pairing_file_from_bytes(const uint8_t *data,
                                                        uintptr_t size,
                                                        struct IdevicePairingFile **pairing_file);
struct IdeviceFfiError *idevice_pairing_file_serialize(const struct IdevicePairingFile *pairing_file,
                                                       uint8_t **data,
                                                       uintptr_t *size);
void idevice_pairing_file_free(struct IdevicePairingFile *pairing_file);
struct IdeviceFfiError *idevice_tcp_provider_new(const idevice_sockaddr *ip,
                                                 struct IdevicePairingFile *pairing_file,
                                                 const char *label,
                                                 struct IdeviceProviderHandle **provider);
void idevice_provider_free(struct IdeviceProviderHandle *provider);
struct IdeviceFfiError *usbmuxd_provider_new(struct UsbmuxdAddrHandle *addr,
                                             uint32_t tag,
                                             const char *udid,
                                             uint32_t device_id,
                                             const char *label,
                                             struct IdeviceProviderHandle **provider);
struct IdeviceFfiError *idevice_provider_get_pairing_file(struct IdeviceProviderHandle *provider,
                                                          struct IdevicePairingFile **pairing_file);
struct IdeviceFfiError *rsd_handshake_new(struct ReadWriteOpaque *socket,
                                          struct RsdHandshakeHandle **handle);
struct IdeviceFfiError *rsd_get_protocol_version(struct RsdHandshakeHandle *handle,
                                                 size_t *version);
struct IdeviceFfiError *rsd_get_uuid(struct RsdHandshakeHandle *handle, char **uuid);
struct IdeviceFfiError *rsd_get_services(struct RsdHandshakeHandle *handle,
                                         struct CRsdServiceArray **services);
struct IdeviceFfiError *rsd_service_available(struct RsdHandshakeHandle *handle,
                                              const char *service_name,
                                              bool *available);
struct IdeviceFfiError *rsd_get_service_info(struct RsdHandshakeHandle *handle,
                                             const char *service_name,
                                             struct CRsdService **service_info);
struct RsdHandshakeHandle *rsd_handshake_clone(struct RsdHandshakeHandle *handshake);
void rsd_free_string(char *string);
void rsd_free_service(struct CRsdService *service);
void rsd_free_services(struct CRsdServiceArray *services);
void rsd_handshake_free(struct RsdHandshakeHandle *handle);
struct IdeviceFfiError *screenshotr_connect(struct IdeviceProviderHandle *provider,
                                            struct ScreenshotrClientHandle **client);
struct IdeviceFfiError *screenshotr_take_screenshot(struct ScreenshotrClientHandle *client,
                                                    struct ScreenshotData *screenshot);
void screenshotr_screenshot_free(struct ScreenshotData screenshot);
void screenshotr_client_free(struct ScreenshotrClientHandle *handle);
struct IdeviceFfiError *springboard_services_connect(struct IdeviceProviderHandle *provider,
                                                     struct SpringBoardServicesClientHandle **client);
struct IdeviceFfiError *springboard_services_new(struct IdeviceHandle *socket,
                                                 struct SpringBoardServicesClientHandle **client);
struct IdeviceFfiError *springboard_services_get_icon(struct SpringBoardServicesClientHandle *client,
                                                      const char *bundle_identifier,
                                                      void **out_result,
                                                      size_t *out_result_len);
struct IdeviceFfiError *springboard_services_get_home_screen_wallpaper_preview(struct SpringBoardServicesClientHandle *client,
                                                                               void **out_result,
                                                                               size_t *out_result_len);
struct IdeviceFfiError *springboard_services_get_lock_screen_wallpaper_preview(struct SpringBoardServicesClientHandle *client,
                                                                               void **out_result,
                                                                               size_t *out_result_len);
struct IdeviceFfiError *springboard_services_get_interface_orientation(struct SpringBoardServicesClientHandle *client,
                                                                       uint8_t *out_orientation);
struct IdeviceFfiError *springboard_services_get_homescreen_icon_metrics(struct SpringBoardServicesClientHandle *client,
                                                                         plist_t *res);
void springboard_services_free(struct SpringBoardServicesClientHandle *handle);
struct IdeviceFfiError *syslog_relay_connect_tcp(struct IdeviceProviderHandle *provider,
                                                 struct SyslogRelayClientHandle **client);
void syslog_relay_client_free(struct SyslogRelayClientHandle *handle);
struct IdeviceFfiError *syslog_relay_next(struct SyslogRelayClientHandle *client,
                                          char **log_message);
struct IdeviceFfiError *idevice_tcp_stack_into_sync_objects(const char *our_ip,
                                                            const char *their_ip,
                                                            struct TcpFeedObject **feeder,
                                                            struct TcpEatObject **tcp_receiver,
                                                            struct AdapterHandle **adapter_handle);
struct IdeviceFfiError *idevice_tcp_feed_object_write(struct TcpFeedObject *object,
                                                      const uint8_t *data,
                                                      uintptr_t len);
struct IdeviceFfiError *idevice_tcp_eat_object_read(struct TcpEatObject *object,
                                                    uint8_t **data,
                                                    uintptr_t *len);
void idevice_free_tcp_feed_object(struct TcpFeedObject *object);
void idevice_free_tcp_eat_object(struct TcpEatObject *object);
struct IdeviceFfiError *idevice_usbmuxd_new_tcp_connection(const idevice_sockaddr *addr,
                                                           idevice_socklen_t addr_len,
                                                           uint32_t tag,
                                                           struct UsbmuxdConnectionHandle **out);
struct IdeviceFfiError *idevice_usbmuxd_new_unix_socket_connection(const char *addr,
                                                                   uint32_t tag,
                                                                   struct UsbmuxdConnectionHandle **usbmuxd_connection);
struct IdeviceFfiError *idevice_usbmuxd_new_default_connection(uint32_t tag,
                                                               struct UsbmuxdConnectionHandle **usbmuxd_connection);
struct IdeviceFfiError *idevice_usbmuxd_get_devices(struct UsbmuxdConnectionHandle *usbmuxd_conn,
                                                    struct UsbmuxdDeviceHandle ***devices,
                                                    int *count);
struct IdeviceFfiError *idevice_usbmuxd_connect_to_device(struct UsbmuxdConnectionHandle *usbmuxd_connection,
                                                          uint32_t device_id,
                                                          uint16_t port,
                                                          const char *label,
                                                          struct IdeviceHandle **idevice);
struct IdeviceFfiError *idevice_usbmuxd_get_pair_record(struct UsbmuxdConnectionHandle *usbmuxd_conn,
                                                        const char *udid,
                                                        struct IdevicePairingFile **pair_record);
struct IdeviceFfiError *idevice_usbmuxd_save_pair_record(struct UsbmuxdConnectionHandle *usbmuxd_conn,
                                                         const char *udid,
                                                         uint8_t *pair_record,
                                                         uintptr_t pair_record_len);
struct IdeviceFfiError *idevice_usbmuxd_listen(struct UsbmuxdConnectionHandle *usbmuxd_conn,
                                               struct UsbmuxdListenerHandle **stream_handle);
void idevice_usbmuxd_listener_handle_free(struct UsbmuxdListenerHandle *stream_handle);
struct IdeviceFfiError *idevice_usbmuxd_listener_next(struct UsbmuxdListenerHandle *stream_handle,
                                                      bool *connect,
                                                      struct UsbmuxdDeviceHandle **connection_device,
                                                      uint32_t *disconnection_id);
struct IdeviceFfiError *idevice_usbmuxd_get_buid(struct UsbmuxdConnectionHandle *usbmuxd_conn,
                                                 char **buid);
void idevice_usbmuxd_connection_free(struct UsbmuxdConnectionHandle *usbmuxd_connection);
struct IdeviceFfiError *idevice_usbmuxd_tcp_addr_new(const idevice_sockaddr *addr,
                                                     idevice_socklen_t addr_len,
                                                     struct UsbmuxdAddrHandle **usbmuxd_addr);
struct IdeviceFfiError *idevice_usbmuxd_unix_addr_new(const char *addr,
                                                      struct UsbmuxdAddrHandle **usbmuxd_addr);
struct IdeviceFfiError *idevice_usbmuxd_default_addr_new(struct UsbmuxdAddrHandle **usbmuxd_addr);
void idevice_usbmuxd_addr_free(struct UsbmuxdAddrHandle *usbmuxd_addr);
void idevice_usbmuxd_device_list_free(struct UsbmuxdDeviceHandle **devices, int count);
void idevice_usbmuxd_device_free(struct UsbmuxdDeviceHandle *device);
char *idevice_usbmuxd_device_get_udid(const struct UsbmuxdDeviceHandle *device);
uint32_t idevice_usbmuxd_device_get_device_id(const struct UsbmuxdDeviceHandle *device);
uint8_t idevice_usbmuxd_device_get_connection_type(const struct UsbmuxdDeviceHandle *device);
#endif
#ifndef LIBPLIST_H
#define LIBPLIST_H
#ifdef __cplusplus
extern "C"
{
#endif
#if _MSC_VER && _MSC_VER < 1700
    typedef __int8 int8_t;
    typedef __int16 int16_t;
    typedef __int32 int32_t;
    typedef __int64 int64_t;
    typedef unsigned __int8 uint8_t;
    typedef unsigned __int16 uint16_t;
    typedef unsigned __int32 uint32_t;
    typedef unsigned __int64 uint64_t;
#else
#include <stdint.h>
#endif
#ifdef __llvm__
  #if defined(__has_extension)
    #if (__has_extension(attribute_deprecated_with_message))
      #ifndef PLIST_WARN_DEPRECATED
        #define PLIST_WARN_DEPRECATED(x) __attribute__((deprecated(x)))
      #endif
    #else
      #ifndef PLIST_WARN_DEPRECATED
        #define PLIST_WARN_DEPRECATED(x) __attribute__((deprecated))
      #endif
    #endif
  #else
    #ifndef PLIST_WARN_DEPRECATED
      #define PLIST_WARN_DEPRECATED(x) __attribute__((deprecated))
    #endif
  #endif
#elif (__GNUC__ > 4 || (__GNUC__ == 4 && (__GNUC_MINOR__ >= 5)))
  #ifndef PLIST_WARN_DEPRECATED
    #define PLIST_WARN_DEPRECATED(x) __attribute__((deprecated(x)))
  #endif
#elif defined(_MSC_VER)
  #ifndef PLIST_WARN_DEPRECATED
    #define PLIST_WARN_DEPRECATED(x) __declspec(deprecated(x))
  #endif
#else
  #define PLIST_WARN_DEPRECATED(x)
  #pragma message("WARNING: You need to implement DEPRECATED for this compiler")
#endif
#ifndef PLIST_API
  #ifdef LIBPLIST_STATIC
    #define PLIST_API
  #elif defined(_WIN32)
    #define PLIST_API __declspec(dllimport)
  #else
    #define PLIST_API
  #endif
#endif
#include <sys/types.h>
#include <stdarg.h>
#include <stdio.h>
    typedef void *plist_t;
    typedef void* plist_dict_iter;
    typedef void* plist_array_iter;
    typedef enum
    {
        PLIST_NONE =-1,
        PLIST_BOOLEAN,
        PLIST_INT,
        PLIST_REAL,
        PLIST_STRING,
        PLIST_ARRAY,
        PLIST_DICT,
        PLIST_DATE,
        PLIST_DATA,
        PLIST_KEY,
        PLIST_UID,
        PLIST_NULL,
    } plist_type;
    #define PLIST_UINT PLIST_INT
    typedef enum
    {
        PLIST_ERR_SUCCESS      =  0,
        PLIST_ERR_INVALID_ARG  = -1,
        PLIST_ERR_FORMAT       = -2,
        PLIST_ERR_PARSE        = -3,
        PLIST_ERR_NO_MEM       = -4,
        PLIST_ERR_IO           = -5,
        PLIST_ERR_CIRCULAR_REF = -6,
        PLIST_ERR_MAX_NESTING  = -7,
        PLIST_ERR_UNKNOWN      = -255
    } plist_err_t;
    typedef enum
    {
        PLIST_FORMAT_NONE    = 0,
        PLIST_FORMAT_XML     = 1,
        PLIST_FORMAT_BINARY  = 2,
        PLIST_FORMAT_JSON    = 3,
        PLIST_FORMAT_OSTEP   = 4,
        PLIST_FORMAT_PRINT   = 10,
        PLIST_FORMAT_LIMD    = 11,
        PLIST_FORMAT_PLUTIL  = 12,
    } plist_format_t;
    typedef enum
    {
        PLIST_OPT_NONE      = 0,
        PLIST_OPT_COMPACT   = 1 << 0,
        PLIST_OPT_PARTIAL_DATA = 1 << 1,
        PLIST_OPT_NO_NEWLINE = 1 << 2,
        PLIST_OPT_INDENT = 1 << 3,
    } plist_write_options_t;
    #define PLIST_OPT_INDENT_BY(x) ((x & 0xFF) << 24)
    PLIST_API plist_t plist_new_dict(void);
    PLIST_API plist_t plist_new_array(void);
    PLIST_API plist_t plist_new_string(const char *val);
    PLIST_API plist_t plist_new_bool(uint8_t val);
    PLIST_API plist_t plist_new_uint(uint64_t val);
    PLIST_API plist_t plist_new_int(int64_t val);
    PLIST_API plist_t plist_new_real(double val);
    PLIST_API plist_t plist_new_data(const char *val, uint64_t length);
    PLIST_API plist_t plist_new_unix_date(int64_t sec);
    PLIST_API plist_t plist_new_uid(uint64_t val);
    PLIST_API plist_t plist_new_null(void);
    PLIST_API void plist_free(plist_t plist);
    PLIST_API plist_t plist_copy(plist_t node);
    PLIST_API uint32_t plist_array_get_size(plist_t node);
    PLIST_API plist_t plist_array_get_item(plist_t node, uint32_t n);
    PLIST_API uint32_t plist_array_get_item_index(plist_t node);
    PLIST_API void plist_array_set_item(plist_t node, plist_t item, uint32_t n);
    PLIST_API void plist_array_append_item(plist_t node, plist_t item);
    PLIST_API void plist_array_insert_item(plist_t node, plist_t item, uint32_t n);
    PLIST_API void plist_array_remove_item(plist_t node, uint32_t n);
    PLIST_API void plist_array_item_remove(plist_t node);
    PLIST_API void plist_array_new_iter(plist_t node, plist_array_iter *iter);
    PLIST_API void plist_array_next_item(plist_t node, plist_array_iter iter, plist_t *item);
    PLIST_API void plist_array_free_iter(plist_array_iter iter);
    PLIST_API uint32_t plist_dict_get_size(plist_t node);
    PLIST_API void plist_dict_new_iter(plist_t node, plist_dict_iter *iter);
    PLIST_API void plist_dict_next_item(plist_t node, plist_dict_iter iter, char **key, plist_t *val);
    PLIST_API void plist_dict_free_iter(plist_dict_iter iter);
    PLIST_API void plist_dict_get_item_key(plist_t node, char **key);
    PLIST_API plist_t plist_dict_get_item(plist_t node, const char* key);
    PLIST_API plist_t plist_dict_item_get_key(plist_t node);
    PLIST_API void plist_dict_set_item(plist_t node, const char* key, plist_t item);
    PLIST_API void plist_dict_remove_item(plist_t node, const char* key);
    PLIST_API void plist_dict_merge(plist_t *target, plist_t source);
    PLIST_API uint8_t plist_dict_get_bool(plist_t dict, const char *key);
    PLIST_API int64_t plist_dict_get_int(plist_t dict, const char *key);
    PLIST_API uint64_t plist_dict_get_uint(plist_t dict, const char *key);
    PLIST_API plist_err_t plist_dict_copy_item(plist_t target_dict, plist_t source_dict, const char *key, const char *alt_source_key);
    PLIST_API plist_err_t plist_dict_copy_bool(plist_t target_dict, plist_t source_dict, const char *key, const char *alt_source_key);
    PLIST_API plist_err_t plist_dict_copy_int(plist_t target_dict, plist_t source_dict, const char *key, const char *alt_source_key);
    PLIST_API plist_err_t plist_dict_copy_uint(plist_t target_dict, plist_t source_dict, const char *key, const char *alt_source_key);
    PLIST_API plist_err_t plist_dict_copy_data(plist_t target_dict, plist_t source_dict, const char *key, const char *alt_source_key);
    PLIST_API plist_err_t plist_dict_copy_string(plist_t target_dict, plist_t source_dict, const char *key, const char *alt_source_key);
    PLIST_API plist_t plist_get_parent(plist_t node);
    PLIST_API plist_type plist_get_node_type(plist_t node);
    PLIST_API void plist_get_key_val(plist_t node, char **val);
    PLIST_API void plist_get_string_val(plist_t node, char **val);
    PLIST_API const char* plist_get_string_ptr(plist_t node, uint64_t* length);
    PLIST_API void plist_get_bool_val(plist_t node, uint8_t * val);
    PLIST_API void plist_get_uint_val(plist_t node, uint64_t * val);
    PLIST_API void plist_get_int_val(plist_t node, int64_t * val);
    PLIST_API void plist_get_real_val(plist_t node, double *val);
    PLIST_API void plist_get_data_val(plist_t node, char **val, uint64_t * length);
    PLIST_API const char* plist_get_data_ptr(plist_t node, uint64_t* length);
    PLIST_API void plist_get_unix_date_val(plist_t node, int64_t *sec);
    PLIST_API void plist_get_uid_val(plist_t node, uint64_t * val);
    PLIST_API void plist_set_key_val(plist_t node, const char *val);
    PLIST_API void plist_set_string_val(plist_t node, const char *val);
    PLIST_API void plist_set_bool_val(plist_t node, uint8_t val);
    PLIST_API void plist_set_uint_val(plist_t node, uint64_t val);
    PLIST_API void plist_set_int_val(plist_t node, int64_t val);
    PLIST_API void plist_set_real_val(plist_t node, double val);
    PLIST_API void plist_set_data_val(plist_t node, const char *val, uint64_t length);
    PLIST_API void plist_set_unix_date_val(plist_t node, int64_t sec);
    PLIST_API void plist_set_uid_val(plist_t node, uint64_t val);
    PLIST_API plist_err_t plist_to_xml(plist_t plist, char **plist_xml, uint32_t * length);
    PLIST_API plist_err_t plist_to_bin(plist_t plist, char **plist_bin, uint32_t * length);
    PLIST_API plist_err_t plist_to_json(plist_t plist, char **plist_json, uint32_t* length, int prettify);
    PLIST_API plist_err_t plist_to_openstep(plist_t plist, char **plist_openstep, uint32_t* length, int prettify);
    PLIST_API plist_err_t plist_from_xml(const char *plist_xml, uint32_t length, plist_t * plist);
    PLIST_API plist_err_t plist_from_bin(const char *plist_bin, uint32_t length, plist_t * plist);
    PLIST_API plist_err_t plist_from_json(const char *json, uint32_t length, plist_t * plist);
    PLIST_API plist_err_t plist_from_openstep(const char *openstep, uint32_t length, plist_t * plist);
    PLIST_API plist_err_t plist_from_memory(const char *plist_data, uint32_t length, plist_t *plist, plist_format_t *format);
    PLIST_API plist_err_t plist_read_from_file(const char *filename, plist_t *plist, plist_format_t *format);
    PLIST_API plist_err_t plist_write_to_string(plist_t plist, char **output, uint32_t* length, plist_format_t format, plist_write_options_t options);
    PLIST_API plist_err_t plist_write_to_stream(plist_t plist, FILE* stream, plist_format_t format, plist_write_options_t options);
    PLIST_API plist_err_t plist_write_to_file(plist_t plist, const char *filename, plist_format_t format, plist_write_options_t options);
    PLIST_API void plist_print(plist_t plist);
    PLIST_API int plist_is_binary(const char *plist_data, uint32_t length);
    PLIST_API plist_t plist_access_path(plist_t plist, uint32_t length, ...);
    PLIST_API plist_t plist_access_pathv(plist_t plist, uint32_t length, va_list v);
    PLIST_API char plist_compare_node_value(plist_t node_l, plist_t node_r);
    #define _PLIST_IS_TYPE(__plist, __plist_type) (__plist && (plist_get_node_type(__plist) == PLIST_##__plist_type))
    #define PLIST_IS_BOOLEAN(__plist) _PLIST_IS_TYPE(__plist, BOOLEAN)
    #define PLIST_IS_INT(__plist)     _PLIST_IS_TYPE(__plist, INT)
    #define PLIST_IS_REAL(__plist)    _PLIST_IS_TYPE(__plist, REAL)
    #define PLIST_IS_STRING(__plist)  _PLIST_IS_TYPE(__plist, STRING)
    #define PLIST_IS_ARRAY(__plist)   _PLIST_IS_TYPE(__plist, ARRAY)
    #define PLIST_IS_DICT(__plist)    _PLIST_IS_TYPE(__plist, DICT)
    #define PLIST_IS_DATE(__plist)    _PLIST_IS_TYPE(__plist, DATE)
    #define PLIST_IS_DATA(__plist)    _PLIST_IS_TYPE(__plist, DATA)
    #define PLIST_IS_KEY(__plist)     _PLIST_IS_TYPE(__plist, KEY)
    #define PLIST_IS_UID(__plist)     _PLIST_IS_TYPE(__plist, UID)
    #define PLIST_IS_UINT             PLIST_IS_INT
    PLIST_API int plist_bool_val_is_true(plist_t boolnode);
    PLIST_API int plist_int_val_is_negative(plist_t intnode);
    PLIST_API int plist_int_val_compare(plist_t uintnode, int64_t cmpval);
    PLIST_API int plist_uint_val_compare(plist_t uintnode, uint64_t cmpval);
    PLIST_API int plist_uid_val_compare(plist_t uidnode, uint64_t cmpval);
    PLIST_API int plist_real_val_compare(plist_t realnode, double cmpval);
    PLIST_API int plist_unix_date_val_compare(plist_t datenode, int64_t cmpval);
    PLIST_API int plist_string_val_compare(plist_t strnode, const char* cmpval);
    PLIST_API int plist_string_val_compare_with_size(plist_t strnode, const char* cmpval, size_t n);
    PLIST_API int plist_string_val_contains(plist_t strnode, const char* substr);
    PLIST_API int plist_key_val_compare(plist_t keynode, const char* cmpval);
    PLIST_API int plist_key_val_compare_with_size(plist_t keynode, const char* cmpval, size_t n);
    PLIST_API int plist_key_val_contains(plist_t keynode, const char* substr);
    PLIST_API int plist_data_val_compare(plist_t datanode, const uint8_t* cmpval, size_t n);
    PLIST_API int plist_data_val_compare_with_size(plist_t datanode, const uint8_t* cmpval, size_t n);
    PLIST_API int plist_data_val_contains(plist_t datanode, const uint8_t* cmpval, size_t n);
    PLIST_API void plist_sort(plist_t plist);
    PLIST_API void plist_mem_free(void* ptr);
    PLIST_API void plist_set_debug(int debug);
    PLIST_API const char* libplist_version();
    PLIST_WARN_DEPRECATED("use plist_new_unix_date instead")
    PLIST_API plist_t plist_new_date(int32_t sec, int32_t usec);
    PLIST_WARN_DEPRECATED("use plist_get_unix_date_val instead")
    PLIST_API void plist_get_date_val(plist_t node, int32_t * sec, int32_t * usec);
    PLIST_WARN_DEPRECATED("use plist_set_unix_date_val instead")
    PLIST_API void plist_set_date_val(plist_t node, int32_t sec, int32_t usec);
    PLIST_WARN_DEPRECATED("use plist_unix_date_val_compare instead")
    PLIST_API int plist_date_val_compare(plist_t datenode, int32_t cmpsec, int32_t cmpusec);
#ifdef __cplusplus
}
#endif
#endif