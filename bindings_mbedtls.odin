package bifrost

import "core:mem"
import "core:testing"
import "core:log"

foreign import mbedtls "system:mbedtls"

SSL_CONTEXT_ESTIMATED_SIZE :: 512

mbedtls_net_context :: rawptr
mbedtls_ssl_context :: rawptr

foreign mbedtls {
    mbedtls_net_init :: proc(fd: ^mbedtls_net_context)  ---
    mbedtls_net_free :: proc(fd: ^mbedtls_net_context)  ---
    mbedtls_ssl_init :: proc(ssl: ^mbedtls_ssl_context) ---
    mbedtls_ssl_free :: proc(ssl: ^mbedtls_ssl_context) ---
}

@(test)
test_mbedtls_bindings :: proc(t: ^testing.T) {
    backing_buf := make([]byte, 10*mem.Kilobyte)
    defer delete(backing_buf)

    arena: mem.Arena
    mem.arena_init(&arena, backing_buf)

    fd, fd_alloc_err := mem.arena_alloc(&arena, size_of(mbedtls_net_context))
    if fd_alloc_err != .None { testing.fail_now(t, "fd_alloc_err") }

    ssl, ssl_alloc_err := mem.arena_alloc(&arena, SSL_CONTEXT_ESTIMATED_SIZE)
    if ssl_alloc_err != .None { testing.fail_now(t, "ssl_alloc_err") }

    mbedtls_net_init(cast(^mbedtls_net_context)fd)
    defer mbedtls_net_free(cast(^mbedtls_net_context)fd)
    log.infof("fd: %v\n", fd)

    mbedtls_ssl_init(cast(^mbedtls_ssl_context)ssl)
    defer mbedtls_ssl_free(cast(^mbedtls_ssl_context)ssl)
    log.infof("ssl: %v\n", ssl)
}

