package main

import "core:mem"
import "core:fmt"
import bifrost "../.."

main :: proc() {
    buf := make([]u8, 4*mem.Kilobyte)
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
        fmt.printf("request_do failed %v\n", err)
        return
    }
    fmt.printf("req.res: %v\n", req.res)
}
