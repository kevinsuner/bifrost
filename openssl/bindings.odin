package openssl

import "core:c"

foreign import lib {
    "system:ssl",
    "system:crypto",
}

SSL_CTRL_SET_TLSEXT_HOSTNAME    :: 55
TLSEXT_NAMETYPE_host_name       :: 0

SSL_CTX     :: struct {}
SSL_METHOD  :: struct {}
SSL         :: struct {}

foreign lib {
    SSL_CTX_new         :: proc(method: ^SSL_METHOD) -> ^SSL_CTX                                ---
    SSL_CTX_free        :: proc(ctx: ^SSL_CTX)                                                  ---
    SSL_new             :: proc(ctx: ^SSL_CTX) -> ^SSL                                          ---
    SSL_free            :: proc(ssl: ^SSL)                                                      ---
    SSL_set_fd          :: proc(ssl: ^SSL, fd: c.int) -> c.int                                  ---
    SSL_ctrl            :: proc(ssl: ^SSL, cmd: c.int, larg: c.long, parg: rawptr) -> c.long    ---
    SSL_connect         :: proc(ssl: ^SSL) -> c.int                                             ---
    SSL_write           :: proc(ssl: ^SSL, buf: [^]u8, num: c.int) -> c.int                     ---
    SSL_read            :: proc(ssl: ^SSL, buf: [^]u8, num: c.int) -> c.int                     ---
    TLS_client_method   :: proc() -> ^SSL_METHOD                                                ---
    ERR_get_error       :: proc() -> c.long                                                     ---
    ERR_error_string_n  :: proc(e: c.long, buf: [^]u8, len: c.int)                              ---
}

SSL_set_tlsext_host_name :: proc(ssl: ^SSL, name: cstring) -> c.int {
    return c.int(SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, rawptr(name)))
}

