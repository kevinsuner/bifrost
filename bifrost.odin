package main

import "core:net"
import "core:os"
import "core:fmt"
// import "core:mem"

/*

backing_buffer := make([]byte, 2*mem.Kilobyte)
defer delete(backing_buffer)

arena: mem.Arena
mem.arena_init(&arena, backing_buffer)

buffer, err_alloc := mem.arena_alloc_bytes(&arena, 1*mem.Kilobyte)     
if err_alloc != nil {
  fmt.println("Failed to alloc bytes")
  break
}

*/

main :: proc() {
  socket, err_dial := net.dial_tcp_from_host(
    net.Host{"0.0.0.0", 8000},
    net.default_tcp_options,
  )
  if err_dial != nil {
    fmt.println("Failed to dial tcp")
    return
  }

  buffer: [1024]u8
  for {
    n, err_read := os.read(os.stdin, buffer[:])
    if err_read != nil {
      fmt.println("Failed to read data")
      break
    }
    if n == 0 || (n == 1 && buffer[0] == '\n') {
      break
    }

    data := buffer[:n]
    bytes_sent, err_sent := net.send_tcp(socket, data)
    if err_sent != nil {
      fmt.println("Failed to send data")
      break
    }

    bytes_recv, err_recv := net.recv_tcp(socket, buffer[:])
    if err_recv != nil {
      fmt.println("Failed to recv data")
      break
    }

    received := buffer[:bytes_recv]
    fmt.printf("Client received [ %d bytes ]: %s", len(received), received)
  }

  net.close(socket)
}

