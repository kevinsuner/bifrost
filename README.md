# Bifrost

A simple HTTP/1.1 client written in Odin (besides the SSL stuff).

## Dependencies

The package depends on [OpenSSL](https://github.com/openssl/openssl) to make
HTTPS requests.

I've tested it on Linux (Mint 22.1), macOS (Sequoia 15.4) and Windows 11, the
first two had OpenSSL preinstalled, but you can get it through a package manager
usually as `libssl`.

For Windows, the repository itself contains a copy of these libraries.

## Example

```odin
package main

import "core:mem"
import "core:fmt"
import bifrost "../.." // Change the path.

main :: proc() {
    buf := make([]u8, 8*mem.Kilobyte)
    defer delete(buf)

    arena: mem.Arena
    mem.arena_init(&arena, buf)
    defer mem.arena_free_all(&arena)
    context.allocator = mem.arena_allocator(&arena)

    url := bifrost.url_init()
    defer bifrost.url_free(url)
    err := bifrost.url_parse(url, "https://dummyjson.com/test")
    if err != nil {
        fmt.printf("url_parse failed: %v\n", err)
        return
    }

    req := bifrost.request_init(.Get, url, nil)
    defer bifrost.request_free(req)
    err = bifrost.request_do(req)
    if err != nil {
        fmt.printf("request_do failed: %v\n", err)
        return
    }

    fmt.printf("req.res: %v\n", req.res)
}
```

