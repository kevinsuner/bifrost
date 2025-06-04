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

    url, parse_err := bifrost.parse_url("https://dummyjson.com/test")
    if parse_err != .None {
        fmt.printf("parse_url failed: %v\n", parse_err)
        return
    }
    
    res, req_err := bifrost.make_request(.Get, url, nil, nil)
    if req_err != nil {
        fmt.printf("make_request failed: %v\n", req_err)
        return
    }
    fmt.printf("res: %v\n", res)
}
