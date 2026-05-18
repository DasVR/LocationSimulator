#ifndef IDEVICE_H
#define IDEVICE_H

#include <stdint.h>
#include <sys/socket.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * idevice.h — C FFI header for jkcoxson/idevice Rust library.
 *
 * This header declares the minimal surface area required for
 * LocationSimulator to communicate with an iOS device over
 * RPPairing (Remote Pairing) tunnel and control location simulation.
 *
 * All opaque handles are represented as void* (OpaquePointer in Swift).
 */

/* ------------------------------------------------------------------ */
/* Type aliases                                                        */
/* ------------------------------------------------------------------ */

/** Underlying socket address type used by the FFI layer. */
typedef struct sockaddr idevice_sockaddr;

/** Generic error handle returned by idevice FFI functions. */
typedef const char* idevice_error_t;

/* ------------------------------------------------------------------ */
/* Error helpers                                                       */
/* ------------------------------------------------------------------ */

/**
 * Convert an idevice error handle to a human-readable C string.
 *
 * @param error  The error handle returned by a failed FFI call.
 * @return       A null-terminated string describing the error. The caller
 *               must NOT free this string; it is owned by the library.
 */
const char* idevice_error_to_string(idevice_error_t error);

/* ------------------------------------------------------------------ */
/* Pairing file                                                        */
/* ------------------------------------------------------------------ */

/**
 * Parse a raw pairing file (binary plist) into an opaque handle.
 *
 * @param bytes   Pointer to the raw file bytes.
 * @param length  Length of the byte buffer.
 * @param handle  Out-pointer to receive the pairing-file handle.
 * @return        NULL on success, or an error handle on failure.
 */
idevice_error_t rp_pairing_file_from_bytes(const uint8_t* bytes,
                                              size_t length,
                                              void** handle);

/**
 * Free a pairing-file handle obtained from rp_pairing_file_from_bytes.
 *
 * @param handle  The pairing-file handle to release.
 */
void rp_pairing_file_free(void* handle);

/* ------------------------------------------------------------------ */
/* RPPairing tunnel                                                    */
/* ------------------------------------------------------------------ */

/**
 * Create an RPPairing tunnel to the device.
 *
 * @param addr            Pointer to a socket address (sockaddr_in for IPv4).
 * @param addr_len        Size of the socket address structure.
 * @param hostname        Target hostname or IP string (e.g. "10.7.0.1").
 * @param pairing_file    Pairing-file handle from rp_pairing_file_from_bytes.
 * @param user            Optional username (may be NULL).
 * @param pass            Optional password (may be NULL).
 * @param adapter_out     Out-pointer for the tunnel adapter handle.
 * @param handshake_out   Out-pointer for the RSD handshake handle.
 * @return                NULL on success, or an error handle on failure.
 */
idevice_error_t tunnel_create_rppairing(const idevice_sockaddr* addr,
                                         socklen_t addr_len,
                                         const char* hostname,
                                         void* pairing_file,
                                         const char* user,
                                         const char* pass,
                                         void** adapter_out,
                                         void** handshake_out);

/**
 * Free a tunnel adapter handle.
 *
 * @param adapter  The adapter handle returned by tunnel_create_rppairing.
 */
void adapter_free(void* adapter);

/**
 * Free an RSD handshake handle.
 *
 * @param handshake  The handshake handle returned by tunnel_create_rppairing.
 */
void rsd_handshake_free(void* handshake);

/* ------------------------------------------------------------------ */
/* Remote server                                                       */
/* ------------------------------------------------------------------ */

/**
 * Connect to the remote debug server over an established RSD handshake.
 *
 * @param adapter   Tunnel adapter handle.
 * @param handshake RSD handshake handle.
 * @param server_out Out-pointer for the remote-server handle.
 * @return         NULL on success, or an error handle on failure.
 */
idevice_error_t remote_server_connect_rsd(void* adapter,
                                            void* handshake,
                                            void** server_out);

/**
 * Disconnect and free a remote-server handle.
 *
 * @param server  The remote-server handle to release.
 */
void remote_server_disconnect(void* server);

/* ------------------------------------------------------------------ */
/* Location simulation                                                 */
/* ------------------------------------------------------------------ */

/**
 * Create a location-simulation session on the remote server.
 *
 * @param server  Connected remote-server handle.
 * @param handle_out  Out-pointer for the location-simulation handle.
 * @return      NULL on success, or an error handle on failure.
 */
idevice_error_t location_simulation_new(void* server, void** handle_out);

/**
 * Set the simulated geographic location.
 *
 * @param handle     Location-simulation handle.
 * @param latitude   Latitude in decimal degrees.
 * @param longitude  Longitude in decimal degrees.
 * @return           NULL on success, or an error handle on failure.
 */
idevice_error_t location_simulation_set(void* handle,
                                         double latitude,
                                         double longitude);

/**
 * Clear the simulated location, restoring real GPS.
 *
 * @param handle  Location-simulation handle.
 * @return        NULL on success, or an error handle on failure.
 */
idevice_error_t location_simulation_clear(void* handle);

/**
 * Free a location-simulation handle.
 *
 * @param handle  The location-simulation handle to release.
 */
void location_simulation_free(void* handle);

#ifdef __cplusplus
}
#endif

#endif /* IDEVICE_H */
